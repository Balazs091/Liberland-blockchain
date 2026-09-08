// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {TreasuryVault} from "../../contracts/apps/TreasuryVault.sol";
import {BudgetEnvelopeRegistry} from "../../contracts/registries/BudgetEnvelopeRegistry.sol";
import {ITreasuryVault} from "../../contracts/interfaces/ITreasuryVault.sol";
import {IBudgetEnvelopeRegistry} from "../../contracts/interfaces/IBudgetEnvelopeRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockUSDC} from "../../contracts/mocks/MockUSDC.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";

contract TreasuryHandoffFeeToken is MockUSDC {
    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0) && amount > 1) {
            super._update(from, address(0), 1);
            amount -= 1;
        }
        super._update(from, to, amount);
    }
}

/// @notice Tests the custody/accounting layer; real queued replacement is covered in TreasuryAndOfficesTest.
contract TreasuryUpgradeTest is Test {
    ConstitutionKernel private kernel;
    TreasuryVault private original;
    BudgetEnvelopeRegistry private budgets;
    MockUSDC private token;
    address private nextWriter;
    bytes32 private constant BUDGET = keccak256("upgrade.budget");
    bytes32 private constant REQUEST = keccak256("upgrade.request");

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        original = new TreasuryVault(address(kernel));
        budgets = new BudgetEnvelopeRegistry(address(kernel));
        token = new MockUSDC();
        nextWriter = address(new MockModule(keccak256("next.writer")));
        kernel.bootstrapSetModule(KernelModuleIds.TREASURY_VAULT, address(original));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY, address(budgets));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));
        kernel.disableBootstrapAuthority();
        budgets.recordBudgetApproval(
            BUDGET,
            TreasuryTypes.BudgetEnvelopeInput({
                officeId: keccak256("finance"),
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(token),
                allocatedAmount: 10_000,
                startsAt: uint64(block.timestamp),
                endsAt: uint64(block.timestamp + 365 days),
                policyReference: bytes32(0)
            })
        );
        token.mint(address(original), 10_000);
    }

    function test_HandoffHasOnlyGovernedReceiverAndPreservesExecutionReceipts() public {
        budgets.reserveBudget(REQUEST, BUDGET, 100);
        original.executeDisbursement(_payload());
        TreasuryVault next = new TreasuryVault(address(kernel));
        kernel.governanceUpdateModule(KernelModuleIds.TREASURY_VAULT, address(next));
        vm.prank(address(0xBEEF));
        assertEq(original.handoffAsset(address(token)), 9_900);
        assertEq(token.balanceOf(address(original)), 0);
        assertEq(token.balanceOf(address(next)), 9_900);
        assertTrue(original.isDisbursementExecuted(REQUEST));
        assertFalse(next.isDisbursementExecuted(REQUEST));
        // Accounting can still consume the old receipt without copying it into the new vault.
        budgets.recordDisbursement(REQUEST);
        assertEq(budgets.getBudgetEnvelope(BUDGET).spentAmount, 100);
        vm.expectRevert(abi.encodeWithSelector(ITreasuryVault.InactiveTreasuryVault.selector, address(original)));
        original.executeDisbursement(_payload());
    }

    function test_CurrentOrDifferentKernelVaultCannotReceiveHandoff() public {
        vm.expectRevert(
            abi.encodeWithSelector(ITreasuryVault.IncompatibleTreasurySuccessor.selector, address(original))
        );
        original.handoffAsset(address(token));
        TreasuryVault foreign = new TreasuryVault(address(new ConstitutionKernel(address(this))));
        kernel.governanceUpdateModule(KernelModuleIds.TREASURY_VAULT, address(foreign));
        vm.expectRevert(abi.encodeWithSelector(ITreasuryVault.IncompatibleTreasurySuccessor.selector, address(foreign)));
        original.handoffAsset(address(token));
        assertEq(token.balanceOf(address(original)), 10_000);
    }

    function test_HandoffRejectsUnderpaymentAtomically() public {
        TreasuryHandoffFeeToken feeToken = new TreasuryHandoffFeeToken();
        feeToken.mint(address(original), 100);
        TreasuryVault next = new TreasuryVault(address(kernel));
        kernel.governanceUpdateModule(KernelModuleIds.TREASURY_VAULT, address(next));
        vm.expectRevert(abi.encodeWithSelector(ITreasuryVault.UnexpectedDisbursementAmount.selector, 100, 99));
        original.handoffAsset(address(feeToken));
        assertEq(feeToken.balanceOf(address(original)), 100);
        assertEq(feeToken.balanceOf(address(next)), 0);
    }

    function test_HandoffSupportsLateDepositsAndGovernedRollback() public {
        TreasuryVault next = new TreasuryVault(address(kernel));
        kernel.governanceUpdateModule(KernelModuleIds.TREASURY_VAULT, address(next));
        original.handoffAsset(address(token));
        vm.expectRevert(abi.encodeWithSelector(ITreasuryVault.InvalidTreasuryDeposit.selector, 0));
        original.handoffAsset(address(token));
        token.mint(address(original), 7);
        assertEq(original.handoffAsset(address(token)), 7);
        kernel.governanceUpdateModule(KernelModuleIds.TREASURY_VAULT, address(original));
        assertEq(next.handoffAsset(address(token)), 10_007);
        assertEq(token.balanceOf(address(original)), 10_007);
    }

    function testFuzz_RetiredWriterCanOnlySettleItsExistingCommitment(bool spent) public {
        budgets.reserveBudget(REQUEST, BUDGET, 100);
        kernel.governanceUpdateModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, nextWriter);
        assertEq(budgets.commitmentAuthority(REQUEST), address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBudgetEnvelopeRegistry.UnauthorizedBudgetEnvelopeRegistryCaller.selector, address(this)
            )
        );
        budgets.reserveBudget(keccak256("other"), BUDGET, 100);
        if (spent) {
            original.executeDisbursement(_payload());
            budgets.recordDisbursement(REQUEST);
        } else {
            budgets.releaseBudget(REQUEST);
        }
        assertEq(budgets.commitmentAuthority(REQUEST), address(0));
        assertEq(budgets.getBudgetEnvelope(BUDGET).committedAmount, 0);
        assertEq(budgets.getBudgetEnvelope(BUDGET).spentAmount, spent ? 100 : 0);
        bytes32 nextRequest = spent ? keccak256("next.request") : REQUEST;
        vm.prank(nextWriter);
        budgets.reserveBudget(nextRequest, BUDGET, 200);
        assertEq(budgets.commitmentAuthority(nextRequest), nextWriter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBudgetEnvelopeRegistry.UnauthorizedBudgetEnvelopeRegistryCaller.selector, address(this)
            )
        );
        budgets.releaseBudget(nextRequest);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBudgetEnvelopeRegistry.UnauthorizedBudgetEnvelopeRegistryCaller.selector, address(this)
            )
        );
        budgets.recordDisbursement(nextRequest);
        assertEq(budgets.getBudgetEnvelope(BUDGET).committedAmount, 200);
    }

    function test_StatefulPayoutQueueRequiresStateModuleRoute() public view {
        assertEq(uint256(kernel.moduleClass(KernelModuleIds.PAYOUT_QUEUE)), uint256(GovernanceTypes.ModuleClass.State));
    }

    function test_StableReceiptBlocksUnsyncedDuplicateThroughNewVault() public {
        budgets.reserveBudget(REQUEST, BUDGET, 100);
        original.executeDisbursement(_payload());
        TreasuryVault next = new TreasuryVault(address(kernel));
        kernel.governanceUpdateModule(KernelModuleIds.TREASURY_VAULT, address(next));
        original.handoffAsset(address(token));
        assertTrue(budgets.hasCommittedRequest(REQUEST));
        assertTrue(budgets.isRequestExecuted(REQUEST));
        assertFalse(next.isDisbursementExecuted(REQUEST));
        vm.expectRevert(abi.encodeWithSelector(IBudgetEnvelopeRegistry.BudgetRequestAlreadyExecuted.selector, REQUEST));
        next.executeDisbursement(_payload());
        assertEq(token.balanceOf(address(0xA11CE)), 100);
        assertEq(token.balanceOf(address(next)), 9_900);
        assertFalse(next.isDisbursementExecuted(REQUEST));
        budgets.recordDisbursement(REQUEST);
        assertTrue(budgets.isRequestExecuted(REQUEST));
        assertEq(budgets.getBudgetEnvelope(BUDGET).spentAmount, 100);
    }

    function test_ExecutedIdentifierCannotBeReusedAfterWriterAndVaultReplacement() public {
        budgets.reserveBudget(REQUEST, BUDGET, 100);
        original.executeDisbursement(_payload());
        budgets.recordDisbursement(REQUEST);
        TreasuryVault next = new TreasuryVault(address(kernel));
        kernel.governanceUpdateModule(KernelModuleIds.TREASURY_VAULT, address(next));
        kernel.governanceUpdateModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, nextWriter);
        original.handoffAsset(address(token));
        assertFalse(budgets.hasCommittedRequest(REQUEST));
        vm.prank(nextWriter);
        vm.expectRevert(abi.encodeWithSelector(IBudgetEnvelopeRegistry.BudgetRequestAlreadyExecuted.selector, REQUEST));
        budgets.reserveBudget(REQUEST, BUDGET, 100);
        assertEq(token.balanceOf(address(0xA11CE)), 100);
        assertEq(budgets.getBudgetEnvelope(BUDGET).committedAmount, 0);
    }

    function test_OnlyCurrentVaultCanMarkActiveCommitmentAndOnlyOnce() public {
        budgets.reserveBudget(REQUEST, BUDGET, 100);
        vm.expectPartialRevert(IBudgetEnvelopeRegistry.UnauthorizedBudgetEnvelopeRegistryCaller.selector);
        budgets.markExecution(REQUEST);
        TreasuryVault next = new TreasuryVault(address(kernel));
        kernel.governanceUpdateModule(KernelModuleIds.TREASURY_VAULT, address(next));
        vm.prank(address(original));
        vm.expectPartialRevert(IBudgetEnvelopeRegistry.UnauthorizedBudgetEnvelopeRegistryCaller.selector);
        budgets.markExecution(REQUEST);
        vm.prank(address(next));
        vm.expectPartialRevert(IBudgetEnvelopeRegistry.BudgetRequestCommitmentMissing.selector);
        budgets.markExecution(keccak256("unknown.request"));
        vm.prank(address(next));
        budgets.markExecution(REQUEST);
        vm.prank(address(next));
        vm.expectRevert(abi.encodeWithSelector(IBudgetEnvelopeRegistry.BudgetRequestAlreadyExecuted.selector, REQUEST));
        budgets.markExecution(REQUEST);
        assertTrue(budgets.isRequestExecuted(REQUEST));
    }

    function test_RejectedTokenTransferRollsBackStableAndLocalExecutionReceipts() public {
        TreasuryHandoffFeeToken feeToken = new TreasuryHandoffFeeToken();
        bytes32 feeBudget = keccak256("fee.budget");
        budgets.recordBudgetApproval(
            feeBudget,
            TreasuryTypes.BudgetEnvelopeInput({
                officeId: keccak256("finance"),
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(feeToken),
                allocatedAmount: 100,
                startsAt: uint64(block.timestamp),
                endsAt: uint64(block.timestamp + 365 days),
                policyReference: bytes32(0)
            })
        );
        feeToken.mint(address(original), 100);
        budgets.reserveBudget(REQUEST, feeBudget, 100);
        GovernanceTypes.TreasuryDisbursementPayload memory payload = _payload();
        payload.asset = address(feeToken);
        payload.budgetId = feeBudget;
        vm.expectRevert(abi.encodeWithSelector(ITreasuryVault.UnexpectedDisbursementAmount.selector, 100, 99));
        original.executeDisbursement(payload);
        assertFalse(budgets.isRequestExecuted(REQUEST));
        assertFalse(original.isDisbursementExecuted(REQUEST));
        assertTrue(budgets.hasCommittedRequest(REQUEST));
        assertEq(feeToken.balanceOf(address(original)), 100);
        assertEq(feeToken.balanceOf(payload.recipient), 0);
    }

    function test_CanceledUnexecutedIdentifierCanBeReservedAgain() public {
        budgets.reserveBudget(REQUEST, BUDGET, 100);
        budgets.releaseBudget(REQUEST);
        assertFalse(budgets.isRequestExecuted(REQUEST));
        kernel.governanceUpdateModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, nextWriter);
        vm.prank(nextWriter);
        budgets.reserveBudget(REQUEST, BUDGET, 200);
        assertTrue(budgets.hasCommittedRequest(REQUEST));
        assertEq(budgets.commitmentAuthority(REQUEST), nextWriter);
        assertEq(budgets.getBudgetEnvelope(BUDGET).committedAmount, 200);
    }

    function testFuzz_CurrentOrRetiredWriterCannotReleaseExecutedCommitment(bool retired) public {
        budgets.reserveBudget(REQUEST, BUDGET, 100);
        original.executeDisbursement(_payload());
        if (retired) {
            kernel.governanceUpdateModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, nextWriter);
        }
        vm.expectRevert(abi.encodeWithSelector(IBudgetEnvelopeRegistry.BudgetRequestAlreadyExecuted.selector, REQUEST));
        budgets.releaseBudget(REQUEST);
        assertTrue(budgets.hasCommittedRequest(REQUEST));
        assertEq(budgets.availableAmount(BUDGET), 9_900);
        budgets.recordDisbursement(REQUEST);
        assertEq(budgets.getBudgetEnvelope(BUDGET).spentAmount, 100);
        assertEq(budgets.getBudgetEnvelope(BUDGET).committedAmount, 0);
        assertEq(budgets.availableAmount(BUDGET), 9_900);
        assertEq(token.balanceOf(address(0xA11CE)), 100);
    }

    function testFuzz_CurrentOrRetiredWriterCannotRecordUnexecutedCommitmentAsSpent(bool retired) public {
        budgets.reserveBudget(REQUEST, BUDGET, 100);
        if (retired) {
            kernel.governanceUpdateModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, nextWriter);
        }
        vm.expectRevert(abi.encodeWithSelector(IBudgetEnvelopeRegistry.BudgetRequestNotExecuted.selector, REQUEST));
        budgets.recordDisbursement(REQUEST);
        assertTrue(budgets.hasCommittedRequest(REQUEST));
        assertEq(budgets.getBudgetEnvelope(BUDGET).spentAmount, 0);
        assertEq(token.balanceOf(address(0xA11CE)), 0);
        budgets.releaseBudget(REQUEST);
        assertEq(budgets.availableAmount(BUDGET), 10_000);
    }

    function _payload() private view returns (GovernanceTypes.TreasuryDisbursementPayload memory) {
        return GovernanceTypes.TreasuryDisbursementPayload({
            requestId: REQUEST,
            budgetId: BUDGET,
            recipient: address(0xA11CE),
            asset: address(token),
            amount: 100,
            noteHash: bytes32(0)
        });
    }
}
