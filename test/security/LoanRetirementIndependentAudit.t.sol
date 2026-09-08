// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {LlmBackedUSDCFixture} from "../apps/LlmBackedUSDC.t.sol";
import {USDCLendingPoolApp} from "../../contracts/apps/USDCLendingPoolApp.sol";
import {StakeLienRegistry} from "../../contracts/registries/StakeLienRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {IStakeLienRegistry} from "../../contracts/interfaces/IStakeLienRegistry.sol";
import {IUSDCLendingPoolApp} from "../../contracts/interfaces/IUSDCLendingPoolApp.sol";
import {FixedLlmUsdcPriceOraclePolicy} from "../../contracts/policies/FixedLlmUsdcPriceOraclePolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";

/// @notice Independent characterization of collateral and canonical-pointer boundaries during pool retirement.
contract LoanRetirementIndependentAuditTest is LlmBackedUSDCFixture {
    function test_IndependentAudit_RetiredPoolCannotSeizeLaterUnpledgedStake() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);
        uint256 recordedLien = stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID);
        assertEq(recordedLien, 5_000 * ONE_LLM);
        USDCLendingPoolApp successor = new USDCLendingPoolApp(
            address(kernel),
            address(usdc),
            address(identityRegistry),
            address(stakeRegistry),
            address(stakeLienRegistry),
            BORROW_CAP
        );
        kernel.bootstrapSetModule(KernelModuleIds.USDC_LENDING_POOL_APP, address(successor));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY, address(successor));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY, address(successor));

        // Legitimate additional political stake after retirement does not increase the retired pool's recorded lien.
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(BORROWER_PERSON_ID, 10_000 * ONE_LLM);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), recordedLien);
        FixedLlmUsdcPriceOraclePolicy crash = new FixedLlmUsdcPriceOraclePolicy(address(usdc), USDC_UNIT / 10);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(crash));
        usdc.mint(LIQUIDATOR, 1_250 * USDC_UNIT);
        uint256 totalStake = stakeRegistry.totalActiveStake();
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 1_250 * USDC_UNIT);
        vm.expectPartialRevert(IUSDCLendingPoolApp.InsufficientLiquidationCollateral.selector);
        lendingPool.liquidate(BORROWER_PERSON_ID, 1_250 * USDC_UNIT);
        (uint256 repaid, uint256 seized) = lendingPool.liquidate(BORROWER_PERSON_ID, 434_782_608);
        vm.stopPrank();
        assertEq(repaid, 434_782_608);
        assertEq(seized, recordedLien);
        assertEq(stakeRegistry.activeStakeOf(BORROWER_PERSON_ID), 15_000 * ONE_LLM);
        assertEq(stakeRegistry.totalActiveStake(), totalStake);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(lendingPool));
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(lendingPool.healthFactorOf(BORROWER_PERSON_ID), 0);
        // Newly added unpledged stake must not freeze bad-debt closure after the retired numerical lien is exhausted.
        (uint256 writtenOff,,) = lendingPool.absorbBadDebt(BORROWER_PERSON_ID);
        assertEq(writtenOff, 815_217_392);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        assertEq(stakeRegistry.activeStakeOf(BORROWER_PERSON_ID), 15_000 * ONE_LLM);
    }

    function test_IndependentAudit_CurrentPoolKeepsAllActiveSurplusCollateralModel() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(BORROWER_PERSON_ID, 10_000 * ONE_LLM);
        FixedLlmUsdcPriceOraclePolicy crash = new FixedLlmUsdcPriceOraclePolicy(address(usdc), USDC_UNIT / 10);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(crash));
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 5_000 * ONE_LLM);
        usdc.mint(LIQUIDATOR, 1_250 * USDC_UNIT);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 1_250 * USDC_UNIT);
        (, uint256 seized) = lendingPool.liquidate(BORROWER_PERSON_ID, 1_250 * USDC_UNIT);
        vm.stopPrank();
        assertEq(seized, 14_375 * ONE_LLM);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
    }

    function test_IndependentAudit_RetiredRegistryCannotReuseSeizureBudget() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);
        USDCLendingPoolApp successor = new USDCLendingPoolApp(
            address(kernel),
            address(usdc),
            address(identityRegistry),
            address(stakeRegistry),
            address(stakeLienRegistry),
            BORROW_CAP
        );
        kernel.bootstrapSetModule(KernelModuleIds.USDC_LENDING_POOL_APP, address(successor));
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(BORROWER_PERSON_ID, 10_000 * ONE_LLM);
        vm.startPrank(address(lendingPool));
        vm.expectPartialRevert(IStakeLienRegistry.RetiredLoanCollateralExceeded.selector);
        stakeLienRegistry.settleLiquidation(BORROWER_PERSON_ID, LIQUIDATOR_PERSON_ID, 6_000 * ONE_LLM, 0, true);
        vm.expectPartialRevert(IStakeLienRegistry.RetiredLoanCollateralExceeded.selector);
        stakeLienRegistry.settleLiquidation(BORROWER_PERSON_ID, LIQUIDATOR_PERSON_ID, ONE_LLM, 5_000 * ONE_LLM, false);
        vm.stopPrank();
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 5_000 * ONE_LLM);
        assertEq(stakeRegistry.activeStakeOf(BORROWER_PERSON_ID), 20_000 * ONE_LLM);
    }

    function testFuzz_IndependentAudit_PartialCanonicalRegistryRotationsBlockNewBorrow(uint8 rawMask) public {
        uint256 mask = bound(uint256(rawMask), 1, 7);
        if (mask & 1 != 0) {
            kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(new IdentityRegistry(address(kernel))));
        }
        if (mask & 2 != 0) {
            kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(new StakeRegistry(address(kernel))));
        }
        if (mask & 4 != 0) {
            kernel.bootstrapSetModule(
                KernelModuleIds.STAKE_LIEN_REGISTRY, address(new StakeLienRegistry(address(kernel)))
            );
        }
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 0);
        vm.prank(BORROWER);
        vm.expectRevert(IUSDCLendingPoolApp.RetiredLendingPool.selector);
        lendingPool.borrow(1_000 * USDC_UNIT);
        if (mask & 4 != 0) {
            vm.prank(address(lendingPool));
            vm.expectPartialRevert(IStakeLienRegistry.UnauthorizedStakeLienRegistryCaller.selector);
            stakeLienRegistry.increaseLien(BORROWER_PERSON_ID, ONE_LLM);
        }
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
    }
}
