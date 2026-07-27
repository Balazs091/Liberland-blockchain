// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MinistryTreasury} from "../../contracts/apps/MinistryTreasury.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IMinistryTreasury} from "../../contracts/interfaces/IMinistryTreasury.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {MockUSDC} from "../../contracts/mocks/MockUSDC.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

/// @dev Minimal 1:1 lending-pool stand-in exposing only the entrypoints MinistryTreasury calls. The real pool's
///      share/yield math is covered by the lending suite; this isolates the ministry-treasury logic.
contract MockLendingPool {
    using SafeERC20 for IERC20;

    MockUSDC private immutable _usdc;

    mapping(address holder => uint256 shares) public shareBalanceOf;

    constructor(MockUSDC usdc_) {
        _usdc = usdc_;
    }

    function usdc() external view returns (address tokenAddress) {
        return address(_usdc);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        IERC20(address(_usdc)).safeTransferFrom(msg.sender, address(this), assets);
        shareBalanceOf[receiver] += assets;
        return assets;
    }

    function withdraw(uint256 assets, address receiver) external returns (uint256 shares) {
        shareBalanceOf[msg.sender] -= assets;
        IERC20(address(_usdc)).safeTransfer(receiver, assets);
        return assets;
    }
}

/// @dev Contract stand-in for the Congress-decision funding authority (a contract in production, e.g. DecisionApp).
contract MockFundingAuthority {
    function fund(MinistryTreasury treasury, bytes32 officeId, address asset, uint256 amount) external {
        // Acts as both the gating funding authority (caller) and, for the test, the funding source.
        IERC20(asset).approve(address(treasury), amount);
        treasury.fund(officeId, asset, address(this), amount);
    }
}

contract MinistryTreasuryTest is Test {
    uint256 internal constant USDC_UNIT = 1_000_000;
    uint256 internal constant ONE_LLM = 1e18;

    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    bytes32 internal constant INTERIOR_OFFICE_ID = keccak256("office.ministry-interior");
    bytes32 internal constant NEW_OFFICE_ID = keccak256("office.ministry-new");

    address internal constant FINANCE_MINISTER = address(0xF1);
    address internal constant FINANCE_CLERK = address(0xF2);
    address internal constant INTERIOR_MINISTER = address(0x11);
    address internal constant NEW_MINISTER = address(0x9E);
    address internal constant PAYEE = address(0xBEEF);

    ConstitutionKernel internal kernel;
    OfficeRegistry internal officeRegistry;
    MockUSDC internal usdc;
    LLMToken internal llm;
    MockLendingPool internal pool;
    MockFundingAuthority internal fundingAuthority;
    MinistryTreasury internal treasury;

    function setUp() public {
        vm.warp(100 days); // move off day 0 so daily-window math is unambiguous

        kernel = new ConstitutionKernel(address(this));
        officeRegistry = new OfficeRegistry(address(kernel));
        usdc = new MockUSDC();
        llm = new LLMToken();
        pool = new MockLendingPool(usdc);
        fundingAuthority = new MockFundingAuthority();
        treasury = new MinistryTreasury(address(kernel));

        bytes32[] memory ids = new bytes32[](4);
        address[] memory addrs = new address[](4);
        ids[0] = KernelModuleIds.OFFICE_REGISTRY;
        addrs[0] = address(officeRegistry);
        ids[1] = KernelModuleIds.OFFICE_REGISTRY_AUTHORITY;
        addrs[1] = address(this); // lets the test register offices/clerks directly
        ids[2] = KernelModuleIds.USDC_LENDING_POOL_APP;
        addrs[2] = address(pool);
        ids[3] = KernelModuleIds.MINISTRY_TREASURY_FUNDING_AUTHORITY;
        addrs[3] = address(fundingAuthority);
        kernel.bootstrapSetModules(ids, addrs);
        kernel.bootstrapSetModule(KernelModuleIds.MINISTRY_TREASURY, address(treasury));

        officeRegistry.registerOffice(
            FINANCE_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "Ministry of Finance", FINANCE_MINISTER
        );
        officeRegistry.setClerkStatus(FINANCE_OFFICE_ID, FINANCE_CLERK, true);
        officeRegistry.registerOffice(
            INTERIOR_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "Ministry of Interior", INTERIOR_MINISTER
        );
    }

    function _fund(bytes32 officeId, MockUSDC token, uint256 amount) private {
        token.mint(address(fundingAuthority), amount);
        fundingAuthority.fund(treasury, officeId, address(token), amount);
    }

    function test_OnlyFundingAuthorityCanFund() public {
        usdc.mint(address(this), 1_000 * USDC_UNIT);
        usdc.approve(address(treasury), 1_000 * USDC_UNIT);
        vm.expectRevert(abi.encodeWithSelector(IMinistryTreasury.UnauthorizedFundingAuthority.selector, address(this)));
        treasury.fund(FINANCE_OFFICE_ID, address(usdc), address(this), 1_000 * USDC_UNIT);

        _fund(FINANCE_OFFICE_ID, usdc, 1_000 * USDC_UNIT);
        assertEq(treasury.balanceOf(FINANCE_OFFICE_ID, address(usdc)), 1_000 * USDC_UNIT);
    }

    function test_MinisterSpendsFreely() public {
        _fund(FINANCE_OFFICE_ID, usdc, 1_000 * USDC_UNIT);

        vm.prank(FINANCE_MINISTER);
        treasury.spend(FINANCE_OFFICE_ID, address(usdc), PAYEE, 900 * USDC_UNIT);

        assertEq(usdc.balanceOf(PAYEE), 900 * USDC_UNIT);
        assertEq(treasury.balanceOf(FINANCE_OFFICE_ID, address(usdc)), 100 * USDC_UNIT);
    }

    function test_ClerkBlockedUntilMinisterSetsDailyLimitThenBoundedAndResets() public {
        _fund(FINANCE_OFFICE_ID, usdc, 1_000 * USDC_UNIT);

        // Default limit is zero, so a clerk cannot spend at all.
        vm.prank(FINANCE_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMinistryTreasury.ClerkDailyLimitExceeded.selector,
                FINANCE_OFFICE_ID,
                FINANCE_CLERK,
                address(usdc),
                uint256(0),
                uint256(0),
                100 * USDC_UNIT
            )
        );
        treasury.spend(FINANCE_OFFICE_ID, address(usdc), PAYEE, 100 * USDC_UNIT);

        // Minister sets a 100 USDC/day clerk limit.
        vm.prank(FINANCE_MINISTER);
        treasury.setClerkDailyLimit(FINANCE_OFFICE_ID, address(usdc), 100 * USDC_UNIT);

        vm.prank(FINANCE_CLERK);
        treasury.spend(FINANCE_OFFICE_ID, address(usdc), PAYEE, 60 * USDC_UNIT);
        assertEq(treasury.clerkSpentToday(FINANCE_OFFICE_ID, FINANCE_CLERK, address(usdc)), 60 * USDC_UNIT);

        // A second spend that would breach the daily limit reverts.
        vm.prank(FINANCE_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMinistryTreasury.ClerkDailyLimitExceeded.selector,
                FINANCE_OFFICE_ID,
                FINANCE_CLERK,
                address(usdc),
                60 * USDC_UNIT,
                100 * USDC_UNIT,
                50 * USDC_UNIT
            )
        );
        treasury.spend(FINANCE_OFFICE_ID, address(usdc), PAYEE, 50 * USDC_UNIT);

        // The minister is never bound by the clerk limit.
        vm.prank(FINANCE_MINISTER);
        treasury.spend(FINANCE_OFFICE_ID, address(usdc), PAYEE, 500 * USDC_UNIT);

        // The next day the clerk allowance resets.
        vm.warp(block.timestamp + 1 days);
        assertEq(treasury.clerkSpentToday(FINANCE_OFFICE_ID, FINANCE_CLERK, address(usdc)), 0);
        vm.prank(FINANCE_CLERK);
        treasury.spend(FINANCE_OFFICE_ID, address(usdc), PAYEE, 90 * USDC_UNIT);
        assertEq(treasury.clerkSpentToday(FINANCE_OFFICE_ID, FINANCE_CLERK, address(usdc)), 90 * USDC_UNIT);
    }

    function test_MinisterSuppliesAndWithdrawsPoolAndClerkCannot() public {
        _fund(FINANCE_OFFICE_ID, usdc, 1_000 * USDC_UNIT);

        vm.prank(FINANCE_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMinistryTreasury.UnauthorizedMinistryCaller.selector, FINANCE_OFFICE_ID, FINANCE_CLERK
            )
        );
        treasury.supplyToPool(FINANCE_OFFICE_ID, 600 * USDC_UNIT);

        vm.prank(FINANCE_MINISTER);
        uint256 shares = treasury.supplyToPool(FINANCE_OFFICE_ID, 600 * USDC_UNIT);
        assertEq(shares, 600 * USDC_UNIT);
        assertEq(treasury.balanceOf(FINANCE_OFFICE_ID, address(usdc)), 400 * USDC_UNIT);
        assertEq(treasury.poolSharesOf(FINANCE_OFFICE_ID), 600 * USDC_UNIT);

        // Take it back in-house at any time (up to the pool's liquidity, which the mock always has).
        vm.prank(FINANCE_MINISTER);
        treasury.withdrawFromPool(FINANCE_OFFICE_ID, 250 * USDC_UNIT);
        assertEq(treasury.balanceOf(FINANCE_OFFICE_ID, address(usdc)), 650 * USDC_UNIT);
        assertEq(treasury.poolSharesOf(FINANCE_OFFICE_ID), 350 * USDC_UNIT);
    }

    function test_OfficeBalancesAndPoolSharesAreIsolatedPerOffice() public {
        _fund(FINANCE_OFFICE_ID, usdc, 1_000 * USDC_UNIT);
        _fund(INTERIOR_OFFICE_ID, usdc, 1_000 * USDC_UNIT);

        // The finance minister has no role in the interior office and cannot touch its funds.
        vm.prank(FINANCE_MINISTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMinistryTreasury.UnauthorizedMinistryCaller.selector, INTERIOR_OFFICE_ID, FINANCE_MINISTER
            )
        );
        treasury.spend(INTERIOR_OFFICE_ID, address(usdc), PAYEE, 100 * USDC_UNIT);

        // Both offices supply into the pool; the treasury commingles the shares but tracks them per office.
        vm.prank(FINANCE_MINISTER);
        treasury.supplyToPool(FINANCE_OFFICE_ID, 1_000 * USDC_UNIT);
        vm.prank(INTERIOR_MINISTER);
        treasury.supplyToPool(INTERIOR_OFFICE_ID, 600 * USDC_UNIT);

        assertEq(treasury.poolSharesOf(FINANCE_OFFICE_ID), 1_000 * USDC_UNIT);
        assertEq(treasury.poolSharesOf(INTERIOR_OFFICE_ID), 600 * USDC_UNIT);
        assertEq(treasury.balanceOf(INTERIOR_OFFICE_ID, address(usdc)), 400 * USDC_UNIT);

        // Even though the treasury holds 1,600 shares in total, finance cannot redeem more than its own 1,000 —
        // its withdrawal cannot eat into interior's shares.
        vm.prank(FINANCE_MINISTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMinistryTreasury.InsufficientMinistryPoolShares.selector,
                FINANCE_OFFICE_ID,
                address(pool),
                1_000 * USDC_UNIT,
                1_400 * USDC_UNIT
            )
        );
        treasury.withdrawFromPool(FINANCE_OFFICE_ID, 1_400 * USDC_UNIT);

        // Interior's position is intact after finance's failed over-withdrawal.
        assertEq(treasury.poolSharesOf(INTERIOR_OFFICE_ID), 600 * USDC_UNIT);
        assertEq(treasury.balanceOf(INTERIOR_OFFICE_ID, address(usdc)), 400 * USDC_UNIT);
    }

    function test_PoolReplacementDoesNotMixOfficeSharesAndOldPoolRemainsWithdrawable() public {
        _fund(FINANCE_OFFICE_ID, usdc, 1_000 * USDC_UNIT);
        _fund(INTERIOR_OFFICE_ID, usdc, 1_000 * USDC_UNIT);

        MockLendingPool oldPool = pool;
        vm.prank(FINANCE_MINISTER);
        treasury.supplyToPool(FINANCE_OFFICE_ID, 1_000 * USDC_UNIT);

        MockLendingPool replacementPool = new MockLendingPool(usdc);
        kernel.bootstrapSetModule(KernelModuleIds.USDC_LENDING_POOL_APP, address(replacementPool));

        vm.prank(INTERIOR_MINISTER);
        treasury.supplyToPool(INTERIOR_OFFICE_ID, 600 * USDC_UNIT);

        assertEq(treasury.poolSharesOf(FINANCE_OFFICE_ID), 0);
        assertEq(treasury.poolSharesAt(FINANCE_OFFICE_ID, address(oldPool)), 1_000 * USDC_UNIT);
        assertEq(treasury.poolSharesOf(INTERIOR_OFFICE_ID), 600 * USDC_UNIT);

        vm.prank(FINANCE_MINISTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMinistryTreasury.NoMinistryPoolShares.selector, FINANCE_OFFICE_ID, address(replacementPool)
            )
        );
        treasury.withdrawFromPool(FINANCE_OFFICE_ID, 100 * USDC_UNIT);

        assertEq(replacementPool.shareBalanceOf(address(treasury)), 600 * USDC_UNIT);
        assertEq(treasury.poolSharesOf(INTERIOR_OFFICE_ID), 600 * USDC_UNIT);

        vm.prank(FINANCE_MINISTER);
        treasury.withdrawFromPoolAt(FINANCE_OFFICE_ID, address(oldPool), 250 * USDC_UNIT);

        assertEq(treasury.balanceOf(FINANCE_OFFICE_ID, address(usdc)), 250 * USDC_UNIT);
        assertEq(treasury.poolSharesAt(FINANCE_OFFICE_ID, address(oldPool)), 750 * USDC_UNIT);
        assertEq(replacementPool.shareBalanceOf(address(treasury)), 600 * USDC_UNIT);
    }

    function test_NewlyRegisteredOfficeCanHoldAndSpendFunds() public {
        // An office added after deployment (as Congress would via a RegisterOffice decision) works with no change.
        officeRegistry.registerOffice(
            NEW_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "New Ministry", NEW_MINISTER
        );

        _fund(NEW_OFFICE_ID, usdc, 500 * USDC_UNIT);
        vm.prank(NEW_MINISTER);
        treasury.spend(NEW_OFFICE_ID, address(usdc), PAYEE, 500 * USDC_UNIT);

        assertEq(usdc.balanceOf(PAYEE), 500 * USDC_UNIT);
        assertEq(treasury.balanceOf(NEW_OFFICE_ID, address(usdc)), 0);
    }

    function test_NonMinisterCannotSetClerkLimit() public {
        vm.prank(FINANCE_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMinistryTreasury.UnauthorizedMinistryCaller.selector, FINANCE_OFFICE_ID, FINANCE_CLERK
            )
        );
        treasury.setClerkDailyLimit(FINANCE_OFFICE_ID, address(usdc), 100 * USDC_UNIT);
    }

    function test_FundRevertsForUnknownOffice() public {
        usdc.mint(address(fundingAuthority), 100 * USDC_UNIT);
        vm.expectRevert(
            abi.encodeWithSelector(IMinistryTreasury.InvalidMinistryOffice.selector, keccak256("office.unknown"))
        );
        fundingAuthority.fund(treasury, keccak256("office.unknown"), address(usdc), 100 * USDC_UNIT);
    }
}
