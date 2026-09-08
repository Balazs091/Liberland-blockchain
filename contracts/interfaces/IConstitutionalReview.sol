// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title IConstitutionalReview
/// @notice Optional constitutional-review (judiciary) hook consulted by the action timelock before executing a
///         queued governance action. A future court module registered under
///         `KernelModuleIds.CONSTITUTIONAL_REVIEW` can pause execution of specific actions pending review. Until
///         such a module is registered the timelock treats every action as not paused, so a constitutional court is
///         a post-launch add-on (registered through a constitutional-threshold module referendum after bootstrap)
///         that needs no upgrade to the deliberately un-repointable core timelock.
interface IConstitutionalReview {
    /// @notice Returns whether execution of a queued governance action is currently paused for constitutional review.
    /// @dev The optional timelock probe supplies at most 100,000 gas and accepts only a canonical 32-byte bool.
    ///      A reverting, over-budget or malformed implementation cannot hold the queue closed. Caller-induced
    ///      underfunding reverts the outer operation rather than bypassing an active review.
    /// @param actionId The queued action identifier.
    /// @return paused True if timelock execution of the action must be blocked pending review.
    function isActionExecutionPaused(bytes32 actionId) external view returns (bool paused);
}
