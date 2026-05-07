// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ISenatePowersPolicy} from "../interfaces/ISenatePowersPolicy.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title SenatePowersPolicy
/// @notice Bounds Senate negative-control authority to explicit queued-action cancellation classes.
contract SenatePowersPolicy is ISenatePowersPolicy {
    error InvalidActionCancellationSupport(uint32 minimumSupport);

    uint32 internal constant SEAT_COUNT = 100;

    uint32 private immutable _minimumActionCancellationSupport;

    /// @param minimumActionCancellationSupport_ The minimum equal-weight seat support required to cancel a queued action.
    constructor(uint32 minimumActionCancellationSupport_) {
        if (minimumActionCancellationSupport_ == 0 || minimumActionCancellationSupport_ > SEAT_COUNT) {
            revert InvalidActionCancellationSupport(minimumActionCancellationSupport_);
        }

        _minimumActionCancellationSupport = minimumActionCancellationSupport_;
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
    function isActionCancellationAllowed(GovernanceTypes.ActionRecord calldata actionRecord)
        external
        pure
        returns (bool allowed)
    {
        return actionRecord.actionId != bytes32(0) && actionRecord.state == GovernanceTypes.ActionState.Queued
            && (actionRecord.actionType == GovernanceTypes.ActionType.ModulePointerUpdate
                || actionRecord.actionType == GovernanceTypes.ActionType.TreasuryBudgetApproval
                || actionRecord.actionType == GovernanceTypes.ActionType.LegislationEnactment
                || actionRecord.actionType == GovernanceTypes.ActionType.TreasuryDisbursement);
    }
}
