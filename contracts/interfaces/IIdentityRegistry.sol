// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IdentityTypes} from "../types/IdentityTypes.sol";

/// @title IIdentityRegistry
/// @notice Stable fact registry for person-level identity state and wallet links.
interface IIdentityRegistry {
    error InvalidPersonId(bytes32 personId);
    error InvalidWallet(address wallet);
    error InvalidWalletLinkStatus(IdentityTypes.WalletLinkStatus status);
    error UnauthorizedIdentityRegistryCaller(address caller);
    error WalletLinkPersonMismatch(address wallet, bytes32 expectedPersonId, bytes32 providedPersonId);
    error WalletLinkRequiresIdentity(bytes32 personId);

    event IdentityRecordUpdated(
        bytes32 indexed personId,
        bytes32 metadataHash,
        string metadataURI,
        IdentityTypes.VerificationStatus verificationStatus,
        IdentityTypes.CitizenshipStatus citizenshipStatus,
        IdentityTypes.AgeClass ageClass,
        bool correctionFlag,
        bool finalSuspension,
        uint64 updatedAt,
        address indexed updatedBy
    );

    event CitizenshipStatusUpdated(
        bytes32 indexed personId,
        IdentityTypes.CitizenshipStatus previousStatus,
        IdentityTypes.CitizenshipStatus newStatus,
        uint64 updatedAt,
        address indexed updatedBy
    );

    event WalletLinkUpdated(
        address indexed wallet,
        bytes32 indexed personId,
        IdentityTypes.WalletLinkStatus status,
        uint64 linkedAt,
        uint64 unlinkedAt,
        address indexed updatedBy
    );

    /// @notice Returns the kernel used for narrow write authorization.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress);

    /// @notice Returns the stored identity record for a person identifier.
    /// @param personId The canonical person identifier.
    /// @return record The stored identity record, or an empty record if unset.
    function getIdentityRecord(bytes32 personId) external view returns (IdentityTypes.IdentityRecord memory record);

    /// @notice Returns the stored wallet link for a wallet address.
    /// @param wallet The wallet to query.
    /// @return link The stored wallet link, or an empty link if unset.
    function getWalletLink(address wallet) external view returns (IdentityTypes.WalletLink memory link);

    /// @notice Resolves the canonical person identifier for a wallet.
    /// @param wallet The wallet to query.
    /// @return personId The linked person identifier, or zero if none exists.
    function resolveWalletToPersonId(address wallet) external view returns (bytes32 personId);

    /// @notice Returns the identity record associated with a wallet link.
    /// @param wallet The wallet to query.
    /// @return record The linked identity record, or an empty record if the wallet is not linked.
    function getWalletIdentityRecord(address wallet) external view returns (IdentityTypes.IdentityRecord memory record);

    /// @notice Returns true when a person identifier has a stored identity record.
    /// @param personId The canonical person identifier.
    /// @return exists Whether the record exists.
    function identityExists(bytes32 personId) external view returns (bool exists);

    /// @notice Returns the total number of person identifiers stored in the registry.
    /// @return count The number of stored identity records.
    function totalIdentityCount() external view returns (uint256 count);

    /// @notice Returns the person identifier stored at a sequential registry index.
    /// @param index The sequential identity index to query.
    /// @return personId The stored person identifier.
    function identityIdAt(uint256 index) external view returns (bytes32 personId);

    /// @notice Returns the number of active wallet links currently attached to a person identifier.
    /// @param personId The canonical person identifier.
    /// @return count The number of active wallet links.
    function activeWalletCountOf(bytes32 personId) external view returns (uint256 count);

    /// @notice Returns true when a wallet has an active link to a person identifier.
    /// @param wallet The wallet to query.
    /// @return linked Whether the wallet is actively linked.
    function hasActiveWalletLink(address wallet) external view returns (bool linked);

    /// @notice Creates or replaces the stored identity record for a person identifier.
    /// @param personId The canonical person identifier.
    /// @param recordInput The new identity fields to store.
    function setIdentityRecord(bytes32 personId, IdentityTypes.IdentityRecordInput calldata recordInput) external;

    /// @notice Updates the wallet link status for a person identifier.
    /// @param personId The canonical person identifier to link or revoke.
    /// @param wallet The wallet whose link should be updated.
    /// @param status The new wallet link status.
    function setWalletLink(bytes32 personId, address wallet, IdentityTypes.WalletLinkStatus status) external;
}
