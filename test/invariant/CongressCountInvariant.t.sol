// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {CongressElectionApp} from "../../contracts/apps/CongressElectionApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {CongressRankingStore} from "../../contracts/registries/CongressRankingStore.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {ElectorateRegistry} from "../../contracts/registries/ElectorateRegistry.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {CandidateEligibilityPolicy} from "../../contracts/policies/CandidateEligibilityPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {CongressElectionPolicy} from "../../contracts/policies/CongressElectionPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";

/// @notice Exercises interrupted counts with 80 candidates, live eligibility/wallet changes and policy replacement.
contract CongressCountHandler is Test {
    CongressElectionApp public immutable app;
    CongressCandidateRegistry public immutable registry;
    CongressRankingStore public immutable ranking;
    IdentityRegistry public immutable identities;
    ConstitutionKernel public immutable kernel;
    address public immutable fixtureAuthority;
    address public immutable originalPolicy;
    address public immutable replacementPolicy;
    uint256 public immutable cycleId;
    uint256 public constant POPULATION = 80;
    bool public unexpectedRevert;
    bool public frozenInputChanged;
    bool public invalidOutcome;
    bool public invalidProgress;
    uint256 public successfulChunks;
    uint256 public maximumChunkGas;

    constructor(
        CongressElectionApp app_,
        CongressCandidateRegistry registry_,
        IdentityRegistry identities_,
        ConstitutionKernel kernel_,
        address authority_,
        address replacementPolicy_,
        uint256 cycleId_
    ) {
        app = app_;
        registry = registry_;
        ranking = CongressRankingStore(registry_.rankingStore());
        identities = identities_;
        kernel = kernel_;
        fixtureAuthority = authority_;
        originalPolicy = registry_.getCycle(cycleId_).policy;
        replacementPolicy = replacementPolicy_;
        cycleId = cycleId_;
    }

    /// @notice Changes current citizenship while leaving the vote's historical weight fixed.
    function changeEligibility(uint8 seed, bool eligible) external {
        if (finished()) return;
        bytes32 person = bytes32(uint256(10_000) + seed % POPULATION);
        IdentityTypes.IdentityRecord memory old = identities.getIdentityRecord(person);
        vm.prank(fixtureAuthority);
        identities.setIdentityRecord(
            person,
            IdentityTypes.IdentityRecordInput({
                metadataHash: old.metadataHash,
                metadataURI: old.metadataURI,
                verificationStatus: old.verificationStatus,
                citizenshipStatus: eligible
                    ? IdentityTypes.CitizenshipStatus.Citizen
                    : IdentityTypes.CitizenshipStatus.Suspended,
                ageClass: old.ageClass,
                correctionFlag: false,
                finalSuspension: !eligible
            })
        );
    }

    /// @notice Simulates authorized person-preserving migrations between two candidate-owned wallets.
    function migrateCandidate(uint8 seed) external {
        if (finished()) return;
        uint256 index = seed % POPULATION;
        bytes32 person = bytes32(10_000 + index);
        address old = identities.activeWalletOf(person);
        address next = old == address(uint160(10_000 + index))
            ? address(uint160(20_000 + index))
            : address(uint160(10_000 + index));
        vm.startPrank(fixtureAuthority);
        identities.setWalletLink(person, old, IdentityTypes.WalletLinkStatus.Revoked);
        identities.setWalletLink(person, next, IdentityTypes.WalletLinkStatus.Active);
        vm.stopPrank();
    }

    /// @notice Mutates the live policy pointer without changing the cycle's pinned rules.
    function replacePolicy(bool replacement) external {
        if (finished()) return;
        address target = replacement ? replacementPolicy : originalPolicy;
        if (kernel.getModule(KernelModuleIds.CONGRESS_ELECTION_POLICY) == target) return;
        vm.prank(fixtureAuthority);
        kernel.governanceUpdateModule(KernelModuleIds.CONGRESS_ELECTION_POLICY, target);
    }

    /// @notice Attempts prohibited post-vote ballot/candidate mutations and records any successful write.
    function attemptFrozenMutation(uint8 seed, uint8 operation) external {
        uint256 index = seed % POPULATION;
        address canonical = address(uint160(10_000 + index));
        address caller = identities.activeWalletOf(bytes32(10_000 + index));
        (int256 beforeVotes,,) = registry.getCandidateRankingData(cycleId, canonical);
        address[] memory candidates = new address[](1);
        int256[] memory votes = new int256[](1);
        candidates[0] = canonical;
        votes[0] = 1;
        bytes memory callData;
        if (operation % 3 == 0) callData = abi.encodeCall(app.castBallot, (cycleId, candidates, votes));
        else if (operation % 3 == 1) callData = abi.encodeCall(app.clearBallot, (cycleId));
        else callData = abi.encodeCall(app.withdrawCandidacy, (cycleId));
        vm.prank(caller);
        (bool ok,) = address(app).call(callData);
        (int256 afterVotes,,) = registry.getCandidateRankingData(cycleId, canonical);
        if (ok || beforeVotes != afterVotes || registry.getCycleCandidateCount(cycleId) != POPULATION) {
            frozenInputChanged = true;
        }
    }

    /// @notice Advances completed blocks and performs one permissionless bounded count transaction.
    function countStep() public {
        if (finished()) return;
        vm.roll(block.number + 1);
        ElectionTypes.FinalizationProgress memory before = ranking.progress(cycleId);
        uint256 gasBefore = gasleft();
        try app.finalizeElection(cycleId) {
            uint256 used = gasBefore - gasleft();
            if (used > maximumChunkGas) maximumChunkGas = used;
            ++successfulChunks;
            ElectionTypes.FinalizationProgress memory after_ = ranking.progress(cycleId);
            if (
                after_.processedCount < before.processedCount || after_.processedCount > POPULATION
                    || after_.processedCount - before.processedCount > 32 || after_.selectedCount > 9
            ) invalidProgress = true;
            if (finished()) _checkOutcome();
        } catch {
            unexpectedRevert = true;
        }
    }

    /// @notice Advances time without altering the established vote input or election cadence.
    function advanceTime(uint32 seconds_) external {
        if (finished()) return;
        vm.warp(block.timestamp + bound(uint256(seconds_), 1, 10 days));
        vm.roll(block.number + 1);
    }

    /// @notice Returns whether the canonical registry, rather than merely a successful chunk, is finalized.
    function finished() public view returns (bool) {
        return registry.getCycle(cycleId).status == ElectionTypes.ElectionStatus.Finalized;
    }

    function _checkOutcome() private {
        address[] memory expected = new address[](POPULATION);
        int256[] memory scores = new int256[](POPULATION);
        uint256 count;
        CongressElectionPolicy policy = CongressElectionPolicy(originalPolicy);
        for (uint256 i; i < POPULATION; ++i) {
            address canonical = address(uint160(10_000 + i));
            (int256 score,, bytes32 person) = registry.getCandidateRankingData(cycleId, canonical);
            if (
                score < 0 || ranking.disqualified(cycleId, canonical)
                    || !policy.isEligibleCandidate(identities.activeWalletOf(person))
            ) continue;
            uint256 j = count;
            while (j > 0 && (score > scores[j - 1] || (score == scores[j - 1] && canonical < expected[j - 1]))) {
                expected[j] = expected[j - 1];
                scores[j] = scores[j - 1];
                --j;
            }
            expected[j] = canonical;
            scores[j] = score;
            ++count;
        }
        uint256 elected = count < 7 ? count : 7;
        uint256 runners = count - elected < 2 ? count - elected : 2;
        if (registry.getElectedCandidateCount(cycleId) != elected || registry.getRunnerUpCount(cycleId) != runners) {
            invalidOutcome = true;
            return;
        }
        for (uint256 i; i < elected + runners; ++i) {
            address candidate =
                i < elected ? registry.getElectedCandidateAt(cycleId, i) : registry.getRunnerUpAt(cycleId, i - elected);
            if (candidate != expected[i]) invalidOutcome = true;
            if (i < elected) {
                ElectionTypes.CongressSeatRecord memory seat = registry.getSeatRecord(uint32(i));
                if (
                    seat.holderPersonId != bytes32(uint256(uint160(candidate)))
                        || seat.holder != identities.activeWalletOf(seat.holderPersonId)
                        || !policy.isEligibleCandidate(seat.holder)
                ) invalidOutcome = true;
            }
        }
    }
}

contract CongressCountInvariantTest is Test {
    CongressCountHandler internal handler;
    ConstitutionKernel private kernel;
    IdentityRegistry private identities;
    StakeRegistry private stakes;
    ElectorateRegistry private electorate;
    CitizenEligibilityPolicy private citizen;
    CandidateEligibilityPolicy private eligible;
    VotingPowerPolicy private voting;
    CongressCandidateRegistry private registry;
    CongressElectionPolicy private policy;
    CongressElectionPolicy private replacement;
    CongressElectionApp private app;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identities = new IdentityRegistry(address(kernel));
        stakes = new StakeRegistry(address(kernel));
        electorate = new ElectorateRegistry(address(kernel), address(identities), address(stakes));
        citizen = new CitizenEligibilityPolicy(address(identities), address(stakes), 5_000);
        eligible = new CandidateEligibilityPolicy(address(identities), address(stakes), address(citizen), 6_000);
        voting = new VotingPowerPolicy(address(identities), address(stakes), address(citizen), address(electorate));
        registry = new CongressCandidateRegistry(address(kernel));
        policy = new CongressElectionPolicy(
            address(eligible), address(voting), 7, 2, 0, 6_000, 2 days, 3 days, 14 days, 90 days
        );
        replacement = new CongressElectionPolicy(
            address(eligible), address(voting), 3, 2, 0, 6_000, 2 days, 3 days, 14 days, 90 days
        );
        app = new CongressElectionApp(address(identities), address(registry), address(eligible), address(policy));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identities));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(stakes));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(citizen));
        kernel.bootstrapSetModule(KernelModuleIds.CANDIDATE_ELIGIBILITY_POLICY, address(eligible));
        kernel.bootstrapSetModule(KernelModuleIds.VOTING_POWER_POLICY, address(voting));
        kernel.bootstrapSetModule(KernelModuleIds.ELECTORATE_REGISTRY, address(electorate));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(app));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_POLICY, address(policy));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));
        kernel.disableBootstrapAuthority();
        for (uint256 i; i < 80; ++i) {
            bytes32 person = bytes32(10_000 + i);
            identities.setIdentityRecord(
                person,
                IdentityTypes.IdentityRecordInput({
                    metadataHash: keccak256(abi.encode(i)),
                    metadataURI: "ipfs://count-invariant",
                    verificationStatus: IdentityTypes.VerificationStatus.Verified,
                    citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                    ageClass: IdentityTypes.AgeClass.Adult,
                    correctionFlag: false,
                    finalSuspension: false
                })
            );
            identities.setWalletLink(person, address(uint160(10_000 + i)), IdentityTypes.WalletLinkStatus.Active);
            stakes.increaseStake(person, 6_000 + (i % 13) * 100);
        }
        vm.roll(block.number + 1);
        uint256 cycle = app.createNextElectionCycle();
        ElectionTypes.CongressCycleRecord memory record = registry.getCycle(cycle);
        vm.warp(record.nominationStart);
        for (uint256 i = 80; i > 0; --i) {
            vm.prank(address(uint160(9_999 + i)));
            app.applyAsCandidate(cycle, keccak256(abi.encode(i)), "ipfs://candidate");
        }
        vm.warp(record.votingStart);
        for (uint256 i; i < 80; ++i) {
            bool negative = i % 5 == 0;
            address[] memory candidates = new address[](negative ? 2 : 1);
            int256[] memory allocations = new int256[](negative ? 2 : 1);
            candidates[0] = address(uint160(10_000 + i));
            int256 weight = int256(6_000 + (i % 13) * 100);
            allocations[0] = negative ? int256(-1_000) : weight;
            if (negative) {
                candidates[1] = address(uint160(10_079));
                allocations[1] = weight - 1_000;
            }
            vm.prank(candidates[0]);
            app.castBallot(cycle, candidates, allocations);
        }
        vm.warp(record.votingEnd);
        handler =
            new CongressCountHandler(app, registry, identities, kernel, address(this), address(replacement), cycle);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.changeEligibility.selector;
        selectors[1] = handler.migrateCandidate.selector;
        selectors[2] = handler.replacePolicy.selector;
        selectors[3] = handler.attemptFrozenMutation.selector;
        selectors[4] = handler.countStep.selector;
        selectors[5] = handler.advanceTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_CountPreservesFixedInputAndBoundedProgress() public view {
        assertFalse(handler.frozenInputChanged());
        assertFalse(handler.invalidProgress());
        assertEq(handler.registry().getCycleCandidateCount(handler.cycleId()), 80);
    }

    function invariant_ActivationMatchesIndependentSortAndCurrentEligibility() public view {
        assertFalse(handler.invalidOutcome());
    }

    function invariant_CompletedBlockCountNeverUnexpectedlyReverts() public view {
        assertFalse(handler.unexpectedRevert());
    }

    function test_InterruptedCountCompletesAfterMigrationDisqualificationAndPolicyChange() public {
        handler.countStep();
        for (uint8 i; i < 70; ++i) {
            handler.changeEligibility(i, false);
        }
        handler.migrateCandidate(71);
        handler.replacePolicy(true);
        for (uint256 i; i < 8 && !handler.finished(); ++i) {
            handler.countStep();
        }
        assertTrue(handler.finished());
        assertGt(handler.successfulChunks(), 2);
        assertLt(handler.maximumChunkGas(), 12_000_000);
        assertFalse(handler.invalidOutcome());
        assertFalse(handler.unexpectedRevert());
    }
}
