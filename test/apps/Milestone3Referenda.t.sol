// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ReferendumApp} from "../../contracts/apps/ReferendumApp.sol";
import {TreasuryVault} from "../../contracts/apps/TreasuryVault.sol";
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
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {MockCongressAuthority} from "../../contracts/mocks/MockCongressAuthority.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {CandidateEligibilityPolicy} from "../../contracts/policies/CandidateEligibilityPolicy.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {CongressElectionPolicy} from "../../contracts/policies/CongressElectionPolicy.sol";
import {ReferendumPolicy} from "../../contracts/policies/ReferendumPolicy.sol";
import {ITreasurySpendingPolicy} from "../../contracts/interfaces/ITreasurySpendingPolicy.sol";
import {TreasurySpendingPolicy} from "../../contracts/policies/TreasurySpendingPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {BudgetEnvelopeRegistry} from "../../contracts/registries/BudgetEnvelopeRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LegislationRegistry} from "../../contracts/registries/LegislationRegistry.sol";
import {ReferendumRegistry} from "../../contracts/registries/ReferendumRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LegislationTypes} from "../../contracts/types/LegislationTypes.sol";
import {ReferendumTypes} from "../../contracts/types/ReferendumTypes.sol";
import {SenateTypes} from "../../contracts/types/SenateTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";

contract MockSenateAppForReferendumFinalization {
    mapping(bytes32 referendumId => SenateTypes.ReferendumVetoRecord record) private _referendumVetoRecords;
    mapping(bytes32 actionId => SenateTypes.ActionCancellationRecord record) private _actionCancellationRecords;

    function openReferendumVeto(bytes32 referendumId, uint64 deadline) external {
        _referendumVetoRecords[referendumId] = SenateTypes.ReferendumVetoRecord({
            referendumId: referendumId,
            createdAt: uint64(block.timestamp),
            deadline: deadline,
            finalizedAt: 0,
            vetoedAt: 0,
            supportSnapshot: 0,
            presidentProxySupportSnapshot: 0,
            exists: true,
            finalized: false,
            vetoed: false
        });
    }

    function finalizeReferendumVeto(bytes32 referendumId) external {
        SenateTypes.ReferendumVetoRecord storage record = _referendumVetoRecords[referendumId];
        record.finalized = true;
        record.finalizedAt = uint64(block.timestamp);
    }

    function getReferendumVetoRecord(bytes32 referendumId)
        external
        view
        returns (SenateTypes.ReferendumVetoRecord memory record)
    {
        return _referendumVetoRecords[referendumId];
    }

    function getActionCancellationRecord(bytes32 actionId)
        external
        view
        returns (SenateTypes.ActionCancellationRecord memory record)
    {
        return _actionCancellationRecords[actionId];
    }

    function getDisbursementSuspension(bytes32)
        external
        pure
        returns (SenateTypes.DisbursementSuspension memory suspension)
    {
        return suspension;
    }
}

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
    uint64 internal constant MINIMUM_VOTING_DURATION = 7 days;
    uint64 internal constant STANDARD_ADOPTION_DELAY = 7 days;
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
    uint16 internal constant CONSTITUTIONAL_FOR_STAKE_BPS = 6_500;

    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");

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
    TreasuryVault internal treasuryVault;
    LLMToken internal llmToken;
    BudgetEnvelopeRegistry internal budgetEnvelopeRegistry;
    TreasurySpendingPolicy internal treasurySpendingPolicy;
    ReferendumPolicy internal referendumPolicy;
    ReferendumApp internal referendumApp;
    MockSenateAppForReferendumFinalization internal mockSenateApp;

    function setUp() public {
        _deployFoundation();
        _deployReferendumSystem();
        _registerDefaultCitizens();
        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();
    }

    function _deployFoundation() internal {
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(address(kernel), _defaultDelayConfig());
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

    function _defaultDelayConfig() internal pure returns (GovernanceTypes.TimelockDelayConfig memory config) {
        config = GovernanceTypes.TimelockDelayConfig({
            moduleGovernanceDelay: 2 days,
            treasuryBudgetApprovalDelay: 1 days,
            legislationEnactmentDelay: 1 days,
            treasuryDisbursementDelay: 2 days,
            defaultExecutionWindow: 7 days
        });
    }

    function _deployReferendumSystem() internal {
        legislationRegistry = new LegislationRegistry(address(kernel));
        referendumRegistry = new ReferendumRegistry(address(kernel));
        treasuryVault = new TreasuryVault(address(kernel));
        llmToken = new LLMToken();
        budgetEnvelopeRegistry = new BudgetEnvelopeRegistry(address(kernel));
        congressElectionPolicy = _deployCongressElectionPolicy(ELECTION_CYCLE_DURATION);
        // Budget-approval referenda fail-fast if the asset is outside the spending-policy allowlist, so register a
        // policy that allows the budget asset (LLM) used by the budget test.
        ITreasurySpendingPolicy.AssetSpendingLimit[] memory spendingLimits =
            new ITreasurySpendingPolicy.AssetSpendingLimit[](1);
        spendingLimits[0] = ITreasurySpendingPolicy.AssetSpendingLimit({
            asset: address(llmToken), clerkOperationsLimit: 1_000 ether, clerkSalaryLimit: 1_000 ether
        });
        treasurySpendingPolicy = new TreasurySpendingPolicy(FINANCE_OFFICE_ID, spendingLimits);
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY, address(legislationRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.TREASURY_VAULT, address(treasuryVault));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY, address(budgetEnvelopeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.TREASURY_SPENDING_POLICY, address(treasurySpendingPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_POLICY, address(congressElectionPolicy));
        referendumPolicy = new ReferendumPolicy(
            address(citizenEligibilityPolicy),
            address(votingPowerPolicy),
            address(congressAuthority),
            address(llmToken),
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
        mockSenateApp = new MockSenateAppForReferendumFinalization();

        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(referendumApp));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(mockSenateApp));

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
        assertTrue(IReferendumApp.createCongressBudgetApprovalReferendum.selector != bytes4(0));
        assertTrue(IReferendumApp.createCitizenModuleGovernanceReferendum.selector != bytes4(0));
        assertTrue(IReferendumApp.createCongressModuleGovernanceReferendum.selector != bytes4(0));
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

    function test_CreateReferendum_TransfersProposalFeeToTreasury() public {
        uint256 proposalFee = 1 ether;
        ReferendumPolicy feePolicy = new ReferendumPolicy(
            address(citizenEligibilityPolicy),
            address(votingPowerPolicy),
            address(congressAuthority),
            address(llmToken),
            proposalFee,
            0,
            CITIZEN_QUORUM,
            CONGRESS_QUORUM,
            CITIZEN_PROPOSAL_BOND,
            CONSTITUTIONAL_FOR_VOTER_QUORUM,
            CONSTITUTIONAL_FOR_STAKE_BPS
        );
        ReferendumApp feeApp = new ReferendumApp(
            address(identityRegistry),
            address(legislationRegistry),
            address(referendumRegistry),
            address(feePolicy),
            address(router),
            address(votingPowerPolicy)
        );
        vm.prank(address(timelock));
        kernel.governanceUpdateModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(feeApp));

        ReferendumTypes.LegislationProposal memory proposal = _defaultProposal("measure-fee", "proposal-fee", "law-fee");
        uint256 treasuryBalanceBefore = llmToken.balanceOf(address(treasuryVault));

        llmToken.mint(WALLET_ONE, proposalFee);
        vm.prank(WALLET_ONE);
        llmToken.approve(address(feeApp), proposalFee);
        vm.prank(WALLET_ONE);
        bytes32 referendumId = feeApp.createCitizenLegislationReferendum(proposal);

        assertEq(llmToken.balanceOf(address(treasuryVault)), treasuryBalanceBefore + proposalFee);
        assertEq(llmToken.balanceOf(WALLET_ONE), 0);
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

    function test_CreateCongressConstitutionalReferendum_RevertsForEmergencySchedule() public {
        ReferendumTypes.LegislationProposal memory proposal =
            _constitutionalProposal("measure-2c", "proposal-2c", "constitution-2c");
        proposal.endTime = uint64(block.timestamp + 3 days);
        proposal.adoptionDelay = 0;
        proposal.emergency = true;
        congressAuthority.setMember(WALLET_TWO, true);

        vm.prank(WALLET_TWO);
        vm.expectRevert(
            abi.encodeWithSelector(
                IReferendumApp.InvalidEmergencyReferendumClass.selector,
                ReferendumTypes.ReferendumClass.ConstitutionalAmendment
            )
        );
        referendumApp.createCongressConstitutionalAmendmentReferendum(proposal);
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
            endTime: uint64(block.timestamp + MINIMUM_VOTING_DURATION),
            adoptionDelay: STANDARD_ADOPTION_DELAY
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

    function test_ModuleGovernanceReferendum_QueuesAndExecutesModuleRegistration() public {
        bytes32 spaceshipRegistry = keccak256("registry.spaceship");
        MockModule newModule = new MockModule(keccak256("spaceship-registry"));
        ReferendumTypes.ModuleGovernanceProposal memory proposal = _defaultModuleGovernanceProposal(
            "proposal-register-spaceship", "module-register-spaceship", spaceshipRegistry, address(newModule), true
        );

        vm.prank(WALLET_ONE);
        bytes32 referendumId = referendumApp.createCitizenModuleGovernanceReferendum(proposal);

        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        assertEq(uint256(referendumRecord.referendumClass), uint256(ReferendumTypes.ReferendumClass.ModuleGovernance));
        assertEq(referendumRecord.targetModule, spaceshipRegistry);
        assertEq(referendumRecord.proposedModuleAddress, address(newModule));
        assertTrue(referendumRecord.registerNewModule);

        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_THREE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(referendumId);

        ReferendumTypes.ReferendumResult memory result = referendumRegistry.getReferendumResult(referendumId);
        assertTrue(result.passed);

        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(result.enactmentActionId);
        assertEq(uint256(actionRecord.actionType), uint256(GovernanceTypes.ActionType.ModuleRegistration));
        assertEq(actionRecord.targetModule, spaceshipRegistry);

        vm.warp(actionRecord.earliestExecutionTime);
        timelock.executeAction(result.enactmentActionId);

        assertEq(kernel.getModule(spaceshipRegistry), address(newModule));
    }

    function test_ModuleGovernanceReferendum_QueuesAndExecutesModulePointerUpdate() public {
        congressAuthority.setMember(WALLET_TWO, true);
        MockModule replacementBudgetRegistry = new MockModule(keccak256("replacement-budget-registry"));
        ReferendumTypes.ModuleGovernanceProposal memory proposal = _defaultModuleGovernanceProposal(
            "proposal-replace-budget",
            "module-replace-budget",
            KernelModuleIds.BUDGET_ENVELOPE_REGISTRY,
            address(replacementBudgetRegistry),
            false
        );

        vm.prank(WALLET_TWO);
        bytes32 referendumId = referendumApp.createCongressModuleGovernanceReferendum(proposal);

        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_THREE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(referendumId);

        ReferendumTypes.ReferendumResult memory result = referendumRegistry.getReferendumResult(referendumId);
        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(result.enactmentActionId);
        assertEq(uint256(actionRecord.actionType), uint256(GovernanceTypes.ActionType.ModulePointerUpdate));
        assertEq(actionRecord.targetModule, KernelModuleIds.BUDGET_ENVELOPE_REGISTRY);

        vm.warp(actionRecord.earliestExecutionTime);
        timelock.executeAction(result.enactmentActionId);

        assertEq(kernel.getModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY), address(replacementBudgetRegistry));
    }

    function test_SensitiveModuleGovernanceReferendum_TakesSnapshotAndFailsWithoutSupermajority() public {
        MockModule replacementLegislationRegistry = new MockModule(keccak256("replacement-legislation-registry"));
        ReferendumTypes.ModuleGovernanceProposal memory proposal = _defaultModuleGovernanceProposal(
            "proposal-repoint-legislation",
            "module-repoint-legislation",
            KernelModuleIds.LEGISLATION_REGISTRY,
            address(replacementLegislationRegistry),
            false
        );

        vm.prank(WALLET_ONE);
        bytes32 referendumId = referendumApp.createCitizenModuleGovernanceReferendum(proposal);

        // A rule-defining `registry.*` target flags the supermajority path and snapshots the electorate.
        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        assertTrue(referendumRecord.requiresSupermajority);
        assertEq(referendumRecord.electorateHeadcountSnapshot, 3);
        assertEq(referendumRecord.electorateVotingPowerSnapshot, 19_000);

        // 11_000 For / 8_000 Against of 19_000 cast clears the ordinary absolute quorum (For > Against and
        // turnout >= CITIZEN_QUORUM) but is only ~58% of cast, below the 65% supermajority prong.
        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_TWO);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_THREE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.Against);

        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(referendumId);

        ReferendumTypes.ReferendumResult memory result = referendumRegistry.getReferendumResult(referendumId);
        assertEq(result.forVotes, 11_000);
        assertEq(result.againstVotes, 8_000);
        assertGe(result.turnout, CITIZEN_QUORUM);
        assertGt(result.forVotes, result.againstVotes);
        assertEq(result.headcountQuorumRequired, 2);
        assertEq(result.quorumRequired, 12_350);
        assertFalse(result.quorumMet);
        assertFalse(result.passed);

        ReferendumTypes.ReferendumRecord memory finalizedRecord = referendumRegistry.getReferendum(referendumId);
        assertEq(uint256(finalizedRecord.status), uint256(ReferendumTypes.ReferendumStatus.Defeated));
        assertEq(result.enactmentActionId, bytes32(0));
        assertEq(kernel.getModule(KernelModuleIds.LEGISLATION_REGISTRY), address(legislationRegistry));
    }

    function test_SensitiveModuleGovernanceReferendum_PassesUnderDoubleThresholdAndExecutesRepoint() public {
        MockModule replacementStakeAuthority = new MockModule(keccak256("replacement-stake-authority"));
        ReferendumTypes.ModuleGovernanceProposal memory proposal = _defaultModuleGovernanceProposal(
            "proposal-repoint-stake-authority",
            "module-repoint-stake-authority",
            KernelModuleIds.STAKE_REGISTRY_AUTHORITY,
            address(replacementStakeAuthority),
            false
        );

        vm.prank(WALLET_ONE);
        bytes32 referendumId = referendumApp.createCitizenModuleGovernanceReferendum(proposal);

        // A rule-defining `authority.*` target likewise flags the supermajority path and snapshots.
        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        assertTrue(referendumRecord.requiresSupermajority);
        assertEq(referendumRecord.electorateHeadcountSnapshot, 3);
        assertEq(referendumRecord.electorateVotingPowerSnapshot, 19_000);

        // Genuine supermajority: all three citizens (19_000 = 100% of cast, 3 of 3 by headcount) vote For.
        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_TWO);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_THREE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(referendumId);

        ReferendumTypes.ReferendumResult memory result = referendumRegistry.getReferendumResult(referendumId);
        assertEq(result.headcountQuorumRequired, 2);
        assertEq(result.quorumRequired, 12_350);
        assertEq(result.electorateVotingPower, 19_000);
        assertTrue(result.quorumMet);
        assertTrue(result.passed);

        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(result.enactmentActionId);
        assertEq(uint256(actionRecord.actionType), uint256(GovernanceTypes.ActionType.ModulePointerUpdate));
        assertEq(actionRecord.targetModule, KernelModuleIds.STAKE_REGISTRY_AUTHORITY);

        vm.warp(actionRecord.earliestExecutionTime);
        timelock.executeAction(result.enactmentActionId);

        assertEq(kernel.getModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY), address(replacementStakeAuthority));
    }

    function test_AppModuleGovernanceReferendum_StaysOrdinaryThreshold() public {
        MockModule replacementSenateApp = new MockModule(keccak256("replacement-senate-app"));
        ReferendumTypes.ModuleGovernanceProposal memory proposal = _defaultModuleGovernanceProposal(
            "proposal-repoint-senate-app",
            "module-repoint-senate-app",
            KernelModuleIds.SENATE_APP,
            address(replacementSenateApp),
            false
        );

        vm.prank(WALLET_ONE);
        bytes32 referendumId = referendumApp.createCitizenModuleGovernanceReferendum(proposal);

        // An operational `app.*` pointer stays at the ordinary threshold: no supermajority flag, no snapshot.
        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        assertFalse(referendumRecord.requiresSupermajority);
        assertEq(referendumRecord.electorateHeadcountSnapshot, 0);
        assertEq(referendumRecord.electorateVotingPowerSnapshot, 0);

        // The same 11_000-of-19_000 (~58%) tally that fails the sensitive path passes here at ordinary quorum.
        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_TWO);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_THREE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.Against);

        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(referendumId);

        ReferendumTypes.ReferendumResult memory result = referendumRegistry.getReferendumResult(referendumId);
        assertEq(result.quorumRequired, CITIZEN_QUORUM);
        assertEq(result.headcountQuorumRequired, 0);
        assertEq(result.electorateVotingPower, 0);
        assertTrue(result.quorumMet);
        assertTrue(result.passed);

        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(result.enactmentActionId);
        assertEq(uint256(actionRecord.actionType), uint256(GovernanceTypes.ActionType.ModulePointerUpdate));
        assertEq(actionRecord.targetModule, KernelModuleIds.SENATE_APP);

        vm.warp(actionRecord.earliestExecutionTime);
        timelock.executeAction(result.enactmentActionId);

        assertEq(kernel.getModule(KernelModuleIds.SENATE_APP), address(replacementSenateApp));
    }

    function test_ModuleGovernanceReferendum_RevertsForCoreRouterAndTimelockTargets() public {
        MockModule replacement = new MockModule(keccak256("core-replacement"));

        ReferendumTypes.ModuleGovernanceProposal memory routerProposal = _defaultModuleGovernanceProposal(
            "proposal-repoint-router",
            "module-repoint-router",
            KernelModuleIds.GOVERNANCE_ROUTER,
            address(replacement),
            false
        );
        vm.prank(WALLET_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IReferendumApp.InvalidModuleGovernanceProposal.selector,
                KernelModuleIds.GOVERNANCE_ROUTER,
                address(replacement),
                false
            )
        );
        referendumApp.createCitizenModuleGovernanceReferendum(routerProposal);

        ReferendumTypes.ModuleGovernanceProposal memory timelockProposal = _defaultModuleGovernanceProposal(
            "proposal-repoint-timelock",
            "module-repoint-timelock",
            KernelModuleIds.ACTION_TIMELOCK,
            address(replacement),
            false
        );
        vm.prank(WALLET_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IReferendumApp.InvalidModuleGovernanceProposal.selector,
                KernelModuleIds.ACTION_TIMELOCK,
                address(replacement),
                false
            )
        );
        referendumApp.createCitizenModuleGovernanceReferendum(timelockProposal);
    }

    function test_CongressBudgetApprovalReferendum_QueuesBudgetLawAfterAdoptionDelay() public {
        congressAuthority.setMember(WALLET_TWO, true);
        ReferendumTypes.BudgetApprovalProposal memory proposal =
            _defaultBudgetProposal("budget-operations", "proposal-budget", "budget-law");

        vm.prank(WALLET_TWO);
        bytes32 referendumId = referendumApp.createCongressBudgetApprovalReferendum(proposal);

        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        assertEq(uint256(referendumRecord.referendumClass), uint256(ReferendumTypes.ReferendumClass.BudgetApproval));
        assertEq(uint256(referendumRecord.proposalOrigin), uint256(ReferendumTypes.ProposalOrigin.Congress));
        assertEq(referendumRecord.proposedMeasureId, proposal.budgetId);
        assertEq(referendumRecord.targetModule, KernelModuleIds.BUDGET_ENVELOPE_REGISTRY);
        ReferendumTypes.BudgetApprovalDetails memory budgetDetails =
            referendumRegistry.getBudgetApprovalDetails(referendumId);
        assertEq(budgetDetails.officeId, proposal.budget.officeId);
        assertEq(budgetDetails.allocatedAmount, proposal.budget.allocatedAmount);

        vm.prank(WALLET_TWO);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_THREE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(referendumId);

        ReferendumTypes.ReferendumResult memory result = referendumRegistry.getReferendumResult(referendumId);
        assertTrue(result.passed);
        assertTrue(result.enactmentActionId != bytes32(0));
        assertFalse(budgetEnvelopeRegistry.budgetExists(proposal.budgetId));

        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(result.enactmentActionId);
        assertEq(uint256(actionRecord.actionType), uint256(GovernanceTypes.ActionType.TreasuryBudgetApproval));
        assertEq(actionRecord.targetModule, KernelModuleIds.BUDGET_ENVELOPE_REGISTRY);
        assertEq(actionRecord.earliestExecutionTime, proposal.endTime + proposal.adoptionDelay);

        vm.warp(actionRecord.earliestExecutionTime);
        timelock.executeAction(result.enactmentActionId);

        TreasuryTypes.BudgetEnvelope memory budgetEnvelope = budgetEnvelopeRegistry.getBudgetEnvelope(proposal.budgetId);
        assertEq(budgetEnvelope.budgetId, proposal.budgetId);
        assertEq(budgetEnvelope.officeId, FINANCE_OFFICE_ID);
        assertEq(budgetEnvelope.allocatedAmount, proposal.budget.allocatedAmount);
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

    function test_FinalizeReferendum_WaitsForOpenedSenateVetoAtDeadline() public {
        ReferendumTypes.LegislationProposal memory proposal =
            _defaultProposal("measure-veto-wait", "proposal-veto-wait", "law-veto-wait");
        bytes32 referendumId = _createCitizenReferendum(WALLET_ONE, proposal);

        vm.prank(WALLET_ONE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
        vm.prank(WALLET_THREE);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);

        mockSenateApp.openReferendumVeto(referendumId, proposal.endTime);
        vm.warp(proposal.endTime);

        vm.expectRevert(
            abi.encodeWithSelector(IReferendumApp.SenateVetoPending.selector, referendumId, proposal.endTime)
        );
        referendumApp.finalizeReferendum(referendumId);

        mockSenateApp.finalizeReferendumVeto(referendumId);
        referendumApp.finalizeReferendum(referendumId);

        ReferendumTypes.ReferendumRecord memory referendumRecord = referendumRegistry.getReferendum(referendumId);
        assertEq(uint256(referendumRecord.status), uint256(ReferendumTypes.ReferendumStatus.Succeeded));
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
        ReferendumTypes.VoteReceipt memory receipt = referendumRegistry.getVoteReceipt(referendumId, PERSON_ONE_ID);
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
    ) internal view {
        assertEq(referendumRecord.referendumId, referendumId);
        assertEq(uint256(referendumRecord.referendumClass), uint256(ReferendumTypes.ReferendumClass.Legislation));
        assertEq(uint256(referendumRecord.proposalOrigin), uint256(ReferendumTypes.ProposalOrigin.Citizen));
        assertEq(referendumRecord.proposedMeasureId, proposal.proposedMeasureId);
        assertEq(referendumRecord.proposalMetadataHash, proposal.proposalMetadataHash);
        assertEq(referendumRecord.legislationTextHash, proposal.legislationTextHash);
        assertEq(referendumRecord.proposerReference, proposerReference);
        assertEq(referendumRecord.startTime, proposal.startTime);
        assertEq(referendumRecord.endTime, proposal.endTime);
        assertEq(referendumRegistry.adoptionDelayOf(referendumId), proposal.adoptionDelay);
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
        assertEq(uint256(legislationRecord.tier), uint256(LegislationTypes.LegislationTier.Law));
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
            legislationTier: LegislationTypes.LegislationTier.Law,
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + MINIMUM_VOTING_DURATION),
            adoptionDelay: STANDARD_ADOPTION_DELAY,
            emergency: false
        });
    }

    function _constitutionalProposal(string memory measureSeed, string memory proposalSeed, string memory lawSeed)
        internal
        view
        returns (ReferendumTypes.LegislationProposal memory proposal)
    {
        proposal = _defaultProposal(measureSeed, proposalSeed, lawSeed);
        proposal.legislationTier = LegislationTypes.LegislationTier.ConstitutionalOrInternationalTreaty;
    }

    function _defaultBudgetProposal(string memory budgetSeed, string memory proposalSeed, string memory lawSeed)
        internal
        view
        returns (ReferendumTypes.BudgetApprovalProposal memory proposal)
    {
        return ReferendumTypes.BudgetApprovalProposal({
            proposalMetadataHash: keccak256(bytes(proposalSeed)),
            budgetId: keccak256(bytes(budgetSeed)),
            budgetLawTextHash: keccak256(bytes(lawSeed)),
            budget: ReferendumTypes.BudgetApprovalDetails({
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(llmToken),
                allocatedAmount: 8 ether,
                startsAt: uint64(block.timestamp),
                endsAt: uint64(block.timestamp + 90 days)
            }),
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + MINIMUM_VOTING_DURATION),
            adoptionDelay: STANDARD_ADOPTION_DELAY,
            emergency: false
        });
    }

    function _defaultModuleGovernanceProposal(
        string memory proposalSeed,
        string memory proposalIdSeed,
        bytes32 targetModule,
        address newModuleAddress,
        bool registerNewModule
    ) internal view returns (ReferendumTypes.ModuleGovernanceProposal memory proposal) {
        return ReferendumTypes.ModuleGovernanceProposal({
                proposalMetadataHash: keccak256(bytes(proposalSeed)),
                proposalId: keccak256(bytes(proposalIdSeed)),
                targetModule: targetModule,
                newModuleAddress: newModuleAddress,
                registerNewModule: registerNewModule,
                startTime: uint64(block.timestamp),
                endTime: uint64(block.timestamp + MINIMUM_VOTING_DURATION),
                adoptionDelay: STANDARD_ADOPTION_DELAY
            });
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
