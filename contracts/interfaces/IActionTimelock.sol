// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title IActionTimelock
/// @notice Interface for the privileged governance action queue and execution lifecycle.
interface IActionTimelock {
    error ActionAlreadyQueued(bytes32 actionId);
    error ActionAlreadyFinalized(bytes32 actionId, GovernanceTypes.ActionState state);
    error ActionExpired(bytes32 actionId, uint64 expiresAt);
    error ActionCancellationPending(bytes32 actionId, uint64 deadline);
    error ActionSuspended(bytes32 actionId, uint64 suspendedUntil);
    error ActionUnderConstitutionalReview(bytes32 actionId);
    error ActionNotFound(bytes32 actionId);
    error ActionNotExpired(bytes32 actionId, uint64 expiresAt);
    error ActionNotReady(bytes32 actionId, uint64 earliestExecutionTime);
    error InvalidActionExpiry(bytes32 actionId, uint64 expiresAt, uint64 earliestExecutionTime);
    error InvalidActionPayload(bytes32 actionId);
    error InvalidDelayConfig(GovernanceTypes.TimelockDelayConfig config);
    error QueuedTargetModuleChanged(
        bytes32 actionId, bytes32 targetModule, address expectedAddress, address actualAddress
    );
    error UnauthorizedTimelockCaller(address caller);
    error UnsupportedExecutionAction(GovernanceTypes.ActionType actionType);

    event ActionQueued(
        bytes32 indexed actionId,
        GovernanceTypes.ActionType indexed actionType,
        bytes32 indexed targetModule,
        GovernanceTypes.ActionOrigin origin,
        bytes32 originReference,
        bytes32 policyReference,
        address targetModuleAddress,
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

    /// @notice Returns whether the timelock accepts and can execute a governance action type.
    /// @dev Mirrors {IGovernanceRouter-isActionTypeSupported}; the routed and executable sets must stay identical.
    /// @param actionType The governance action type.
    /// @return supported Whether the action type is queueable and executable through the timelock.
    function isActionTypeSupported(GovernanceTypes.ActionType actionType) external pure returns (bool supported);
}
