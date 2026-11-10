// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IElectorateRegistry} from "../../contracts/interfaces/IElectorateRegistry.sol";
import {IMembershipRegistry} from "../../contracts/interfaces/IMembershipRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {JusticeCitizenEligibilityPolicy} from "../../contracts/policies/JusticeCitizenEligibilityPolicy.sol";
import {CandidateEligibilityPolicy} from "../../contracts/policies/CandidateEligibilityPolicy.sol";
import {UnstakingPolicy} from "../../contracts/policies/UnstakingPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {ElectorateRegistry} from "../../contracts/registries/ElectorateRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {MembershipRegistry} from "../../contracts/registries/MembershipRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {MembershipTypes} from "../../contracts/types/MembershipTypes.sol";

contract JusticeBrokenElectorateCallback {
    fallback() external {
        revert("failed callback");
    }
}

contract JusticeMembershipEligibilityTest is Test {
    ConstitutionKernel private kernel;
    IdentityRegistry private identity;
    StakeRegistry private stake;
    MembershipRegistry private membership;
    ElectorateRegistry private electorate;
    JusticeCitizenEligibilityPolicy private policy;
    VotingPowerPolicy private votes;
    CandidateEligibilityPolicy private candidates;
    address private writer;

    bytes32 private constant PERSON = bytes32(uint256(1));
    address private constant WALLET = address(0xA11CE);
    bytes32 private constant RECEIPT = keccak256("authenticated legal receipt");
    uint256 private constant MINIMUM = 5_000;
    uint256 private constant STAKE = 10_000;
    uint64 private constant WELFARE = 30 days;

    function setUp() public {
        vm.warp(1_000_000);
        vm.roll(10);
        kernel = new ConstitutionKernel(address(this));
        identity = new IdentityRegistry(address(kernel));
        stake = new StakeRegistry(address(kernel));
        membership = new MembershipRegistry(address(kernel), address(identity));
        writer = address(new MockModule(keccak256("justice")));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_WRITER, writer);
        kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_APP, writer);
        kernel.bootstrapSetModule(KernelModuleIds.MEMBERSHIP_REGISTRY, address(membership));
        kernel.bootstrapSetModule(
            KernelModuleIds.UNSTAKING_POLICY, address(new UnstakingPolicy(address(stake), WELFARE, 1_000))
        );
        policy = new JusticeCitizenEligibilityPolicy(address(identity), address(stake), MINIMUM, address(membership));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(policy));
        electorate = new ElectorateRegistry(address(kernel), address(identity), address(stake));
        kernel.bootstrapSetModule(KernelModuleIds.ELECTORATE_REGISTRY, address(electorate));
        votes = new VotingPowerPolicy(address(identity), address(stake), address(policy), address(electorate));
        candidates = new CandidateEligibilityPolicy(address(identity), address(stake), address(policy), MINIMUM);
        _register(PERSON, WALLET);
        vm.roll(block.number + 1);
        assertTrue(electorate.isReady());
    }

    function testRemovalIsRevisionBoundAndDoesNotChangeCitizenshipOrCredit() public {
        uint48 prior = uint48(block.number - 1);
        _remove(PERSON, true);
        assertTrue(membership.membershipRemoved(PERSON));
        assertEq(membership.membershipRevisionOf(PERSON), 1);
        assertEq(membership.electorateMutationCount(), 1);
        assertEq(
            uint8(identity.getIdentityRecord(PERSON).citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.Citizen)
        );
        assertEq(stake.activeStakeOf(PERSON), STAKE);
        assertTrue(policy.isEligibleForCredit(WALLET));
        assertFalse(policy.isCitizenInGoodStanding(WALLET));
        assertFalse(candidates.isEligibleCandidate(WALLET));
        assertEq(votes.votingPowerAt(WALLET, prior), 0);
        assertTrue(electorate.wasEligibleAt(PERSON, prior));
        (uint256 oldCount,) = electorate.snapshotAt(prior);
        assertEq(oldCount, 1);
        _assertCount(0);
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.MembershipRevisionMismatch.selector, 0, 1));
        vm.prank(writer);
        membership.setMembershipRemoved(PERSON, false, 0, RECEIPT);
        _remove(PERSON, false);
        assertTrue(policy.isCitizenInGoodStanding(WALLET));
        _assertCount(1);
    }

    function testRemovalRejectsUnauthorizedUnknownEmptyReceiptAndNoOp() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.UnauthorizedMembershipRegistryCaller.selector, address(this))
        );
        membership.setMembershipRemoved(PERSON, true, 0, RECEIPT);
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.UnknownPerson.selector, bytes32(uint256(9))));
        vm.prank(writer);
        membership.setMembershipRemoved(bytes32(uint256(9)), true, 0, RECEIPT);
        vm.expectRevert(IMembershipRegistry.InvalidReceiptId.selector);
        vm.prank(writer);
        membership.setMembershipRemoved(PERSON, true, 0, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.MembershipRemovalUnchanged.selector, PERSON, false));
        vm.prank(writer);
        membership.setMembershipRemoved(PERSON, false, 0, RECEIPT);
        assertEq(membership.electorateMutationCount(), 0);
    }

    function testTemporaryPoliticalRestrictionBlocksLiveVoteButNotDenominatorOrCredit() public {
        uint48 prior = uint48(block.number - 1);
        _order(PERSON, 1, 1, 100);
        assertFalse(policy.isCitizenInGoodStanding(WALLET));
        assertEq(votes.votingPowerAt(WALLET, prior), 0);
        assertFalse(candidates.isEligibleCandidate(WALLET));
        assertTrue(policy.isEligibleForCredit(WALLET));
        _assertCount(1);
        assertEq(electorate.nextWelfareExpiry(), 0);
        vm.warp(block.timestamp + 100);
        assertTrue(policy.isCitizenInGoodStanding(WALLET));
        assertEq(votes.votingPowerAt(WALLET, prior), STAKE);
        assertTrue(electorate.isReady());
        assertEq(membership.membershipRevisionOf(PERSON), 1);
        _assertCount(1);
    }

    function testAppointmentRestrictionDoesNotBlockVoteOrCredit() public {
        _order(PERSON, 1, 16, 100);
        assertFalse(candidates.isEligibleCandidate(WALLET));
        assertTrue(policy.isCitizenInGoodStanding(WALLET));
        assertEq(votes.votingPower(WALLET), STAKE);
        assertTrue(policy.isEligibleForCredit(WALLET));
        _assertCount(1);
        vm.warp(block.timestamp + 100);
        assertTrue(candidates.isEligibleCandidate(WALLET));
    }

    function testRemovalRestorationDoesNotClearIndependentOrder() public {
        _order(PERSON, 1, 1, 100);
        _remove(PERSON, true);
        _remove(PERSON, false);
        assertTrue(membership.isRestrictedNow(PERSON, MembershipTypes.Right.Political));
        assertFalse(policy.isCitizenInGoodStanding(WALLET));
        _assertCount(1);
    }

    function testBelowMinimumPooledStakeExcludesHeadcount() public {
        stake.slashStake(PERSON, STAKE - MINIMUM + 1);
        _assertCount(0);
        assertFalse(policy.isCitizenInGoodStanding(WALLET));
        stake.increaseStake(PERSON, 1);
        _assertCount(1);
        assertTrue(policy.isCitizenInGoodStanding(WALLET));
    }

    function testWelfareExcludedImmediatelyAndExpiryRequiresCompletedBlockCertification() public {
        (, uint64 until) = stake.unstake(PERSON);
        _assertCount(0);
        assertFalse(policy.isEligibleForCredit(WALLET));
        assertFalse(policy.isCitizenInGoodStanding(WALLET));
        assertEq(electorate.nextWelfareExpiry(), until);
        vm.roll(block.number + 1);
        vm.warp(until);
        assertTrue(policy.isCitizenInGoodStanding(WALLET));
        assertFalse(electorate.isReady());
        vm.expectRevert(abi.encodeWithSelector(IElectorateRegistry.ElectorateWelfareExpiryPending.selector, until));
        electorate.snapshot();
        _expectUncertifiedPreviousBlock();
        assertEq(electorate.syncExpired(1), 1);
        _assertCount(1);
        assertEq(electorate.nextWelfareExpiry(), 0);
        _expectUncertifiedPreviousBlock();
        vm.roll(block.number + 1);
        (uint256 count,) = electorate.snapshotAtCurrentEpoch(uint48(block.number - 1));
        assertEq(count, 1);
    }

    function testExpiryBoundaryIsExactAndUnrelatedSyncCannotSkipDueEntry() public {
        (, uint64 until) = stake.unstake(PERSON);
        vm.warp(until - 1);
        assertEq(electorate.syncExpired(32), 0);
        _assertCount(0);
        vm.warp(until);
        electorate.syncPerson(PERSON);
        assertFalse(electorate.isReady());
        assertEq(electorate.syncExpired(32), 1);
        _assertCount(1);
    }

    function testPartialExpiryBatchRemainsUnavailableAndAcceptsUnrelatedPeople() public {
        for (uint256 i = 2; i <= 4; ++i) {
            _register(bytes32(i), address(uint160(100 + i)));
        }
        for (uint256 i = 1; i <= 4; ++i) {
            stake.unstake(bytes32(i));
        }
        _assertCount(0);
        vm.warp(block.timestamp + WELFARE);
        assertEq(electorate.syncExpired(2), 2);
        assertFalse(electorate.isReady());
        assertEq(electorate.syncExpired(2), 2);
        _assertCount(4);
        assertEq(electorate.syncExpired(1), 0);
        vm.expectRevert(abi.encodeWithSelector(IElectorateRegistry.InvalidExpiryBatchSize.selector, 0));
        electorate.syncExpired(0);
        vm.expectRevert(abi.encodeWithSelector(IElectorateRegistry.InvalidExpiryBatchSize.selector, 33));
        electorate.syncExpired(33);
    }

    function testNewWelfarePeriodDoesNotAllowOldEntryToRestoreEligibility() public {
        (, uint64 firstEnd) = stake.unstake(PERSON);
        vm.warp(firstEnd);
        (, uint64 secondEnd) = stake.unstake(PERSON);
        assertFalse(electorate.isReady());
        assertEq(electorate.nextWelfareExpiry(), firstEnd);
        assertEq(electorate.syncExpired(1), 1);
        _assertCount(0);
        assertEq(electorate.nextWelfareExpiry(), secondEnd);
        vm.warp(secondEnd);
        assertEq(electorate.syncExpired(1), 1);
        _assertCount(1);
    }

    function testExpiryHeapOrdersDifferentDeadlinesAndStopsBeforeFutureEntries() public {
        _register(bytes32(uint256(2)), address(102));
        _register(bytes32(uint256(3)), address(103));
        (, uint64 firstEnd) = stake.unstake(bytes32(uint256(3)));
        vm.warp(block.timestamp + 10);
        (, uint64 secondEnd) = stake.unstake(PERSON);
        vm.warp(block.timestamp + 10);
        (, uint64 thirdEnd) = stake.unstake(bytes32(uint256(2)));
        assertEq(electorate.nextWelfareExpiry(), firstEnd);
        vm.warp(firstEnd);
        assertEq(electorate.syncExpired(32), 1);
        _assertCount(1);
        assertEq(electorate.nextWelfareExpiry(), secondEnd);
        vm.warp(secondEnd);
        assertEq(electorate.syncExpired(32), 1);
        _assertCount(2);
        vm.warp(thirdEnd);
        assertEq(electorate.syncExpired(32), 1);
        _assertCount(3);
    }

    function testThirtyThreeExpiriesRequireTwoBoundedBatchesWithSuccessfulSourceCallbacks() public {
        for (uint256 i = 2; i <= 33; ++i) {
            _register(bytes32(i), address(uint160(100 + i)));
        }
        for (uint256 i = 1; i <= 33; ++i) {
            stake.unstake(bytes32(i));
            // Every real source callback receives its fixed 500k budget; no manual catch-up is needed.
            assertTrue(electorate.isReady());
        }
        _assertCount(0);
        vm.warp(block.timestamp + WELFARE);
        assertEq(electorate.syncExpired(32), 32);
        assertFalse(electorate.isReady());
        assertEq(electorate.syncExpired(32), 1);
        _assertCount(33);
    }

    function testUnderfundedProductionUnstakeCannotLeaveMissingExpiry() public {
        uint256 successes;
        uint256 failures;
        for (uint256 budget = 50_000; budget <= 950_000; budget += 50_000) {
            uint256 snapshotId = vm.snapshotState();
            vm.cool(address(stake));
            vm.cool(address(electorate));
            (bool success,) = address(stake).call{gas: budget}(abi.encodeCall(stake.unstake, (PERSON)));
            assertTrue(electorate.isReady());
            assertEq(stake.isInWelfare(PERSON), success);
            _assertCount(success ? 0 : 1);
            assertEq(electorate.nextWelfareExpiry(), success ? block.timestamp + WELFARE : 0);
            if (success) ++successes;
            else ++failures;
            vm.revertToStateAndDelete(snapshotId);
        }
        assertGt(successes, 0);
        assertGt(failures, 0);
    }

    function testPolicyRebuildReschedulesFutureWelfareOnceAndClearsOldEpochQueue() public {
        (, uint64 until) = stake.unstake(PERSON);
        uint64 oldEpoch = electorate.epoch();
        JusticeCitizenEligibilityPolicy successor =
            new JusticeCitizenEligibilityPolicy(address(identity), address(stake), MINIMUM, address(membership));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(successor));
        assertEq(electorate.epoch(), oldEpoch + 1);
        assertFalse(electorate.isReady());
        electorate.rebuild(0, 1);
        electorate.syncPerson(PERSON);
        _assertCount(0);
        vm.warp(until);
        assertEq(electorate.syncExpired(32), 1);
        _assertCount(1);
    }

    function testLegacyPolicyRetainsWelfareAndMembershipSemantics() public {
        CitizenEligibilityPolicy legacy = new CitizenEligibilityPolicy(address(identity), address(stake), MINIMUM);
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(legacy));
        electorate.rebuild(0, 1);
        _remove(PERSON, true);
        _order(PERSON, 1, 1, 100);
        assertTrue(legacy.isCitizenInGoodStanding(WALLET));
        stake.unstake(PERSON);
        _assertCount(1);
        assertEq(electorate.nextWelfareExpiry(), 0);
        assertFalse(legacy.isCitizenInGoodStanding(WALLET));
        vm.warp(block.timestamp + WELFARE);
        assertTrue(electorate.isReady());
        assertTrue(legacy.isCitizenInGoodStanding(WALLET));
    }

    function testBrokenMembershipCallbackBlocksNewSnapshotsUntilCatchup() public {
        uint48 oldBlock = uint48(block.number - 1);
        kernel.bootstrapSetModule(KernelModuleIds.ELECTORATE_REGISTRY, address(new JusticeBrokenElectorateCallback()));
        _remove(PERSON, true);
        assertFalse(electorate.isReady());
        vm.expectRevert(abi.encodeWithSelector(IElectorateRegistry.ElectorateMembershipIncomplete.selector, 0, 1));
        electorate.snapshot();
        kernel.bootstrapSetModule(KernelModuleIds.ELECTORATE_REGISTRY, address(electorate));
        vm.roll(block.number + 1);
        electorate.syncPerson(PERSON);
        _assertCount(0);
        _expectUncertifiedPreviousBlock();
        (uint256 historical,) = electorate.snapshotAt(oldBlock);
        assertEq(historical, 1);
        vm.roll(block.number + 1);
        (uint256 count,) = electorate.snapshotAtCurrentEpoch(uint48(block.number - 1));
        assertEq(count, 0);
    }

    function testUnderfundedMembershipWriteCannotPoisonReadiness() public {
        uint256 successes;
        uint256 failures;
        for (uint256 budget = 50_000; budget <= 850_000; budget += 50_000) {
            uint256 snapshotId = vm.snapshotState();
            vm.cool(address(membership));
            vm.cool(address(electorate));
            vm.prank(writer);
            (bool success,) = address(membership).call{gas: budget}(
                abi.encodeCall(membership.setMembershipRemoved, (PERSON, true, 0, RECEIPT))
            );
            assertTrue(electorate.isReady());
            assertEq(membership.membershipRemoved(PERSON), success);
            _assertCount(success ? 0 : 1);
            if (success) ++successes;
            else ++failures;
            vm.revertToStateAndDelete(snapshotId);
        }
        assertGt(successes, 0);
        assertGt(failures, 0);
    }

    function testRetiredJusticeMarkerFailsClosedWithoutDestroyingCanonicalRoll() public {
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_WRITER, address(new MockModule(keccak256("successor"))));
        assertFalse(policy.isCitizenInGoodStanding(WALLET));
        assertFalse(electorate.isReady());
        vm.expectRevert(IElectorateRegistry.ElectoratePolicyConfigurationInvalid.selector);
        electorate.syncPerson(PERSON);
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_WRITER, writer);
        _assertCount(1);
        assertTrue(policy.isCitizenInGoodStanding(WALLET));
    }

    function testPinnedMembershipReplacementNeedsMatchingPolicyAndFullEpochRebuild() public {
        MembershipRegistry next = new MembershipRegistry(address(kernel), address(identity));
        kernel.bootstrapSetModule(KernelModuleIds.MEMBERSHIP_REGISTRY, address(next));
        assertFalse(policy.electorateConfigurationValid());
        assertFalse(electorate.isReady());
        JusticeCitizenEligibilityPolicy replacement =
            new JusticeCitizenEligibilityPolicy(address(identity), address(stake), MINIMUM, address(next));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(replacement));
        assertFalse(electorate.isReady());
        electorate.rebuild(0, 1);
        _assertCount(1);
    }

    function testFuzzMixedWelfareRemovalAndStakeCountMatchesIndependentModel(
        uint8 rawPeople,
        uint256 removalMask,
        uint256 welfareMask,
        uint256 lowStakeMask
    ) public {
        uint256 people = bound(rawPeople, 1, 16);
        for (uint256 i = 2; i <= people; ++i) {
            _register(bytes32(i), address(uint160(100 + i)));
        }
        uint256 expectedBefore;
        uint256 expectedAfter;
        for (uint256 i = 1; i <= people; ++i) {
            bool removed = (removalMask & (1 << i)) != 0;
            bool welfare = (welfareMask & (1 << i)) != 0;
            bool lowStake = (lowStakeMask & (1 << i)) != 0;
            if (removed) _remove(bytes32(i), true);
            if (welfare) stake.unstake(bytes32(i));
            if (lowStake) stake.slashStake(bytes32(i), stake.activeStakeOf(bytes32(i)) - MINIMUM + 1);
            if (!removed && !lowStake) {
                ++expectedAfter;
                if (!welfare) ++expectedBefore;
            }
        }
        _assertCount(expectedBefore);
        vm.warp(block.timestamp + WELFARE);
        electorate.syncExpired(32);
        _assertCount(expectedAfter);
    }

    function _register(bytes32 person, address wallet) private {
        identity.setIdentityRecord(
            person,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256("person"),
                metadataURI: "",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identity.setWalletLink(person, wallet, IdentityTypes.WalletLinkStatus.Active);
        stake.increaseStake(person, STAKE);
    }

    function _remove(bytes32 person, bool removed) private {
        uint256 revision = membership.membershipRevisionOf(person);
        vm.prank(writer);
        membership.setMembershipRemoved(person, removed, revision, RECEIPT);
    }

    function _order(bytes32 person, uint256 id, uint16 mask, uint64 duration) private {
        vm.prank(writer);
        membership.recordOrder(
            MembershipTypes.OrderInput(
                person, bytes32(id), mask, uint64(block.timestamp), uint64(block.timestamp + duration), false
            ),
            RECEIPT
        );
    }

    function _assertCount(uint256 expected) private view {
        assertTrue(electorate.isReady());
        (uint256 count,) = electorate.snapshot();
        assertEq(count, expected);
    }

    function _expectUncertifiedPreviousBlock() private {
        vm.expectPartialRevert(IElectorateRegistry.ElectorateCurrentEpochUnavailable.selector);
        electorate.snapshotAtCurrentEpoch(uint48(block.number - 1));
    }
}
