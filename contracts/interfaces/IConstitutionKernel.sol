// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title IConstitutionKernel
/// @notice Canonical interface for governed module pointer storage.
interface IConstitutionKernel {
    error InvalidModuleAddress(bytes32 moduleId, address moduleAddress);
    error ModuleNotRegistered(bytes32 moduleId);
    error UnauthorizedKernelCaller(address caller);

    event ModuleRegistered(bytes32 indexed moduleId, address indexed moduleAddress, uint64 activatedAt);

    event ModuleReplaced(
        bytes32 indexed moduleId, address indexed previousModule, address indexed newModule, uint64 updatedAt
    );

    /// @notice Returns the canonical module address for a module identifier.
    /// @param moduleId The module identifier.
    /// @return moduleAddress The active module address.
    function getModule(bytes32 moduleId) external view returns (address moduleAddress);

    /// @notice Returns the temporary bootstrap authority, or zero once permanently disabled.
    /// @return authority The current bootstrap authority.
    function bootstrapAuthority() external view returns (address authority);

    /// @notice Returns the full module record for a module identifier.
    /// @param moduleId The module identifier.
    /// @return moduleRecord The stored module record.
    function getModuleRecord(bytes32 moduleId) external view returns (GovernanceTypes.ModuleRecord memory moduleRecord);

    /// @notice Returns true when an account is one of the active registered modules.
    /// @param account The account to check.
    /// @return authorized Whether the account is an authorized module.
    function isAuthorizedModule(address account) external view returns (bool authorized);

    /// @notice Registers or replaces multiple module pointers during bootstrap.
    /// @param moduleIds The module identifiers to register or replace.
    /// @param moduleAddresses The module implementation addresses to store.
    function bootstrapSetModules(bytes32[] calldata moduleIds, address[] calldata moduleAddresses) external;

    /// @notice Replaces the canonical pointer for an existing module through the governed execution path.
    /// @param moduleId The module identifier to update.
    /// @param moduleAddress The new active module address.
    function governanceUpdateModule(bytes32 moduleId, address moduleAddress) external;
}
