// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DeploySepoliaGoverned} from "../../scripts/DeploySepoliaGoverned.s.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ReferendumApp} from "../../contracts/apps/ReferendumApp.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {MembershipRegistry} from "../../contracts/registries/MembershipRegistry.sol";
import {IMembershipRegistry} from "../../contracts/interfaces/IMembershipRegistry.sol";
import {ReferendumRegistry} from "../../contracts/registries/ReferendumRegistry.sol";
import {ModuleUpgradePlanRegistry} from "../../contracts/registries/ModuleUpgradePlanRegistry.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {SepoliaGovernedMembershipController} from "../../contracts/mocks/SepoliaGovernedMembershipController.sol";
import {
    ISepoliaGovernedMembershipController
} from "../../contracts/interfaces/ISepoliaGovernedMembershipController.sol";
import {LiberlandMerit} from "../../contracts/tokens/LiberlandMerit.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {ReferendumTypes} from "../../contracts/types/ReferendumTypes.sol";
import {MembershipTypes} from "../../contracts/types/MembershipTypes.sol";

contract DeploySepoliaGovernedHarness is DeploySepoliaGoverned {
    function deployForTest(address[3] memory testers) external returns (Deployment memory) {
        require(block.chainid == 11155111, "test staging requires Sepolia");
        _configureActors(address(this), testers);
        _civicReviewers = [address(0xA001), address(0xA002), address(0xA003), address(0xA004), address(0xA005)];
        _deployCompleteDemo(address(this));
        _assertGovernedReady();
        return _snapshot(address(this));
    }

    function memberships() external view returns (MembershipRegistry) {
        return _membershipRegistry;
    }

    function controller() external view returns (SepoliaGovernedMembershipController) {
        return _membershipController;
    }
}

/// @notice Full governed deployment and actual citizen-vote replacement, not direct kernel-authority injection.
contract DeploySepoliaGovernedTest is Test {
    address private constant TESTER_ONE = address(0xB101);
    address private constant TESTER_TWO = address(0xB102);
    address private constant TESTER_THREE = address(0xB103);
    DeploySepoliaGovernedHarness private stage;
    DeploySepoliaGoverned.Deployment private d;
    ConstitutionKernel private kernel;
    MembershipRegistry private membership;
    SepoliaGovernedMembershipController private controller;
    ReferendumApp private referenda;
    ReferendumRegistry private votes;
    ActionTimelock private queue;

    function setUp() public {
        vm.chainId(11155111);
        vm.warp(1_900_000_000);
        vm.roll(1000);
        stage = new DeploySepoliaGovernedHarness();
        d = stage.deployForTest([TESTER_ONE, TESTER_TWO, TESTER_THREE]);
        kernel = ConstitutionKernel(d.kernel);
        membership = stage.memberships();
        controller = stage.controller();
        referenda = ReferendumApp(d.referendumApp);
        votes = ReferendumRegistry(d.referendumRegistry);
        queue = ActionTimelock(d.timelock);
        // Live public proposals use a certified completed-block snapshot, unlike the synthetic imported examples.
        vm.roll(block.number + 1);
    }

    function test_GovernedStageHasFixedRealTokenBackedStakeAndNoBootstrap() public {
        LiberlandMerit token = LiberlandMerit(d.llmToken);
        assertEq(token.name(), "Liberland Merit");
        assertEq(token.totalSupply(), 1_000_000e18);
        assertEq(token.cap(), 70_000_000e18);
        assertEq(token.balanceOf(d.stakingVault), 45_000e18);
        assertEq(token.balanceOf(d.treasuryVault), 100_000e18);
        assertEq(token.balanceOf(TESTER_ONE), 10_000e18);
        assertEq(token.balanceOf(TESTER_TWO), 10_000e18);
        assertEq(token.balanceOf(TESTER_THREE), 10_000e18);
        assertEq(token.balanceOf(address(stage)), 825_000e18);
        assertEq(kernel.bootstrapAuthority(), address(0));
        assertEq(kernel.getModule(KernelModuleIds.GOVERNANCE_ROUTER), d.router);
        assertEq(kernel.getModule(KernelModuleIds.ACTION_TIMELOCK), d.timelock);
        assertEq(kernel.getModule(KernelModuleIds.MEMBERSHIP_REGISTRY), address(membership));
        assertTrue(controller.canSubmit(address(stage)));
        assertTrue(controller.canSubmit(TESTER_TWO));
        assertFalse(controller.canSubmit(TESTER_ONE));
        (bool minted,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", address(this), 1));
        assertFalse(minted);
    }

    function test_CurrentCongressDrivesOnlySyntheticSubjectsAndDoesNotChangeCitizenship() public {
        MembershipTypes.OrderInput memory effect = _order(1);
        vm.expectRevert(
            abi.encodeWithSelector(ISepoliaGovernedMembershipController.NotCurrentCongressMember.selector, TESTER_ONE)
        );
        vm.prank(TESTER_ONE);
        controller.recordRestriction(effect);
        vm.prank(TESTER_TWO);
        bytes32 receipt = controller.recordRestriction(effect);
        assertTrue(receipt != bytes32(0));
        assertTrue(membership.isRestrictedNow(bytes32(uint256(1)), MembershipTypes.Right.Political));
        assertEq(
            IdentityRegistry(d.identityRegistry).getIdentityRecord(bytes32(uint256(1))).personId, bytes32(uint256(1))
        );
        effect.personId = bytes32(uint256(5));
        vm.expectRevert(
            abi.encodeWithSelector(ISepoliaGovernedMembershipController.NotSyntheticPerson.selector, effect.personId)
        );
        vm.prank(TESTER_TWO);
        controller.recordRestriction(effect);
        assertEq(controller.nextReceiptNonce(), 1);
    }

    function test_ControllerCanBeReplacedWithoutOriginalDeployerOrLosingOrders() public {
        MembershipTypes.OrderInput memory effect = _order(1);
        vm.prank(TESTER_TWO);
        bytes32 originalReceipt = controller.recordRestriction(effect);
        SepoliaGovernedMembershipController replacement =
            new SepoliaGovernedMembershipController(d.identityRegistry, address(membership));
        assertFalse(replacement.canSubmit(TESTER_TWO));
        bytes32 action = _approveReplacement(address(replacement));
        GovernanceTypes.ActionRecord memory scheduled = queue.getAction(action);
        vm.warp(scheduled.earliestExecutionTime);
        queue.executeAction(action);
        assertEq(kernel.getModule(KernelModuleIds.IDENTITY_WRITER), address(replacement));
        assertFalse(controller.canSubmit(TESTER_TWO));
        assertTrue(replacement.canSubmit(TESTER_TWO));
        assertEq(membership.orderOf(effect.personId, effect.orderId).sourceReceiptId, originalReceipt);
        assertEq(membership.membershipRevisionOf(effect.personId), 1);
        assertTrue(membership.isRestrictedNow(effect.personId, MembershipTypes.Right.Political));
        vm.prank(TESTER_TWO);
        replacement.stayRestriction(effect.personId, effect.orderId, 1);
        assertFalse(membership.isRestrictedNow(effect.personId, MembershipTypes.Right.Political));
        assertEq(membership.orderOf(effect.personId, effect.orderId).sourceReceiptId, originalReceipt);
        assertEq(replacement.nextReceiptNonce(), 1);
        assertEq(controller.nextReceiptNonce(), 1);

        // A rollback is a second ordinary governed plan, retaining the ledger and all revisions.
        action = _approveReplacement(address(controller));
        scheduled = queue.getAction(action);
        vm.warp(scheduled.earliestExecutionTime);
        queue.executeAction(action);
        assertTrue(controller.canSubmit(TESTER_TWO));
        assertFalse(replacement.canSubmit(TESTER_TWO));
        vm.prank(TESTER_TWO);
        controller.revokeRestriction(effect.personId, effect.orderId, 2);
        assertEq(membership.membershipRevisionOf(effect.personId), 3);
        assertEq(membership.orderOf(effect.personId, effect.orderId).sourceReceiptId, originalReceipt);
    }

    function test_CongressCanStayResumeAndRevokeWithoutExtendingExpiryOrConsumingFailedReceipts() public {
        assertEq(controller.kernel(), d.kernel);
        assertEq(controller.identityRegistry(), d.identityRegistry);
        assertEq(controller.membershipRegistry(), address(membership));
        MembershipTypes.OrderInput memory effect = _order(7);
        effect.indefinite = false;
        effect.expiresAt = uint64(block.timestamp + 1 days);
        vm.prank(TESTER_TWO);
        bytes32 sourceReceipt = controller.recordRestriction(effect);
        vm.prank(TESTER_TWO);
        controller.stayRestriction(effect.personId, effect.orderId, 1);
        assertFalse(membership.isRestrictedNow(effect.personId, MembershipTypes.Right.Political));

        // A stale browser action cannot apply to a newer order or consume its synthetic receipt nonce.
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.OrderRevisionMismatch.selector, 1, 2));
        vm.prank(TESTER_TWO);
        controller.resumeRestriction(effect.personId, effect.orderId, 1);
        assertEq(controller.nextReceiptNonce(), 2);
        assertEq(membership.orderOf(effect.personId, effect.orderId).revision, 2);
        vm.prank(TESTER_TWO);
        controller.resumeRestriction(effect.personId, effect.orderId, 2);
        assertTrue(membership.isRestrictedNow(effect.personId, MembershipTypes.Right.Political));
        MembershipTypes.RestrictionOrder memory order = membership.orderOf(effect.personId, effect.orderId);
        assertEq(order.expiresAt, effect.expiresAt);
        assertEq(order.sourceReceiptId, sourceReceipt);
        assertEq(order.revision, 3);

        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.OrderRevisionMismatch.selector, 2, 3));
        vm.prank(TESTER_TWO);
        controller.revokeRestriction(effect.personId, effect.orderId, 2);
        assertEq(controller.nextReceiptNonce(), 3);
        vm.prank(TESTER_TWO);
        controller.stayRestriction(effect.personId, effect.orderId, 3);
        vm.warp(effect.expiresAt);
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.OrderExpired.selector, effect.expiresAt));
        vm.prank(TESTER_TWO);
        controller.resumeRestriction(effect.personId, effect.orderId, 4);
        assertEq(controller.nextReceiptNonce(), 4);
        assertEq(membership.orderOf(effect.personId, effect.orderId).revision, 4);
        assertFalse(membership.isRestrictedNow(effect.personId, MembershipTypes.Right.Political));

        // An expired stayed order remains revocable for a final procedural record, without resurrecting rights.
        vm.prank(TESTER_TWO);
        controller.revokeRestriction(effect.personId, effect.orderId, 4);
        order = membership.orderOf(effect.personId, effect.orderId);
        assertEq(uint256(order.status), uint256(MembershipTypes.OrderStatus.Revoked));
        assertEq(order.revision, 5);
        assertEq(order.sourceReceiptId, sourceReceipt);
        assertEq(controller.nextReceiptNonce(), 5);
        assertEq(membership.membershipRevisionOf(effect.personId), 5);
    }

    function test_ReplacementRejectsCrossKernelAndWrongIdentityLedgersBeforeItCanBeProposed() public {
        vm.expectRevert(
            abi.encodeWithSelector(ISepoliaGovernedMembershipController.InvalidDependency.selector, address(0))
        );
        new SepoliaGovernedMembershipController(address(0), address(membership));
        vm.expectRevert(
            abi.encodeWithSelector(ISepoliaGovernedMembershipController.InvalidDependency.selector, address(0))
        );
        new SepoliaGovernedMembershipController(d.identityRegistry, address(0));

        ConstitutionKernel otherKernel = new ConstitutionKernel(address(this));
        IdentityRegistry otherIdentity = new IdentityRegistry(address(otherKernel));
        MembershipRegistry otherMembership = new MembershipRegistry(address(otherKernel), address(otherIdentity));
        vm.expectRevert(
            abi.encodeWithSelector(
                ISepoliaGovernedMembershipController.DependencyMismatch.selector, d.kernel, address(otherKernel)
            )
        );
        new SepoliaGovernedMembershipController(d.identityRegistry, address(otherMembership));

        IdentityRegistry auxiliaryIdentity = new IdentityRegistry(d.kernel);
        MembershipRegistry auxiliaryMembership = new MembershipRegistry(d.kernel, address(auxiliaryIdentity));
        vm.expectRevert(
            abi.encodeWithSelector(
                ISepoliaGovernedMembershipController.DependencyMismatch.selector,
                d.identityRegistry,
                address(auxiliaryIdentity)
            )
        );
        new SepoliaGovernedMembershipController(d.identityRegistry, address(auxiliaryMembership));
        // Valid deployment alone never grants the successor permission while the current writer is unchanged.
        SepoliaGovernedMembershipController successor =
            new SepoliaGovernedMembershipController(d.identityRegistry, address(membership));
        assertFalse(successor.canSubmit(TESTER_TWO));
        assertEq(kernel.getModule(KernelModuleIds.IDENTITY_WRITER), address(controller));
    }

    function test_MembershipWriterReplacementCannotPassWithOnlyOneCitizen() public {
        SepoliaGovernedMembershipController replacement =
            new SepoliaGovernedMembershipController(d.identityRegistry, address(membership));
        ReferendumTypes.ModuleGovernanceProposal memory proposal = _proposal(address(replacement));
        vm.prank(TESTER_ONE);
        bytes32 id = referenda.createCitizenModuleGovernanceReferendum(proposal);
        vm.prank(address(stage));
        referenda.castVote(id, ReferendumTypes.VoteOption.For);
        vm.warp(proposal.endTime);
        referenda.finalizeReferendum(id);
        assertFalse(votes.getReferendumResult(id).passed);
        assertEq(kernel.getModule(KernelModuleIds.IDENTITY_WRITER), address(controller));
    }

    function test_GovernedControllerRejectsMainnetAndCannotBeUsedAfterChainChange() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(ISepoliaGovernedMembershipController.WrongChain.selector, uint256(1)));
        new SepoliaGovernedMembershipController(d.identityRegistry, address(membership));
        assertFalse(controller.canSubmit(TESTER_TWO));
        vm.expectRevert();
        stage.run();
        vm.expectRevert(abi.encodeWithSelector(ISepoliaGovernedMembershipController.WrongChain.selector, uint256(1)));
        vm.prank(TESTER_TWO);
        controller.recordRestriction(_order(1));
    }

    function test_TestersMustBeDistinctAndDoNotDefaultToUnsignableDummyAddresses() public {
        DeploySepoliaGovernedHarness invalid = new DeploySepoliaGovernedHarness();
        vm.expectRevert("duplicate governed tester");
        invalid.deployForTest([TESTER_ONE, TESTER_ONE, TESTER_THREE]);
        assertEq(IdentityRegistry(d.identityRegistry).activeWalletOf(bytes32(uint256(2))), TESTER_ONE);
        assertEq(IdentityRegistry(d.identityRegistry).activeWalletOf(bytes32(uint256(3))), TESTER_TWO);
        assertEq(IdentityRegistry(d.identityRegistry).activeWalletOf(bytes32(uint256(4))), TESTER_THREE);
        assertEq(CongressCandidateRegistry(d.congressCandidateRegistry).currentCongressMembers().length, 2);
    }

    function _order(uint256 id) private view returns (MembershipTypes.OrderInput memory) {
        return MembershipTypes.OrderInput(bytes32(uint256(1)), bytes32(id), 1, uint64(block.timestamp), 0, true);
    }

    function _proposal(address replacement) private view returns (ReferendumTypes.ModuleGovernanceProposal memory) {
        return ReferendumTypes.ModuleGovernanceProposal(
            keccak256("synthetic controller replacement metadata"),
            keccak256("synthetic controller replacement"),
            KernelModuleIds.IDENTITY_WRITER,
            replacement,
            false,
            uint64(block.timestamp),
            uint64(block.timestamp + 7 days),
            7 days
        );
    }

    function _approveReplacement(address replacement) private returns (bytes32 action) {
        ModuleUpgradePlanRegistry plans =
            ModuleUpgradePlanRegistry(kernel.getModule(KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY));
        GovernanceTypes.ModuleUpdate[] memory updates = new GovernanceTypes.ModuleUpdate[](1);
        updates[0] = GovernanceTypes.ModuleUpdate(
            KernelModuleIds.IDENTITY_WRITER,
            kernel.getModule(KernelModuleIds.IDENTITY_WRITER),
            replacement,
            replacement.codehash
        );
        bytes32 planId = plans.publishPlan(updates, keccak256(abi.encode("reviewed synthetic controller", replacement)));
        ReferendumTypes.ModuleBundleProposal memory proposal = ReferendumTypes.ModuleBundleProposal(
            keccak256("synthetic controller bundle metadata"),
            planId,
            address(plans),
            uint64(block.timestamp),
            uint64(block.timestamp + 7 days),
            7 days
        );
        vm.prank(TESTER_ONE);
        bytes32 id = referenda.createCitizenModuleBundleReferendum(proposal);
        vm.prank(TESTER_ONE);
        referenda.castVote(id, ReferendumTypes.VoteOption.For);
        vm.prank(TESTER_TWO);
        referenda.castVote(id, ReferendumTypes.VoteOption.For);
        vm.warp(proposal.endTime);
        referenda.finalizeReferendum(id);
        assertTrue(votes.getReferendumResult(id).passed);
        return votes.getReferendumResult(id).enactmentActionId;
    }
}
