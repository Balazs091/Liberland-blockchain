// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {LlmBackedUSDCFixture, ConstantInterestRatePolicy} from "../apps/LlmBackedUSDC.t.sol";
import {IUSDCLendingPoolApp} from "../../contracts/interfaces/IUSDCLendingPoolApp.sol";
import {IInterestRatePolicy} from "../../contracts/interfaces/IInterestRatePolicy.sol";
import {InterestRateBounds} from "../../contracts/libraries/InterestRateBounds.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {KinkedInterestRatePolicy} from "../../contracts/policies/KinkedInterestRatePolicy.sol";
import {FixedLlmUsdcPriceOraclePolicy} from "../../contracts/policies/FixedLlmUsdcPriceOraclePolicy.sol";

/// @notice Numerical configuration bounds and explicit underwater-liquidation semantics.
contract LendingRateBoundsTest is LlmBackedUSDCFixture {
    function test_PoolRejectsWrongInterestRateScale() public {
        vm.mockCall(address(interestRatePolicy), abi.encodeCall(IInterestRatePolicy.ray, ()), abi.encode(uint256(1e18)));
        vm.expectRevert(abi.encodeWithSelector(IUSDCLendingPoolApp.UnsupportedInterestRateScale.selector, 1e18));
        lendingPool.accrueInterest();
        vm.clearMockedCalls();
        lendingPool.accrueInterest();
        assertEq(lendingPool.borrowIndex(), 1e27);
    }

    function test_InterestPolicyRejectsUnsafeAggregateAndExtremeIndividualInputs() public {
        vm.expectRevert(abi.encodeWithSelector(KinkedInterestRatePolicy.InvalidAnnualRateBps.selector, 20_001));
        new KinkedInterestRatePolicy(5_000, 5_000, 10_001, 8e26);
        vm.expectRevert(
            abi.encodeWithSelector(KinkedInterestRatePolicy.InvalidAnnualRateBps.selector, type(uint256).max)
        );
        new KinkedInterestRatePolicy(0, 0, type(uint256).max, 8e26);

        KinkedInterestRatePolicy maximum = new KinkedInterestRatePolicy(0, 0, 20_000, 8e26);
        assertEq(maximum.borrowRatePerSecond(1e27), InterestRateBounds.MAX_RATE_PER_SECOND_RAY);
        assertLe(interestRatePolicy.borrowRatePerSecond(1e27), InterestRateBounds.MAX_RATE_PER_SECOND_RAY);
    }

    function test_ReplacementCannotPoisonStoredRateAndValidReplacementRestoresAccrual() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);
        uint256 storedIndex = lendingPool.borrowIndex();
        uint256 excessiveRate = InterestRateBounds.MAX_RATE_PER_SECOND_RAY + 1;
        ConstantInterestRatePolicy invalidPolicy = new ConstantInterestRatePolicy(excessiveRate);
        kernel.bootstrapSetModule(KernelModuleIds.USDC_INTEREST_RATE_POLICY, address(invalidPolicy));
        skip(1 days);
        vm.expectRevert(abi.encodeWithSelector(IUSDCLendingPoolApp.UnsupportedBorrowRate.selector, excessiveRate));
        lendingPool.accrueInterest();
        assertEq(lendingPool.borrowIndex(), storedIndex);

        kernel.bootstrapSetModule(KernelModuleIds.USDC_INTEREST_RATE_POLICY, address(interestRatePolicy));
        lendingPool.accrueInterest();
        assertGt(lendingPool.borrowIndex(), storedIndex);
        uint256 debt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        usdc.mint(BORROWER, debt);
        vm.startPrank(BORROWER);
        usdc.approve(address(lendingPool), debt);
        lendingPool.repay(type(uint256).max);
        vm.stopPrank();
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
    }

    function test_MaximumRateAndLaunchBorrowCapAccrueForFiftyYearsThenRepay() public {
        ConstantInterestRatePolicy maximum = new ConstantInterestRatePolicy(InterestRateBounds.MAX_RATE_PER_SECOND_RAY);
        kernel.bootstrapSetModule(KernelModuleIds.USDC_INTEREST_RATE_POLICY, address(maximum));
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(BORROWER_PERSON_ID, 4_000_000 * ONE_LLM);
        _fundAndDeposit(LP, 2_000_000 * USDC_UNIT);
        vm.prank(BORROWER);
        lendingPool.borrow(BORROW_CAP);
        skip(50 * 365 days);

        uint256 previewDebt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        lendingPool.accrueInterest();
        assertEq(lendingPool.totalBorrows(), previewDebt);
        assertGt(lendingPool.borrowIndex(), 1e70);
        assertLt(lendingPool.borrowIndex(), 3e70);
        assertLt(previewDebt, 3e55);
        usdc.mint(BORROWER, previewDebt);
        vm.startPrank(BORROWER);
        usdc.approve(address(lendingPool), previewDebt);
        lendingPool.repay(type(uint256).max);
        vm.stopPrank();
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        assertEq(lendingPool.borrowIndex(), 1e27);
        // Resetting a fully settled book restores even the smallest unit's borrowing precision.
        vm.prank(BORROWER);
        lendingPool.borrow(1);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 1);
    }

    function test_IndexResetsOnlyAfterTheLastBorrowerClosesWithoutChangingAssetsOrReserves() public {
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(LIQUIDATOR_PERSON_ID, 5_000 * ONE_LLM);
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);
        vm.prank(LIQUIDATOR);
        lendingPool.borrow(500 * USDC_UNIT);
        skip(365 days);
        lendingPool.accrueInterest();
        uint256 index = lendingPool.borrowIndex();
        assertGt(index, 1e27);
        uint256 otherDebt = lendingPool.currentDebtOf(LIQUIDATOR_PERSON_ID);
        uint256 assets = lendingPool.totalManagedAssets();
        uint256 reserves = lendingPool.totalReserves();
        uint256 shares = lendingPool.totalSupply();

        usdc.mint(BORROWER, lendingPool.currentDebtOf(BORROWER_PERSON_ID));
        vm.startPrank(BORROWER);
        usdc.approve(address(lendingPool), type(uint256).max);
        lendingPool.repay(type(uint256).max);
        vm.stopPrank();
        assertEq(lendingPool.borrowIndex(), index);
        assertEq(lendingPool.currentDebtOf(LIQUIDATOR_PERSON_ID), otherDebt);

        usdc.mint(LIQUIDATOR, otherDebt);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), otherDebt);
        lendingPool.repay(type(uint256).max);
        vm.stopPrank();
        assertEq(lendingPool.borrowIndex(), 1e27);
        assertEq(lendingPool.totalBorrows(), 0);
        assertEq(lendingPool.totalReserves(), reserves);
        assertEq(lendingPool.totalSupply(), shares);
        // Aggregated ceil debt can differ by at most one unit from two individually settled ceil debts.
        assertApproxEqAbs(lendingPool.totalManagedAssets(), assets, 1);
    }

    function test_LastBadDebtClosureResetsEmptyBookIndex() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);
        skip(365 days);
        lendingPool.accrueInterest();
        assertGt(lendingPool.borrowIndex(), 1e27);
        FixedLlmUsdcPriceOraclePolicy repriced = new FixedLlmUsdcPriceOraclePolicy(address(usdc), 1);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(repriced));
        usdc.mint(LIQUIDATOR, 4_348);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 4_348);
        lendingPool.liquidate(BORROWER_PERSON_ID, 4_347);
        // The first scaled-debt rounding leaves exactly enough collateral for one final paid micro-unit.
        // The maximum quote needs a second unit of rounding headroom; only the effective amount is pulled.
        (uint256 finalPaid,) = lendingPool.liquidate(BORROWER_PERSON_ID, 2);
        assertEq(finalPaid, 1);
        vm.stopPrank();
        lendingPool.absorbBadDebt(BORROWER_PERSON_ID);
        assertEq(lendingPool.borrowIndex(), 1e27);
        assertEq(lendingPool.totalBorrows(), 0);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
    }

    function test_UnderwaterPartialLiquidationRecoversAssetsDespiteWorseningRatio() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);
        // A severe external repricing, not the partial repayment, makes the position insolvent first.
        FixedLlmUsdcPriceOraclePolicy repriced = new FixedLlmUsdcPriceOraclePolicy(address(usdc), 180_000);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(repriced));
        uint256 healthBefore = lendingPool.healthFactorOf(BORROWER_PERSON_ID);
        uint256 cashBefore = usdc.balanceOf(address(lendingPool));
        uint256 totalStakeBefore = stakeRegistry.totalActiveStake();
        usdc.mint(LIQUIDATOR, 100 * USDC_UNIT);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 100 * USDC_UNIT);
        (uint256 repaid,) = lendingPool.liquidate(BORROWER_PERSON_ID, 100 * USDC_UNIT);
        vm.stopPrank();

        assertLt(lendingPool.healthFactorOf(BORROWER_PERSON_ID), healthBefore);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 1_000 * USDC_UNIT - repaid);
        assertEq(usdc.balanceOf(address(lendingPool)), cashBefore + repaid);
        assertEq(stakeRegistry.totalActiveStake(), totalStakeBefore);
    }
}
