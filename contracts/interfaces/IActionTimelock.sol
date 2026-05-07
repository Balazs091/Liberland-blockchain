// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title IActionTimelock
/// @notice Interface for the privileged governance action queue and execution lifecycle.
interface IActionTimelock {
    error ActionAlreadyQueued(bytes32 actionId);
    error ActionAlreadyFinalized(bytes32 actionId, GovernanceTypes.ActionState state);
    error ActionExpired(bytes32 actionId, uint64 expiresAt);
    error ActionNotFound(bytes32 actionId);
    error ActionNotExpired(bytes32 actionId, uint64 expiresAt);
    error ActionNotReady(bytes32 actionId, uint64 earliestExecutionTime);
    error InvalidActionExpiry(bytes32 actionId, uint64 expiresAt, uint64 earliestExecutionTime);
    error InvalidActionPayload(bytes32 actionId);
    error UnauthorizedTimelockCaller(address caller);
    error UnsupportedExecutionAction(GovernanceTypes.ActionType actionType);

    event ActionQueued(
        bytes32 indexed actionId,
        GovernanceTypes.ActionType indexed actionType,
        bytes32 indexed targetModule,
        GovernanceTypes.ActionOrigin origin,
        bytes32 originReference,
        bytes32 policyReference,
        bytes32 payloadHash,
        uint64 createdAt,
        uint64 earliestExecutionTime,
        uint64 expiresAt
    );

    event ActionCanceled(bytes32 indexed actionId, address indexed canceledBy);

    event ActionExecuted(bytes32 indexed actionId, address indexed executedBy);

    event ActionExpiredRecorded(bytes32 indexed actionId, uint64 expiredAt);

    /// @notice Computes the deterministic action identifier for a request.
    /// @param request The governance action request.
    /// @return actionId The deterministic action identifier.
    function computeActionId(GovernanceTypes.ActionRequest calldata request) external view returns (bytes32 actionId);

    /// @notice Queues a governance action for delayed execution.
    /// @param request The governance action request.
    /// @return actionId The queued deterministic action identifier.
    function queueAction(GovernanceTypes.ActionRequest calldata request) external returns (bytes32 actionId);

    /// @notice Cancels a previously queued governance action.
    /// @param actionId The deterministic action identifier.
    function cancelAction(bytes32 actionId) external;

    /// @notice Executes a previously queued governance action.
    /// @param actionId The deterministic action identifier.
    function executeAction(bytes32 actionId) external;

    /// @notice Records expiration for a queued action whose execution window has elapsed.
    /// @param actionId The deterministic action identifier.
    function expireAction(bytes32 actionId) external;

    /// @notice Returns the stored action record for an identifier.
    /// @param actionId The deterministic action identifier.
    /// @return actionRecord The stored action record.
    function getAction(bytes32 actionId) external view returns (GovernanceTypes.ActionRecord memory actionRecord);

    /// @notice Returns the current state for a queued governance action.
    /// @param actionId The deterministic action identifier.
    /// @return state The current action state.
    function getActionState(bytes32 actionId) external view returns (GovernanceTypes.ActionState state);

    /// @notice Returns true when an action can be executed at the current time.
    /// @param actionId The deterministic action identifier.
    /// @return executable Whether the action is currently executable.
    function isActionExecutable(bytes32 actionId) external view returns (bool executable);

    /// @notice Returns the minimum delay for a governance action type.
    /// @param actionType The governance action type.
    /// @return delaySeconds The minimum delay in seconds.
    function minimumDelay(GovernanceTypes.ActionType actionType) external view returns (uint64 delaySeconds);
}
