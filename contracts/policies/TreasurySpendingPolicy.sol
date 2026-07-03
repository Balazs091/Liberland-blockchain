// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ITreasurySpendingPolicy} from "../interfaces/ITreasurySpendingPolicy.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title TreasurySpendingPolicy
/// @notice v1 spending guardrails for office-origin treasury requests over an explicit ERC20 asset allowlist.
/// @dev The allowed asset set and per-asset clerk limits are fixed at deployment; changing them means deploying a
///      new policy and repointing the module through governance, consistent with the replaceable-policy model.
contract TreasurySpendingPolicy is ITreasurySpendingPolicy {
    error DuplicateSpendingAsset(address asset);
    error InvalidFinanceOffice(bytes32 officeId);
    error InvalidSpendingAsset(address asset);
    error InvalidSpendingAssetSet(uint256 assetCount);
    error InvalidSpendingLimit(uint256 operationsLimit, uint256 salaryLimit);

    uint64 internal constant STANDARD_QUEUE_DELAY = 6 hours;
    uint64 internal constant SENSITIVE_QUEUE_DELAY = 1 days;

    bytes32 private immutable _financeOfficeId;

    mapping(address asset => AssetSpendingLimit assetLimit) private _assetLimits;
    address[] private _allowedAssets;

    constructor(bytes32 financeOfficeId_, AssetSpendingLimit[] memory assetLimits_) {
        if (financeOfficeId_ == bytes32(0)) {
            revert InvalidFinanceOffice(financeOfficeId_);
        }
        if (assetLimits_.length == 0) {
            revert InvalidSpendingAssetSet(assetLimits_.length);
        }

        _financeOfficeId = financeOfficeId_;

        for (uint256 index = 0; index < assetLimits_.length; index++) {
            AssetSpendingLimit memory assetLimit = assetLimits_[index];
            if (assetLimit.asset == address(0) || assetLimit.asset.code.length == 0) {
                revert InvalidSpendingAsset(assetLimit.asset);
            }
            if (assetLimit.clerkOperationsLimit == 0 || assetLimit.clerkSalaryLimit == 0) {
                revert InvalidSpendingLimit(assetLimit.clerkOperationsLimit, assetLimit.clerkSalaryLimit);
            }
            if (_assetLimits[assetLimit.asset].asset != address(0)) {
                revert DuplicateSpendingAsset(assetLimit.asset);
            }

            _assetLimits[assetLimit.asset] = assetLimit;
            _allowedAssets.push(assetLimit.asset);
        }
    }

    /// @inheritdoc ITreasurySpendingPolicy
    function financeOfficeId() external view returns (bytes32 officeId) {
        return _financeOfficeId;
    }

    /// @inheritdoc ITreasurySpendingPolicy
    function isAssetAllowed(address asset) public view returns (bool allowed) {
        return _assetLimits[asset].asset != address(0);
    }

    /// @inheritdoc ITreasurySpendingPolicy
    function allowedAssetCount() external view returns (uint256 count) {
        return _allowedAssets.length;
    }

    /// @inheritdoc ITreasurySpendingPolicy
    function allowedAssetAt(uint256 index) external view returns (AssetSpendingLimit memory assetLimit) {
        return _assetLimits[_allowedAssets[index]];
    }

    /// @inheritdoc ITreasurySpendingPolicy
    function isPayoutAllowed(
        bytes32 officeId,
        OfficeTypes.OfficeRole officeRole,
        TreasuryTypes.DisbursementType disbursementType,
        address asset,
        uint256 amount
    ) public view returns (bool allowed) {
        if (
            officeId != _financeOfficeId || officeRole == OfficeTypes.OfficeRole.None
                || disbursementType == TreasuryTypes.DisbursementType.Undefined || amount == 0 || !isAssetAllowed(asset)
        ) {
            return false;
        }

        if (officeRole == OfficeTypes.OfficeRole.Admin) {
            return disbursementType == TreasuryTypes.DisbursementType.Operations
                || disbursementType == TreasuryTypes.DisbursementType.Salary
                || disbursementType == TreasuryTypes.DisbursementType.Grant
                || disbursementType == TreasuryTypes.DisbursementType.Refund
                || disbursementType == TreasuryTypes.DisbursementType.CapitalExpenditure;
        }

        if (officeRole == OfficeTypes.OfficeRole.Clerk) {
            AssetSpendingLimit storage assetLimit = _assetLimits[asset];
            if (
                disbursementType == TreasuryTypes.DisbursementType.Operations
                    || disbursementType == TreasuryTypes.DisbursementType.Refund
            ) {
                return amount <= assetLimit.clerkOperationsLimit;
            }

            if (disbursementType == TreasuryTypes.DisbursementType.Salary) {
                return amount <= assetLimit.clerkSalaryLimit;
            }
        }

        return false;
    }

    /// @inheritdoc ITreasurySpendingPolicy
    function minimumQueueDelay(
        bytes32 officeId,
        OfficeTypes.OfficeRole officeRole,
        TreasuryTypes.DisbursementType disbursementType,
        address asset,
        uint256 amount
    ) external view returns (uint64 delaySeconds) {
        return _minimumQueueDelay(officeId, officeRole, disbursementType, asset, amount);
    }

    /// @inheritdoc ITreasurySpendingPolicy
    function computePolicyReference(
        bytes32 officeId,
        OfficeTypes.OfficeRole officeRole,
        TreasuryTypes.DisbursementType disbursementType,
        address asset,
        uint256 amount
    ) external view returns (bytes32 policyReference) {
        return keccak256(
            abi.encode(
                address(this),
                officeId,
                officeRole,
                disbursementType,
                asset,
                amount,
                // Internal call (JUMP, not an external self-CALL) so the branch logic runs once.
                _minimumQueueDelay(officeId, officeRole, disbursementType, asset, amount)
            )
        );
    }

    function _minimumQueueDelay(
        bytes32 officeId,
        OfficeTypes.OfficeRole officeRole,
        TreasuryTypes.DisbursementType disbursementType,
        address asset,
        uint256 amount
    ) private view returns (uint64 delaySeconds) {
        if (!isPayoutAllowed(officeId, officeRole, disbursementType, asset, amount)) {
            return 0;
        }

        if (
            disbursementType == TreasuryTypes.DisbursementType.Grant
                || disbursementType == TreasuryTypes.DisbursementType.CapitalExpenditure
        ) {
            return SENSITIVE_QUEUE_DELAY;
        }

        return STANDARD_QUEUE_DELAY;
    }
}
