// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {LlmBackedUSDCFixture} from "../apps/LlmBackedUSDC.t.sol";
import {USDCLendingPoolApp} from "../../contracts/apps/USDCLendingPoolApp.sol";
import {IStakeLienRegistry} from "../../contracts/interfaces/IStakeLienRegistry.sol";
import {IStakeRegistry} from "../../contracts/interfaces/IStakeRegistry.sol";
import {IUSDCLendingPoolApp} from "../../contracts/interfaces/IUSDCLendingPoolApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {FixedLlmUsdcPriceOraclePolicy} from "../../contracts/policies/FixedLlmUsdcPriceOraclePolicy.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";

/// @notice Regression tests for safe retirement of an outstanding lending book, using the standard lending fixture.
contract WorkflowLivenessAuditTest is LlmBackedUSDCFixture {
    function test_WorkflowAudit_UnrelatedCitizenPolicyFailureDoesNotFreezeUnencumberedStake() public {
        MockModule incompatible = new MockModule(keccak256("incompatible-citizen-policy"));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(incompatible));
        uint256 expected = unstakingPolicy.unstakePortion(10_000 * ONE_LLM);
        vm.prank(address(stakeAuthority));
        (uint256 released,) = stakeRegistry.unstake(BORROWER_PERSON_ID);
        assertEq(released, expected);
    }

    function test_WorkflowAudit_FinalLiquidationUsesCapturedFloorWithIncompatibleCitizenPolicy() public {
        _borrow(1_250 * USDC_UNIT);
        _replacePool();
        _setPrice(USDC_UNIT / 2);
        MockModule incompatible = new MockModule(keccak256("incompatible-citizen-policy"));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(incompatible));
        usdc.mint(LIQUIDATOR, 1_250 * USDC_UNIT);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 1_250 * USDC_UNIT);
        lendingPool.liquidate(BORROWER_PERSON_ID, 1_250 * USDC_UNIT);
        vm.stopPrank();
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        assertEq(stakeRegistry.activeStakeOf(BORROWER_PERSON_ID), 7_125 * ONE_LLM);
    }

    function testFuzz_WorkflowAudit_RetiredRepaymentWithAccrual(uint32 borrowed, uint32 elapsed) public {
        _borrow(bound(uint256(borrowed), USDC_UNIT, 1_500 * USDC_UNIT));
        skip(bound(uint256(elapsed), 1, 60 days));
        _replacePool();
        uint256 debt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        uint256 cashBefore = usdc.balanceOf(address(lendingPool));
        uint256 totalStakeBefore = stakeRegistry.totalActiveStake();
        usdc.mint(BORROWER, debt);
        vm.startPrank(BORROWER);
        usdc.approve(address(lendingPool), debt);
        uint256 partialPayment = lendingPool.repay(debt / 2);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(lendingPool));
        uint256 finalPayment = lendingPool.repay(type(uint256).max);
        vm.stopPrank();
        assertEq(partialPayment + finalPayment, debt);
        assertEq(usdc.balanceOf(address(lendingPool)), cashBefore + debt);
        assertEq(stakeRegistry.totalActiveStake(), totalStakeBefore);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
    }

    function test_WorkflowAudit_RetiredPoolCannotBorrowOrTopUp() public {
        _borrow(1_000 * USDC_UNIT);
        _replacePool();

        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 0);
        vm.prank(BORROWER);
        vm.expectRevert(IUSDCLendingPoolApp.RetiredLendingPool.selector);
        lendingPool.borrow(500 * USDC_UNIT);
        vm.prank(LIQUIDATOR);
        vm.expectRevert(IUSDCLendingPoolApp.RetiredLendingPool.selector);
        lendingPool.borrow(1);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 1_000 * USDC_UNIT);
    }

    function test_WorkflowAudit_ReplacementCannotReuseOutstandingCollateral() public {
        _borrow(1_500 * USDC_UNIT);
        USDCLendingPoolApp successor = _replacePool();
        _fundSuccessor(successor);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(lendingPool));
        assertEq(successor.maxBorrowable(BORROWER_PERSON_ID), 0);

        vm.prank(BORROWER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IUSDCLendingPoolApp.ForeignLoanBook.selector, BORROWER_PERSON_ID, address(lendingPool)
            )
        );
        successor.borrow(1_500 * USDC_UNIT);
        assertEq(successor.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(usdc.balanceOf(BORROWER), 1_500 * USDC_UNIT);
    }

    function test_WorkflowAudit_RetiredPartialAndFullRepaymentThenSuccessorBorrow() public {
        _borrow(1_000 * USDC_UNIT);
        USDCLendingPoolApp successor = _replacePool();
        _fundSuccessor(successor);

        vm.startPrank(BORROWER);
        usdc.approve(address(lendingPool), type(uint256).max);
        assertEq(lendingPool.repay(400 * USDC_UNIT), 400 * USDC_UNIT);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(lendingPool));
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 5_000 * ONE_LLM);
        assertEq(lendingPool.repay(600 * USDC_UNIT), 600 * USDC_UNIT);
        vm.stopPrank();

        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(usdc.balanceOf(address(lendingPool)), 10_000 * USDC_UNIT);
        vm.prank(LP);
        lendingPool.withdraw(10_000 * USDC_UNIT, LP);
        assertEq(lendingPool.balanceOf(LP), 0);

        vm.prank(BORROWER);
        successor.borrow(1_500 * USDC_UNIT);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(successor));
        vm.prank(address(lendingPool));
        vm.expectPartialRevert(IStakeLienRegistry.LoanBookConflict.selector);
        stakeLienRegistry.closeLoan(BORROWER_PERSON_ID);
        assertEq(successor.currentDebtOf(BORROWER_PERSON_ID), 1_500 * USDC_UNIT);
    }

    function test_WorkflowAudit_RetiredRepayForRemainsPermissionless() public {
        _borrow(1_000 * USDC_UNIT);
        _replacePool();
        usdc.mint(LIQUIDATOR, 1_000 * USDC_UNIT);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 1_000 * USDC_UNIT);
        lendingPool.repayFor(BORROWER_PERSON_ID, 1_000 * USDC_UNIT);
        vm.stopPrank();
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
    }

    function test_WorkflowAudit_RetiredPartialAndFinalLiquidationConserveCollateral() public {
        _borrow(1_250 * USDC_UNIT);
        _replacePool();
        _setPrice(USDC_UNIT / 2);
        uint256 totalBefore = stakeRegistry.totalActiveStake();
        uint256 liquidatorBefore = stakeRegistry.activeStakeOf(LIQUIDATOR_PERSON_ID);
        uint256 cashBefore = usdc.balanceOf(address(lendingPool));
        usdc.mint(LIQUIDATOR, 1_250 * USDC_UNIT);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 1_250 * USDC_UNIT);
        (uint256 paidFirst, uint256 seizedFirst) = lendingPool.liquidate(BORROWER_PERSON_ID, 250 * USDC_UNIT);
        assertEq(paidFirst, 250 * USDC_UNIT);
        assertEq(seizedFirst, 575 * ONE_LLM);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 4_425 * ONE_LLM);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(lendingPool));
        (uint256 paidFinal, uint256 seizedFinal) = lendingPool.liquidate(BORROWER_PERSON_ID, 1_000 * USDC_UNIT);
        vm.stopPrank();

        assertEq(paidFinal, 1_000 * USDC_UNIT);
        assertEq(seizedFinal, 2_300 * ONE_LLM);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeRegistry.activeStakeOf(BORROWER_PERSON_ID), 7_125 * ONE_LLM);
        assertEq(stakeRegistry.activeStakeOf(LIQUIDATOR_PERSON_ID), liquidatorBefore + seizedFirst + seizedFinal);
        assertEq(stakeRegistry.totalActiveStake(), totalBefore);
        assertEq(usdc.balanceOf(address(lendingPool)), cashBefore + paidFirst + paidFinal);
    }

    function test_WorkflowAudit_ZeroLienDebtRetainsOwnershipAndFloorUntilAbsorption() public {
        _borrow(1_250 * USDC_UNIT);
        USDCLendingPoolApp successor = _replacePool();
        _setPrice(250_000);
        usdc.mint(LIQUIDATOR, 1_086_956_521);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 1_086_956_521);
        lendingPool.liquidate(BORROWER_PERSON_ID, 1_086_956_521);
        vm.stopPrank();
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(lendingPool));
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 163_043_479);

        CitizenEligibilityPolicy higherFloor =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), 9_000 * ONE_LLM);
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(higherFloor));
        assertEq(stakeLienRegistry.retainedStakeFloorOf(BORROWER_PERSON_ID), MINIMUM_RETAINED_STAKE);
        assertEq(successor.maxBorrowable(BORROWER_PERSON_ID), 0);
        lendingPool.absorbBadDebt(BORROWER_PERSON_ID);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        assertEq(stakeLienRegistry.retainedStakeFloorOf(BORROWER_PERSON_ID), 9_000 * ONE_LLM);
    }

    function test_WorkflowAudit_ZeroLienDebtCanBeFullyRepaidAfterRetirement() public {
        _borrow(1_250 * USDC_UNIT);
        _replacePool();
        _setPrice(250_000);
        usdc.mint(LIQUIDATOR, 1_086_956_521);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 1_086_956_521);
        lendingPool.liquidate(BORROWER_PERSON_ID, 1_086_956_521);
        vm.stopPrank();
        uint256 debt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        vm.startPrank(BORROWER);
        usdc.approve(address(lendingPool), debt);
        lendingPool.repay(debt);
        vm.stopPrank();
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
    }

    function test_WorkflowAudit_OnlyRecordedOwnerCanSettleAndOwnerCannotTakeOtherPositions() public {
        _borrow(1_000 * USDC_UNIT);
        USDCLendingPoolApp successor = _replacePool();

        vm.startPrank(address(successor));
        vm.expectPartialRevert(IStakeLienRegistry.LoanBookConflict.selector);
        stakeLienRegistry.increaseLien(BORROWER_PERSON_ID, 1);
        vm.expectPartialRevert(IStakeLienRegistry.LoanBookConflict.selector);
        stakeLienRegistry.decreaseLien(BORROWER_PERSON_ID, 1);
        vm.expectPartialRevert(IStakeLienRegistry.LoanBookConflict.selector);
        stakeLienRegistry.closeLoan(BORROWER_PERSON_ID);
        vm.expectPartialRevert(IStakeLienRegistry.LoanBookConflict.selector);
        stakeLienRegistry.settleLiquidation(BORROWER_PERSON_ID, LIQUIDATOR_PERSON_ID, 1, 0, true);
        vm.stopPrank();

        vm.startPrank(address(lendingPool));
        vm.expectPartialRevert(IStakeLienRegistry.UnauthorizedStakeLienRegistryCaller.selector);
        stakeLienRegistry.increaseLien(BORROWER_PERSON_ID, 1);
        vm.expectPartialRevert(IStakeLienRegistry.LoanBookConflict.selector);
        stakeLienRegistry.settleLiquidation(LIQUIDATOR_PERSON_ID, BORROWER_PERSON_ID, 1, 0, true);
        vm.expectPartialRevert(IStakeRegistry.UnauthorizedStakeRegistryCaller.selector);
        stakeRegistry.transferActiveStake(LIQUIDATOR_PERSON_ID, BORROWER_PERSON_ID, 1);
        vm.stopPrank();

        vm.prank(address(successor));
        vm.expectPartialRevert(IStakeRegistry.UnauthorizedStakeRegistryCaller.selector);
        stakeRegistry.transferActiveStake(LIQUIDATOR_PERSON_ID, BORROWER_PERSON_ID, 1);
        vm.expectPartialRevert(IStakeLienRegistry.LoanBookConflict.selector);
        stakeLienRegistry.closeLoan(BORROWER_PERSON_ID);
    }

    function test_WorkflowAudit_TypedSettlementRejectsLienIncreaseAndFloorBreach() public {
        _borrow(1_000 * USDC_UNIT);
        _replacePool();
        vm.startPrank(address(lendingPool));
        vm.expectPartialRevert(IStakeLienRegistry.InvalidLiquidationSettlement.selector);
        stakeLienRegistry.settleLiquidation(BORROWER_PERSON_ID, LIQUIDATOR_PERSON_ID, 1, 5_000 * ONE_LLM + 1, false);
        vm.expectPartialRevert(IStakeLienRegistry.LienExceedsActiveStake.selector);
        stakeLienRegistry.settleLiquidation(BORROWER_PERSON_ID, LIQUIDATOR_PERSON_ID, 5_000 * ONE_LLM + 1, 0, true);
        vm.expectPartialRevert(IStakeLienRegistry.InvalidLiquidationSettlement.selector);
        stakeLienRegistry.settleLiquidation(BORROWER_PERSON_ID, LIQUIDATOR_PERSON_ID, 1, 1, true);
        vm.stopPrank();
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(lendingPool));
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 5_000 * ONE_LLM);
    }

    function test_WorkflowAudit_DownstreamFailureRollsBackDebtTokensLienAndOwnership() public {
        _borrow(1_250 * USDC_UNIT);
        _replacePool();
        _setPrice(USDC_UNIT / 2);
        usdc.mint(LIQUIDATOR, 1_250 * USDC_UNIT);
        vm.prank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 1_250 * USDC_UNIT);
        bytes memory failure = abi.encodeWithSignature("Error(string)", "synthetic stake transfer failure");
        vm.mockCallRevert(
            address(stakeRegistry), abi.encodeWithSelector(IStakeRegistry.transferActiveStake.selector), failure
        );
        vm.prank(LIQUIDATOR);
        vm.expectRevert(failure);
        lendingPool.liquidate(BORROWER_PERSON_ID, 1_250 * USDC_UNIT);
        vm.clearMockedCalls();
        assertEq(usdc.balanceOf(LIQUIDATOR), 1_250 * USDC_UNIT);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 1_250 * USDC_UNIT);
        assertEq(stakeRegistry.activeStakeOf(BORROWER_PERSON_ID), 10_000 * ONE_LLM);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(lendingPool));
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 5_000 * ONE_LLM);
    }

    function test_WorkflowAudit_UnpairedAuthorityBlocksQuoteAndBorrow() public {
        USDCLendingPoolApp successor = _newPool();
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY, address(successor));
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 0);
        vm.prank(BORROWER);
        vm.expectRevert(IUSDCLendingPoolApp.RetiredLendingPool.selector);
        lendingPool.borrow(1);
    }

    function _borrow(uint256 amount) private {
        vm.prank(BORROWER);
        lendingPool.borrow(amount);
    }

    function _newPool() private returns (USDCLendingPoolApp) {
        return new USDCLendingPoolApp(
            address(kernel),
            address(usdc),
            address(identityRegistry),
            address(stakeRegistry),
            address(stakeLienRegistry),
            BORROW_CAP
        );
    }

    function _replacePool() private returns (USDCLendingPoolApp successor) {
        successor = _newPool();
        kernel.bootstrapSetModule(KernelModuleIds.USDC_LENDING_POOL_APP, address(successor));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY, address(successor));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY, address(successor));
    }

    function _fundSuccessor(USDCLendingPoolApp successor) private {
        usdc.mint(LP, 10_000 * USDC_UNIT);
        vm.startPrank(LP);
        usdc.approve(address(successor), 10_000 * USDC_UNIT);
        successor.deposit(10_000 * USDC_UNIT, LP);
        vm.stopPrank();
    }

    function _setPrice(uint256 price) private {
        FixedLlmUsdcPriceOraclePolicy nextOracle = new FixedLlmUsdcPriceOraclePolicy(address(usdc), price);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(nextOracle));
    }
}
