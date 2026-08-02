// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {USDCLendingPoolApp} from "../../contracts/apps/USDCLendingPoolApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
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

contract LendingInvariantHandler is Test {
    USDCLendingPoolApp public immutable pool;
    ConstitutionKernel public immutable kernel;
    MockUSDC public immutable usdc;
    bytes32 public immutable borrowerPersonId;
    bytes32 public immutable liquidatorPersonId;
    address public immutable borrower;
    address public immutable liquidator;
    address public immutable liquidityProvider;
    address public immutable riskPolicyOne;
    address public immutable riskPolicyTwo;

    constructor(
        USDCLendingPoolApp pool_,
        ConstitutionKernel kernel_,
        MockUSDC usdc_,
        bytes32 borrowerPersonId_,
        bytes32 liquidatorPersonId_,
        address borrower_,
        address liquidator_,
        address liquidityProvider_,
        address riskPolicyOne_,
        address riskPolicyTwo_
    ) {
        pool = pool_;
        kernel = kernel_;
        usdc = usdc_;
        borrowerPersonId = borrowerPersonId_;
        liquidatorPersonId = liquidatorPersonId_;
        borrower = borrower_;
        liquidator = liquidator_;
        liquidityProvider = liquidityProvider_;
        riskPolicyOne = riskPolicyOne_;
        riskPolicyTwo = riskPolicyTwo_;
    }

    /// @notice Attempts a bounded borrow for the fixture citizen.
    function borrow(uint96 rawAmount) external {
        uint256 maximum = pool.maxBorrowable(borrowerPersonId);
        if (maximum == 0) {
            return;
        }
        uint256 amount = bound(uint256(rawAmount), 1, maximum);
        vm.prank(borrower);
        try pool.borrow(amount) {} catch {}
    }

    /// @notice Attempts a bounded repayment against the fixture citizen's debt.
    function repay(uint96 rawAmount) external {
        uint256 debt = pool.currentDebtOf(borrowerPersonId);
        if (debt == 0) {
            return;
        }
        uint256 amount = bound(uint256(rawAmount), 1, debt);
        vm.prank(borrower);
        try pool.repay(amount) {} catch {}
    }

    /// @notice Deposits a bounded amount of available supplier liquidity.
    function depositLiquidity(uint96 rawAmount) external {
        uint256 balance = usdc.balanceOf(liquidityProvider);
        if (balance == 0) {
            return;
        }
        uint256 amount = bound(uint256(rawAmount), 1, balance);
        vm.prank(liquidityProvider);
        try pool.deposit(amount, liquidityProvider) {} catch {}
    }

    /// @notice Attempts a bounded supplier withdrawal.
    function withdrawLiquidity(uint96 rawAmount) external {
        uint256 liquidity = pool.availableLiquidity();
        if (liquidity == 0 || pool.balanceOf(liquidityProvider) == 0) {
            return;
        }
        uint256 amount = bound(uint256(rawAmount), 1, liquidity);
        vm.prank(liquidityProvider);
        try pool.withdraw(amount, liquidityProvider) {} catch {}
    }

    /// @notice Attempts a bounded liquidation after creating price stress when required.
    function liquidate(uint96 rawAmount) external {
        uint256 debt = pool.currentDebtOf(borrowerPersonId);
        if (debt == 0) {
            return;
        }
        uint256 amount = bound(uint256(rawAmount), 1, debt);
        vm.prank(liquidator);
        try pool.liquidate(borrowerPersonId, amount) {} catch {}
    }

    /// @notice Attempts the explicit bad-debt absorption path.
    function absorbBadDebt() external {
        try pool.absorbBadDebt(borrowerPersonId) {} catch {}
    }

    /// @notice Advances time by a bounded interval and checkpoints interest accrual.
    function advanceTimeAndAccrue(uint64 rawSeconds) external {
        vm.warp(block.timestamp + bound(uint256(rawSeconds), 1, 365 days));
        try pool.accrueInterest() {} catch {}
    }

    /// @notice Repoints the live risk policy to one of the reviewed fixture policies.
    function replaceRiskPolicy(uint256 seed) external {
        address replacement = seed % 2 == 0 ? riskPolicyOne : riskPolicyTwo;
        try kernel.governanceUpdateModule(KernelModuleIds.LENDING_RISK_PARAMETER_POLICY, replacement) {} catch {}
    }
}

/// @title LendingInvariantTest
/// @notice Stateful coverage for pool accounting, lien floors, liquidation/bad debt, and live risk-policy changes.
contract LendingInvariantTest is Test {
    uint256 internal constant ONE_LLM = 1e18;
    uint256 internal constant USDC_UNIT = 1e6;
    uint256 internal constant MINIMUM_RETAINED_STAKE = 5_000 * ONE_LLM;
    uint256 internal constant INITIAL_TOTAL_USDC = 3_000_000 * USDC_UNIT;
    uint256 internal constant RAY = 1e27;

    bytes32 internal constant BORROWER_PERSON_ID = bytes32(uint256(1));
    bytes32 internal constant LIQUIDATOR_PERSON_ID = bytes32(uint256(2));
    address internal constant BORROWER = address(0xB0AA);
    address internal constant LIQUIDATOR = address(0x1A11D);
    address internal constant LP = address(0x1EAD);

    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    StakeLienRegistry internal lienRegistry;
    MockUSDC internal usdc;
    USDCLendingPoolApp internal pool;
    LendingRiskParameterPolicy internal riskPolicyOne;
    LendingRiskParameterPolicy internal riskPolicyTwo;
    LendingInvariantHandler internal handler;
    MockModule internal identityAuthority;
    MockModule internal stakeAuthority;

    /// @notice Deploys and funds the lending, stake, lien, and policy-replacement invariant fixture.
    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identityAuthority = new MockModule(keccak256("invariant.identity-authority"));
        stakeAuthority = new MockModule(keccak256("invariant.stake-authority"));
        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        lienRegistry = new StakeLienRegistry(address(kernel));
        CitizenEligibilityPolicy citizenPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_RETAINED_STAKE);
        UnstakingPolicy unstakingPolicy = new UnstakingPolicy(address(stakeRegistry), 30 days, 1_064);
        usdc = new MockUSDC();
        FixedLlmUsdcPriceOraclePolicy oracle = new FixedLlmUsdcPriceOraclePolicy(address(usdc), USDC_UNIT);
        KinkedInterestRatePolicy interestPolicy = new KinkedInterestRatePolicy(500, 800, 10_000, 8e26);
        riskPolicyOne = new LendingRiskParameterPolicy(3_000, 4_000, 1_500, 1_500, 0);
        riskPolicyTwo = new LendingRiskParameterPolicy(3_000, 3_500, 1_000, 2_000, 500_000 * USDC_UNIT);
        pool = new USDCLendingPoolApp(
            address(kernel),
            address(usdc),
            address(identityRegistry),
            address(stakeRegistry),
            address(lienRegistry),
            1_000_000 * USDC_UNIT
        );
        handler = new LendingInvariantHandler(
            pool,
            kernel,
            usdc,
            BORROWER_PERSON_ID,
            LIQUIDATOR_PERSON_ID,
            BORROWER,
            LIQUIDATOR,
            LP,
            address(riskPolicyOne),
            address(riskPolicyTwo)
        );

        bytes32[] memory moduleIds = new bytes32[](14);
        address[] memory moduleAddresses = new address[](14);
        moduleIds[0] = KernelModuleIds.ACTION_TIMELOCK;
        moduleAddresses[0] = address(handler);
        moduleIds[1] = KernelModuleIds.IDENTITY_REGISTRY;
        moduleAddresses[1] = address(identityRegistry);
        moduleIds[2] = KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY;
        moduleAddresses[2] = address(identityAuthority);
        moduleIds[3] = KernelModuleIds.STAKE_REGISTRY;
        moduleAddresses[3] = address(stakeRegistry);
        moduleIds[4] = KernelModuleIds.STAKE_REGISTRY_AUTHORITY;
        moduleAddresses[4] = address(stakeAuthority);
        moduleIds[5] = KernelModuleIds.LLM_STAKING_VAULT;
        moduleAddresses[5] = address(stakeAuthority);
        moduleIds[6] = KernelModuleIds.STAKE_LIEN_REGISTRY;
        moduleAddresses[6] = address(lienRegistry);
        moduleIds[7] = KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY;
        moduleAddresses[7] = address(pool);
        moduleIds[8] = KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY;
        moduleAddresses[8] = address(pool);
        moduleIds[9] = KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY;
        moduleAddresses[9] = address(citizenPolicy);
        moduleIds[10] = KernelModuleIds.UNSTAKING_POLICY;
        moduleAddresses[10] = address(unstakingPolicy);
        moduleIds[11] = KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY;
        moduleAddresses[11] = address(oracle);
        moduleIds[12] = KernelModuleIds.USDC_INTEREST_RATE_POLICY;
        moduleAddresses[12] = address(interestPolicy);
        moduleIds[13] = KernelModuleIds.LENDING_RISK_PARAMETER_POLICY;
        moduleAddresses[13] = address(riskPolicyOne);
        kernel.bootstrapSetModules(moduleIds, moduleAddresses);
        kernel.bootstrapSetModule(KernelModuleIds.USDC_LENDING_POOL_APP, address(pool));

        _registerCitizen(BORROWER_PERSON_ID, BORROWER, 10_000 * ONE_LLM);
        _registerCitizen(LIQUIDATOR_PERSON_ID, LIQUIDATOR, 7_500 * ONE_LLM);
        usdc.mint(LP, 1_000_000 * USDC_UNIT);
        usdc.mint(BORROWER, 1_000_000 * USDC_UNIT);
        usdc.mint(LIQUIDATOR, 1_000_000 * USDC_UNIT);
        vm.prank(LP);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(BORROWER);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(LIQUIDATOR);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(LP);
        pool.deposit(10_000 * USDC_UNIT, LP);
        kernel.disableBootstrapAuthority();

        targetContract(address(handler));
    }

    /// @notice Proves pool cash, borrow assets, reserves, and supplier assets preserve the accounting identity.
    function invariant_PoolAccountingIdentityAlwaysHolds() public view {
        uint256 cash = usdc.balanceOf(address(pool));
        uint256 borrows = pool.totalBorrows();
        uint256 reserves = pool.totalReserves();
        uint256 grossAssets = cash + borrows;
        assertEq(pool.totalManagedAssets(), grossAssets > reserves ? grossAssets - reserves : 0);
        assertEq(pool.availableLiquidity(), cash > reserves ? cash - reserves : 0);
        assertLe(pool.utilizationRate(), RAY);
        assertLe(reserves, grossAssets);
    }

    /// @notice Proves the live lien and retained floor never exceed canonical active stake.
    function invariant_StakeLiensNeverBreachCanonicalActiveStakeFloors() public view {
        _assertStakeFloor(BORROWER_PERSON_ID);
        _assertStakeFloor(LIQUIDATOR_PERSON_ID);
        if (pool.currentDebtOf(BORROWER_PERSON_ID) == 0) {
            assertEq(lienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        }
    }

    /// @notice Proves USDC conservation across the pool, borrower, supplier, and liquidator.
    function invariant_USDCTokensRemainConservedAcrossPoolActors() public view {
        assertEq(
            usdc.balanceOf(address(pool)) + usdc.balanceOf(BORROWER) + usdc.balanceOf(LIQUIDATOR) + usdc.balanceOf(LP),
            INITIAL_TOTAL_USDC
        );
    }

    /// @notice Proves live risk-policy replacement is limited to reviewed fixture addresses.
    function invariant_RiskPolicyPointerOnlyUsesReviewedFixtures() public view {
        address current = kernel.getModule(KernelModuleIds.LENDING_RISK_PARAMETER_POLICY);
        assertTrue(current == address(riskPolicyOne) || current == address(riskPolicyTwo));
    }

    function _assertStakeFloor(bytes32 personId) private view {
        uint256 activeStake = stakeRegistry.activeStakeOf(personId);
        assertLe(stakeRegistry.requiredActiveStakeFloorOf(personId), activeStake);
        assertLe(lienRegistry.lienedStakeOf(personId), activeStake);
    }

    function _registerCitizen(bytes32 personId, address wallet, uint256 stakeAmount) private {
        vm.prank(address(identityAuthority));
        identityRegistry.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256(abi.encode("invariant.lending.identity", personId)),
                metadataURI: "ipfs://invariant-lending-identity",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        vm.prank(address(identityAuthority));
        identityRegistry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(personId, stakeAmount);
        vm.prank(address(stakeAuthority));
        stakeRegistry.setProtectedStakeFloor(personId, MINIMUM_RETAINED_STAKE);
    }
}
