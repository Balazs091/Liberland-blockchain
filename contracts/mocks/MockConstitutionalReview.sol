// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IConstitutionalReview} from "../interfaces/IConstitutionalReview.sol";

/// @title MockConstitutionalReview
/// @notice Test double for a future constitutional-review (judiciary) module: lets a test pause/release execution
///         of a specific queued action so the action-timelock hook can be exercised.
contract MockConstitutionalReview is IConstitutionalReview {
    mapping(bytes32 actionId => bool paused) private _paused;

    function setActionPaused(bytes32 actionId, bool paused) external {
        _paused[actionId] = paused;
    }

    /// @inheritdoc IConstitutionalReview
    function isActionExecutionPaused(bytes32 actionId) external view returns (bool paused) {
        return _paused[actionId];
    }
}
