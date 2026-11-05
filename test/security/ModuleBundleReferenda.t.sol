// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {ReferendumApp} from "../../contracts/apps/ReferendumApp.sol";
import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {IReferendumApp} from "../../contracts/interfaces/IReferendumApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {MockConstitutionalReview} from "../../contracts/mocks/MockConstitutionalReview.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {ReferendumPolicy} from "../../contracts/policies/ReferendumPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {ElectorateRegistry} from "../../contracts/registries/ElectorateRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LegislationRegistry} from "../../contracts/registries/LegislationRegistry.sol";
import {ModuleUpgradePlanRegistry} from "../../contracts/registries/ModuleUpgradePlanRegistry.sol";
import {ReferendumRegistry} from "../../contracts/registries/ReferendumRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LegislationTypes} from "../../contracts/types/LegislationTypes.sol";
import {ReferendumTypes} from "../../contracts/types/ReferendumTypes.sol";
import {SenateTypes} from "../../contracts/types/SenateTypes.sol";

/// @notice Only the Senate boundary is synthetic; proposal eligibility, voting and execution use real contracts.
contract ModuleBundleSenateBoundary {
    bool public referendumPending;
    bool public actionPending;

    function setPending(bool referendumPending_, bool actionPending_) external {
        referendumPending = referendumPending_;
        actionPending = actionPending_;
    }

    function getReferendumVetoRecord(bytes32 id)
        external
        view
        returns (SenateTypes.ReferendumVetoRecord memory record)
    {
        if (referendumPending) {
            record.referendumId = id;
            record.exists = true;
            record.deadline = 1;
        }
    }

    function getActionCancellationRecord(bytes32 id)
        external
        view
        returns (SenateTypes.ActionCancellationRecord memory record)
    {
        if (actionPending) {
            record.actionId = id;
            record.exists = true;
            record.deadline = 1;
        }
    }

    function veto(ReferendumApp app, bytes32 id) external {
        app.cancelReferendumBySenate(id);
    }

    function cancel(GovernanceRouter router, bytes32 id) external {
        router.cancelAction(id);
    }
}

/// @notice Full public proposal/ballot/queue journeys for typed atomic module upgrades.
contract ModuleBundleReferendaTest is Test {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA201);
    bytes32 private constant A = bytes32(uint256(100));
    bytes32 private constant B = bytes32(uint256(200));
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
    ModuleUpgradePlanRegistry private plans;
    ReferendumPolicy private policy;
    ReferendumApp private app;
    ModuleBundleSenateBoundary private senate;
    MockConstitutionalReview private review;
    MockModule private oldA;
    MockModule private oldB;
    MockModule private nextA;
    MockModule private nextB;

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
        plans = new ModuleUpgradePlanRegistry(address(kernel));
        LLMToken token = new LLMToken();
        policy = new ReferendumPolicy(
            address(citizen), address(voting), address(this), address(token), 0, 0, 10_000, 10_000, 6_000, 2, 6_500
        );
        app = _newApp();
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY, address(legislation));
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY, address(referenda));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(app));
        kernel.bootstrapSetModule(KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY, address(plans));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_POLICY, address(policy));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_APP, address(app));
        senate = new ModuleBundleSenateBoundary();
        review = new MockConstitutionalReview();
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(senate));
        kernel.bootstrapSetModule(KernelModuleIds.CONSTITUTIONAL_REVIEW, address(review));
        oldA = new MockModule(keccak256("ballot old A"));
        oldB = new MockModule(keccak256("ballot old B"));
        nextA = new MockModule(keccak256("ballot new A"));
        nextB = new MockModule(keccak256("ballot new B"));
        kernel.bootstrapSetModule(A, address(oldA));
        kernel.bootstrapSetModule(B, address(oldB));
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, address(app));
        _person(bytes32(uint256(1)), ALICE, 12_000);
        _person(bytes32(uint256(2)), BOB, 8_000);
        _person(bytes32(uint256(3)), CAROL, 6_000);
        vm.roll(block.number + 1);
        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();
    }

    /// @notice This fixture supplies only Congress membership, never proposal outcomes or execution authority.
    function isCongressMember(address wallet) external pure returns (bool) {
        return wallet == ALICE;
    }

    function test_CitizenBallotQueuesOneConstitutionalActionForBothPointers() public {
        ReferendumTypes.ModuleBundleProposal memory proposal = _proposal(_publish(false), "citizen", 7 days);
        bytes32 expectedId =
            app.previewModuleBundleReferendumId(ReferendumTypes.ProposalOrigin.Citizen, proposal, bytes32(uint256(1)));
        vm.prank(ALICE);
        bytes32 id = app.createCitizenModuleBundleReferendum(proposal);
        assertEq(id, expectedId);
        ReferendumTypes.ReferendumRecord memory record = referenda.getReferendum(id);
        assertEq(uint8(record.referendumClass), 7);
        assertTrue(record.requiresSupermajority);
        assertEq(record.electorateHeadcountSnapshot, 3);
        assertEq(record.electorateVotingPowerSnapshot, 26_000);
        _support(id);
        bytes32 action = _finalize(id, proposal.endTime);
        GovernanceTypes.ActionRecord memory queued = timelock.getAction(action);
        assertEq(uint8(queued.actionType), 13);
        assertEq(queued.targetModule, KernelModuleIds.ACTION_TIMELOCK);
        assertEq(queued.payload.length, 64);
        GovernanceTypes.ModuleBundleUpdatePayload memory payload =
            abi.decode(queued.payload, (GovernanceTypes.ModuleBundleUpdatePayload));
        assertEq(payload.planRegistry, address(plans));
        assertEq(payload.planId, proposal.planId);
        assertEq(queued.originReference, id);
        _assertPointers(false);
        vm.expectRevert();
        timelock.executeAction(action);
        _assertPointers(false);
        _execute(action);
        _assertPointers(true);
        vm.expectRevert();
        timelock.executeAction(action);
    }

    function test_OneSupportingCitizenCannotUseOrdinaryQuorumForBundle() public {
        ReferendumTypes.ModuleBundleProposal memory proposal = _proposal(_publish(false), "headcount", 7 days);
        vm.prank(ALICE);
        bytes32 id = app.createCitizenModuleBundleReferendum(proposal);
        _vote(id, ALICE, ReferendumTypes.VoteOption.For);
        vm.warp(proposal.endTime);
        app.finalizeReferendum(id);
        ReferendumTypes.ReferendumResult memory result = referenda.getReferendumResult(id);
        assertFalse(result.passed);
        assertEq(result.headcountQuorumRequired, 2);
        assertEq(result.enactmentActionId, bytes32(0));
        _assertPointers(false);
    }

    function test_SimpleWeightedMajorityWithTwoSupportersStillNeedsSixtyFivePercent() public {
        stake.increaseStake(bytes32(uint256(3)), 6_000);
        vm.roll(block.number + 1);
        ReferendumTypes.ModuleBundleProposal memory proposal = _proposal(_publish(false), "stake threshold", 7 days);
        vm.prank(ALICE);
        bytes32 id = app.createCitizenModuleBundleReferendum(proposal);
        _support(id);
        _vote(id, CAROL, ReferendumTypes.VoteOption.Against);
        vm.warp(proposal.endTime);
        app.finalizeReferendum(id);
        ReferendumTypes.ReferendumResult memory result = referenda.getReferendumResult(id);
        assertFalse(result.passed); // 20,000 / 32,000 = 62.5%, although 2 support and for > against.
        assertEq(result.headcountQuorumRequired, 2);
        assertEq(result.quorumRequired, 20_800);
        assertEq(result.enactmentActionId, bytes32(0));
        _assertPointers(false);
    }

    function test_CongressProposalUsesTheSamePublicBallotAndThreshold() public {
        ReferendumTypes.ModuleBundleProposal memory proposal = _proposal(_publish(false), "congress", 7 days);
        vm.expectRevert();
        vm.prank(BOB);
        app.createCongressModuleBundleReferendum(proposal);
        vm.prank(ALICE);
        bytes32 id = app.createCongressModuleBundleReferendum(proposal);
        ReferendumTypes.ReferendumRecord memory record = referenda.getReferendum(id);
        assertEq(uint8(record.proposalOrigin), uint8(ReferendumTypes.ProposalOrigin.Congress));
        assertTrue(record.requiresSupermajority);
        _support(id);
        _execute(_finalize(id, proposal.endTime));
        _assertPointers(true);
    }

    function test_InverseRollbackCanBeOpenedBeforeCutoverAndFinalizedAfterward() public {
        ReferendumTypes.ModuleBundleProposal memory rollback = _proposal(_publish(true), "preopened rollback", 21 days);
        vm.prank(ALICE);
        bytes32 rollbackId = app.createCitizenModuleBundleReferendum(rollback);
        _support(rollbackId);
        ReferendumTypes.ModuleBundleProposal memory forward = _proposal(_publish(false), "forward", 7 days);
        vm.prank(ALICE);
        bytes32 forwardId = app.createCitizenModuleBundleReferendum(forward);
        _support(forwardId);
        _execute(_finalize(forwardId, forward.endTime));
        _assertPointers(true);
        assertEq(referenda.getReferendum(rollbackId).referendumPolicy, address(policy));
        bytes32 action = _finalize(rollbackId, rollback.endTime);
        _execute(action);
        _assertPointers(false);
        assertEq(uint8(timelock.getActionState(action)), uint8(GovernanceTypes.ActionState.Executed));
    }

    function test_NormalSenatePendingAndReviewBoundariesStillApplyToPublicBundle() public {
        ReferendumTypes.ModuleBundleProposal memory proposal = _proposal(_publish(false), "negative controls", 7 days);
        vm.prank(ALICE);
        bytes32 id = app.createCitizenModuleBundleReferendum(proposal);
        _support(id);
        vm.warp(proposal.endTime);
        senate.setPending(true, false);
        vm.expectRevert(abi.encodeWithSelector(IReferendumApp.SenateVetoPending.selector, id, uint64(1)));
        app.finalizeReferendum(id);
        senate.setPending(false, false);
        app.finalizeReferendum(id);
        bytes32 action = referenda.getReferendumResult(id).enactmentActionId;
        vm.warp(timelock.getAction(action).earliestExecutionTime);
        review.setActionPaused(action, true);
        assertFalse(timelock.isActionExecutable(action));
        vm.expectRevert();
        timelock.executeAction(action);
        review.setActionPaused(action, false);
        senate.setPending(false, true);
        assertFalse(timelock.isActionExecutable(action));
        vm.expectRevert();
        timelock.executeAction(action);
        senate.setPending(false, false);
        assertTrue(timelock.isActionExecutable(action));
        senate.cancel(router, action);
        assertEq(uint8(timelock.getActionState(action)), uint8(GovernanceTypes.ActionState.Canceled));
        vm.expectRevert();
        timelock.executeAction(action);
        _assertPointers(false);
    }

    function test_ConstitutionalBundleDoesNotAcquireAnExemptionFromSenateBallotVeto() public {
        ReferendumTypes.ModuleBundleProposal memory proposal = _proposal(_publish(false), "senate veto", 7 days);
        vm.prank(ALICE);
        bytes32 id = app.createCitizenModuleBundleReferendum(proposal);
        _support(id);
        senate.veto(app, id);
        assertEq(uint8(referenda.getReferendum(id).status), uint8(ReferendumTypes.ReferendumStatus.Canceled));
        vm.warp(proposal.endTime);
        vm.expectRevert();
        app.finalizeReferendum(id);
        _assertPointers(false);
    }

    function test_ActualAppAndWriterBundlePreservesAnExistingVoteAndAllowsNewProposals() public {
        ReferendumTypes.LegislationProposal memory law = _law();
        vm.prank(ALICE);
        bytes32 existingVote = app.createCitizenLegislationReferendum(law);
        _vote(existingVote, ALICE, ReferendumTypes.VoteOption.For);
        ReferendumApp replacement = _newApp();
        GovernanceTypes.ModuleUpdate[] memory updates = new GovernanceTypes.ModuleUpdate[](2);
        updates[0] = _entry(KernelModuleIds.REFERENDUM_APP, address(app), address(replacement));
        updates[1] = _entry(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(app), address(replacement));
        _sort(updates);
        bytes32 planId = plans.publishPlan(updates, keccak256("same stable facts, app and writer reconciled"));
        ReferendumTypes.ModuleBundleProposal memory proposal = _proposal(planId, "actual app upgrade", 7 days);
        vm.prank(ALICE);
        bytes32 id = app.createCitizenModuleBundleReferendum(proposal);
        _support(id);
        bytes32 action = _finalize(id, proposal.endTime);
        assertEq(kernel.getModule(KernelModuleIds.REFERENDUM_APP), address(app));
        assertEq(kernel.getModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY), address(app));
        _execute(action);
        assertEq(kernel.getModule(KernelModuleIds.REFERENDUM_APP), address(replacement));
        assertEq(kernel.getModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY), address(replacement));
        assertEq(router.originAuthority(GovernanceTypes.ActionOrigin.Referendum), address(replacement));
        vm.prank(BOB);
        replacement.castVote(existingVote, ReferendumTypes.VoteOption.For);
        vm.warp(law.endTime);
        replacement.finalizeReferendum(existingVote);
        _execute(referenda.getReferendumResult(existingVote).enactmentActionId);
        assertTrue(legislation.legislationExists(law.proposedMeasureId));
        ReferendumTypes.LegislationProposal memory newLaw = _law();
        newLaw.proposedMeasureId = keccak256("after actual atomic app upgrade");
        vm.prank(ALICE);
        assertTrue(referenda.referendumExists(replacement.createCitizenLegislationReferendum(newLaw)));
    }

    function test_LegacyModuleAndLegislationPreviewIdentifiersRemainUnchanged() public view {
        // Fixed vectors use the pre-bundle schema and ordinals, independent of this fixture's deployed addresses.
        ReferendumTypes.ModuleGovernanceProposal memory module = ReferendumTypes.ModuleGovernanceProposal(
            bytes32(uint256(0x123)),
            bytes32(uint256(0x456)),
            bytes32(uint256(0x789)),
            address(0x1234),
            false,
            1_900_000_000,
            1_900_604_800,
            604_800
        );
        assertEq(
            app.previewModuleGovernanceReferendumId(
                ReferendumTypes.ProposalOrigin.Citizen, module, bytes32(uint256(1))
            ),
            0xf0235a7d9b4fdf900e118484e3557552ebbaaf1edf182b3aec55ab633b949bef
        );
        ReferendumTypes.LegislationProposal memory law = ReferendumTypes.LegislationProposal(
            bytes32(uint256(0x123)),
            bytes32(uint256(0x456)),
            bytes32(0),
            bytes32(uint256(0x789)),
            LegislationTypes.LegislationTier.Law,
            1_900_000_000,
            1_900_604_800,
            604_800,
            false
        );
        assertEq(
            app.previewReferendumId(
                ReferendumTypes.ReferendumClass.Legislation,
                ReferendumTypes.ProposalOrigin.Citizen,
                law,
                bytes32(uint256(1))
            ),
            0xe7cb03762704f203817bebbdbe51876239a10190221786463b2c8cf28f75fecd
        );
    }

    function _newApp() private returns (ReferendumApp) {
        return new ReferendumApp(
            address(identity),
            address(legislation),
            address(referenda),
            address(policy),
            address(router),
            address(voting)
        );
    }

    function _person(bytes32 id, address wallet, uint256 amount) private {
        identity.setIdentityRecord(
            id,
            IdentityTypes.IdentityRecordInput(
                keccak256(abi.encode(id)),
                "synthetic://module-bundle",
                IdentityTypes.VerificationStatus.Verified,
                IdentityTypes.CitizenshipStatus.Citizen,
                IdentityTypes.AgeClass.Adult,
                false,
                false
            )
        );
        identity.setWalletLink(id, wallet, IdentityTypes.WalletLinkStatus.Active);
        stake.increaseStake(id, amount);
    }

    function _publish(bool inverse) private returns (bytes32) {
        GovernanceTypes.ModuleUpdate[] memory updates = new GovernanceTypes.ModuleUpdate[](2);
        updates[0] = inverse ? _entry(A, address(nextA), address(oldA)) : _entry(A, address(oldA), address(nextA));
        updates[1] = inverse ? _entry(B, address(nextB), address(oldB)) : _entry(B, address(oldB), address(nextB));
        return plans.publishPlan(updates, keccak256(abi.encode("reviewed two-module transition", inverse)));
    }

    function _entry(bytes32 id, address expected, address replacement)
        private
        view
        returns (GovernanceTypes.ModuleUpdate memory)
    {
        return GovernanceTypes.ModuleUpdate(id, expected, replacement, replacement.codehash);
    }

    function _sort(GovernanceTypes.ModuleUpdate[] memory updates) private pure {
        if (uint256(updates[0].moduleId) > uint256(updates[1].moduleId)) {
            (updates[0], updates[1]) = (updates[1], updates[0]);
        }
    }

    function _proposal(bytes32 id, string memory description, uint64 duration)
        private
        view
        returns (ReferendumTypes.ModuleBundleProposal memory)
    {
        return ReferendumTypes.ModuleBundleProposal(
            keccak256(bytes(description)),
            id,
            address(plans),
            uint64(block.timestamp),
            uint64(block.timestamp) + duration,
            7 days
        );
    }

    function _support(bytes32 id) private {
        _vote(id, ALICE, ReferendumTypes.VoteOption.For);
        _vote(id, BOB, ReferendumTypes.VoteOption.For);
    }

    function _vote(bytes32 id, address wallet, ReferendumTypes.VoteOption option) private {
        vm.prank(wallet);
        app.castVote(id, option);
    }

    function _finalize(bytes32 id, uint64 endTime) private returns (bytes32 action) {
        vm.warp(endTime);
        app.finalizeReferendum(id);
        assertTrue(referenda.getReferendumResult(id).passed);
        action = referenda.getReferendumResult(id).enactmentActionId;
        assertTrue(action != bytes32(0));
    }

    function _execute(bytes32 action) private {
        uint64 ready = timelock.getAction(action).earliestExecutionTime;
        if (block.timestamp < ready) vm.warp(ready);
        timelock.executeAction(action);
    }

    function _assertPointers(bool upgraded) private view {
        assertEq(kernel.getModule(A), upgraded ? address(nextA) : address(oldA));
        assertEq(kernel.getModule(B), upgraded ? address(nextB) : address(oldB));
    }

    function _law() private view returns (ReferendumTypes.LegislationProposal memory) {
        return ReferendumTypes.LegislationProposal(
            keccak256("existing vote metadata"),
            keccak256("existing law through atomic upgrade"),
            bytes32(0),
            keccak256("existing law text"),
            LegislationTypes.LegislationTier.Law,
            uint64(block.timestamp),
            uint64(block.timestamp + 21 days),
            7 days,
            false
        );
    }
}
