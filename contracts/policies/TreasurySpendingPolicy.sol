// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ITreasurySpendingPolicy} from "../interfaces/ITreasurySpendingPolicy.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title TreasurySpendingPolicy
/// @notice v1 spending guardrails for office-origin treasury requests.
contract TreasurySpendingPolicy is ITreasurySpendingPolicy {
    error InvalidFinanceOffice(bytes32 officeId);
    error InvalidSpendingLimit(uint256 operationsLimit, uint256 salaryLimit);

    uint64 internal constant STANDARD_QUEUE_DELAY = 6 hours;
    uint64 internal constant SENSITIVE_QUEUE_DELAY = 1 days;

    bytes32 private immutable _financeOfficeId;
    uint256 private immutable _financeClerkOperationsLimit;
    uint256 private immutable _financeClerkSalaryLimit;

    constructor(bytes32 financeOfficeId_, uint256 financeClerkOperationsLimit_, uint256 financeClerkSalaryLimit_) {
        if (financeOfficeId_ == bytes32(0)) {
            revert InvalidFinanceOffice(financeOfficeId_);
        }
        if (financeClerkOperationsLimit_ == 0 || financeClerkSalaryLimit_ == 0) {
            revert InvalidSpendingLimit(financeClerkOperationsLimit_, financeClerkSalaryLimit_);
        }

        _financeOfficeId = financeOfficeId_;
        _financeClerkOperationsLimit = financeClerkOperationsLimit_;
        _financeClerkSalaryLimit = financeClerkSalaryLimit_;
    }

    /// @inheritdoc ITreasurySpendingPolicy
    function financeOfficeId() external view returns (bytes32 officeId) {
        return _financeOfficeId;
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
                || disbursementType == TreasuryTypes.DisbursementType.Undefined || asset != address(0) || amount == 0
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
            if (
                disbursementType == TreasuryTypes.DisbursementType.Operations
                    || disbursementType == TreasuryTypes.DisbursementType.Refund
            ) {
                return amount <= _financeClerkOperationsLimit;
            }

            if (disbursementType == TreasuryTypes.DisbursementType.Salary) {
                return amount <= _financeClerkSalaryLimit;
            }
        }

        return false;
    }

    /// @inheritdoc ITreasurySpendingPolicy
    function minimumQueueDelay(
        bytes32 officeId,
        OfficeTypes.OfficeRole officeRole,
        TreasuryTypes.DisbursementType disbursementType,
        uint256 amount
    ) external view returns (uint64 delaySeconds) {
        if (!isPayoutAllowed(officeId, officeRole, disbursementType, address(0), amount)) {
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

    /// @inheritdoc ITreasurySpendingPolicy
    function computePolicyReference(
        bytes32 officeId,
        OfficeTypes.OfficeRole officeRole,
        TreasuryTypes.DisbursementType disbursementType,
        uint256 amount
    ) external view returns (bytes32 policyReference) {
        return keccak256(
            abi.encode(
                address(this),
                officeId,
                officeRole,
                disbursementType,
                amount,
                this.minimumQueueDelay(officeId, officeRole, disbursementType, amount)
            )
        );
    }
}
