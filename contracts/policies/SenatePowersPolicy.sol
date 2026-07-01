// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ISenatePowersPolicy} from "../interfaces/ISenatePowersPolicy.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title SenatePowersPolicy
/// @notice Bounds Senate negative-control authority to explicit queued-action cancellation classes.
contract SenatePowersPolicy is ISenatePowersPolicy {
    error InvalidActionCancellationSupport(uint32 minimumSupport);
    error InvalidDisbursementSuspensionPeriod(uint64 suspensionPeriod);

    uint32 internal constant SEAT_COUNT = 100;

    uint32 private immutable _minimumActionCancellationSupport;
    uint64 private immutable _disbursementSuspensionPeriod;

    /// @param minimumActionCancellationSupport_ The minimum equal-weight seat support required to cancel a queued action.
    /// @param disbursementSuspensionPeriod_ The auto-lapsing window a Senate treasury-disbursement suspension blocks for.
    constructor(uint32 minimumActionCancellationSupport_, uint64 disbursementSuspensionPeriod_) {
        if (minimumActionCancellationSupport_ == 0 || minimumActionCancellationSupport_ > SEAT_COUNT) {
            revert InvalidActionCancellationSupport(minimumActionCancellationSupport_);
        }
        if (disbursementSuspensionPeriod_ == 0) {
            revert InvalidDisbursementSuspensionPeriod(disbursementSuspensionPeriod_);
        }

        _minimumActionCancellationSupport = minimumActionCancellationSupport_;
        _disbursementSuspensionPeriod = disbursementSuspensionPeriod_;
    }

    /// @inheritdoc ISenatePowersPolicy
    function seatCount() external pure returns (uint32 count) {
        return SEAT_COUNT;
    }

    /// @inheritdoc ISenatePowersPolicy
    function minimumActionCancellationSupport() external view returns (uint32 count) {
        return _minimumActionCancellationSupport;
    }

    /// @inheritdoc ISenatePowersPolicy
    function disbursementSuspensionPeriod() external view returns (uint64 suspensionPeriod) {
        return _disbursementSuspensionPeriod;
    }

    /// @inheritdoc ISenatePowersPolicy
    function isActionCancellationAllowed(GovernanceTypes.ActionRecord calldata actionRecord)
        external
        pure
        returns (bool allowed)
    {
        return actionRecord.actionId != bytes32(0) && actionRecord.state == GovernanceTypes.ActionState.Queued
            && (actionRecord.actionType == GovernanceTypes.ActionType.ModulePointerUpdate
                || actionRecord.actionType == GovernanceTypes.ActionType.ModuleRegistration
                || actionRecord.actionType == GovernanceTypes.ActionType.TreasuryBudgetApproval
                || actionRecord.actionType == GovernanceTypes.ActionType.LegislationEnactment
                || actionRecord.actionType == GovernanceTypes.ActionType.TreasuryDisbursement);
    }
}
