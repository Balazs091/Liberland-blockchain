// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IdentityTypes} from "../types/IdentityTypes.sol";

/// @title IIdentityApp
/// @notice Standing governed identity authority: office-gated citizenship lifecycle, caller-initiated
///         citizenship renunciation, and timelocked, office-approved single-wallet migration.
interface IIdentityApp {
    error InvalidIdentityRegistry(address registryAddress);
    error InvalidOfficeRegistry(address registryAddress);
    error KernelMismatch(address identityKernel, address officeKernel);
    error InvalidIdentityOffice(bytes32 officeId);
    error InvalidMigrationDelay(uint64 migrationDelaySeconds);
    error UnauthorizedIdentityOfficer(address caller, bytes32 officeId);
    error NotRenounceableCitizen(address caller, bytes32 personId);
    error WalletNotLinked(address wallet);
    error InvalidNewWallet(address newWallet);
    error NewWalletAlreadyLinked(address newWallet, bytes32 personId);
    error MigrationAlreadyPending(bytes32 personId);
    error MigrationNotFound(bytes32 personId);
    error MigrationAlreadyApproved(bytes32 personId);
    error MigrationNotApproved(bytes32 personId);
    error MigrationDelayNotElapsed(bytes32 personId, uint64 readyAt);
    error MigrationOldWalletInactive(bytes32 personId, address oldWallet);
    error UnauthorizedMigrationCanceller(address caller, bytes32 personId);

    event CitizenshipRenounced(bytes32 indexed personId, address indexed wallet, uint64 timestamp);

    event WalletMigrationRequested(
        bytes32 indexed personId, address indexed oldWallet, address indexed newWallet, uint64 requestedAt
    );

    event WalletMigrationApproved(bytes32 indexed personId, address indexed approvedBy, uint64 approvedAt);

    event WalletMigrationFinalized(
        bytes32 indexed personId, address indexed oldWallet, address indexed newWallet, uint64 timestamp
    );

    event WalletMigrationCancelled(bytes32 indexed personId, address indexed cancelledBy, uint64 timestamp);

    /// @notice Returns the identity registry this app mutates as the standing authority.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the office registry used to resolve identity-office roles.
    /// @return registryAddress The office registry address.
    function officeRegistry() external view returns (address registryAddress);

    /// @notice Returns the kernel shared by the identity and office registries.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress);

    /// @notice Returns the pinned identity office identifier gating management actions.
    /// @return officeId The identity office identifier.
    function identityOfficeId() external view returns (bytes32 officeId);

    /// @notice Returns the post-approval timelock delay applied before a wallet migration can finalize.
    /// @return delaySeconds The migration delay in seconds.
    function migrationDelay() external view returns (uint64 delaySeconds);

    /// @notice Creates or replaces the identity record for a person. Identity-office admin only.
    /// @param personId The canonical person identifier.
    /// @param input The identity fields to store.
    function registerIdentity(bytes32 personId, IdentityTypes.IdentityRecordInput calldata input) external;

    /// @notice Sets a wallet link status for a person. Identity-office admin only.
    /// @param personId The canonical person identifier.
    /// @param wallet The wallet whose link is updated.
    /// @param status The new wallet link status.
    function linkWallet(bytes32 personId, address wallet, IdentityTypes.WalletLinkStatus status) external;

    /// @notice Updates only the citizenship status for a person, preserving all other identity fields. Admin only.
    /// @param personId The canonical person identifier.
    /// @param status The new citizenship status.
    function setCitizenship(bytes32 personId, IdentityTypes.CitizenshipStatus status) external;

    /// @notice Renounces the caller's own citizenship (Art IV §2.3). The office cannot block this.
    /// @dev Resolves the caller to a person with an active wallet link and current Citizen status, then sets
    ///      citizenship to None while preserving all other fields and leaving the wallet link intact.
    function renounceCitizenship() external;

    /// @notice Requests migration of the caller's single active wallet to a new, currently-unlinked wallet.
    /// @param newWallet The wallet to migrate to once approved and the timelock elapses.
    function requestWalletMigration(address newWallet) external;

    /// @notice Approves a pending wallet migration, starting the finalization timelock. Identity-office admin or clerk.
    /// @param personId The person identifier whose migration is approved.
    function approveWalletMigration(bytes32 personId) external;

    /// @notice Finalizes an approved wallet migration after the timelock elapses. Callable by anyone.
    /// @param personId The person identifier whose migration is finalized.
    function finalizeWalletMigration(bytes32 personId) external;

    /// @notice Cancels a pending wallet migration. Callable by the recorded old wallet or an identity officer.
    /// @param personId The person identifier whose migration is cancelled.
    function cancelWalletMigration(bytes32 personId) external;

    /// @notice Returns the pending migration request for a person, if any.
    /// @param personId The canonical person identifier.
    /// @return request The stored migration request, or an empty request when none is pending.
    function getWalletMigration(bytes32 personId) external view returns (IdentityTypes.MigrationRequest memory request);
}
