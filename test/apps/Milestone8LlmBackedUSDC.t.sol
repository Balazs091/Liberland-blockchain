// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {USDCLendingPoolApp} from "../../contracts/apps/USDCLendingPoolApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {IStakeLienRegistry} from "../../contracts/interfaces/IStakeLienRegistry.sol";
import {IStakeRegistry} from "../../contracts/interfaces/IStakeRegistry.sol";
import {IUSDCLendingPoolApp} from "../../contracts/interfaces/IUSDCLendingPoolApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {MockUSDC} from "../../contracts/mocks/MockUSDC.sol";
import {FixedLlmUsdcPriceOraclePolicy} from "../../contracts/policies/FixedLlmUsdcPriceOraclePolicy.sol";
import {KinkedInterestRatePolicy} from "../../contracts/policies/KinkedInterestRatePolicy.sol";
import {UnstakingPolicy} from "../../contracts/policies/UnstakingPolicy.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {StakeLienRegistry} from "../../contracts/registries/StakeLienRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LendingTypes} from "../../contracts/types/LendingTypes.sol";

/// @title Milestone8LlmBackedUSDCTest
/// @notice Covers USDC lending backed by already-staked LLM above the 5,000 retained floor.
contract Milestone8LlmBackedUSDCTest is Test {
    uint256 internal constant MINIMUM_RETAINED_STAKE = 5_000;
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
    UnstakingPolicy internal unstakingPolicy;
    MockUSDC internal usdc;
    FixedLlmUsdcPriceOraclePolicy internal oraclePolicy;
    KinkedInterestRatePolicy internal interestRatePolicy;
    USDCLendingPoolApp internal lendingPool;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));

        identityAuthority = new MockModule(keccak256("identity-authority"));
        stakeAuthority = new MockModule(keccak256("stake-authority"));
        treasury = new MockModule(keccak256("treasury"));

        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        stakeLienRegistry = new StakeLienRegistry(address(kernel), MINIMUM_RETAINED_STAKE);
        unstakingPolicy = new UnstakingPolicy(address(stakeRegistry), WELFARE_PERIOD, ANNUAL_UNSTAKE_RATE_BPS);
        usdc = new MockUSDC();
        oraclePolicy = new FixedLlmUsdcPriceOraclePolicy(address(usdc), USDC_UNIT);
        interestRatePolicy = new KinkedInterestRatePolicy(200, 800, 10_000, 8e26);
        lendingPool = new USDCLendingPoolApp(
            address(kernel),
            address(usdc),
            address(identityRegistry),
            address(stakeRegistry),
            address(stakeLienRegistry),
            address(oraclePolicy),
            address(interestRatePolicy),
            BORROW_CAP
        );

        bytes32[] memory moduleIds = new bytes32[](10);
        address[] memory moduleAddresses = new address[](10);

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

        kernel.bootstrapSetModules(moduleIds, moduleAddresses);
        kernel.bootstrapSetModule(KernelModuleIds.USDC_LENDING_POOL_APP, address(lendingPool));
        kernel.bootstrapSetModule(KernelModuleIds.UNSTAKING_POLICY, address(unstakingPolicy));

        _registerCitizen(BORROWER_PERSON_ID, BORROWER, 10_000);
        _registerCitizen(LIQUIDATOR_PERSON_ID, LIQUIDATOR, MINIMUM_RETAINED_STAKE);
        _fundAndDeposit(LP, 10_000 * USDC_UNIT);
    }

    function test_Milestone8InterfacesExposeSelectors() public pure {
        assertTrue(IStakeLienRegistry.increaseLien.selector != bytes4(0));
        assertTrue(IStakeRegistry.requiredActiveStakeFloorOf.selector != bytes4(0));
        assertTrue(IStakeRegistry.transferActiveStake.selector != bytes4(0));
        assertTrue(IUSDCLendingPoolApp.borrow.selector != bytes4(0));
        assertTrue(IUSDCLendingPoolApp.liquidate.selector != bytes4(0));
    }

    function test_BorrowUsesOnlyStakeAboveRetainedFiveThousandAndLocksSurplus() public {
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 1_250 * USDC_UNIT);

        vm.startPrank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);
        vm.stopPrank();

        assertEq(usdc.balanceOf(BORROWER), 1_000 * USDC_UNIT);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 1_000 * USDC_UNIT);
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 5_000);
        assertEq(stakeRegistry.requiredActiveStakeFloorOf(BORROWER_PERSON_ID), 10_000);

        // The lien lifts the required floor up to the full active stake, so nothing is releasable.
        assertFalse(unstakingPolicy.canUnstake(BORROWER_PERSON_ID));
        vm.expectRevert(abi.encodeWithSelector(IStakeRegistry.NothingToUnstake.selector, BORROWER_PERSON_ID));
        vm.prank(address(stakeAuthority));
        stakeRegistry.unstake(BORROWER_PERSON_ID);
    }

    function test_HigherProtectedFloorReducesBorrowCollateral() public {
        vm.prank(address(stakeAuthority));
        stakeRegistry.setProtectedStakeFloor(BORROWER_PERSON_ID, 8_000);

        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 500 * USDC_UNIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IUSDCLendingPoolApp.BorrowWouldBreachLtv.selector, BORROWER_PERSON_ID, 501 * USDC_UNIT, 500 * USDC_UNIT
            )
        );
        vm.prank(BORROWER);
        lendingPool.borrow(501 * USDC_UNIT);

        vm.prank(BORROWER);
        lendingPool.borrow(500 * USDC_UNIT);

        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 2_000);
        assertEq(stakeRegistry.requiredActiveStakeFloorOf(BORROWER_PERSON_ID), 10_000);
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

    /// @notice M12: a person with no lien exits down to their own protected floor, ignoring the retained minimum.
    function test_M12_NonBorrowerCanUnstakeBelowRetainedFloor() public {
        // Drop the borrower's protected floor to zero while they hold no lien.
        vm.prank(address(stakeAuthority));
        stakeRegistry.setProtectedStakeFloor(BORROWER_PERSON_ID, 0);

        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.minimumRetainedStake(), MINIMUM_RETAINED_STAKE);

        // Because there is no lien, the 5,000 retained minimum does not bind: the floor is 0.
        assertEq(stakeRegistry.requiredActiveStakeFloorOf(BORROWER_PERSON_ID), 0);
        assertTrue(unstakingPolicy.canUnstake(BORROWER_PERSON_ID));

        uint256 expectedPortion = unstakingPolicy.unstakePortion(10_000);
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

        skip(20 * 365 days);
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

    /// @notice H2: a person cannot obtain a second active wallet, blocking cross-wallet self-liquidation.
    function test_SamePersonCannotHoldSecondActiveWalletForSelfLiquidation() public {
        address secondBorrowerWallet = address(0xB0AB);

        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistry.PersonAlreadyHasActiveWallet.selector, BORROWER_PERSON_ID)
        );
        vm.prank(address(identityAuthority));
        identityRegistry.setWalletLink(BORROWER_PERSON_ID, secondBorrowerWallet, IdentityTypes.WalletLinkStatus.Active);
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

    function test_ProtocolReservesCanOnlyBeClaimedToTreasury() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_250 * USDC_UNIT);

        skip(365 days);
        lendingPool.accrueInterest();

        uint256 reserves = lendingPool.totalReserves();
        uint256 treasuryBalanceBefore = usdc.balanceOf(address(treasury));

        lendingPool.claimProtocolReserves(reserves);

        assertEq(usdc.balanceOf(address(treasury)), treasuryBalanceBefore + reserves);
        assertEq(lendingPool.totalReserves(), 0);
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
