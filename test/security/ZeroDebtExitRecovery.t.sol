// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LlmBackedUSDCFixture} from "../apps/LlmBackedUSDC.t.sol";
import {USDCLendingPoolApp} from "../../contracts/apps/USDCLendingPoolApp.sol";
import {IInterestRatePolicy} from "../../contracts/interfaces/IInterestRatePolicy.sol";
import {ILendingRiskParameterPolicy} from "../../contracts/interfaces/ILendingRiskParameterPolicy.sol";
import {IUSDCLendingPoolApp} from "../../contracts/interfaces/IUSDCLendingPoolApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

contract UnusableExitRatePolicy is IInterestRatePolicy {
    error RateUnavailable();

    function ray() external pure returns (uint256) {
        return 1e27;
    }

    function borrowRatePerSecond(uint256) external pure returns (uint256) {
        revert RateUnavailable();
    }

    function supplyRatePerSecond(uint256, uint16) external pure returns (uint256) {
        revert RateUnavailable();
    }
}

contract UnusableExitRiskPolicy is ILendingRiskParameterPolicy {
    error RiskUnavailable();

    function riskParameters() external pure returns (RiskParameters memory) {
        revert RiskUnavailable();
    }

    function maxLtvBps() external pure returns (uint16) {
        revert RiskUnavailable();
    }

    function liquidationThresholdBps() external pure returns (uint16) {
        revert RiskUnavailable();
    }

    function liquidationBonusBps() external pure returns (uint16) {
        revert RiskUnavailable();
    }

    function reserveFactorBps() external pure returns (uint16) {
        revert RiskUnavailable();
    }

    function maxDebtPerPerson() external pure returns (uint256) {
        revert RiskUnavailable();
    }
}

/// @notice Empty-book settlement is independent of unusable future terms; ongoing debt remains fail-closed.
contract ZeroDebtExitRecoveryTest is LlmBackedUSDCFixture {
    struct SettlementState {
        uint256 borrowerDebt;
        uint256 otherDebt;
        uint256 totalDebt;
        uint256 index;
        uint256 reserves;
        uint256 cash;
        uint256 payerCash;
        uint256 shares;
        uint256 lien;
        address loanBook;
    }

    function _sealGovernanceHarness() private {
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));
        kernel.disableBootstrapAuthority();
    }

    function _breakRate() private {
        kernel.governanceUpdateModule(KernelModuleIds.USDC_INTEREST_RATE_POLICY, address(new UnusableExitRatePolicy()));
    }

    function _breakRisk() private {
        kernel.governanceUpdateModule(
            KernelModuleIds.LENDING_RISK_PARAMETER_POLICY, address(new UnusableExitRiskPolicy())
        );
    }

    function _borrowAndApprove() private {
        vm.startPrank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);
        usdc.approve(address(lendingPool), type(uint256).max);
        vm.stopPrank();
    }

    function _state() private view returns (SettlementState memory state) {
        state.borrowerDebt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        state.otherDebt = lendingPool.currentDebtOf(LIQUIDATOR_PERSON_ID);
        state.totalDebt = lendingPool.totalBorrows();
        state.index = lendingPool.borrowIndex();
        state.reserves = lendingPool.totalReserves();
        state.cash = usdc.balanceOf(address(lendingPool));
        state.payerCash = usdc.balanceOf(BORROWER);
        state.shares = lendingPool.balanceOf(LP);
        state.lien = stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID);
        state.loanBook = stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID);
    }

    function _assertUnchanged(SettlementState memory beforeState) private view {
        SettlementState memory afterState = _state();
        assertEq(abi.encode(afterState), abi.encode(beforeState));
    }

    function _assertClosed() private view {
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(lendingPool.totalBorrows(), 0);
        assertEq(lendingPool.borrowIndex(), 1e27);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
    }

    function test_DebtFreeLpExitWithBrokenRate() public {
        _sealGovernanceHarness();
        _breakRate();
        skip(30 days);
        vm.prank(LP);
        lendingPool.withdraw(10_000 * USDC_UNIT, LP);
        assertEq(lendingPool.balanceOf(LP), 0);
        assertEq(usdc.balanceOf(LP), 10_000 * USDC_UNIT);
        _assertClosed();
    }

    function test_DebtFreeLpExitWithBrokenRiskAndRateStillRejectsNewExposure() public {
        _sealGovernanceHarness();
        _breakRate();
        _breakRisk();
        usdc.mint(LP, USDC_UNIT);
        vm.startPrank(LP);
        usdc.approve(address(lendingPool), type(uint256).max);
        vm.expectRevert(UnusableExitRiskPolicy.RiskUnavailable.selector);
        lendingPool.deposit(USDC_UNIT, LP);
        lendingPool.withdraw(10_000 * USDC_UNIT, LP);
        vm.stopPrank();
        vm.prank(BORROWER);
        vm.expectRevert(UnusableExitRiskPolicy.RiskUnavailable.selector);
        lendingPool.borrow(1);
        vm.prank(LIQUIDATOR);
        vm.expectRevert(UnusableExitRiskPolicy.RiskUnavailable.selector);
        lendingPool.liquidate(BORROWER_PERSON_ID, 1);
        assertEq(lendingPool.balanceOf(LP), 0);
        assertEq(usdc.balanceOf(LP), 10_001 * USDC_UNIT);
        _assertClosed();
    }

    function test_LastRepaymentUnderBrokenRulesMatchesHealthySettlementAndPreservesReserves() public {
        _borrowAndApprove();
        usdc.mint(BORROWER, 100 * USDC_UNIT);
        _sealGovernanceHarness();
        skip(30 days);
        uint256 checkpoint = vm.snapshotState();
        vm.prank(BORROWER);
        uint256 healthyRepaid = lendingPool.repay(type(uint256).max);
        uint256 healthyReserves = lendingPool.totalReserves();
        uint256 healthyCash = usdc.balanceOf(address(lendingPool));
        uint256 healthyManaged = lendingPool.totalManagedAssets();
        assertGt(healthyRepaid, 1_000 * USDC_UNIT);
        assertGt(healthyReserves, 0);
        assertTrue(vm.revertToStateAndDelete(checkpoint));
        _breakRate();
        _breakRisk();
        vm.prank(BORROWER);
        assertEq(lendingPool.repay(type(uint256).max), healthyRepaid);
        assertEq(lendingPool.totalReserves(), healthyReserves);
        assertEq(usdc.balanceOf(address(lendingPool)), healthyCash);
        assertEq(lendingPool.totalManagedAssets(), healthyManaged);
        _assertClosed();
        uint256 reserves = lendingPool.totalReserves();
        vm.prank(LP);
        lendingPool.withdraw(10_000 * USDC_UNIT, LP);
        assertEq(lendingPool.totalReserves(), reserves);
        assertEq(lendingPool.availableLiquidity(), healthyCash - reserves - 10_000 * USDC_UNIT);
        // No future rate interval was selected by closing an empty book.
        vm.expectRevert(UnusableExitRatePolicy.RateUnavailable.selector);
        lendingPool.ratePreview();
    }

    function test_PartialRepaymentAndLpExitWithDebtRemainAtomicUnderBrokenRules() public {
        _borrowAndApprove();
        _sealGovernanceHarness();
        skip(7 days);
        _breakRate();
        SettlementState memory beforeState = _state();
        vm.prank(BORROWER);
        vm.expectRevert(UnusableExitRatePolicy.RateUnavailable.selector);
        lendingPool.repay(100 * USDC_UNIT);
        _assertUnchanged(beforeState);
        vm.prank(LP);
        vm.expectRevert(UnusableExitRatePolicy.RateUnavailable.selector);
        lendingPool.withdraw(100 * USDC_UNIT, LP);
        _assertUnchanged(beforeState);
    }

    function test_ClosingOnlyOneBorrowerCannotSkipBrokenPolicy() public {
        _borrowAndApprove();
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(LIQUIDATOR_PERSON_ID, 5_000 * ONE_LLM);
        vm.prank(LIQUIDATOR);
        lendingPool.borrow(500 * USDC_UNIT);
        _sealGovernanceHarness();
        _breakRisk();
        SettlementState memory beforeState = _state();
        vm.prank(BORROWER);
        vm.expectRevert(UnusableExitRiskPolicy.RiskUnavailable.selector);
        lendingPool.repay(type(uint256).max);
        _assertUnchanged(beforeState);
        assertEq(stakeLienRegistry.loanBookOf(LIQUIDATOR_PERSON_ID), address(lendingPool));
    }

    function test_LastRepaymentNeedsActualCanonicalTokenReceipt() public {
        _borrowAndApprove();
        _sealGovernanceHarness();
        skip(1 days);
        usdc.mint(BORROWER, 10 * USDC_UNIT);
        _breakRate();
        _breakRisk();
        uint256 debt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        SettlementState memory beforeState = _state();
        vm.mockCall(
            address(usdc),
            abi.encodeWithSelector(IERC20.transferFrom.selector, BORROWER, address(lendingPool), debt),
            abi.encode(true)
        );
        vm.prank(BORROWER);
        vm.expectRevert(abi.encodeWithSelector(IUSDCLendingPoolApp.UnexpectedAssetAmount.selector, debt, 0));
        lendingPool.repay(type(uint256).max);
        _assertUnchanged(beforeState);
        vm.clearMockedCalls();
        vm.prank(BORROWER);
        lendingPool.repay(type(uint256).max);
        _assertClosed();
    }

    function test_LastRepaymentTokenRevertRestoresDebtInterestAndLien() public {
        _borrowAndApprove();
        _sealGovernanceHarness();
        skip(1 days);
        usdc.mint(BORROWER, 10 * USDC_UNIT);
        _breakRisk();
        uint256 debt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        SettlementState memory beforeState = _state();
        vm.mockCall(
            address(usdc),
            abi.encodeWithSelector(IERC20.transferFrom.selector, BORROWER, address(lendingPool), debt),
            abi.encode(false)
        );
        vm.prank(BORROWER);
        vm.expectRevert();
        lendingPool.repay(type(uint256).max);
        _assertUnchanged(beforeState);
    }

    function test_DebtFreeWithdrawalTokenFailureRestoresSharesAndCash() public {
        _sealGovernanceHarness();
        _breakRate();
        SettlementState memory beforeState = _state();
        vm.mockCall(
            address(usdc), abi.encodeWithSelector(IERC20.transfer.selector, LP, 10_000 * USDC_UNIT), abi.encode(false)
        );
        vm.prank(LP);
        vm.expectRevert();
        lendingPool.withdraw(10_000 * USDC_UNIT, LP);
        _assertUnchanged(beforeState);
        vm.clearMockedCalls();
        vm.prank(LP);
        lendingPool.withdraw(10_000 * USDC_UNIT, LP);
        assertEq(lendingPool.balanceOf(LP), 0);
    }

    function test_RetiredRevokedBorrowerLastLoanCanBeRepaidForUnderBrokenPolicy() public {
        _borrowAndApprove();
        USDCLendingPoolApp successor = new USDCLendingPoolApp(
            address(kernel),
            address(usdc),
            address(identityRegistry),
            address(stakeRegistry),
            address(stakeLienRegistry),
            BORROW_CAP
        );
        _sealGovernanceHarness();
        kernel.governanceUpdateModule(KernelModuleIds.USDC_LENDING_POOL_APP, address(successor));
        kernel.governanceUpdateModule(KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY, address(successor));
        kernel.governanceUpdateModule(KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY, address(successor));
        IdentityTypes.IdentityRecordInput memory revoked = _defaultIdentityInput();
        revoked.citizenshipStatus = IdentityTypes.CitizenshipStatus.Revoked;
        vm.prank(address(identityAuthority));
        identityRegistry.setIdentityRecord(BORROWER_PERSON_ID, revoked);
        _breakRate();
        _breakRisk();
        skip(2 days);
        usdc.mint(LIQUIDATOR, 1_100 * USDC_UNIT);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), type(uint256).max);
        lendingPool.repayFor(BORROWER_PERSON_ID, type(uint256).max);
        vm.stopPrank();
        _assertClosed();
        assertEq(successor.totalBorrows(), 0);
        vm.prank(LP);
        lendingPool.withdraw(10_000 * USDC_UNIT, LP);
    }

    function test_NewLoanAfterEmptyExitUsesFreshTermsAndUnitIndex() public {
        _borrowAndApprove();
        usdc.mint(BORROWER, 100 * USDC_UNIT);
        _sealGovernanceHarness();
        skip(30 days);
        _breakRate();
        vm.prank(BORROWER);
        lendingPool.repay(type(uint256).max);
        skip(180 days);
        vm.prank(BORROWER);
        vm.expectRevert(UnusableExitRatePolicy.RateUnavailable.selector);
        lendingPool.borrow(100 * USDC_UNIT);
        kernel.governanceUpdateModule(KernelModuleIds.USDC_INTEREST_RATE_POLICY, address(interestRatePolicy));
        vm.prank(BORROWER);
        lendingPool.borrow(100 * USDC_UNIT);
        assertEq(lendingPool.borrowIndex(), 1e27);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 100 * USDC_UNIT);
        skip(1 days);
        assertGt(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 100 * USDC_UNIT);
    }

    function testFuzz_LastRepaymentCapsExcessAmount(uint128 excess) public {
        _borrowAndApprove();
        _sealGovernanceHarness();
        _breakRate();
        uint256 debt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        uint256 cashBefore = usdc.balanceOf(address(lendingPool));
        vm.prank(BORROWER);
        assertEq(lendingPool.repay(debt + uint256(excess)), debt);
        assertEq(usdc.balanceOf(address(lendingPool)), cashBefore + debt);
        _assertClosed();
    }
}
