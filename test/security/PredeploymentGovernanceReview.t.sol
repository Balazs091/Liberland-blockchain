// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {ReferendumApp} from "../../contracts/apps/ReferendumApp.sol";
import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {IReferendumApp} from "../../contracts/interfaces/IReferendumApp.sol";
import {IReferendumRegistry} from "../../contracts/interfaces/IReferendumRegistry.sol";
import {ITreasurySpendingPolicy} from "../../contracts/interfaces/ITreasurySpendingPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {CandidateEligibilityPolicy} from "../../contracts/policies/CandidateEligibilityPolicy.sol";
import {CongressElectionPolicy} from "../../contracts/policies/CongressElectionPolicy.sol";
import {ReferendumPolicy} from "../../contracts/policies/ReferendumPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {TreasurySpendingPolicy} from "../../contracts/policies/TreasurySpendingPolicy.sol";
import {BudgetEnvelopeRegistry} from "../../contracts/registries/BudgetEnvelopeRegistry.sol";
import {ElectorateRegistry} from "../../contracts/registries/ElectorateRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LegislationRegistry} from "../../contracts/registries/LegislationRegistry.sol";
import {ReferendumRegistry} from "../../contracts/registries/ReferendumRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LegislationTypes} from "../../contracts/types/LegislationTypes.sol";
import {ReferendumTypes} from "../../contracts/types/ReferendumTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";

/// @notice Standalone user journeys with real voting, registries, router and queue; no inherited duplicate tests.
contract PredeploymentGovernanceReviewTest is Test {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA201);
    ConstitutionKernel private kernel;
    ActionTimelock private timelock;
    GovernanceRouter private router;
    IdentityRegistry private identity;
    StakeRegistry private stake;
    CitizenEligibilityPolicy private citizen;
    VotingPowerPolicy private voting;
    ElectorateRegistry private electorate;
    LegislationRegistry private legislation;
    ReferendumRegistry private referenda;
    ReferendumPolicy private policy;
    ReferendumApp private app;
    LLMToken private token;
    CongressElectionPolicy private electionPolicy;
    BudgetEnvelopeRegistry private budgets;

    function setUp() public {
        vm.warp(1_900_000_000);
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(
            address(kernel), GovernanceTypes.TimelockDelayConfig(2 days, 1 days, 1 days, 2 days, 7 days)
        );
        router = new GovernanceRouter(address(kernel), address(this));
        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));
        identity = new IdentityRegistry(address(kernel));
        stake = new StakeRegistry(address(kernel));
        electorate = new ElectorateRegistry(address(kernel), address(identity), address(stake));
        citizen = new CitizenEligibilityPolicy(address(identity), address(stake), 5_000);
        voting = new VotingPowerPolicy(address(identity), address(stake), address(citizen), address(electorate));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identity));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(stake));
        kernel.bootstrapSetModule(KernelModuleIds.ELECTORATE_REGISTRY, address(electorate));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(citizen));
        kernel.bootstrapSetModule(KernelModuleIds.VOTING_POWER_POLICY, address(voting));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_APP, address(this));
        legislation = new LegislationRegistry(address(kernel));
        referenda = new ReferendumRegistry(address(kernel));
        token = new LLMToken();
        policy = _newPolicy(10_000);
        app = _newApp(policy);
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY, address(legislation));
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY, address(referenda));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(app));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_POLICY, address(policy));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_APP, address(app));
        CandidateEligibilityPolicy candidate =
            new CandidateEligibilityPolicy(address(identity), address(stake), address(citizen), 6_000);
        electionPolicy = new CongressElectionPolicy(
            address(candidate), address(voting), 2, 1, 0, 6_000, 2 days, 3 days, 14 days, 90 days
        );
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_POLICY, address(electionPolicy));
        budgets = new BudgetEnvelopeRegistry(address(kernel));
        ITreasurySpendingPolicy.AssetSpendingLimit[] memory limits = new ITreasurySpendingPolicy.AssetSpendingLimit[](1);
        limits[0] = ITreasurySpendingPolicy.AssetSpendingLimit(address(token), 1_000, 1_000);
        TreasurySpendingPolicy spending = new TreasurySpendingPolicy(keccak256("finance"), address(token), limits);
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY, address(budgets));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.TREASURY_SPENDING_POLICY, address(spending));
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, address(app));
        _person(bytes32(uint256(1)), ALICE, 12_000);
        _person(bytes32(uint256(2)), BOB, 8_000);
        _person(bytes32(uint256(3)), CAROL, 6_000);
        vm.roll(block.number + 1);
        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();
    }

    /// @notice The Congress proposer fixture is narrow; every voting/custody dependency above is real.
    function isCongressMember(address wallet) external pure returns (bool) {
        return wallet == ALICE;
    }

    function test_OrdinaryCitizenCannotAmendConstitutionByLabellingProposalLaw() public {
        bytes32 target = _seedMeasure(LegislationTypes.LegislationTier.ConstitutionalOrInternationalTreaty);
        ReferendumTypes.LegislationProposal memory p = _law("citizen-protected", target);
        vm.expectRevert(abi.encodeWithSelector(IReferendumApp.InvalidLegislationTier.selector, uint8(1)));
        vm.prank(ALICE);
        app.createCitizenLegislationReferendum(p);
    }

    function test_OrdinaryCongressCannotAmendConstitutionByLabellingProposalLaw() public {
        bytes32 target = _seedMeasure(LegislationTypes.LegislationTier.ConstitutionalOrInternationalTreaty);
        ReferendumTypes.LegislationProposal memory p = _law("congress-protected", target);
        vm.expectRevert(abi.encodeWithSelector(IReferendumApp.InvalidLegislationTier.selector, uint8(1)));
        vm.prank(ALICE);
        app.createCongressLegislationReferendum(p);
    }

    function test_LawAmendmentStillPassesAndExecutesUnderOrdinaryRules() public {
        bytes32 target = _seedMeasure(LegislationTypes.LegislationTier.Law);
        ReferendumTypes.LegislationProposal memory p = _law("law-amendment", target);
        vm.prank(ALICE);
        bytes32 id = app.createCitizenLegislationReferendum(p);
        _vote(id, ALICE);
        vm.warp(p.endTime);
        app.finalizeReferendum(id);
        _execute(referenda.getReferendumResult(id).enactmentActionId);
        LegislationTypes.LegislationRecord memory enacted = legislation.getLegislationRecord(p.proposedMeasureId);
        assertEq(enacted.amendsMeasureId, target);
        assertEq(uint8(enacted.tier), uint8(LegislationTypes.LegislationTier.Law));
        assertTrue(enacted.active);
    }

    function test_ConstitutionalAmendmentRetainsItsRequiredHeadcount() public {
        bytes32 target = _seedMeasure(LegislationTypes.LegislationTier.ConstitutionalOrInternationalTreaty);
        ReferendumTypes.LegislationProposal memory p = _law("proper-constitutional-amendment", target);
        p.legislationTier = LegislationTypes.LegislationTier.ConstitutionalOrInternationalTreaty;
        vm.prank(ALICE);
        bytes32 id = app.createCongressConstitutionalAmendmentReferendum(p);
        _vote(id, ALICE);
        vm.warp(p.endTime);
        app.finalizeReferendum(id);
        assertFalse(referenda.getReferendumResult(id).passed);
        assertEq(referenda.getReferendumResult(id).enactmentActionId, bytes32(0));
        assertFalse(legislation.legislationExists(p.proposedMeasureId));
    }

    function test_ConstitutionalAmendmentPassesItsProperRouteAndExecutes() public {
        bytes32 target = _seedMeasure(LegislationTypes.LegislationTier.ConstitutionalOrInternationalTreaty);
        ReferendumTypes.LegislationProposal memory p = _law("proper-passing-amendment", target);
        p.legislationTier = LegislationTypes.LegislationTier.ConstitutionalOrInternationalTreaty;
        vm.prank(ALICE);
        bytes32 id = app.createCongressConstitutionalAmendmentReferendum(p);
        _vote(id, ALICE);
        _vote(id, BOB);
        vm.warp(p.endTime);
        app.finalizeReferendum(id);
        _execute(referenda.getReferendumResult(id).enactmentActionId);
        assertEq(legislation.getLegislationRecord(p.proposedMeasureId).amendsMeasureId, target);
    }

    function test_SameAddressModuleProposalCanPreauthorizeRollbackAfterLaterCutover() public {
        ReferendumTypes.ModuleGovernanceProposal memory repair =
            _module("preopened-original-address-repair", KernelModuleIds.REFERENDUM_POLICY, address(policy));
        repair.endTime = uint64(block.timestamp + 21 days);
        vm.prank(ALICE);
        bytes32 repairId = app.createCitizenModuleGovernanceReferendum(repair);
        _vote(repairId, ALICE);
        _vote(repairId, BOB);
        MockModule broken = new MockModule(keccak256("broken-after-repair-opened"));
        _execute(_approveModule("break-after-repair-opened", KernelModuleIds.REFERENDUM_POLICY, address(broken)));
        assertEq(kernel.getModule(KernelModuleIds.REFERENDUM_POLICY), address(broken));
        assertEq(referenda.getReferendum(repairId).referendumPolicy, address(policy));
        vm.warp(repair.endTime);
        app.finalizeReferendum(repairId);
        bytes32 repairAction = referenda.getReferendumResult(repairId).enactmentActionId;
        // The queue captures the incumbent at finalization, after cutover, so this is not a stale-target bypass.
        assertEq(timelock.getAction(repairAction).targetModuleAddress, address(broken));
        _execute(repairAction);
        assertEq(kernel.getModule(KernelModuleIds.REFERENDUM_POLICY), address(policy));
        ReferendumTypes.LegislationProposal memory newLaw = _law("governance-restored", bytes32(0));
        vm.prank(ALICE);
        assertTrue(referenda.referendumExists(app.createCitizenLegislationReferendum(newLaw)));
    }

    function test_DedicatedElectionPolicyProposalCanPreauthorizeOriginalAddressRollback() public {
        ReferendumTypes.CongressElectionPolicyProposal memory p = ReferendumTypes.CongressElectionPolicyProposal({
            proposalMetadataHash: keccak256("preopened-election-rollback-metadata"),
            proposalId: keccak256("preopened-election-rollback-id"),
            newPolicy: address(electionPolicy),
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + 21 days),
            adoptionDelay: 7 days
        });
        vm.prank(ALICE);
        bytes32 id = app.createCitizenCongressElectionPolicyReferendum(p);
        _vote(id, ALICE);
        _vote(id, BOB);
        CongressElectionPolicy replacement = new CongressElectionPolicy(
            electionPolicy.candidateEligibilityPolicy(),
            address(voting),
            2,
            1,
            0,
            6_000,
            2 days,
            3 days,
            14 days,
            60 days
        );
        _execute(_approveModule("election-cutover", KernelModuleIds.CONGRESS_ELECTION_POLICY, address(replacement)));
        assertEq(kernel.getModule(KernelModuleIds.CONGRESS_ELECTION_POLICY), address(replacement));
        vm.warp(p.endTime);
        app.finalizeReferendum(id);
        bytes32 rollback = referenda.getReferendumResult(id).enactmentActionId;
        assertEq(timelock.getAction(rollback).targetModuleAddress, address(replacement));
        _execute(rollback);
        assertEq(kernel.getModule(KernelModuleIds.CONGRESS_ELECTION_POLICY), address(electionPolicy));
    }

    function test_UnchangedAddressActionFailsSafelyAndCanExpireWithoutBlockingGovernance() public {
        bytes32 action = _approveModule("unchanged-target", KernelModuleIds.REFERENDUM_POLICY, address(policy));
        vm.warp(timelock.getAction(action).earliestExecutionTime);
        vm.expectRevert(
            abi.encodeWithSelector(
                ConstitutionKernel.ModuleAddressUnchanged.selector, KernelModuleIds.REFERENDUM_POLICY, address(policy)
            )
        );
        timelock.executeAction(action);
        assertEq(uint8(timelock.getActionState(action)), uint8(GovernanceTypes.ActionState.Queued));
        vm.warp(uint256(timelock.getAction(action).expiresAt) + 1);
        timelock.expireAction(action);
        assertEq(uint8(timelock.getActionState(action)), uint8(GovernanceTypes.ActionState.Expired));
        ReferendumTypes.LegislationProposal memory p = _law("after-futile-action", bytes32(0));
        vm.prank(ALICE);
        bytes32 id = app.createCitizenLegislationReferendum(p);
        assertTrue(referenda.referendumExists(id));
    }

    function test_ActualPolicyUpgradePreservesOldVoteRulesAndAppliesNewQuorumToNewVotes() public {
        ReferendumTypes.LegislationProposal memory oldLaw = _law("old-pinned-law", bytes32(0));
        oldLaw.endTime = uint64(block.timestamp + 21 days);
        vm.prank(ALICE);
        bytes32 oldId = app.createCitizenLegislationReferendum(oldLaw);
        _vote(oldId, ALICE);
        ReferendumPolicy nextPolicy = _newPolicy(13_000);
        bytes32 action = _approveModule("new-policy", KernelModuleIds.REFERENDUM_POLICY, address(nextPolicy));
        _execute(action);
        assertEq(kernel.getModule(KernelModuleIds.REFERENDUM_POLICY), address(nextPolicy));
        assertEq(referenda.getReferendum(oldId).referendumPolicy, address(policy));
        ReferendumTypes.LegislationProposal memory newLaw = _law("new-quorum-law", bytes32(0));
        vm.prank(ALICE);
        bytes32 newId = app.createCitizenLegislationReferendum(newLaw);
        _vote(newId, ALICE);
        vm.warp(newLaw.endTime);
        app.finalizeReferendum(newId);
        app.finalizeReferendum(oldId);
        assertFalse(referenda.getReferendumResult(newId).passed);
        assertTrue(referenda.getReferendumResult(oldId).passed);
        _execute(referenda.getReferendumResult(oldId).enactmentActionId);
        assertTrue(legislation.legislationExists(oldLaw.proposedMeasureId));
    }

    function test_ActualReferendumAppBundleUpgradeContinuesAnExistingRegistryBackedVote() public {
        ReferendumTypes.LegislationProposal memory p = _law("continues-through-app-upgrade", bytes32(0));
        p.endTime = uint64(block.timestamp + 21 days);
        vm.prank(ALICE);
        bytes32 existingId = app.createCitizenLegislationReferendum(p);
        _vote(existingId, ALICE);
        ReferendumApp replacement = _newApp(policy);
        ReferendumTypes.ModuleGovernanceProposal memory appProposal =
            _module("app-pointer", KernelModuleIds.REFERENDUM_APP, address(replacement));
        ReferendumTypes.ModuleGovernanceProposal memory writerProposal =
            _module("writer-pointer", KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(replacement));
        vm.prank(ALICE);
        bytes32 appVote = app.createCitizenModuleGovernanceReferendum(appProposal);
        vm.prank(ALICE);
        bytes32 writerVote = app.createCitizenModuleGovernanceReferendum(writerProposal);
        _vote(appVote, ALICE);
        _vote(appVote, BOB);
        _vote(writerVote, ALICE);
        _vote(writerVote, BOB);
        vm.warp(appProposal.endTime);
        // Both approvals must be finalized before retiring the old origin.
        app.finalizeReferendum(appVote);
        app.finalizeReferendum(writerVote);
        bytes32 appAction = referenda.getReferendumResult(appVote).enactmentActionId;
        bytes32 writerAction = referenda.getReferendumResult(writerVote).enactmentActionId;
        uint64 readyAt = timelock.getAction(writerAction).earliestExecutionTime;
        // Individually executable members are safe here: the second approved action can complete the bundle.
        vm.warp(readyAt);
        timelock.executeAction(appAction);
        ReferendumTypes.LegislationProposal memory premature = _law("partial-bundle", bytes32(0));
        vm.expectRevert();
        vm.prank(ALICE);
        replacement.createCitizenLegislationReferendum(premature);
        timelock.executeAction(writerAction);
        vm.prank(BOB);
        replacement.castVote(existingId, ReferendumTypes.VoteOption.Against);
        vm.warp(p.endTime > block.timestamp ? p.endTime : block.timestamp);
        replacement.finalizeReferendum(existingId);
        assertEq(referenda.getReferendum(existingId).forVotes, 12_000);
        assertEq(referenda.getReferendum(existingId).againstVotes, 8_000);
        _execute(referenda.getReferendumResult(existingId).enactmentActionId);
        assertTrue(legislation.legislationExists(p.proposedMeasureId));
    }

    function test_ApprovedBrokenPolicyCanDisableTheOnlyRouteNeededToReplaceIt() public {
        MockModule broken = new MockModule(keccak256("approved-incompatible-policy"));
        bytes32 action = _approveModule("broken-policy", KernelModuleIds.REFERENDUM_POLICY, address(broken));
        _execute(action);
        assertEq(kernel.getModule(KernelModuleIds.REFERENDUM_POLICY), address(broken));
        ReferendumTypes.ModuleGovernanceProposal memory repair =
            _module("repair", KernelModuleIds.REFERENDUM_POLICY, address(policy));
        vm.expectRevert();
        vm.prank(ALICE);
        app.createCitizenModuleGovernanceReferendum(repair);
        assertEq(kernel.bootstrapAuthority(), address(0));
    }

    function test_BudgetExpiringBeforeVoteEndsIsRejectedBeforeVoting() public {
        ReferendumTypes.BudgetApprovalProposal memory p = _budget(false);
        p.budget.endsAt = uint64(block.timestamp + 1 days);
        _expectInvalidBudget(p);
    }

    function test_BudgetExpiringDuringMandatoryAdoptionDelayIsRejected() public {
        ReferendumTypes.BudgetApprovalProposal memory p = _budget(false);
        p.budget.endsAt = p.endTime + 1 days;
        _expectInvalidBudget(p);
    }

    function test_EmergencyBudgetMustStillSurviveImmutableQueueDelay() public {
        ReferendumTypes.BudgetApprovalProposal memory p = _budget(true);
        p.budget.endsAt = p.endTime + 12 hours;
        _expectInvalidBudget(p);
    }

    function test_UsableBudgetStillVotesQueuesAndBecomesActive() public {
        ReferendumTypes.BudgetApprovalProposal memory p = _budget(false);
        vm.prank(ALICE);
        bytes32 id = app.createCongressBudgetApprovalReferendum(p);
        _vote(id, ALICE);
        vm.warp(p.endTime);
        app.finalizeReferendum(id);
        _execute(referenda.getReferendumResult(id).enactmentActionId);
        assertTrue(budgets.budgetExists(p.budgetId));
        assertTrue(budgets.isBudgetActive(p.budgetId));
    }

    function _budget(bool emergency) private view returns (ReferendumTypes.BudgetApprovalProposal memory p) {
        p = ReferendumTypes.BudgetApprovalProposal({
            proposalMetadataHash: keccak256("budget-metadata"),
            budgetId: keccak256("review-budget"),
            budgetLawTextHash: keccak256("budget-text"),
            budget: ReferendumTypes.BudgetApprovalDetails({
                officeId: keccak256("finance"),
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(token),
                allocatedAmount: 1_000,
                startsAt: uint64(block.timestamp),
                endsAt: uint64(block.timestamp + 30 days)
            }),
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + (emergency ? 3 days : 7 days)),
            adoptionDelay: emergency ? 0 : 7 days,
            emergency: emergency
        });
    }

    function _expectInvalidBudget(ReferendumTypes.BudgetApprovalProposal memory p) private {
        vm.expectRevert(abi.encodeWithSelector(IReferendumApp.InvalidBudgetProposal.selector, p.budgetId));
        vm.prank(ALICE);
        app.createCongressBudgetApprovalReferendum(p);
        assertFalse(budgets.budgetExists(p.budgetId));
    }

    function _person(bytes32 personId, address wallet, uint256 amount) private {
        identity.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput(
                keccak256(abi.encode(personId)),
                "synthetic://review",
                IdentityTypes.VerificationStatus.Verified,
                IdentityTypes.CitizenshipStatus.Citizen,
                IdentityTypes.AgeClass.Adult,
                false,
                false
            )
        );
        identity.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        stake.increaseStake(personId, amount);
    }

    function _newPolicy(uint256 quorum) private returns (ReferendumPolicy) {
        return new ReferendumPolicy(
            address(citizen), address(voting), address(this), address(token), 0, 0, quorum, quorum, 6_000, 2, 6_500
        );
    }

    function _newApp(ReferendumPolicy initialPolicy) private returns (ReferendumApp) {
        return new ReferendumApp(
            address(identity),
            address(legislation),
            address(referenda),
            address(initialPolicy),
            address(router),
            address(voting)
        );
    }

    function _seedMeasure(LegislationTypes.LegislationTier tier) private returns (bytes32 id) {
        id = keccak256(abi.encode("original", tier));
        vm.prank(address(timelock));
        legislation.recordEnactment(
            id,
            LegislationTypes.LegislationRecordInput(
                tier, keccak256("original-text"), bytes32(uint256(1)), keccak256("original-adoption"), bytes32(0)
            )
        );
    }

    function _law(string memory seed, bytes32 target)
        private
        view
        returns (ReferendumTypes.LegislationProposal memory)
    {
        return ReferendumTypes.LegislationProposal(
            keccak256(abi.encode(seed, "metadata")),
            keccak256(abi.encode(seed, "measure")),
            target,
            keccak256(abi.encode(seed, "text")),
            LegislationTypes.LegislationTier.Law,
            uint64(block.timestamp),
            uint64(block.timestamp + 7 days),
            7 days,
            false
        );
    }

    function _module(string memory seed, bytes32 slot, address replacement)
        private
        view
        returns (ReferendumTypes.ModuleGovernanceProposal memory)
    {
        return ReferendumTypes.ModuleGovernanceProposal(
            keccak256(abi.encode(seed, "metadata")),
            keccak256(abi.encode(seed, "id")),
            slot,
            replacement,
            false,
            uint64(block.timestamp),
            uint64(block.timestamp + 7 days),
            7 days
        );
    }

    function _approveModule(string memory seed, bytes32 slot, address replacement) private returns (bytes32 action) {
        ReferendumTypes.ModuleGovernanceProposal memory p = _module(seed, slot, replacement);
        vm.prank(ALICE);
        bytes32 id = app.createCitizenModuleGovernanceReferendum(p);
        _vote(id, ALICE);
        _vote(id, BOB);
        vm.warp(p.endTime);
        app.finalizeReferendum(id);
        action = referenda.getReferendumResult(id).enactmentActionId;
        assertTrue(action != bytes32(0));
    }

    function _vote(bytes32 id, address wallet) private {
        vm.prank(wallet);
        app.castVote(id, ReferendumTypes.VoteOption.For);
    }

    function _execute(bytes32 action) private {
        uint64 readyAt = timelock.getAction(action).earliestExecutionTime;
        if (block.timestamp < readyAt) vm.warp(readyAt);
        timelock.executeAction(action);
    }
}
