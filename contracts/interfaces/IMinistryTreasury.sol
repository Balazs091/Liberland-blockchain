// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IKernelModule} from "./IKernelModule.sol";

/// @title IMinistryTreasury
/// @notice Shared, office-keyed treasury holding ERC20 balances (LLM, stablecoins) for ministries and offices, with
///         in-house lending-pool supply so idle funds earn. Balances are keyed by office ID, so any office —
///         including ones Congress creates later — can hold funds without redeploying this module.
interface IMinistryTreasury is IKernelModule {
    error ClerkDailyLimitExceeded(
        bytes32 officeId, address clerk, address asset, uint256 spentToday, uint256 dailyLimit, uint256 requested
    );
    error InsufficientMinistryBalance(bytes32 officeId, address asset, uint256 available, uint256 requested);
    error InsufficientMinistryPoolShares(bytes32 officeId, address pool, uint256 available, uint256 required);
    error InvalidAmount(uint256 amount);
    error InvalidAsset(address asset);
    error InvalidMinistryOffice(bytes32 officeId);
    error InvalidRecipient(address recipient);
    error NoMinistryPoolShares(bytes32 officeId, address pool);
    error UnauthorizedFundingAuthority(address caller);
    error UnauthorizedMinistryCaller(bytes32 officeId, address caller);
    error UnexpectedAssetAmount(uint256 expectedAmount, uint256 actualAmount);

    event MinistryFunded(
        bytes32 indexed officeId, address indexed asset, uint256 amount, address indexed fundedBy, uint64 fundedAt
    );
    event MinistrySpent(
        bytes32 indexed officeId,
        address indexed asset,
        address indexed recipient,
        uint256 amount,
        address spender,
        uint64 spentAt
    );
    event ClerkDailyLimitSet(
        bytes32 indexed officeId, address indexed asset, uint256 dailyLimit, address setBy, uint64 setAt
    );
    event MinistrySuppliedToPool(
        bytes32 indexed officeId, address indexed pool, uint256 assets, uint256 shares, uint64 suppliedAt
    );
    event MinistryWithdrewFromPool(
        bytes32 indexed officeId, address indexed pool, uint256 assets, uint256 shares, uint64 withdrewAt
    );

    /// @notice Returns an office's idle (non-pool) balance of an asset.
    function balanceOf(bytes32 officeId, address asset) external view returns (uint256 amount);

    /// @notice Returns an office's share balance in the current governed lending pool.
    function poolSharesOf(bytes32 officeId) external view returns (uint256 shares);

    /// @notice Returns an office's share balance in a specific current or retired lending pool.
    function poolSharesAt(bytes32 officeId, address pool) external view returns (uint256 shares);

    /// @notice Returns the per-clerk daily spend limit an office's minister set for an asset (0 = clerks blocked).
    function clerkDailyLimit(bytes32 officeId, address asset) external view returns (uint256 dailyLimit);

    /// @notice Returns how much a clerk has spent of an asset in the current day window for an office.
    function clerkSpentToday(bytes32 officeId, address clerk, address asset) external view returns (uint256 amount);

    /// @notice Credits an office's balance. Restricted to the Congress-decision funding authority.
    /// @param officeId The office/ministry to credit.
    /// @param asset The ERC20 asset to fund.
    /// @param from The funding source wallet; must have approved this treasury for the amount. Only the gating
    ///        funding authority (the caller) can trigger the pull, so the approval cannot be spent arbitrarily.
    /// @param amount The amount to fund in the asset's smallest units.
    function fund(bytes32 officeId, address asset, address from, uint256 amount) external;

    /// @notice Sets the per-clerk daily spend limit for an asset. Minister (office admin) only.
    function setClerkDailyLimit(bytes32 officeId, address asset, uint256 dailyLimit) external;

    /// @notice Spends an office's funds to a recipient. Minister spends any amount; clerks are bound by the daily
    ///         limit the minister set for that asset.
    function spend(bytes32 officeId, address asset, address recipient, uint256 amount) external;

    /// @notice Supplies an office's stablecoin balance into the lending pool to earn the supply rate. Minister only.
    /// @return shares The lending-pool shares credited to the office.
    function supplyToPool(bytes32 officeId, uint256 amount) external returns (uint256 shares);

    /// @notice Withdraws stablecoin from the lending pool back into an office's idle balance. Minister only.
    /// @return shares The lending-pool shares redeemed from the office.
    function withdrawFromPool(bytes32 officeId, uint256 amount) external returns (uint256 shares);

    /// @notice Withdraws from a specific current or retired lending pool in which the office owns recorded shares.
    /// @dev This keeps pool-pointer replacement from stranding an office's old-pool position or mixing it with
    ///      another office's position in the replacement pool.
    /// @return shares The lending-pool shares redeemed from the office.
    function withdrawFromPoolAt(bytes32 officeId, address pool, uint256 amount) external returns (uint256 shares);
}
