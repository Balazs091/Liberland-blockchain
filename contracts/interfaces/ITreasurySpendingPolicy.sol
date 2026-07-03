// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OfficeTypes} from "../types/OfficeTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title ITreasurySpendingPolicy
/// @notice Policy interface for bounded office spending rules and payout queue delays over allowed ERC20 assets.
interface ITreasurySpendingPolicy {
    /// @notice Per-asset spending configuration for treasury payouts.
    /// @param asset The ERC20 token address allowed for treasury spending.
    /// @param clerkOperationsLimit The per-payout clerk cap for Operations/Refund, in the asset's smallest units.
    /// @param clerkSalaryLimit The per-payout clerk cap for Salary, in the asset's smallest units.
    struct AssetSpendingLimit {
        address asset;
        uint256 clerkOperationsLimit;
        uint256 clerkSalaryLimit;
    }

    function financeOfficeId() external view returns (bytes32 officeId);

    /// @notice Returns whether an ERC20 asset is allowed for treasury spending.
    /// @param asset The ERC20 token address.
    /// @return allowed True when the asset is configured in this policy.
    function isAssetAllowed(address asset) external view returns (bool allowed);

    /// @notice Returns the number of allowed spending assets.
    /// @return count The allowed asset count.
    function allowedAssetCount() external view returns (uint256 count);

    /// @notice Returns the allowed asset configuration at an index.
    /// @param index The asset index.
    /// @return assetLimit The asset spending configuration.
    function allowedAssetAt(uint256 index) external view returns (AssetSpendingLimit memory assetLimit);

    function isPayoutAllowed(
        bytes32 officeId,
        OfficeTypes.OfficeRole officeRole,
        TreasuryTypes.DisbursementType disbursementType,
        address asset,
        uint256 amount
    ) external view returns (bool allowed);

    function minimumQueueDelay(
        bytes32 officeId,
        OfficeTypes.OfficeRole officeRole,
        TreasuryTypes.DisbursementType disbursementType,
        address asset,
        uint256 amount
    ) external view returns (uint64 delaySeconds);

    function computePolicyReference(
        bytes32 officeId,
        OfficeTypes.OfficeRole officeRole,
        TreasuryTypes.DisbursementType disbursementType,
        address asset,
        uint256 amount
    ) external view returns (bytes32 policyReference);
}
