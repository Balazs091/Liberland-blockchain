// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title IGovernanceRouter
/// @notice Interface for validating governance-origin actions before timelock queuing.
interface IGovernanceRouter {
    error InvalidTargetModule(bytes32 targetModule);
    error SelfReplacementCancellationForbidden(bytes32 actionId, bytes32 targetModule);
    error UnauthorizedGovernanceOrigin(address caller);
    error UnsupportedActionType(GovernanceTypes.ActionType actionType);

    event GovernanceActionRouted(
        bytes32 indexed actionId,
        GovernanceTypes.ActionType indexed actionType,
        GovernanceTypes.ActionOrigin indexed origin,
        bytes32 targetModule
    );

    event GovernanceActionCancellationRouted(
        bytes32 indexed actionId, GovernanceTypes.ActionOrigin indexed origin, address indexed canceledBy
    );

    event OriginAuthorityConfigured(
        GovernanceTypes.ActionOrigin indexed origin, address indexed previousAuthority, address indexed authority
    );

    /// @notice Returns the kernel used for canonical module resolution.
    /// @return kernelAddress The kernel contract address.
    function kernel() external view returns (address kernelAddress);

    /// @notice Returns the timelock used for privileged action queueing.
    /// @return timelockAddress The timelock contract address.
    function timelock() external view returns (address timelockAddress);

    /// @notice Computes the deterministic action identifier for a request.
    /// @param request The governance action request.
    /// @return actionId The deterministic action identifier.
    function previewActionId(GovernanceTypes.ActionRequest calldata request) external view returns (bytes32 actionId);

    /// @notice Validates and routes a governance action into the timelock pipeline.
    /// @param request The governance action request.
    /// @return actionId The queued deterministic action identifier.
    function routeAction(GovernanceTypes.ActionRequest calldata request) external returns (bytes32 actionId);

    /// @notice Validates and routes cancellation of a queued action through the approved governance origin.
    /// @param actionId The queued deterministic action identifier.
    function cancelAction(bytes32 actionId) external;

    /// @notice Returns the configured authority for a governance origin.
    /// @param origin The governance origin to inspect.
    /// @return authority The currently configured authority address.
    function originAuthority(GovernanceTypes.ActionOrigin origin) external view returns (address authority);

    /// @notice Returns true when an action type is supported by the router.
    /// @param actionType The action type to check.
    /// @return supported Whether the action type is supported.
    function isActionTypeSupported(GovernanceTypes.ActionType actionType) external view returns (bool supported);
}
