// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ReferendumApp} from "../../contracts/apps/ReferendumApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {ICongressElectionPolicy} from "../../contracts/interfaces/ICongressElectionPolicy.sol";
import {ICitizenEligibilityPolicy} from "../../contracts/interfaces/ICitizenEligibilityPolicy.sol";
import {IGovernanceRouter} from "../../contracts/interfaces/IGovernanceRouter.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {ILegislationRegistry} from "../../contracts/interfaces/ILegislationRegistry.sol";
import {IReferendumApp} from "../../contracts/interfaces/IReferendumApp.sol";
import {IReferendumPolicy} from "../../contracts/interfaces/IReferendumPolicy.sol";
import {IReferendumRegistry} from "../../contracts/interfaces/IReferendumRegistry.sol";
import {IStakeRegistry} from "../../contracts/interfaces/IStakeRegistry.sol";
import {IVotingPowerPolicy} from "../../contracts/interfaces/IVotingPowerPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockCongressAuthority} from "../../contracts/mocks/MockCongressAuthority.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {CandidateEligibilityPolicy} from "../../contracts/policies/CandidateEligibilityPolicy.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {CongressElectionPolicy} from "../../contracts/policies/CongressElectionPolicy.sol";
import {ReferendumPolicy} from "../../contracts/policies/ReferendumPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LegislationRegistry} from "../../contracts/registries/LegislationRegistry.sol";
import {ReferendumRegistry} from "../../contracts/registries/ReferendumRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LegislationTypes} from "../../contracts/types/LegislationTypes.sol";
import {ReferendumTypes} from "../../contracts/types/ReferendumTypes.sol";

/// @title Milestone3ReferendaTest
/// @notice Covers referendum proposal, mutable fixed-weight voting, queued enactment, and constitutional routing.
contract Milestone3ReferendaTest is Test {
    struct ExpectedReferendumOutcome {
        ReferendumTypes.ReferendumStatus status;
        bytes32 measureId;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 forVoterCount;
        uint256 againstVoterCount;
        uint256 turnout;
        uint256 quorumRequired;
        uint256 headcountQuorumRequired;
        uint256 electorateVotingPower;
        bool quorumMet;
        bool passed;
    }

    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint256 internal constant MINIMUM_CANDIDATE_STAKE = 6_000;
    uint256 internal constant CANDIDATE_BOND_REQUIREMENT = 6_000;
    uint256 internal constant CITIZEN_PROPOSAL_BOND = 6_000;
    uint64 internal constant MINIMUM_VOTING_DURATION = 3 days;
    uint32 internal constant CONGRESS_SEAT_COUNT = 2;
    uint32 internal constant CONGRESS_RUNNER_UP_COUNT = 2;
    uint32 internal constant CONGRESS_MAX_CANDIDATE_COUNT = 8;
    uint64 internal constant MINIMUM_NOMINATION_DURATION = 2 days;
    uint64 internal constant MINIMUM_ELECTION_VOTING_DURATION = 3 days;
    uint64 internal constant MAX_SCHEDULE_LEAD_TIME = 14 days;
    uint64 internal constant ELECTION_CYCLE_DURATION = 5 days;
    uint256 internal constant CITIZEN_QUORUM = 10_000;
    uint256 internal constant CONGRESS_QUORUM = 8_000;
    uint256 internal constant CONSTITUTIONAL_FOR_VOTER_QUORUM = 2;
    uint16 internal constant CONSTITUTIONAL_FOR_STAKE_BPS = 5_000;

    bytes32 internal constant PERSON_ONE_ID = bytes32(uint256(1));
    bytes32 internal constant PERSON_TWO_ID = bytes32(uint256(2));
    bytes32 internal constant PERSON_THREE_ID = bytes32(uint256(3));

    address internal constant WALLET_ONE = address(0xA11CE);
    address internal constant WALLET_TWO = address(0xB0B);
    address internal constant WALLET_THREE = address(0xCAFE);

    uint256 internal arbitraryExecutionCount;

    ConstitutionKernel internal kernel;
    ActionTimelock internal timelock;
    GovernanceRouter internal router;
    MockModule internal identityAuthority;
    MockModule internal stakeAuthority;
    MockCongressAuthority internal congressAuthority;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    CandidateEligibilityPolicy internal candidateEligibilityPolicy;
    VotingPowerPolicy internal votingPowerPolicy;
    CongressElectionPolicy internal congressElectionPolicy;
    LegislationRegistry internal legislationRegistry;
    ReferendumRegistry internal referendumRegistry;
    ReferendumPolicy internal referendumPolicy;
    ReferendumApp internal referendumApp;

    function setUp() public {
        _deployFoundation();
        _deployReferendumSystem();
        _registerDefaultCitizens();
        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();
    }

    function _deployFoundation() internal {
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(address(kernel));
        router = new GovernanceRouter(address(kernel), address(this));

        identityAuthority = new MockModule(keccak256("identity-authority"));
        stakeAuthority = new MockModule(keccak256("stake-authority"));
        congressAuthority = new MockCongressAuthority();

        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));
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

    function _deployReferendumSystem() internal {
        legislationRegistry = new LegislationRegistry(address(kernel));
        referendumRegistry = new ReferendumRegistry(address(kernel));
        congressElectionPolicy = _deployCongressElectionPolicy(ELECTION_CYCLE_DURATION);
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY, address(legislationRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_POLICY, address(congressElectionPolicy));
        referendumPolicy = new ReferendumPolicy(
            address(citizenEligibilityPolicy),
            address(votingPowerPolicy),
            address(congressAuthority),
            MINIMUM_VOTING_DURATION,
            0,
            0,
            CITIZEN_QUORUM,
            CONGRESS_QUORUM,
            CITIZEN_PROPOSAL_BOND,
            CONSTITUTIONAL_FOR_VOTER_QUORUM,
            CONSTITUTIONAL_FOR_STAKE_BPS
        );
        referendumApp = new ReferendumApp(
            address(identityRegistry),
            address(legislationRegistry),
            address(referendumRegistry),
            address(referendumPolicy),
            address(router),
            address(votingPowerPolicy)
        );

        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(referendumApp));

        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, address(referendumApp));
    }

    function _deployCongressElectionPolicy(uint64 cycleDuration) internal returns (CongressElectionPolicy policy) {
        policy = new CongressElectionPolicy(
            address(candidateEligibilityPolicy),
            address(votingPowerPolicy),
            CONGRESS_SEAT_COUNT,
            CONGRESS_RUNNER_UP_COUNT,
            CONGRESS_MAX_CANDIDATE_COUNT,
            CANDIDATE_BOND_REQUIREMENT,
            MINIMUM_NOMINATION_DURATION,
            MINIMUM_ELECTION_VOTING_DURATION,
            MAX_SCHEDULE_LEAD_TIME,
            cycleDuration
        );
    }

    function _registerDefaultCitizens() internal {
        _registerCitizen(PERSON_ONE_ID, WALLET_ONE, 6_000);
        _registerCitizen(PERSON_TWO_ID, WALLET_TWO, 5_000);
        _registerCitizen(PERSON_THREE_ID, WALLET_THREE, 8_000);
    }

    function bump() external {
        arbitraryExecutionCount += 1;
    }

    function test_Milestone3InterfacesExposeSelectors() public pure {
        assertTrue(IActionTimelock.executeAction.selector != bytes4(0));
        assertTrue(ILegislationRegistry.recordEnactment.selector != bytes4(0));
        assertTrue(IGovernanceRouter.routeAction.selector != bytes4(0));
        assertTrue(IReferendumRegistry.createReferendum.selector != bytes4(0));
        assertTrue(IReferendumRegistry.recordVote.selector != bytes4(0));
        assertTrue(IReferendumPolicy.evaluateOutcome.selector != bytes4(0));
        assertTrue(IReferendumApp.createCitizenLegislationReferendum.selector != bytes4(0));
        assertTrue(IReferendumApp.createCitizenCongressElectionPolicyReferendum.selector != bytes4(0));
        assertTrue(IReferendumApp.createCongressConstitutionalAmendmentReferendum.selector != bytes4(0));
        assertTrue(IReferendumApp.finalizeReferendum.selector != bytes4(0));
        assertTrue(ICongressElectionPolicy.cycleDuration.selector != bytes4(0));
        assertTrue(ICitizenEligibilityPolicy.isCitizenInGoodStanding.selector != bytes4(0));
        assertTrue(IIdentityRegistry.resolveWalletToPersonId.selector != bytes4(0));
        assertTrue(IStakeRegistry.activeStakeOf.selector != bytes4(0));
        assertTrue(IVotingPowerPolicy.votingPower.selector != bytes4(0));
    }

    function test_CreateReferendum_StoresCitizenProposalPathAndMetadata() public {
        ReferendumTypes.LegislationProposal memory proposal = _defaultProposal("measure-1", "proposal-1", "law-1");

        vm.prank(WALLET_ONE);
        bytes32 referendumId = referendumApp.createCitizenLegislationReferendum(proposal);

        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        _assertCreatedReferendum(referendumId, referendumRecord, proposal, PERSON_ONE_ID);
    }

    function test_CreateReferendum_RejectsInvalidCongressProposalOrigin() public {
        ReferendumTypes.LegislationProposal memory proposal = _defaultProposal("measure-2", "proposal-2", "law-2");

        vm.prank(WALLET_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IReferendumApp.InvalidProposerOrigin.selector, WALLET_ONE, ReferendumTypes.ProposalOrigin.Congress
            )
        );
        referendumApp.createCongressLegislationReferendum(proposal);
    }

    function test_CreateCongressConstitutionalReferendum_UsesDedicatedClass() public {
        ReferendumTypes.LegislationProposal memory proposal =
            _constitutionalProposal("measure-2b", "proposal-2b", "constitution-2b");
        congressAuthority.setMember(WALLET_TWO, true);

        vm.prank(WALLET_TWO);
        bytes32 referendumId = referendumApp.createCongressConstitutionalAmendmentReferendum(proposal);

        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        assertEq(
            uint256(referendumRecord.referendumClass), uint256(ReferendumTypes.ReferendumClass.ConstitutionalAmendment)
        );
        assertEq(uint256(referendumRecord.proposalOrigin), uint256(ReferendumTypes.ProposalOrigin.Congress));
        assertEq(referendumRecord.proposerReference, bytes32(uint256(uint160(WALLET_TWO))));
    }

    function test_VoteAndFinalize_SucceedsWhenQuorumAndPassConditionsAreMet() public {
        ReferendumTypes.LegislationProposal memory proposal = _defaultProposal("measure-3", "proposal-3", "law-3");
        bytes32 referendumId = _createCitizenReferendum(WALLET_ONE, proposal);

        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        vm.prank(WALLET_TWO);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(referendumId);

        _assertReferendumOutcome(
            referendumId,
            ExpectedReferendumOutcome({
                status: ReferendumTypes.ReferendumStatus.Succeeded,
                measureId: proposal.proposedMeasureId,
                forVotes: 11_000,
                againstVotes: 0,
                forVoterCount: 2,
                againstVoterCount: 0,
                turnout: 11_000,
                quorumRequired: CITIZEN_QUORUM,
                headcountQuorumRequired: 0,
                electorateVotingPower: 0,
                quorumMet: true,
                passed: true
            })
        );

        ReferendumTypes.ReferendumResult memory referendumResult = referendumRegistry.getReferendumResult(referendumId);
        assertFalse(legislationRegistry.legislationExists(proposal.proposedMeasureId));
        assertTrue(referendumResult.enactmentActionId != bytes32(0));
        assertEq(
            uint256(timelock.getActionState(referendumResult.enactmentActionId)),
            uint256(GovernanceTypes.ActionState.Queued)
        );

        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(referendumResult.enactmentActionId);
        vm.warp(actionRecord.earliestExecutionTime);
        timelock.executeAction(referendumResult.enactmentActionId);

        LegislationTypes.LegislationRecord memory legislationRecord =
            legislationRegistry.getLegislationRecord(proposal.proposedMeasureId);
        _assertLegislationRecord(legislationRecord, proposal, referendumId, PERSON_ONE_ID);
    }

    function test_CongressElectionPolicyReferendum_QueuesAndExecutesPolicyPointerUpdate() public {
        CongressElectionPolicy newPolicy = _deployCongressElectionPolicy(7 days);
        ReferendumTypes.CongressElectionPolicyProposal memory proposal = ReferendumTypes.CongressElectionPolicyProposal({
            proposalMetadataHash: keccak256("proposal-election-policy"),
            proposalId: keccak256("change-election-cycle-duration"),
            newPolicy: address(newPolicy),
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + MINIMUM_VOTING_DURATION)
        });

        vm.prank(WALLET_ONE);
        bytes32 referendumId = referendumApp.createCitizenCongressElectionPolicyReferendum(proposal);

        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        assertEq(
            uint256(referendumRecord.referendumClass), uint256(ReferendumTypes.ReferendumClass.CongressElectionPolicy)
        );
        assertEq(referendumRecord.targetModule, KernelModuleIds.CONGRESS_ELECTION_POLICY);
        assertEq(referendumRecord.proposedModuleAddress, address(newPolicy));

        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_THREE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(referendumId);

        ReferendumTypes.ReferendumResult memory result = referendumRegistry.getReferendumResult(referendumId);
        assertTrue(result.passed);
        assertTrue(result.enactmentActionId != bytes32(0));

        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(result.enactmentActionId);
        assertEq(uint256(actionRecord.actionType), uint256(GovernanceTypes.ActionType.ModulePointerUpdate));
        assertEq(actionRecord.targetModule, KernelModuleIds.CONGRESS_ELECTION_POLICY);

        vm.warp(actionRecord.earliestExecutionTime);
        timelock.executeAction(result.enactmentActionId);

        assertEq(kernel.getModule(KernelModuleIds.CONGRESS_ELECTION_POLICY), address(newPolicy));
        assertEq(
            ICongressElectionPolicy(kernel.getModule(KernelModuleIds.CONGRESS_ELECTION_POLICY)).cycleDuration(), 7 days
        );
    }

    function test_FinalizeReferendum_FailsWhenQuorumIsNotMet() public {
        ReferendumTypes.LegislationProposal memory proposal = _defaultProposal("measure-4", "proposal-4", "law-4");
        bytes32 referendumId = _createCitizenReferendum(WALLET_ONE, proposal);

        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(referendumId);

        _assertReferendumOutcome(
            referendumId,
            ExpectedReferendumOutcome({
                status: ReferendumTypes.ReferendumStatus.Defeated,
                measureId: bytes32(0),
                forVotes: 6_000,
                againstVotes: 0,
                forVoterCount: 1,
                againstVoterCount: 0,
                turnout: 6_000,
                quorumRequired: CITIZEN_QUORUM,
                headcountQuorumRequired: 0,
                electorateVotingPower: 0,
                quorumMet: false,
                passed: false
            })
        );
        assertFalse(legislationRegistry.legislationExists(proposal.proposedMeasureId));
    }

    function test_FinalizeReferendum_FailsWhenPassConditionIsNotMet() public {
        ReferendumTypes.LegislationProposal memory proposal = _defaultProposal("measure-5", "proposal-5", "law-5");
        bytes32 referendumId = _createCitizenReferendum(WALLET_ONE, proposal);

        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        vm.prank(WALLET_THREE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.Against);

        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(referendumId);

        _assertReferendumOutcome(
            referendumId,
            ExpectedReferendumOutcome({
                status: ReferendumTypes.ReferendumStatus.Defeated,
                measureId: bytes32(0),
                forVotes: 6_000,
                againstVotes: 8_000,
                forVoterCount: 1,
                againstVoterCount: 1,
                turnout: 14_000,
                quorumRequired: CITIZEN_QUORUM,
                headcountQuorumRequired: 0,
                electorateVotingPower: 0,
                quorumMet: true,
                passed: false
            })
        );
        assertFalse(legislationRegistry.legislationExists(proposal.proposedMeasureId));
    }

    function test_CastVote_AllowsOptionChangesWhileKeepingStoredWeight() public {
        ReferendumTypes.LegislationProposal memory proposal = _defaultProposal("measure-6", "proposal-6", "law-6");
        bytes32 referendumId = _createCitizenReferendum(WALLET_ONE, proposal);

        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        _increaseStake(PERSON_ONE_ID, 2_000);

        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.Against);

        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        ReferendumTypes.VoteReceipt memory receipt = referendumRegistry.getVoteReceipt(referendumId, WALLET_ONE);
        assertEq(uint256(receipt.option), uint256(ReferendumTypes.VoteOption.Against));
        assertEq(receipt.weight, 6_000);
        assertEq(referendumRecord.forVotes, 0);
        assertEq(referendumRecord.againstVotes, 6_000);
        assertEq(referendumRecord.forVoterCount, 0);
        assertEq(referendumRecord.againstVoterCount, 1);
        assertEq(referendumRecord.voterCount, 1);
    }

    function test_ReferendumApp_HasNoRawArbitraryExecutionPath() public {
        bytes memory callData = abi.encodeWithSignature("bump()");

        (bool successExecuteBytes,) =
            address(referendumApp).call(abi.encodeWithSignature("execute(address,bytes)", address(this), callData));
        (bool successExecuteValueBytes,) = address(referendumApp)
            .call(abi.encodeWithSignature("execute(address,uint256,bytes)", address(this), 0, callData));

        assertFalse(successExecuteBytes);
        assertFalse(successExecuteValueBytes);
        assertEq(arbitraryExecutionCount, 0);
    }

    function _createCitizenReferendum(address proposer, ReferendumTypes.LegislationProposal memory proposal)
        internal
        returns (bytes32 referendumId)
    {
        vm.prank(proposer);
        referendumId = referendumApp.createCitizenLegislationReferendum(proposal);
    }

    function _assertCreatedReferendum(
        bytes32 referendumId,
        ReferendumTypes.ReferendumRecord memory referendumRecord,
        ReferendumTypes.LegislationProposal memory proposal,
        bytes32 proposerReference
    ) internal pure {
        assertEq(referendumRecord.referendumId, referendumId);
        assertEq(uint256(referendumRecord.referendumClass), uint256(ReferendumTypes.ReferendumClass.Legislation));
        assertEq(uint256(referendumRecord.proposalOrigin), uint256(ReferendumTypes.ProposalOrigin.Citizen));
        assertEq(referendumRecord.proposedMeasureId, proposal.proposedMeasureId);
        assertEq(referendumRecord.proposalMetadataHash, proposal.proposalMetadataHash);
        assertEq(referendumRecord.legislationTextHash, proposal.legislationTextHash);
        assertEq(referendumRecord.proposerReference, proposerReference);
        assertEq(referendumRecord.startTime, proposal.startTime);
        assertEq(referendumRecord.endTime, proposal.endTime);
        assertEq(uint256(referendumRecord.status), uint256(ReferendumTypes.ReferendumStatus.Active));
    }

    function _assertReferendumOutcome(bytes32 referendumId, ExpectedReferendumOutcome memory expected) internal view {
        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        ReferendumTypes.ReferendumResult memory referendumResult = referendumRegistry.getReferendumResult(referendumId);

        assertEq(uint256(referendumRecord.status), uint256(expected.status));
        assertEq(referendumRecord.enactedMeasureId, expected.measureId);
        assertEq(referendumRecord.forVotes, expected.forVotes);
        assertEq(referendumRecord.againstVotes, expected.againstVotes);
        assertEq(referendumRecord.forVoterCount, expected.forVoterCount);
        assertEq(referendumRecord.againstVoterCount, expected.againstVoterCount);
        assertEq(referendumResult.turnout, expected.turnout);
        assertEq(referendumResult.quorumRequired, expected.quorumRequired);
        assertEq(referendumResult.headcountQuorumRequired, expected.headcountQuorumRequired);
        assertEq(referendumResult.electorateVotingPower, expected.electorateVotingPower);
        assertEq(referendumResult.quorumMet, expected.quorumMet);
        assertEq(referendumResult.passed, expected.passed);
        assertEq(referendumResult.forVotes, expected.forVotes);
        assertEq(referendumResult.againstVotes, expected.againstVotes);
        assertEq(referendumResult.forVoterCount, expected.forVoterCount);
        assertEq(referendumResult.againstVoterCount, expected.againstVoterCount);
    }

    function _assertLegislationRecord(
        LegislationTypes.LegislationRecord memory legislationRecord,
        ReferendumTypes.LegislationProposal memory proposal,
        bytes32 referendumId,
        bytes32 proposerReference
    ) internal pure {
        assertEq(legislationRecord.measureId, proposal.proposedMeasureId);
        assertEq(uint256(legislationRecord.tier), uint256(LegislationTypes.LegislationTier.OrdinaryLaw));
        assertEq(legislationRecord.textHash, proposal.legislationTextHash);
        assertEq(legislationRecord.proposerReference, proposerReference);
        assertEq(legislationRecord.enactedByReferendumId, referendumId);
        assertEq(legislationRecord.amendsMeasureId, bytes32(0));
        assertTrue(legislationRecord.active);
        assertFalse(legislationRecord.repealed);
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

    function _defaultProposal(string memory measureSeed, string memory proposalSeed, string memory lawSeed)
        internal
        view
        returns (ReferendumTypes.LegislationProposal memory proposal)
    {
        return ReferendumTypes.LegislationProposal({
            proposalMetadataHash: keccak256(bytes(proposalSeed)),
            proposedMeasureId: keccak256(bytes(measureSeed)),
            amendsMeasureId: bytes32(0),
            legislationTextHash: keccak256(bytes(lawSeed)),
            legislationTier: LegislationTypes.LegislationTier.OrdinaryLaw,
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + MINIMUM_VOTING_DURATION)
        });
    }

    function _constitutionalProposal(string memory measureSeed, string memory proposalSeed, string memory lawSeed)
        internal
        view
        returns (ReferendumTypes.LegislationProposal memory proposal)
    {
        proposal = _defaultProposal(measureSeed, proposalSeed, lawSeed);
        proposal.legislationTier = LegislationTypes.LegislationTier.ConstitutionalLaw;
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
