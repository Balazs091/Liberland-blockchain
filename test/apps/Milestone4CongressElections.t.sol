// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {CongressElectionApp} from "../../contracts/apps/CongressElectionApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ICandidateEligibilityPolicy} from "../../contracts/interfaces/ICandidateEligibilityPolicy.sol";
import {ICitizenEligibilityPolicy} from "../../contracts/interfaces/ICitizenEligibilityPolicy.sol";
import {ICongressCandidateRegistry} from "../../contracts/interfaces/ICongressCandidateRegistry.sol";
import {ICongressElectionApp} from "../../contracts/interfaces/ICongressElectionApp.sol";
import {ICongressElectionPolicy} from "../../contracts/interfaces/ICongressElectionPolicy.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../../contracts/interfaces/IStakeRegistry.sol";
import {IVotingPowerPolicy} from "../../contracts/interfaces/IVotingPowerPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {CandidateEligibilityPolicy} from "../../contracts/policies/CandidateEligibilityPolicy.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {CongressElectionPolicy} from "../../contracts/policies/CongressElectionPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

/// @title Milestone4CongressElectionsTest
/// @notice Covers Congress election cycle scheduling, signed-ballot voting, and runner-up replacement.
contract Milestone4CongressElectionsTest is Test {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint256 internal constant MINIMUM_CANDIDATE_STAKE = 6_000;
    uint256 internal constant CANDIDATE_BOND_REQUIREMENT = 6_000;
    uint32 internal constant SEAT_COUNT = 2;
    uint32 internal constant RUNNER_UP_COUNT = 2;
    uint32 internal constant MAX_CANDIDATE_COUNT = 8;
    uint64 internal constant MINIMUM_NOMINATION_DURATION = 2 days;
    uint64 internal constant MINIMUM_VOTING_DURATION = 3 days;
    uint64 internal constant MAX_SCHEDULE_LEAD_TIME = 14 days;
    uint64 internal constant ELECTION_CYCLE_DURATION = 5 days;

    bytes32 internal constant PERSON_ONE_ID = bytes32(uint256(1));
    bytes32 internal constant PERSON_TWO_ID = bytes32(uint256(2));
    bytes32 internal constant PERSON_THREE_ID = bytes32(uint256(3));
    bytes32 internal constant PERSON_FOUR_ID = bytes32(uint256(4));
    bytes32 internal constant PERSON_FIVE_ID = bytes32(uint256(5));
    bytes32 internal constant PERSON_SIX_ID = bytes32(uint256(6));

    address internal constant WALLET_ONE = address(0xA11CE);
    address internal constant WALLET_TWO = address(0xB0B);
    address internal constant WALLET_THREE = address(0xCAFE);
    address internal constant WALLET_FOUR = address(0xD00D);
    address internal constant WALLET_FIVE = address(0xE111);
    address internal constant WALLET_SIX = address(0xF222);

    uint256 internal arbitraryExecutionCount;

    ConstitutionKernel internal kernel;
    MockModule internal identityAuthority;
    MockModule internal stakeAuthority;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    CandidateEligibilityPolicy internal candidateEligibilityPolicy;
    VotingPowerPolicy internal votingPowerPolicy;
    CongressCandidateRegistry internal congressCandidateRegistry;
    CongressElectionPolicy internal congressElectionPolicy;
    CongressElectionApp internal congressElectionApp;

    function setUp() public {
        _deployFoundation();
        _deployCongressElectionSystem();
        _registerDefaultCitizens();
    }

    function _deployFoundation() internal {
        kernel = new ConstitutionKernel(address(this));

        identityAuthority = new MockModule(keccak256("identity-authority"));
        stakeAuthority = new MockModule(keccak256("stake-authority"));

        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(identityAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(stakeAuthority));

        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);
        candidateEligibilityPolicy = new CandidateEligibilityPolicy(
            address(identityRegistry),
            address(stakeRegistry),
            address(citizenEligibilityPolicy),
            MINIMUM_CANDIDATE_STAKE
        );
        votingPowerPolicy =
            new VotingPowerPolicy(address(identityRegistry), address(stakeRegistry), address(citizenEligibilityPolicy));
    }

    function _deployCongressElectionSystem() internal {
        congressCandidateRegistry = new CongressCandidateRegistry(address(kernel));
        congressElectionPolicy = new CongressElectionPolicy(
            address(candidateEligibilityPolicy),
            address(votingPowerPolicy),
            SEAT_COUNT,
            RUNNER_UP_COUNT,
            MAX_CANDIDATE_COUNT,
            CANDIDATE_BOND_REQUIREMENT,
            MINIMUM_NOMINATION_DURATION,
            MINIMUM_VOTING_DURATION,
            MAX_SCHEDULE_LEAD_TIME,
            ELECTION_CYCLE_DURATION
        );
        congressElectionApp = new CongressElectionApp(
            address(identityRegistry),
            address(congressCandidateRegistry),
            address(candidateEligibilityPolicy),
            address(congressElectionPolicy)
        );

        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(congressElectionApp));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_POLICY, address(congressElectionPolicy));
    }

    function _registerDefaultCitizens() internal {
        _registerCitizen(PERSON_ONE_ID, WALLET_ONE, 9_000);
        _registerCitizen(PERSON_TWO_ID, WALLET_TWO, 8_000);
        _registerCitizen(PERSON_THREE_ID, WALLET_THREE, 7_000);
        _registerCitizen(PERSON_FOUR_ID, WALLET_FOUR, 6_500);
        _registerCitizen(PERSON_FIVE_ID, WALLET_FIVE, 5_500);
        _registerCitizen(PERSON_SIX_ID, WALLET_SIX, 5_000);
    }

    function bump() external {
        arbitraryExecutionCount += 1;
    }

    function test_Milestone4InterfacesExposeSelectors() public pure {
        assertTrue(ICandidateEligibilityPolicy.isEligibleCandidate.selector != bytes4(0));
        assertTrue(ICongressCandidateRegistry.createCycle.selector != bytes4(0));
        assertTrue(ICongressCandidateRegistry.recordBallot.selector != bytes4(0));
        assertTrue(ICongressElectionPolicy.cycleDuration.selector != bytes4(0));
        assertTrue(ICongressElectionPolicy.votingWeight.selector != bytes4(0));
        assertTrue(ICongressElectionApp.createElectionCycle.selector != bytes4(0));
        assertTrue(ICongressElectionApp.createNextElectionCycle.selector != bytes4(0));
        assertTrue(ICongressElectionApp.previewNextElectionWindow.selector != bytes4(0));
        assertTrue(ICongressElectionApp.castBallot.selector != bytes4(0));
        assertTrue(ICongressElectionApp.resignSeat.selector != bytes4(0));
        assertTrue(ICitizenEligibilityPolicy.isCitizenInGoodStanding.selector != bytes4(0));
        assertTrue(IIdentityRegistry.resolveWalletToPersonId.selector != bytes4(0));
        assertTrue(IStakeRegistry.activeStakeOf.selector != bytes4(0));
        assertTrue(IVotingPowerPolicy.votingPower.selector != bytes4(0));
    }

    function test_CreateVoteFinalize_ResolvesTopNAndRunnerUps() public {
        (uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) = _createCycle();

        vm.warp(cycleRecord.nominationStart);
        _applyCandidate(cycleId, WALLET_ONE, "candidate-1");
        _applyCandidate(cycleId, WALLET_TWO, "candidate-2");
        _applyCandidate(cycleId, WALLET_THREE, "candidate-3");
        _applyCandidate(cycleId, WALLET_FOUR, "candidate-4");

        vm.warp(cycleRecord.votingStart);
        _castFullWeightBallot(WALLET_ONE, cycleId, WALLET_THREE);
        _castFullWeightBallot(WALLET_TWO, cycleId, WALLET_ONE);
        _castFullWeightBallot(WALLET_THREE, cycleId, WALLET_ONE);
        _castFullWeightBallot(WALLET_FOUR, cycleId, WALLET_TWO);
        _castFullWeightBallot(WALLET_FIVE, cycleId, WALLET_THREE);
        _castFullWeightBallot(WALLET_SIX, cycleId, WALLET_FOUR);

        vm.warp(cycleRecord.votingEnd);
        congressElectionApp.finalizeElection(cycleId);

        ElectionTypes.CongressCycleRecord memory finalizedCycle = congressCandidateRegistry.getCycle(cycleId);
        assertEq(uint256(finalizedCycle.status), uint256(ElectionTypes.ElectionStatus.Finalized));
        assertEq(finalizedCycle.electedCount, SEAT_COUNT);
        assertEq(finalizedCycle.runnerUpSlotCount, RUNNER_UP_COUNT);

        _assertCandidateOutcome(cycleId, WALLET_ONE, ElectionTypes.CandidateStatus.Elected, 1, 15_000);
        _assertCandidateOutcome(cycleId, WALLET_THREE, ElectionTypes.CandidateStatus.Elected, 2, 14_500);
        _assertCandidateOutcome(cycleId, WALLET_TWO, ElectionTypes.CandidateStatus.RunnerUp, 3, 6_500);
        _assertCandidateOutcome(cycleId, WALLET_FOUR, ElectionTypes.CandidateStatus.RunnerUp, 4, 5_000);

        assertEq(congressCandidateRegistry.getElectedCandidateCount(cycleId), 2);
        assertEq(congressCandidateRegistry.getElectedCandidateAt(cycleId, 0), WALLET_ONE);
        assertEq(congressCandidateRegistry.getElectedCandidateAt(cycleId, 1), WALLET_THREE);
        assertEq(congressCandidateRegistry.getRunnerUpCount(cycleId), 2);
        assertEq(congressCandidateRegistry.getRunnerUpAt(cycleId, 0), WALLET_TWO);
        assertEq(congressCandidateRegistry.getRunnerUpAt(cycleId, 1), WALLET_FOUR);

        ElectionTypes.CongressOfficeTerm memory officeTerm = congressCandidateRegistry.getCurrentOfficeTerm();
        assertEq(officeTerm.cycleId, cycleId);
        assertEq(officeTerm.seatCount, SEAT_COUNT);
        assertEq(officeTerm.occupiedSeatCount, SEAT_COUNT);
        assertEq(officeTerm.runnerUpCount, RUNNER_UP_COUNT);
        assertEq(officeTerm.nextRunnerUpIndex, 0);

        _assertSeatHolder(0, cycleId, WALLET_ONE, 1, false);
        _assertSeatHolder(1, cycleId, WALLET_THREE, 2, false);
        assertTrue(congressElectionApp.isCongressMember(WALLET_ONE));
        assertTrue(congressElectionApp.isCongressMember(WALLET_THREE));
        assertFalse(congressElectionApp.isCongressMember(WALLET_TWO));

        address[] memory currentMembers = congressCandidateRegistry.currentCongressMembers();
        assertEq(currentMembers.length, 2);
        assertEq(currentMembers[0], WALLET_ONE);
        assertEq(currentMembers[1], WALLET_THREE);

        ElectionTypes.CongressCycleRecord memory nextCycle = congressCandidateRegistry.getCycle(cycleId + 1);
        assertEq(congressCandidateRegistry.latestCycleId(), cycleId + 1);
        assertEq(uint256(nextCycle.status), uint256(ElectionTypes.ElectionStatus.CandidateRegistration));
        assertEq(nextCycle.nominationStart, cycleRecord.votingEnd);
        assertEq(nextCycle.votingStart, cycleRecord.votingEnd + MINIMUM_NOMINATION_DURATION);
        assertEq(nextCycle.votingEnd, cycleRecord.votingEnd + ELECTION_CYCLE_DURATION);
    }

    function test_CreateNextElectionCycle_UsesPolicyCadenceForInitialCycle() public {
        uint64 expectedNominationStart = uint64(block.timestamp);
        uint64 expectedVotingStart = expectedNominationStart + MINIMUM_NOMINATION_DURATION;
        uint64 expectedVotingEnd = expectedNominationStart + ELECTION_CYCLE_DURATION;

        (uint64 nominationStart, uint64 votingStart, uint64 votingEnd) = congressElectionApp.previewNextElectionWindow();
        assertEq(nominationStart, expectedNominationStart);
        assertEq(votingStart, expectedVotingStart);
        assertEq(votingEnd, expectedVotingEnd);

        uint256 cycleId = congressElectionApp.createNextElectionCycle();
        ElectionTypes.CongressCycleRecord memory cycleRecord = congressCandidateRegistry.getCycle(cycleId);

        assertEq(cycleId, 1);
        assertEq(cycleRecord.nominationStart, expectedNominationStart);
        assertEq(cycleRecord.votingStart, expectedVotingStart);
        assertEq(cycleRecord.votingEnd, expectedVotingEnd);
    }

    function test_AutoRegisteredIncumbents_ReelectWhenNoOneActs() public {
        (uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) = _createCycle();

        vm.warp(cycleRecord.nominationStart);
        _applyCandidate(cycleId, WALLET_ONE, "candidate-1");
        vm.warp(cycleRecord.nominationStart + 1);
        _applyCandidate(cycleId, WALLET_TWO, "candidate-2");

        vm.warp(cycleRecord.votingEnd);
        congressElectionApp.finalizeElection(cycleId);

        uint256 nextCycleId = cycleId + 1;
        ElectionTypes.CongressCycleRecord memory nextCycle = congressCandidateRegistry.getCycle(nextCycleId);

        assertEq(congressCandidateRegistry.getCycleCandidateCount(nextCycleId), 2);
        _assertAutoIncumbentCandidate(nextCycleId, WALLET_ONE);
        _assertAutoIncumbentCandidate(nextCycleId, WALLET_TWO);

        vm.warp(nextCycle.votingEnd);
        congressElectionApp.finalizeElection(nextCycleId);

        ElectionTypes.CongressOfficeTerm memory officeTerm = congressCandidateRegistry.getCurrentOfficeTerm();
        assertEq(officeTerm.cycleId, nextCycleId);
        assertEq(officeTerm.occupiedSeatCount, 2);
        assertTrue(congressElectionApp.isCongressMember(WALLET_ONE));
        assertTrue(congressElectionApp.isCongressMember(WALLET_TWO));
    }

    function test_AutoRegisteredIncumbent_CanWithdrawCandidacy() public {
        (uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) = _createCycle();

        vm.warp(cycleRecord.nominationStart);
        _applyCandidate(cycleId, WALLET_ONE, "candidate-1");
        _applyCandidate(cycleId, WALLET_TWO, "candidate-2");

        vm.warp(cycleRecord.votingEnd);
        congressElectionApp.finalizeElection(cycleId);

        uint256 nextCycleId = cycleId + 1;
        ElectionTypes.CongressCycleRecord memory nextCycle = congressCandidateRegistry.getCycle(nextCycleId);

        vm.prank(WALLET_ONE);
        congressElectionApp.withdrawCandidacy(nextCycleId);

        assertEq(congressCandidateRegistry.getCycleCandidateCount(nextCycleId), 1);
        _assertCandidateStatus(nextCycleId, WALLET_ONE, ElectionTypes.CandidateStatus.Withdrawn);
        _assertCandidateStatus(nextCycleId, WALLET_TWO, ElectionTypes.CandidateStatus.Accepted);

        vm.warp(nextCycle.votingEnd);
        congressElectionApp.finalizeElection(nextCycleId);

        ElectionTypes.CongressOfficeTerm memory officeTerm = congressCandidateRegistry.getCurrentOfficeTerm();
        assertEq(officeTerm.cycleId, nextCycleId);
        assertEq(officeTerm.occupiedSeatCount, 1);
        assertFalse(congressElectionApp.isCongressMember(WALLET_ONE));
        assertTrue(congressElectionApp.isCongressMember(WALLET_TWO));
    }

    function test_CastBallot_ReplacesEntireSignedBallot() public {
        (uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) = _createCycle();

        vm.warp(cycleRecord.nominationStart);
        _applyAllDefaultCandidates(cycleId);

        vm.warp(cycleRecord.votingStart);
        _castBallot(
            WALLET_ONE,
            cycleId,
            _asAddressArray(WALLET_ONE, WALLET_TWO, WALLET_THREE),
            _asIntArray(int256(4_000), int256(3_000), int256(-2_000))
        );

        ElectionTypes.BallotReceipt memory firstReceipt =
            congressCandidateRegistry.getBallotReceipt(cycleId, WALLET_ONE);
        assertEq(firstReceipt.ballotWeight, 9_000);
        assertEq(firstReceipt.positiveAllocationTotal, 7_000);
        assertEq(firstReceipt.negativeAllocationTotal, 2_000);
        assertEq(firstReceipt.allocationCount, 3);
        assertEq(congressCandidateRegistry.getCandidate(cycleId, WALLET_ONE).voteTotal, 4_000);
        assertEq(congressCandidateRegistry.getCandidate(cycleId, WALLET_TWO).voteTotal, 3_000);
        assertEq(congressCandidateRegistry.getCandidate(cycleId, WALLET_THREE).voteTotal, -2_000);

        _castBallot(
            WALLET_ONE, cycleId, _asAddressArray(WALLET_THREE, WALLET_FOUR), _asIntArray(int256(7_000), int256(2_000))
        );

        ElectionTypes.BallotReceipt memory secondReceipt =
            congressCandidateRegistry.getBallotReceipt(cycleId, WALLET_ONE);
        assertEq(secondReceipt.ballotWeight, 9_000);
        assertEq(secondReceipt.positiveAllocationTotal, 9_000);
        assertEq(secondReceipt.negativeAllocationTotal, 0);
        assertEq(secondReceipt.allocationCount, 2);
        assertEq(congressCandidateRegistry.getCandidate(cycleId, WALLET_ONE).voteTotal, 0);
        assertEq(congressCandidateRegistry.getCandidate(cycleId, WALLET_TWO).voteTotal, 0);
        assertEq(congressCandidateRegistry.getCandidate(cycleId, WALLET_THREE).voteTotal, 7_000);
        assertEq(congressCandidateRegistry.getCandidate(cycleId, WALLET_FOUR).voteTotal, 2_000);
    }

    /// @notice H-3: a person who migrates wallets mid-cycle cannot double-vote the same stake; the pre-migration
    ///         standing ballot is dropped when the person re-votes from the new wallet.
    function test_CastBallot_WalletMigrationCannotDoubleVote() public {
        address newWallet = address(0x9999);
        (uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) = _createCycle();

        vm.warp(cycleRecord.nominationStart);
        _applyAllDefaultCandidates(cycleId);

        vm.warp(cycleRecord.votingStart);
        // PERSON_ONE (stake 9,000) votes from WALLET_ONE for candidate WALLET_THREE.
        _castBallot(WALLET_ONE, cycleId, _asAddressArray(WALLET_THREE), _asIntArray(int256(9_000)));
        assertEq(congressCandidateRegistry.getCandidate(cycleId, WALLET_THREE).voteTotal, 9_000);

        // Office-approved wallet migration: revoke WALLET_ONE, activate a fresh wallet for the SAME person.
        _setWalletLink(PERSON_ONE_ID, WALLET_ONE, IdentityTypes.WalletLinkStatus.Revoked);
        _setWalletLink(PERSON_ONE_ID, newWallet, IdentityTypes.WalletLinkStatus.Active);

        // Voting again from the new wallet must REPLACE the person's ballot, not stack a second 9,000.
        _castBallot(newWallet, cycleId, _asAddressArray(WALLET_THREE), _asIntArray(int256(9_000)));
        assertEq(congressCandidateRegistry.getCandidate(cycleId, WALLET_THREE).voteTotal, 9_000);

        // The stale pre-migration standing ballot is gone.
        assertEq(congressCandidateRegistry.getStandingBallotReceipt(WALLET_ONE).voter, address(0));
        assertEq(congressCandidateRegistry.getStandingBallotReceipt(newWallet).ballotWeight, 9_000);
    }

    function test_CastBallot_RejectsMinimumSignedAllocation() public {
        (uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) = _createCycle();

        vm.warp(cycleRecord.nominationStart);
        _applyAllDefaultCandidates(cycleId);

        vm.warp(cycleRecord.votingStart);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICongressCandidateRegistry.InvalidSignedAllocation.selector, WALLET_TWO, type(int256).min
            )
        );
        _castBallot(WALLET_ONE, cycleId, _asAddressArray(WALLET_TWO), _asIntArray(type(int256).min));
    }

    function test_StandingBallot_CarriesForwardUntilChanged() public {
        (uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) = _createCycle();

        vm.warp(cycleRecord.nominationStart);
        _applyAllDefaultCandidates(cycleId);

        vm.warp(cycleRecord.votingStart);
        _castFullWeightBallot(WALLET_FIVE, cycleId, WALLET_ONE);

        vm.warp(cycleRecord.votingEnd);
        congressElectionApp.finalizeElection(cycleId);

        uint256 nextCycleId = cycleId + 1;
        ElectionTypes.CongressCycleRecord memory nextCycle = congressCandidateRegistry.getCycle(nextCycleId);
        vm.warp(nextCycle.nominationStart);

        assertEq(congressCandidateRegistry.getCycleCandidateCount(nextCycleId), 2);
        _assertCandidateStatus(nextCycleId, WALLET_ONE, ElectionTypes.CandidateStatus.Accepted);
        _assertCandidateStatus(nextCycleId, WALLET_TWO, ElectionTypes.CandidateStatus.Accepted);
        assertEq(congressCandidateRegistry.getCandidate(nextCycleId, WALLET_ONE).voteTotal, 5_500);
        assertEq(congressCandidateRegistry.getCandidate(nextCycleId, WALLET_TWO).voteTotal, 0);

        vm.warp(nextCycle.votingStart);
        _castFullWeightBallot(WALLET_FIVE, nextCycleId, WALLET_TWO);

        assertEq(congressCandidateRegistry.getCandidate(nextCycleId, WALLET_ONE).voteTotal, 0);
        assertEq(congressCandidateRegistry.getCandidate(nextCycleId, WALLET_TWO).voteTotal, 5_500);
    }

    function test_ResignSeat_PromotesRunnerUpsInOrder() public {
        (uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) = _createCycle();

        vm.warp(cycleRecord.nominationStart);
        _applyAllDefaultCandidates(cycleId);

        vm.warp(cycleRecord.votingStart);
        _castFullWeightBallot(WALLET_ONE, cycleId, WALLET_THREE);
        _castFullWeightBallot(WALLET_TWO, cycleId, WALLET_ONE);
        _castFullWeightBallot(WALLET_THREE, cycleId, WALLET_ONE);
        _castFullWeightBallot(WALLET_FOUR, cycleId, WALLET_TWO);
        _castFullWeightBallot(WALLET_FIVE, cycleId, WALLET_THREE);
        _castFullWeightBallot(WALLET_SIX, cycleId, WALLET_FOUR);

        vm.warp(cycleRecord.votingEnd);
        congressElectionApp.finalizeElection(cycleId);

        vm.prank(WALLET_ONE);
        (uint32 firstSeat, address firstReplacement) = congressElectionApp.resignSeat();
        assertEq(firstSeat, 0);
        assertEq(firstReplacement, WALLET_TWO);
        assertFalse(congressElectionApp.isCongressMember(WALLET_ONE));
        assertTrue(congressElectionApp.isCongressMember(WALLET_TWO));
        _assertSeatHolder(0, cycleId, WALLET_TWO, 3, true);
        _assertCandidateStatus(cycleId, WALLET_TWO, ElectionTypes.CandidateStatus.Elected);

        vm.prank(WALLET_THREE);
        (uint32 secondSeat, address secondReplacement) = congressElectionApp.resignSeat();
        assertEq(secondSeat, 1);
        assertEq(secondReplacement, WALLET_FOUR);
        assertFalse(congressElectionApp.isCongressMember(WALLET_THREE));
        assertTrue(congressElectionApp.isCongressMember(WALLET_FOUR));
        _assertSeatHolder(1, cycleId, WALLET_FOUR, 4, true);
        _assertCandidateStatus(cycleId, WALLET_FOUR, ElectionTypes.CandidateStatus.Elected);

        ElectionTypes.CongressOfficeTerm memory officeTerm = congressCandidateRegistry.getCurrentOfficeTerm();
        assertEq(officeTerm.occupiedSeatCount, SEAT_COUNT);
        assertEq(officeTerm.nextRunnerUpIndex, RUNNER_UP_COUNT);
    }

    function test_ApplyAsCandidate_RejectsIneligibleCandidate() public {
        (uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) = _createCycle();

        vm.warp(cycleRecord.nominationStart);
        vm.prank(WALLET_FIVE);
        vm.expectRevert(abi.encodeWithSelector(ICongressElectionApp.NotEligibleCandidate.selector, WALLET_FIVE));
        congressElectionApp.applyAsCandidate(cycleId, keccak256("candidate-5"), "ipfs://candidate-5");
    }

    function test_CongressElectionApp_HasNoRawArbitraryExecutionPath() public {
        bytes memory callData = abi.encodeWithSignature("bump()");

        (bool successExecuteBytes,) = address(congressElectionApp)
            .call(abi.encodeWithSignature("execute(address,bytes)", address(this), callData));
        (bool successExecuteValueBytes,) = address(congressElectionApp)
            .call(abi.encodeWithSignature("execute(address,uint256,bytes)", address(this), 0, callData));

        assertFalse(successExecuteBytes);
        assertFalse(successExecuteValueBytes);
        assertEq(arbitraryExecutionCount, 0);
    }

    function _createCycle() internal returns (uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) {
        uint64 nominationStart = uint64(block.timestamp + 1 days);
        uint64 votingStart = nominationStart + MINIMUM_NOMINATION_DURATION;
        uint64 votingEnd = votingStart + MINIMUM_VOTING_DURATION;

        cycleId = congressElectionApp.createElectionCycle(nominationStart, votingStart, votingEnd);
        cycleRecord = congressCandidateRegistry.getCycle(cycleId);
    }

    function _applyAllDefaultCandidates(uint256 cycleId) internal {
        _applyCandidate(cycleId, WALLET_ONE, "candidate-1");
        _applyCandidate(cycleId, WALLET_TWO, "candidate-2");
        _applyCandidate(cycleId, WALLET_THREE, "candidate-3");
        _applyCandidate(cycleId, WALLET_FOUR, "candidate-4");
    }

    function _applyCandidate(uint256 cycleId, address candidate, string memory seed) internal {
        vm.prank(candidate);
        congressElectionApp.applyAsCandidate(cycleId, keccak256(bytes(seed)), string.concat("ipfs://", seed));
    }

    function _castFullWeightBallot(address voter, uint256 cycleId, address candidate) internal {
        vm.startPrank(voter);
        congressElectionApp.castBallot(cycleId, _asAddressArray(candidate), _asIntArray(_voterWeight(voter)));
        vm.stopPrank();
    }

    function _castBallot(address voter, uint256 cycleId, address[] memory candidates, int256[] memory allocations)
        internal
    {
        vm.startPrank(voter);
        congressElectionApp.castBallot(cycleId, candidates, allocations);
        vm.stopPrank();
    }

    function _assertCandidateOutcome(
        uint256 cycleId,
        address candidate,
        ElectionTypes.CandidateStatus expectedStatus,
        uint32 expectedRank,
        int256 expectedVoteTotal
    ) internal view {
        ElectionTypes.CongressCandidateRecord memory candidateRecord =
            congressCandidateRegistry.getCandidate(cycleId, candidate);
        assertEq(uint256(candidateRecord.status), uint256(expectedStatus));
        assertEq(candidateRecord.rank, expectedRank);
        assertEq(candidateRecord.voteTotal, expectedVoteTotal);
    }

    function _assertCandidateStatus(uint256 cycleId, address candidate, ElectionTypes.CandidateStatus expectedStatus)
        internal
        view
    {
        ElectionTypes.CongressCandidateRecord memory candidateRecord =
            congressCandidateRegistry.getCandidate(cycleId, candidate);
        assertEq(uint256(candidateRecord.status), uint256(expectedStatus));
    }

    function _assertAutoIncumbentCandidate(uint256 cycleId, address candidate) internal view {
        ElectionTypes.CongressCandidateRecord memory candidateRecord =
            congressCandidateRegistry.getCandidate(cycleId, candidate);
        assertEq(uint256(candidateRecord.status), uint256(ElectionTypes.CandidateStatus.Accepted));
        assertEq(
            candidateRecord.applicationHash,
            keccak256(
                abi.encode(
                    keccak256("LiberlandCongressIncumbentCandidacy(uint256 cycleId,address incumbent)"),
                    cycleId,
                    candidate
                )
            )
        );
        assertEq(candidateRecord.applicationURI, "liberland://congress/incumbent-candidacy");
    }

    function _assertSeatHolder(
        uint32 seatIndex,
        uint256 cycleId,
        address expectedHolder,
        uint32 expectedRank,
        bool expectedFilledFromRunnerUp
    ) internal view {
        ElectionTypes.CongressSeatRecord memory seatRecord = congressCandidateRegistry.getSeatRecord(seatIndex);
        assertEq(seatRecord.cycleId, cycleId);
        assertEq(seatRecord.holder, expectedHolder);
        assertEq(seatRecord.seatIndex, seatIndex);
        assertEq(seatRecord.sourceRank, expectedRank);
        assertEq(seatRecord.filledFromRunnerUp, expectedFilledFromRunnerUp);
    }

    function _voterWeight(address voter) internal view returns (int256 weight) {
        return int256(uint256(votingPowerPolicy.votingPower(voter)));
    }

    function _asAddressArray(address first) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = first;
    }

    function _asAddressArray(address first, address second) internal pure returns (address[] memory values) {
        values = new address[](2);
        values[0] = first;
        values[1] = second;
    }

    function _asAddressArray(address first, address second, address third)
        internal
        pure
        returns (address[] memory values)
    {
        values = new address[](3);
        values[0] = first;
        values[1] = second;
        values[2] = third;
    }

    function _asIntArray(int256 first) internal pure returns (int256[] memory values) {
        values = new int256[](1);
        values[0] = first;
    }

    function _asIntArray(int256 first, int256 second) internal pure returns (int256[] memory values) {
        values = new int256[](2);
        values[0] = first;
        values[1] = second;
    }

    function _asIntArray(int256 first, int256 second, int256 third) internal pure returns (int256[] memory values) {
        values = new int256[](3);
        values[0] = first;
        values[1] = second;
        values[2] = third;
    }

    function _registerCitizen(bytes32 personId, address wallet, uint256 activeStake) internal {
        _setIdentityRecord(personId, _defaultIdentityInput());
        _setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        _increaseStake(personId, activeStake);
    }

    function _setIdentityRecord(bytes32 personId, IdentityTypes.IdentityRecordInput memory input) internal {
        vm.prank(address(identityAuthority));
        identityRegistry.setIdentityRecord(personId, input);
    }

    function _setWalletLink(bytes32 personId, address wallet, IdentityTypes.WalletLinkStatus status) internal {
        vm.prank(address(identityAuthority));
        identityRegistry.setWalletLink(personId, wallet, status);
    }

    function _increaseStake(bytes32 personId, uint256 amount) internal {
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(personId, amount);
    }

    function _defaultIdentityInput() internal pure returns (IdentityTypes.IdentityRecordInput memory input) {
        return IdentityTypes.IdentityRecordInput({
            metadataHash: keccak256("citizen-metadata"),
            metadataURI: "ipfs://citizen",
            verificationStatus: IdentityTypes.VerificationStatus.Verified,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
            ageClass: IdentityTypes.AgeClass.Adult,
            correctionFlag: false,
            finalSuspension: false
        });
    }
}
