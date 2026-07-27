// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {USDCLendingPoolApp} from "../../contracts/apps/USDCLendingPoolApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {IInterestRatePolicy} from "../../contracts/interfaces/IInterestRatePolicy.sol";
import {IStakeLienRegistry} from "../../contracts/interfaces/IStakeLienRegistry.sol";
import {IStakeRegistry} from "../../contracts/interfaces/IStakeRegistry.sol";
import {IUSDCLendingPoolApp} from "../../contracts/interfaces/IUSDCLendingPoolApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {MockUSDC} from "../../contracts/mocks/MockUSDC.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {FixedLlmUsdcPriceOraclePolicy} from "../../contracts/policies/FixedLlmUsdcPriceOraclePolicy.sol";
import {KinkedInterestRatePolicy} from "../../contracts/policies/KinkedInterestRatePolicy.sol";
import {LendingRiskParameterPolicy} from "../../contracts/policies/LendingRiskParameterPolicy.sol";
import {UnstakingPolicy} from "../../contracts/policies/UnstakingPolicy.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {StakeLienRegistry} from "../../contracts/registries/StakeLienRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LendingTypes} from "../../contracts/types/LendingTypes.sol";

contract ConstantInterestRatePolicy is IInterestRatePolicy {
    uint256 private constant RAY = 1e27;
    uint256 private constant BPS = 10_000;

    uint256 private immutable _ratePerSecondRay;

    constructor(uint256 ratePerSecondRay_) {
        _ratePerSecondRay = ratePerSecondRay_;
    }

    /// @inheritdoc IInterestRatePolicy
    function ray() external pure returns (uint256 ray_) {
        return RAY;
    }

    /// @inheritdoc IInterestRatePolicy
    function borrowRatePerSecond(uint256) external view returns (uint256 rateRay) {
        return _ratePerSecondRay;
    }

    /// @inheritdoc IInterestRatePolicy
    function supplyRatePerSecond(uint256 utilizationRay, uint16 reserveFactorBps)
        external
        view
        returns (uint256 rateRay)
    {
        return (_ratePerSecondRay * utilizationRay / RAY) * (BPS - reserveFactorBps) / BPS;
    }
}

/// @title LlmBackedUSDCTest
/// @notice Covers USDC lending backed by already-staked LLM above the 5,000 retained floor.
contract LlmBackedUSDCTest is Test {
    uint256 internal constant ONE_LLM = 1e18;
    uint256 internal constant MINIMUM_RETAINED_STAKE = 5_000 * ONE_LLM;
    uint256 internal constant USDC_UNIT = 1_000_000;
    uint256 internal constant BORROW_CAP = 1_000_000 * USDC_UNIT;
    uint64 internal constant WELFARE_PERIOD = 30 days;
    uint16 internal constant ANNUAL_UNSTAKE_RATE_BPS = 1_000;

    bytes32 internal constant BORROWER_PERSON_ID = bytes32(uint256(1));
    bytes32 internal constant LIQUIDATOR_PERSON_ID = bytes32(uint256(2));

    address internal constant BORROWER = address(0xB0AA);
    address internal constant LIQUIDATOR = address(0x1A11D);
    address internal constant LP = address(0x1EAD);

    ConstitutionKernel internal kernel;
    MockModule internal identityAuthority;
    MockModule internal stakeAuthority;
    MockModule internal treasury;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    StakeLienRegistry internal stakeLienRegistry;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    UnstakingPolicy internal unstakingPolicy;
    MockUSDC internal usdc;
    FixedLlmUsdcPriceOraclePolicy internal oraclePolicy;
    KinkedInterestRatePolicy internal interestRatePolicy;
    LendingRiskParameterPolicy internal riskParameterPolicy;
    USDCLendingPoolApp internal lendingPool;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));

        identityAuthority = new MockModule(keccak256("identity-authority"));
        stakeAuthority = new MockModule(keccak256("stake-authority"));
        treasury = new MockModule(keccak256("treasury"));

        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        stakeLienRegistry = new StakeLienRegistry(address(kernel));
        // The lien registry sources the retained floor from the citizenship policy, so it must be registered.
        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_RETAINED_STAKE);
        unstakingPolicy = new UnstakingPolicy(address(stakeRegistry), WELFARE_PERIOD, ANNUAL_UNSTAKE_RATE_BPS);
        usdc = new MockUSDC();
        oraclePolicy = new FixedLlmUsdcPriceOraclePolicy(address(usdc), USDC_UNIT);
        interestRatePolicy = new KinkedInterestRatePolicy(500, 800, 10_000, 8e26);
        // Launch risk model: 30% LTV, 40% threshold, 15% bonus, 15% reserve factor, plus an unlimited (0)
        // per-person borrow cap for this isolated pool fixture.
        riskParameterPolicy = new LendingRiskParameterPolicy(3_000, 4_000, 1_500, 1_500, 0);
        lendingPool = new USDCLendingPoolApp(
            address(kernel),
            address(usdc),
            address(identityRegistry),
            address(stakeRegistry),
            address(stakeLienRegistry),
            BORROW_CAP
        );

        bytes32[] memory moduleIds = new bytes32[](12);
        address[] memory moduleAddresses = new address[](12);

        moduleIds[0] = KernelModuleIds.IDENTITY_REGISTRY;
        moduleAddresses[0] = address(identityRegistry);
        moduleIds[1] = KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY;
        moduleAddresses[1] = address(identityAuthority);
        moduleIds[2] = KernelModuleIds.STAKE_REGISTRY;
        moduleAddresses[2] = address(stakeRegistry);
        moduleIds[3] = KernelModuleIds.STAKE_REGISTRY_AUTHORITY;
        moduleAddresses[3] = address(stakeAuthority);
        moduleIds[4] = KernelModuleIds.STAKE_LIEN_REGISTRY;
        moduleAddresses[4] = address(stakeLienRegistry);
        moduleIds[5] = KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY;
        moduleAddresses[5] = address(lendingPool);
        moduleIds[6] = KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY;
        moduleAddresses[6] = address(lendingPool);
        moduleIds[7] = KernelModuleIds.TREASURY_VAULT;
        moduleAddresses[7] = address(treasury);
        moduleIds[8] = KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY;
        moduleAddresses[8] = address(oraclePolicy);
        moduleIds[9] = KernelModuleIds.USDC_INTEREST_RATE_POLICY;
        moduleAddresses[9] = address(interestRatePolicy);
        moduleIds[10] = KernelModuleIds.LENDING_RISK_PARAMETER_POLICY;
        moduleAddresses[10] = address(riskParameterPolicy);
        moduleIds[11] = KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY;
        moduleAddresses[11] = address(citizenEligibilityPolicy);

        kernel.bootstrapSetModules(moduleIds, moduleAddresses);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(stakeAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.USDC_LENDING_POOL_APP, address(lendingPool));
        kernel.bootstrapSetModule(KernelModuleIds.UNSTAKING_POLICY, address(unstakingPolicy));

        _registerCitizen(BORROWER_PERSON_ID, BORROWER, 10_000 * ONE_LLM);
        _registerCitizen(LIQUIDATOR_PERSON_ID, LIQUIDATOR, MINIMUM_RETAINED_STAKE);
        _fundAndDeposit(LP, 10_000 * USDC_UNIT);
    }

    function test_InterfacesExposeSelectors() public pure {
        assertTrue(IStakeLienRegistry.increaseLien.selector != bytes4(0));
        assertTrue(IStakeLienRegistry.retainedStakeFloorOf.selector != bytes4(0));
        assertTrue(IStakeRegistry.requiredActiveStakeFloorOf.selector != bytes4(0));
        assertTrue(IStakeRegistry.transferActiveStake.selector != bytes4(0));
        assertTrue(IUSDCLendingPoolApp.borrow.selector != bytes4(0));
        assertTrue(IUSDCLendingPoolApp.liquidate.selector != bytes4(0));
        assertTrue(IUSDCLendingPoolApp.repayFor.selector != bytes4(0));
    }

    function test_BorrowUsesOnlyStakeAboveRetainedFiveThousandAndLocksSurplus() public {
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 1_500 * USDC_UNIT);

        vm.startPrank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);
        vm.stopPrank();

        assertEq(usdc.balanceOf(BORROWER), 1_000 * USDC_UNIT);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 1_000 * USDC_UNIT);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 5_000 * ONE_LLM);
        assertEq(stakeRegistry.requiredActiveStakeFloorOf(BORROWER_PERSON_ID), 10_000 * ONE_LLM);

        // The lien lifts the required floor up to the full active stake, so nothing is releasable.
        assertFalse(unstakingPolicy.canUnstake(BORROWER_PERSON_ID));
        vm.expectRevert(abi.encodeWithSelector(IStakeRegistry.NothingToUnstake.selector, BORROWER_PERSON_ID));
        vm.prank(address(stakeAuthority));
        stakeRegistry.unstake(BORROWER_PERSON_ID);
    }

    function test_ActiveLendingLienCannotBeBypassedBySlashing() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);

        vm.prank(address(stakeAuthority));
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakeRegistry.ProtectedStakeFloorBreached.selector,
                BORROWER_PERSON_ID,
                10_000 * ONE_LLM - 1,
                10_000 * ONE_LLM
            )
        );
        stakeRegistry.slashStake(BORROWER_PERSON_ID, 1);
    }

    function test_BorrowRequiresCurrentCitizenEligibility() public {
        IdentityTypes.IdentityRecordInput memory input = _defaultIdentityInput();
        input.citizenshipStatus = IdentityTypes.CitizenshipStatus.Revoked;
        vm.prank(address(identityAuthority));
        identityRegistry.setIdentityRecord(BORROWER_PERSON_ID, input);

        vm.prank(BORROWER);
        vm.expectRevert(abi.encodeWithSelector(IUSDCLendingPoolApp.BorrowerNotEligible.selector, BORROWER_PERSON_ID));
        lendingPool.borrow(100 * USDC_UNIT);
    }

    function test_RiskParameterPolicy_RejectsEconomicallyInvalidBounds() public {
        vm.expectRevert(abi.encodeWithSelector(LendingRiskParameterPolicy.InvalidMaxLtv.selector, uint16(0)));
        new LendingRiskParameterPolicy(0, 4_000, 1_500, 1_500, 0);

        // Threshold must sit strictly above max LTV so a fresh max-LTV borrow is not already liquidatable.
        vm.expectRevert(
            abi.encodeWithSelector(
                LendingRiskParameterPolicy.InvalidLiquidationThreshold.selector, uint16(4_000), uint16(4_000)
            )
        );
        new LendingRiskParameterPolicy(4_000, 4_000, 1_500, 1_500, 0);

        // Threshold above the 90% ceiling leaves no headroom for seizure plus bonus.
        vm.expectRevert(
            abi.encodeWithSelector(
                LendingRiskParameterPolicy.InvalidLiquidationThreshold.selector, uint16(3_000), uint16(9_500)
            )
        );
        new LendingRiskParameterPolicy(3_000, 9_500, 1_500, 1_500, 0);

        vm.expectRevert(
            abi.encodeWithSelector(LendingRiskParameterPolicy.InvalidLiquidationBonus.selector, uint16(2_500))
        );
        new LendingRiskParameterPolicy(3_000, 4_000, 2_500, 1_500, 0);

        vm.expectRevert(abi.encodeWithSelector(LendingRiskParameterPolicy.InvalidReserveFactor.selector, uint16(6_000)));
        new LendingRiskParameterPolicy(3_000, 4_000, 1_500, 6_000, 0);

        // Threshold and bonus must also be safe together: a threshold-sized debt cannot seize over 100% collateral.
        vm.expectRevert(
            abi.encodeWithSelector(
                LendingRiskParameterPolicy.UnsafeLiquidationParameters.selector, uint16(9_000), uint16(2_000)
            )
        );
        new LendingRiskParameterPolicy(8_000, 9_000, 2_000, 1_500, 0);
    }

    function test_GovernanceRepointOfRiskPolicyRetunesLivePool() public {
        // 30% LTV policy in setUp: 5,000 LLM surplus at 1 USDC/LLM caps borrowing at 1,500 USDC.
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 1_500 * USDC_UNIT);

        // Governance deploys a 50% LTV policy and repoints the module; the change takes effect live on the pool.
        LendingRiskParameterPolicy loosenedPolicy = new LendingRiskParameterPolicy(5_000, 6_000, 1_500, 1_500, 0);
        kernel.bootstrapSetModule(KernelModuleIds.LENDING_RISK_PARAMETER_POLICY, address(loosenedPolicy));

        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 2_500 * USDC_UNIT);

        vm.prank(BORROWER);
        lendingPool.borrow(2_500 * USDC_UNIT);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 2_500 * USDC_UNIT);
    }

    function test_PerPersonBorrowCapLimitsASingleBorrower() public {
        // Governance repoints to a policy with an 800 USDC per-person cap (30% LTV otherwise unchanged).
        LendingRiskParameterPolicy cappedPolicy =
            new LendingRiskParameterPolicy(3_000, 4_000, 1_500, 1_500, 800 * USDC_UNIT);
        kernel.bootstrapSetModule(KernelModuleIds.LENDING_RISK_PARAMETER_POLICY, address(cappedPolicy));

        // Collateral would allow 1,500 USDC, but the per-person cap clamps borrowable to 800.
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 800 * USDC_UNIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IUSDCLendingPoolApp.BorrowExceedsPerPersonCap.selector,
                BORROWER_PERSON_ID,
                801 * USDC_UNIT,
                800 * USDC_UNIT
            )
        );
        vm.prank(BORROWER);
        lendingPool.borrow(801 * USDC_UNIT);

        vm.prank(BORROWER);
        lendingPool.borrow(800 * USDC_UNIT);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 800 * USDC_UNIT);
    }

    function test_GovernanceCanSwapPriceOracleWithoutRedeployingPool() public {
        // A new manual oracle priced at 2 USDC per LLM (double the launch price) is repointed by governance.
        FixedLlmUsdcPriceOraclePolicy repricedOracle = new FixedLlmUsdcPriceOraclePolicy(address(usdc), 2 * USDC_UNIT);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(repricedOracle));

        assertEq(lendingPool.priceOraclePolicy(), address(repricedOracle));
        // 5,000 LLM surplus now values at 10,000 USDC, so 30% LTV allows 3,000 USDC — read live from the new oracle.
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 3_000 * USDC_UNIT);
    }

    function test_HigherProtectedFloorReducesBorrowCollateral() public {
        vm.prank(address(stakeAuthority));
        stakeRegistry.setProtectedStakeFloor(BORROWER_PERSON_ID, 8_000 * ONE_LLM);

        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 600 * USDC_UNIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IUSDCLendingPoolApp.BorrowWouldBreachLtv.selector, BORROWER_PERSON_ID, 601 * USDC_UNIT, 600 * USDC_UNIT
            )
        );
        vm.prank(BORROWER);
        lendingPool.borrow(601 * USDC_UNIT);

        vm.prank(BORROWER);
        lendingPool.borrow(600 * USDC_UNIT);

        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 2_000 * ONE_LLM);
        assertEq(stakeRegistry.requiredActiveStakeFloorOf(BORROWER_PERSON_ID), 10_000 * ONE_LLM);
    }

    function test_RepayReleasesLienAndRestoresNormalUnstakingFloor() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);

        usdc.mint(BORROWER, 1_000 * USDC_UNIT);
        vm.startPrank(BORROWER);
        usdc.approve(address(lendingPool), 1_000 * USDC_UNIT);
        lendingPool.repay(1_000 * USDC_UNIT);
        vm.stopPrank();

        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeRegistry.requiredActiveStakeFloorOf(BORROWER_PERSON_ID), MINIMUM_RETAINED_STAKE);
        assertTrue(unstakingPolicy.canUnstake(BORROWER_PERSON_ID));

        // With the lien released, the normal discrete unstake works again and starts a welfare period.
        uint256 expectedPortion = unstakingPolicy.unstakePortion(stakeRegistry.activeStakeOf(BORROWER_PERSON_ID));
        vm.prank(address(stakeAuthority));
        (uint256 releasedAmount, uint64 welfareUntil) = stakeRegistry.unstake(BORROWER_PERSON_ID);
        assertEq(releasedAmount, expectedPortion);
        assertGt(releasedAmount, 0);
        assertTrue(stakeRegistry.isInWelfare(BORROWER_PERSON_ID));
        assertEq(stakeRegistry.welfareUntilOf(BORROWER_PERSON_ID), welfareUntil);
    }

    function test_FullRepaymentCannotBeBrickedByAccrualRounding() public {
        vm.prank(BORROWER);
        lendingPool.borrow(10 * USDC_UNIT);

        for (uint256 i; i < 6; ++i) {
            skip(12);
            lendingPool.accrueInterest();
        }

        uint256 debt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        usdc.mint(BORROWER, debt);
        vm.startPrank(BORROWER);
        usdc.approve(address(lendingPool), debt);
        lendingPool.repay(debt);
        vm.stopPrank();

        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(lendingPool.totalBorrows(), 0);
    }

    function test_RepayForAllowsDebtRepaymentAfterBorrowerWalletRevocation() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);

        vm.prank(address(identityAuthority));
        identityRegistry.setWalletLink(BORROWER_PERSON_ID, BORROWER, IdentityTypes.WalletLinkStatus.Revoked);

        usdc.mint(LIQUIDATOR, 1_000 * USDC_UNIT);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 1_000 * USDC_UNIT);
        lendingPool.repayFor(BORROWER_PERSON_ID, 1_000 * USDC_UNIT);
        vm.stopPrank();

        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
    }

    /// @notice A person with no lien exits down to their own protected floor, ignoring the retained minimum.
    function test_NonBorrowerCanUnstakeBelowRetainedFloor() public {
        // Drop the borrower's protected floor to zero while they hold no lien.
        vm.prank(address(stakeAuthority));
        stakeRegistry.setProtectedStakeFloor(BORROWER_PERSON_ID, 0);

        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.minimumRetainedStake(), MINIMUM_RETAINED_STAKE);

        // Because there is no lien, the 5,000 retained minimum does not bind: the floor is 0.
        assertEq(stakeRegistry.requiredActiveStakeFloorOf(BORROWER_PERSON_ID), 0);
        assertTrue(unstakingPolicy.canUnstake(BORROWER_PERSON_ID));

        uint256 expectedPortion = unstakingPolicy.unstakePortion(10_000 * ONE_LLM);
        vm.prank(address(stakeAuthority));
        (uint256 releasedAmount,) = stakeRegistry.unstake(BORROWER_PERSON_ID);
        assertEq(releasedAmount, expectedPortion);
        assertGt(releasedAmount, 0);
    }

    function test_HealthyPositionCannotBeLiquidated() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);

        assertGt(lendingPool.healthFactorOf(BORROWER_PERSON_ID), lendingPool.HEALTH_FACTOR_SCALE());

        usdc.mint(LIQUIDATOR, 1_000 * USDC_UNIT);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 1_000 * USDC_UNIT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IUSDCLendingPoolApp.LiquidationNotAllowed.selector,
                BORROWER_PERSON_ID,
                lendingPool.healthFactorOf(BORROWER_PERSON_ID)
            )
        );
        lendingPool.liquidate(BORROWER_PERSON_ID, 1_000 * USDC_UNIT);
        vm.stopPrank();
    }

    function test_LendersCannotWithdrawBorrowedLiquidity() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);

        assertEq(lendingPool.availableLiquidity(), 8_750 * USDC_UNIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IUSDCLendingPoolApp.InsufficientLiquidity.selector, 8_750 * USDC_UNIT, 8_751 * USDC_UNIT
            )
        );
        vm.prank(LP);
        lendingPool.withdraw(8_751 * USDC_UNIT, LP);
    }

    function test_LiquidationTransfersSeizedStakeAsActiveStakeAndDoesNotBypassWelfare() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);

        FixedLlmUsdcPriceOraclePolicy lowerPriceOracle = new FixedLlmUsdcPriceOraclePolicy(address(usdc), USDC_UNIT / 2);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(lowerPriceOracle));
        assertLt(lendingPool.healthFactorOf(BORROWER_PERSON_ID), lendingPool.HEALTH_FACTOR_SCALE());

        uint256 borrowerDebt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        uint256 borrowerStakeBefore = stakeRegistry.activeStakeOf(BORROWER_PERSON_ID);
        uint256 liquidatorStakeBefore = stakeRegistry.activeStakeOf(LIQUIDATOR_PERSON_ID);

        usdc.mint(LIQUIDATOR, borrowerDebt);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), borrowerDebt);
        (uint256 repaidAmount, uint256 seizedStake) = lendingPool.liquidate(BORROWER_PERSON_ID, borrowerDebt);
        vm.stopPrank();

        assertEq(repaidAmount, borrowerDebt);
        assertGt(seizedStake, 0);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeRegistry.activeStakeOf(BORROWER_PERSON_ID), borrowerStakeBefore - seizedStake);
        assertEq(stakeRegistry.activeStakeOf(LIQUIDATOR_PERSON_ID), liquidatorStakeBefore + seizedStake);

        // The liquidator's seized stake is now active stake; releasing it still runs through the
        // discrete unstake path and starts a welfare period rather than paying out in full instantly.
        assertTrue(unstakingPolicy.canUnstake(LIQUIDATOR_PERSON_ID));
        vm.prank(address(stakeAuthority));
        (uint256 released, uint64 welfareUntil) = stakeRegistry.unstake(LIQUIDATOR_PERSON_ID);

        assertGt(released, 0);
        assertLt(released, seizedStake);
        assertTrue(stakeRegistry.isInWelfare(LIQUIDATOR_PERSON_ID));
        assertEq(stakeRegistry.welfareUntilOf(LIQUIDATOR_PERSON_ID), welfareUntil);
    }

    function test_AbsorbBadDebt_RevertsWhileCollateralIsStillSeizable() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);

        // 5,000 LLM of surplus is still seizable, so liquidators must act first — no write-off is allowed yet.
        vm.expectRevert(
            abi.encodeWithSelector(IUSDCLendingPoolApp.PositionNotBadDebt.selector, BORROWER_PERSON_ID, 5_000 * ONE_LLM)
        );
        lendingPool.absorbBadDebt(BORROWER_PERSON_ID);
    }

    function test_AbsorbBadDebt_WritesOffResidualAfterCollateralExhausted() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);

        // LLM/USDC price crashes to 0.115 USDC per LLM; governance repoints the manual oracle to the new price.
        FixedLlmUsdcPriceOraclePolicy crashedOracle = new FixedLlmUsdcPriceOraclePolicy(address(usdc), 115_000);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(crashedOracle));

        // A liquidator seizes all 5,000 LLM of surplus by repaying 500 USDC (500 * 1.15 bonus = 575 USDC).
        usdc.mint(LIQUIDATOR, 500 * USDC_UNIT);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), 500 * USDC_UNIT);
        (, uint256 seizedStake) = lendingPool.liquidate(BORROWER_PERSON_ID, 500 * USDC_UNIT);
        vm.stopPrank();
        assertEq(seizedStake, 5_000 * ONE_LLM);
        assertEq(stakeRegistry.activeStakeOf(BORROWER_PERSON_ID), MINIMUM_RETAINED_STAKE);

        uint256 residualDebt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        assertEq(residualDebt, 750 * USDC_UNIT);
        uint256 managedBefore = lendingPool.totalManagedAssets();

        // Only the untouchable citizenship floor remains, so the residual is unrecoverable and gets written off.
        (uint256 writtenOff, uint256 coveredByReserves, uint256 supplierShortfall) =
            lendingPool.absorbBadDebt(BORROWER_PERSON_ID);

        assertEq(writtenOff, 750 * USDC_UNIT);
        assertEq(coveredByReserves, 0); // no interest accrued in this block, so reserves are empty
        assertEq(supplierShortfall, 750 * USDC_UNIT);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(lendingPool.totalBorrows(), 0);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        // Suppliers bear the shortfall (share value drops) until the treasury covers it.
        assertEq(lendingPool.totalManagedAssets(), managedBefore - supplierShortfall);

        // Governance covers it with a treasury disbursement to the pool: a plain USDC transfer in restores value.
        usdc.mint(address(lendingPool), supplierShortfall);
        assertEq(lendingPool.totalManagedAssets(), managedBefore);
    }

    function test_AbsorbBadDebt_DoesNotCountUntouchableCitizenshipFloorAsRecoverable() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);

        FixedLlmUsdcPriceOraclePolicy crashedOracle = new FixedLlmUsdcPriceOraclePolicy(address(usdc), 250_000);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(crashedOracle));

        // Rounding the 15% bonus up makes this exact repayment seize all 5,000 LLM of surplus.
        uint256 liquidationRepayment = 1_086_956_521;
        usdc.mint(LIQUIDATOR, liquidationRepayment);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), liquidationRepayment);
        (, uint256 seizedStake) = lendingPool.liquidate(BORROWER_PERSON_ID, liquidationRepayment);
        vm.stopPrank();

        assertEq(seizedStake, 5_000 * ONE_LLM);
        assertEq(stakeRegistry.activeStakeOf(BORROWER_PERSON_ID), MINIMUM_RETAINED_STAKE);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);

        uint256 residualDebt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        assertEq(residualDebt, 163_043_479);

        // The retained citizenship floor cannot be seized, so it must not block clearing the residual debt.
        (uint256 writtenOff,,) = lendingPool.absorbBadDebt(BORROWER_PERSON_ID);
        assertEq(writtenOff, residualDebt);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
    }

    function test_AbsorbBadDebt_UsesSmallestEffectiveScaledDebtRepayment() public {
        uint256 seizableStake = 4e12;
        vm.prank(address(stakeAuthority));
        stakeRegistry.setProtectedStakeFloor(BORROWER_PERSON_ID, 10_000 * ONE_LLM - seizableStake);

        vm.prank(BORROWER);
        lendingPool.borrow(1);

        skip(1);
        lendingPool.accrueInterest();
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 2);

        FixedLlmUsdcPriceOraclePolicy lowerPriceOracle = new FixedLlmUsdcPriceOraclePolicy(address(usdc), USDC_UNIT / 2);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(lowerPriceOracle));

        vm.prank(LIQUIDATOR);
        vm.expectRevert(abi.encodeWithSelector(IUSDCLendingPoolApp.InvalidAmount.selector, 0));
        lendingPool.liquidate(BORROWER_PERSON_ID, 1);

        vm.prank(LIQUIDATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IUSDCLendingPoolApp.InsufficientLiquidationCollateral.selector, BORROWER_PERSON_ID, seizableStake, 6e12
            )
        );
        lendingPool.liquidate(BORROWER_PERSON_ID, 2);

        (uint256 writtenOff,,) = lendingPool.absorbBadDebt(BORROWER_PERSON_ID);
        assertEq(writtenOff, 2);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
    }

    function test_ProtectedFloorCannotExceedActiveStakeNetOfLien() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);

        uint256 activeStake = stakeRegistry.activeStakeOf(BORROWER_PERSON_ID);
        uint256 newProtectedFloor = activeStake - 1;
        uint256 requiredFloor = newProtectedFloor + stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID);
        vm.prank(address(stakeAuthority));
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakeRegistry.ProtectedStakeFloorBreached.selector, BORROWER_PERSON_ID, activeStake, requiredFloor
            )
        );
        stakeRegistry.setProtectedStakeFloor(BORROWER_PERSON_ID, newProtectedFloor);

        assertEq(stakeRegistry.protectedStakeFloorOf(BORROWER_PERSON_ID), MINIMUM_RETAINED_STAKE);
    }

    function test_CitizenshipFloorIncreaseDoesNotFreezeExistingLiquidation() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);

        assertEq(stakeLienRegistry.retainedStakeFloorOf(BORROWER_PERSON_ID), MINIMUM_RETAINED_STAKE);
        CitizenEligibilityPolicy higherCitizenshipFloor =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), 9_000 * ONE_LLM);
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(higherCitizenshipFloor));
        assertEq(stakeLienRegistry.minimumRetainedStake(), 9_000 * ONE_LLM);
        assertEq(stakeLienRegistry.retainedStakeFloorOf(BORROWER_PERSON_ID), MINIMUM_RETAINED_STAKE);

        FixedLlmUsdcPriceOraclePolicy lowerPriceOracle = new FixedLlmUsdcPriceOraclePolicy(address(usdc), USDC_UNIT / 2);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(lowerPriceOracle));

        uint256 debt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        usdc.mint(LIQUIDATOR, debt);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), debt);
        lendingPool.liquidate(BORROWER_PERSON_ID, debt);
        vm.stopPrank();

        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.retainedStakeFloorOf(BORROWER_PERSON_ID), 9_000 * ONE_LLM);
    }

    function test_PriceOracleMustPriceThePoolsUsdc() public {
        // Repoint the oracle module to one that prices a different token; every collateral read must reject it.
        MockUSDC otherToken = new MockUSDC();
        FixedLlmUsdcPriceOraclePolicy wrongOracle = new FixedLlmUsdcPriceOraclePolicy(address(otherToken), USDC_UNIT);
        kernel.bootstrapSetModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(wrongOracle));

        vm.expectRevert(abi.encodeWithSelector(IUSDCLendingPoolApp.InvalidToken.selector, address(wrongOracle)));
        lendingPool.maxBorrowable(BORROWER_PERSON_ID);

        vm.expectRevert(abi.encodeWithSelector(IUSDCLendingPoolApp.InvalidToken.selector, address(wrongOracle)));
        vm.prank(BORROWER);
        lendingPool.borrow(100 * USDC_UNIT);
    }

    /// @notice H2: a person cannot obtain a second active wallet, blocking cross-wallet self-liquidation.
    function test_SamePersonCannotHoldSecondActiveWalletForSelfLiquidation() public {
        address secondBorrowerWallet = address(0xB0AB);

        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistry.PersonAlreadyHasActiveWallet.selector, BORROWER_PERSON_ID)
        );
        vm.prank(address(identityAuthority));
        identityRegistry.setWalletLink(BORROWER_PERSON_ID, secondBorrowerWallet, IdentityTypes.WalletLinkStatus.Active);
    }

    function test_FixedRateAccrualIsIndependentOfCheckpointFrequency() public {
        ConstantInterestRatePolicy constantRatePolicy = new ConstantInterestRatePolicy(uint256(1e27) / 365 days);
        kernel.bootstrapSetModule(KernelModuleIds.USDC_INTEREST_RATE_POLICY, address(constantRatePolicy));

        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);

        uint256 snapshotId = vm.snapshotState();
        skip(365 days);
        lendingPool.accrueInterest();
        uint256 singleCheckpointDebt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        uint256 singleCheckpointBorrows = lendingPool.totalBorrows();
        uint256 singleCheckpointReserves = lendingPool.totalReserves();
        uint256 singleCheckpointIndex = lendingPool.borrowIndex();

        assertTrue(vm.revertToState(snapshotId));
        for (uint256 i; i < 365; ++i) {
            skip(1 days);
            lendingPool.accrueInterest();
        }

        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), singleCheckpointDebt);
        assertEq(lendingPool.totalBorrows(), singleCheckpointBorrows);
        assertEq(lendingPool.totalReserves(), singleCheckpointReserves);
        assertEq(lendingPool.borrowIndex(), singleCheckpointIndex);
    }

    function test_DonatedCashCannotRepriceTheElapsedInterestInterval() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);

        skip(365 days);
        uint256 debtAtCachedRate = lendingPool.currentDebtOf(BORROWER_PERSON_ID);

        usdc.mint(address(lendingPool), 1_000_000 * USDC_UNIT);
        lendingPool.accrueInterest();

        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), debtAtCachedRate);
    }

    function test_NewInterestPolicyCannotRepriceTheElapsedInterestInterval() public {
        ConstantInterestRatePolicy initialRatePolicy = new ConstantInterestRatePolicy(uint256(1e27) / (20 * 365 days));
        ConstantInterestRatePolicy replacementRatePolicy = new ConstantInterestRatePolicy(uint256(1e27) / 365 days);
        kernel.bootstrapSetModule(KernelModuleIds.USDC_INTEREST_RATE_POLICY, address(initialRatePolicy));

        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);

        skip(365 days);
        uint256 debtAtInitialRate = lendingPool.currentDebtOf(BORROWER_PERSON_ID);

        kernel.bootstrapSetModule(KernelModuleIds.USDC_INTEREST_RATE_POLICY, address(replacementRatePolicy));
        lendingPool.accrueInterest();
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), debtAtInitialRate);

        skip(1 days);
        assertGt(lendingPool.currentDebtOf(BORROWER_PERSON_ID), debtAtInitialRate);
    }

    function test_InterestAccrualPaysLendersAndProtocolReserves() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);

        uint256 managedAssetsBefore = lendingPool.totalManagedAssets();
        skip(365 days);
        lendingPool.accrueInterest();

        assertGt(lendingPool.totalManagedAssets(), managedAssetsBefore);
        assertGt(lendingPool.totalReserves(), 0);

        LendingTypes.RatePreview memory preview = lendingPool.ratePreview();
        assertGt(preview.borrowRatePerSecondRay, 0);
        assertGt(preview.supplyRatePerSecondRay, 0);
    }

    function test_ProtocolReservesRemainFirstLossCapital() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);

        skip(365 days);
        lendingPool.accrueInterest();

        uint256 reserves = lendingPool.totalReserves();
        assertGt(reserves, 0);
        assertEq(lendingPool.totalReserves(), reserves);
        assertEq(lendingPool.availableLiquidity(), usdc.balanceOf(address(lendingPool)) - reserves);
    }

    function _fundAndDeposit(address liquidityProvider, uint256 amount) internal {
        usdc.mint(liquidityProvider, amount);

        vm.startPrank(liquidityProvider);
        usdc.approve(address(lendingPool), amount);
        lendingPool.deposit(amount, liquidityProvider);
        vm.stopPrank();
    }

    function _registerCitizen(bytes32 personId, address wallet, uint256 stakeAmount) internal {
        vm.prank(address(identityAuthority));
        identityRegistry.setIdentityRecord(personId, _defaultIdentityInput());

        vm.prank(address(identityAuthority));
        identityRegistry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);

        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(personId, stakeAmount);

        vm.prank(address(stakeAuthority));
        stakeRegistry.setProtectedStakeFloor(personId, MINIMUM_RETAINED_STAKE);
    }

    function _defaultIdentityInput() internal pure returns (IdentityTypes.IdentityRecordInput memory input) {
        input = IdentityTypes.IdentityRecordInput({
            metadataHash: keccak256("metadata"),
            metadataURI: "ipfs://metadata",
            verificationStatus: IdentityTypes.VerificationStatus.Verified,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
            ageClass: IdentityTypes.AgeClass.Adult,
            correctionFlag: false,
            finalSuspension: false
        });
    }
}
