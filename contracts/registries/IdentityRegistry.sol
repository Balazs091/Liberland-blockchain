// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {KernelModule} from "../base/KernelModule.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";

/// @title IdentityRegistry
/// @notice Stable fact registry for person identity status and wallet links.
contract IdentityRegistry is IIdentityRegistry, KernelModule {
    mapping(bytes32 personId => IdentityTypes.IdentityRecord identityRecord) private _identityRecords;
    mapping(address wallet => IdentityTypes.WalletLink walletLink) private _walletLinks;
    mapping(bytes32 personId => uint256 count) private _activeWalletCounts;
    bytes32[] private _identityIds;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IIdentityRegistry
    function getIdentityRecord(bytes32 personId) external view returns (IdentityTypes.IdentityRecord memory record) {
        return _identityRecords[personId];
    }

    /// @inheritdoc IIdentityRegistry
    function getCitizenshipSummary(bytes32 personId)
        external
        view
        returns (
            IdentityTypes.VerificationStatus verificationStatus,
            IdentityTypes.CitizenshipStatus citizenshipStatus,
            IdentityTypes.AgeClass ageClass,
            bool finalSuspension
        )
    {
        IdentityTypes.IdentityRecord storage record = _identityRecords[personId];
        return (record.verificationStatus, record.citizenshipStatus, record.ageClass, record.finalSuspension);
    }

    /// @inheritdoc IIdentityRegistry
    function getWalletLink(address wallet) external view returns (IdentityTypes.WalletLink memory link) {
        return _walletLinks[wallet];
    }

    /// @inheritdoc IIdentityRegistry
    function resolveWalletToPersonId(address wallet) external view returns (bytes32 personId) {
        return _walletLinks[wallet].personId;
    }

    /// @inheritdoc IIdentityRegistry
    function getWalletIdentityRecord(address wallet)
        external
        view
        returns (IdentityTypes.IdentityRecord memory record)
    {
        IdentityTypes.WalletLink storage walletLink = _walletLinks[wallet];
        return _identityRecords[walletLink.personId];
    }

    /// @inheritdoc IIdentityRegistry
    function identityExists(bytes32 personId) public view returns (bool exists) {
        return _identityRecords[personId].personId != bytes32(0);
    }

    /// @inheritdoc IIdentityRegistry
    function totalIdentityCount() external view returns (uint256 count) {
        return _identityIds.length;
    }

    /// @inheritdoc IIdentityRegistry
    function identityIdAt(uint256 index) external view returns (bytes32 personId) {
        return _identityIds[index];
    }

    /// @inheritdoc IIdentityRegistry
    function activeWalletCountOf(bytes32 personId) external view returns (uint256 count) {
        return _activeWalletCounts[personId];
    }

    /// @inheritdoc IIdentityRegistry
    function hasActiveWalletLink(address wallet) external view returns (bool linked) {
        IdentityTypes.WalletLink storage walletLink = _walletLinks[wallet];
        return walletLink.personId != bytes32(0) && walletLink.status == IdentityTypes.WalletLinkStatus.Active;
    }

    /// @inheritdoc IIdentityRegistry
    function setIdentityRecord(bytes32 personId, IdentityTypes.IdentityRecordInput calldata recordInput) external {
        _requireRegistryAuthority(msg.sender);

        if (personId == bytes32(0)) {
            revert InvalidPersonId(personId);
        }

        bool existed = identityExists(personId);
        IdentityTypes.CitizenshipStatus previousStatus = _identityRecords[personId].citizenshipStatus;
        uint64 updatedAt = uint64(block.timestamp);

        if (!existed) {
            _identityIds.push(personId);
        }

        _identityRecords[personId] = IdentityTypes.IdentityRecord({
            personId: personId,
            metadataHash: recordInput.metadataHash,
            metadataURI: recordInput.metadataURI,
            verificationStatus: recordInput.verificationStatus,
            citizenshipStatus: recordInput.citizenshipStatus,
            ageClass: recordInput.ageClass,
            correctionFlag: recordInput.correctionFlag,
            finalSuspension: recordInput.finalSuspension,
            updatedAt: updatedAt
        });

        emit IdentityRecordUpdated(
            personId,
            recordInput.metadataHash,
            recordInput.metadataURI,
            recordInput.verificationStatus,
            recordInput.citizenshipStatus,
            recordInput.ageClass,
            recordInput.correctionFlag,
            recordInput.finalSuspension,
            updatedAt,
            msg.sender
        );

        if (previousStatus != recordInput.citizenshipStatus) {
            emit CitizenshipStatusUpdated(
                personId, previousStatus, recordInput.citizenshipStatus, updatedAt, msg.sender
            );
        }
    }

    /// @inheritdoc IIdentityRegistry
    function setWalletLink(bytes32 personId, address wallet, IdentityTypes.WalletLinkStatus status) external {
        _requireRegistryAuthority(msg.sender);

        if (personId == bytes32(0)) {
            revert InvalidPersonId(personId);
        }
        if (wallet == address(0)) {
            revert InvalidWallet(wallet);
        }
        if (
            status != IdentityTypes.WalletLinkStatus.Pending && status != IdentityTypes.WalletLinkStatus.Active
                && status != IdentityTypes.WalletLinkStatus.Revoked
        ) {
            revert InvalidWalletLinkStatus(status);
        }

        IdentityTypes.WalletLink storage walletLink = _walletLinks[wallet];
        bytes32 currentPersonId = walletLink.personId;
        IdentityTypes.WalletLinkStatus previousStatus = walletLink.status;
        uint64 currentTimestamp = uint64(block.timestamp);

        if (status == IdentityTypes.WalletLinkStatus.Revoked) {
            if (currentPersonId == bytes32(0) || currentPersonId != personId) {
                revert WalletLinkPersonMismatch(wallet, currentPersonId, personId);
            }

            if (previousStatus == IdentityTypes.WalletLinkStatus.Active) {
                _activeWalletCounts[currentPersonId] -= 1;
            }

            walletLink.wallet = wallet;
            walletLink.status = status;
            walletLink.unlinkedAt = currentTimestamp;

            emit WalletLinkUpdated(wallet, personId, status, walletLink.linkedAt, walletLink.unlinkedAt, msg.sender);
            return;
        }

        if (!identityExists(personId)) {
            revert WalletLinkRequiresIdentity(personId);
        }

        if (
            currentPersonId != bytes32(0) && currentPersonId != personId
                && previousStatus != IdentityTypes.WalletLinkStatus.Revoked
        ) {
            revert WalletLinkPersonMismatch(wallet, currentPersonId, personId);
        }

        walletLink.wallet = wallet;
        walletLink.personId = personId;
        walletLink.status = status;
        walletLink.linkedAt = previousStatus == IdentityTypes.WalletLinkStatus.Revoked || walletLink.linkedAt == 0
            ? currentTimestamp
            : walletLink.linkedAt;
        walletLink.unlinkedAt = 0;

        if (
            previousStatus == IdentityTypes.WalletLinkStatus.Active
                && (status != IdentityTypes.WalletLinkStatus.Active || currentPersonId != personId)
        ) {
            _activeWalletCounts[currentPersonId] -= 1;
        }
        if (
            status == IdentityTypes.WalletLinkStatus.Active
                && (previousStatus != IdentityTypes.WalletLinkStatus.Active || currentPersonId != personId)
        ) {
            // One active wallet per person (H2): a person may only hold a single active wallet at a
            // time. Migration stays possible by revoking the prior wallet first (count returns to 0).
            if (_activeWalletCounts[personId] != 0) {
                revert PersonAlreadyHasActiveWallet(personId);
            }
            _activeWalletCounts[personId] += 1;
        }

        emit WalletLinkUpdated(wallet, personId, status, walletLink.linkedAt, walletLink.unlinkedAt, msg.sender);
    }

    function _requireRegistryAuthority(address caller) private view {
        // L7: resolve the primary authority through the same try/catch used for the setup-authority fallback so
        // that an unregistered IDENTITY_REGISTRY_AUTHORITY does not brick every write (including the fallback).
        if (_isModuleCaller(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, caller)) {
            return;
        }
        if (_isActiveSetupAuthority(caller)) {
            return;
        }

        revert UnauthorizedIdentityRegistryCaller(caller);
    }
}
