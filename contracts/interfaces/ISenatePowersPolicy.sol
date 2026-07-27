// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title ISenatePowersPolicy
/// @notice Policy interface for bounded Senate negative-control powers.
interface ISenatePowersPolicy {
    /// @notice Returns the fixed v1 Senate seat count used by the policy.
    /// @return count The total seat count.
    function seatCount() external pure returns (uint32 count);

    /// @notice Returns the minimum equal-weight seat support required to cancel an action.
    /// @return count The minimum seat support threshold.
    function minimumActionCancellationSupport() external view returns (uint32 count);

    /// @notice Returns the auto-lapsing window a Senate treasury-disbursement suspension blocks execution for.
    /// @return suspensionPeriod The disbursement suspension period in seconds.
    function disbursementSuspensionPeriod() external view returns (uint64 suspensionPeriod);

    /// @notice Returns true when an action record falls within the Senate's bounded cancellation scope.
    /// @param actionRecord The queued action record to evaluate.
    /// @return allowed Whether the Senate may cancel the action.
    function isActionCancellationAllowed(GovernanceTypes.ActionRecord calldata actionRecord)
        external
        view
        returns (bool allowed);
}
