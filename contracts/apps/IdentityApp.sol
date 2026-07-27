// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IIdentityApp} from "../interfaces/IIdentityApp.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title IdentityApp
/// @notice Standing governed identity authority. Registered as the kernel identity-registry authority, it is the
///         only live mutator of the identity registry after genesis: it drives the office-gated citizenship
///         lifecycle, honors caller-initiated citizenship renunciation, and executes timelocked, office-approved
///         single-active-wallet migrations that keep person-keyed stake intact.
contract IdentityApp is IIdentityApp {
    IIdentityRegistry private immutable _identityRegistry;
    IOfficeRegistry private immutable _officeRegistry;
    address private immutable _kernel;
    bytes32 private immutable _identityOfficeId;
    uint64 private immutable _migrationDelay;

    mapping(bytes32 personId => IdentityTypes.MigrationRequest migration) private _migrations;

    /// @param identityRegistryAddress The identity registry mutated as the standing authority.
    /// @param officeRegistryAddress The office registry used to resolve identity-office roles.
    /// @param identityOfficeId_ The identity office identifier gating management and migration approval.
    /// @param migrationDelaySeconds The post-approval timelock applied before a wallet migration can finalize.
    constructor(
        address identityRegistryAddress,
        address officeRegistryAddress,
        bytes32 identityOfficeId_,
        uint64 migrationDelaySeconds
    ) {
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidIdentityRegistry(identityRegistryAddress);
        }
        if (officeRegistryAddress == address(0) || officeRegistryAddress.code.length == 0) {
            revert InvalidOfficeRegistry(officeRegistryAddress);
        }

        address identityKernel = IIdentityRegistry(identityRegistryAddress).kernel();
        address officeKernel = IOfficeRegistry(officeRegistryAddress).kernel();
        if (identityKernel != officeKernel) {
            revert KernelMismatch(identityKernel, officeKernel);
        }
        if (identityOfficeId_ == bytes32(0)) {
            revert InvalidIdentityOffice(identityOfficeId_);
        }
        if (migrationDelaySeconds == 0) {
            revert InvalidMigrationDelay(migrationDelaySeconds);
        }

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _officeRegistry = IOfficeRegistry(officeRegistryAddress);
        _kernel = identityKernel;
        _identityOfficeId = identityOfficeId_;
        _migrationDelay = migrationDelaySeconds;
    }

    /// @inheritdoc IIdentityApp
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc IIdentityApp
    function officeRegistry() external view returns (address registryAddress) {
        return address(_officeRegistry);
    }

    /// @inheritdoc IIdentityApp
    function kernel() external view returns (address kernelAddress) {
        return _kernel;
    }

    /// @inheritdoc IIdentityApp
    function identityOfficeId() external view returns (bytes32 officeId) {
        return _identityOfficeId;
    }

    /// @inheritdoc IIdentityApp
    function migrationDelay() external view returns (uint64 delaySeconds) {
        return _migrationDelay;
    }

    /// @inheritdoc IIdentityApp
    function getWalletMigration(bytes32 personId)
        external
        view
        returns (IdentityTypes.MigrationRequest memory request)
    {
        return _migrations[personId];
    }

    /// @inheritdoc IIdentityApp
    function registerIdentity(bytes32 personId, IdentityTypes.IdentityRecordInput calldata input) external {
        _requireIdentityOfficeAdmin(msg.sender);
        _identityRegistry.setIdentityRecord(personId, input);
    }

    /// @inheritdoc IIdentityApp
    function linkWallet(bytes32 personId, address wallet, IdentityTypes.WalletLinkStatus status) external {
        _requireIdentityOfficeAdmin(msg.sender);
        _identityRegistry.setWalletLink(personId, wallet, status);
    }

    /// @inheritdoc IIdentityApp
    function setCitizenship(bytes32 personId, IdentityTypes.CitizenshipStatus status) external {
        _requireIdentityOfficeAdmin(msg.sender);

        IdentityTypes.IdentityRecord memory record = _identityRegistry.getIdentityRecord(personId);
        _identityRegistry.setIdentityRecord(personId, _rewriteCitizenship(record, status));
    }

    /// @inheritdoc IIdentityApp
    function renounceCitizenship() external {
        bytes32 personId = _identityRegistry.resolveWalletToPersonId(msg.sender);
        IdentityTypes.IdentityRecord memory record = _identityRegistry.getIdentityRecord(personId);
        if (
            personId == bytes32(0) || !_identityRegistry.hasActiveWalletLink(msg.sender)
                || record.citizenshipStatus != IdentityTypes.CitizenshipStatus.Citizen
        ) {
            revert NotRenounceableCitizen(msg.sender, personId);
        }

        // Preserve every other field; do not revoke the wallet link so the person can still unstake their LLM.
        _identityRegistry.setIdentityRecord(personId, _rewriteCitizenship(record, IdentityTypes.CitizenshipStatus.None));

        emit CitizenshipRenounced(personId, msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc IIdentityApp
    function requestWalletMigration(address newWallet) external {
        bytes32 personId = _requireActiveWallet(msg.sender);
        if (newWallet == address(0) || newWallet == msg.sender) {
            revert InvalidNewWallet(newWallet);
        }
        _requireWalletUnlinked(newWallet);
        if (_migrations[personId].exists) {
            revert MigrationAlreadyPending(personId);
        }

        uint64 requestedAt = uint64(block.timestamp);
        _migrations[personId] = IdentityTypes.MigrationRequest({
            oldWallet: msg.sender,
            newWallet: newWallet,
            requestedAt: requestedAt,
            approvedAt: 0,
            approved: false,
            exists: true
        });

        emit WalletMigrationRequested(personId, msg.sender, newWallet, requestedAt);
    }

    /// @inheritdoc IIdentityApp
    function approveWalletMigration(bytes32 personId) external {
        _requireIdentityOfficer(msg.sender);

        IdentityTypes.MigrationRequest storage migration = _migrations[personId];
        if (!migration.exists) {
            revert MigrationNotFound(personId);
        }
        if (migration.approved) {
            revert MigrationAlreadyApproved(personId);
        }

        uint64 approvedAt = uint64(block.timestamp);
        migration.approved = true;
        migration.approvedAt = approvedAt;

        emit WalletMigrationApproved(personId, msg.sender, approvedAt);
    }

    /// @inheritdoc IIdentityApp
    function finalizeWalletMigration(bytes32 personId) external {
        IdentityTypes.MigrationRequest memory migration = _migrations[personId];
        if (!migration.exists) {
            revert MigrationNotFound(personId);
        }
        if (!migration.approved) {
            revert MigrationNotApproved(personId);
        }

        uint64 readyAt = migration.approvedAt + _migrationDelay;
        if (block.timestamp < readyAt) {
            revert MigrationDelayNotElapsed(personId, readyAt);
        }

        // Re-validate the swap is still safe at execution time.
        if (
            _identityRegistry.resolveWalletToPersonId(migration.oldWallet) != personId
                || !_identityRegistry.hasActiveWalletLink(migration.oldWallet)
        ) {
            revert MigrationOldWalletInactive(personId, migration.oldWallet);
        }
        _requireWalletUnlinked(migration.newWallet);

        delete _migrations[personId];

        // Revoke first so the person's active-wallet count returns to zero, then activate the new wallet. The
        // one-active-wallet invariant in the registry passes precisely because of this ordering, and staked LLM
        // stays with personId (never touched here).
        _identityRegistry.setWalletLink(personId, migration.oldWallet, IdentityTypes.WalletLinkStatus.Revoked);
        _identityRegistry.setWalletLink(personId, migration.newWallet, IdentityTypes.WalletLinkStatus.Active);

        emit WalletMigrationFinalized(personId, migration.oldWallet, migration.newWallet, uint64(block.timestamp));
    }

    /// @inheritdoc IIdentityApp
    function cancelWalletMigration(bytes32 personId) external {
        IdentityTypes.MigrationRequest memory migration = _migrations[personId];
        if (!migration.exists) {
            revert MigrationNotFound(personId);
        }
        if (
            msg.sender != migration.oldWallet
                && _officeRegistry.roleOf(_identityOfficeId, msg.sender) == OfficeTypes.OfficeRole.None
        ) {
            revert UnauthorizedMigrationCanceller(msg.sender, personId);
        }

        delete _migrations[personId];

        emit WalletMigrationCancelled(personId, msg.sender, uint64(block.timestamp));
    }

    function _rewriteCitizenship(IdentityTypes.IdentityRecord memory record, IdentityTypes.CitizenshipStatus status)
        private
        pure
        returns (IdentityTypes.IdentityRecordInput memory input)
    {
        input = IdentityTypes.IdentityRecordInput({
            metadataHash: record.metadataHash,
            metadataURI: record.metadataURI,
            verificationStatus: record.verificationStatus,
            citizenshipStatus: status,
            ageClass: record.ageClass,
            correctionFlag: record.correctionFlag,
            finalSuspension: record.finalSuspension
        });
    }

    function _requireActiveWallet(address wallet) private view returns (bytes32 personId) {
        personId = _identityRegistry.resolveWalletToPersonId(wallet);
        if (personId == bytes32(0) || !_identityRegistry.hasActiveWalletLink(wallet)) {
            revert WalletNotLinked(wallet);
        }
    }

    function _requireWalletUnlinked(address wallet) private view {
        IdentityTypes.WalletLink memory walletLink = _identityRegistry.getWalletLink(wallet);
        if (walletLink.personId != bytes32(0) && walletLink.status != IdentityTypes.WalletLinkStatus.Revoked) {
            revert NewWalletAlreadyLinked(wallet, walletLink.personId);
        }
    }

    function _requireIdentityOfficeAdmin(address caller) private view {
        if (_officeRegistry.roleOf(_identityOfficeId, caller) != OfficeTypes.OfficeRole.Admin) {
            revert UnauthorizedIdentityOfficer(caller, _identityOfficeId);
        }
    }

    function _requireIdentityOfficer(address caller) private view {
        OfficeTypes.OfficeRole role = _officeRegistry.roleOf(_identityOfficeId, caller);
        if (role != OfficeTypes.OfficeRole.Admin && role != OfficeTypes.OfficeRole.Clerk) {
            revert UnauthorizedIdentityOfficer(caller, _identityOfficeId);
        }
    }
}
