// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {OfficeTypes} from "../types/OfficeTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title ITreasurySpendingPolicy
/// @notice Policy interface for bounded office spending rules and payout queue delays.
interface ITreasurySpendingPolicy {
    function financeOfficeId() external view returns (bytes32 officeId);

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
        uint256 amount
    ) external view returns (uint64 delaySeconds);

    function computePolicyReference(
        bytes32 officeId,
        OfficeTypes.OfficeRole officeRole,
        TreasuryTypes.DisbursementType disbursementType,
        uint256 amount
    ) external view returns (bytes32 policyReference);
}
