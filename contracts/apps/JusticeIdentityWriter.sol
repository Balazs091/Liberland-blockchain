// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {KernelModule} from "../base/KernelModule.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IJusticeIdentityWriter} from "../interfaces/IJusticeIdentityWriter.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";

/// @title JusticeIdentityWriter
/// @notice Sole typed identity writer when installed as the canonical registry authority.
/// @dev The current JusticeApp decides legal cases and binds exact effects to source revisions. This contract
///      independently checks registry ownership, permissible transitions and current wallet invariants.
contract JusticeIdentityWriter is IJusticeIdentityWriter, KernelModule {
    IIdentityRegistry private immutable _identityRegistry;
    mapping(bytes32 personId => WalletMigrationRequest request) private _walletMigrations;

    /// @param identityRegistryAddress Canonical identity registry that the writer is designed to serve.
    constructor(address identityRegistryAddress) KernelModule(_identityKernel(identityRegistryAddress)) {
        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function executeAdmission(bytes32 personId, address wallet, bytes32 evidenceHash, IdentityTypes.AgeClass ageClass)
        external
    {
        _requireJusticeAuthority();
        if (personId == bytes32(0)) revert InvalidPersonId();
        if (evidenceHash == bytes32(0)) revert InvalidAdmissionEvidence();
        if (ageClass == IdentityTypes.AgeClass.Undefined) revert UndefinedAdmissionAge();
        if (wallet == address(0)) revert InvalidDestinationWallet(wallet);

        IdentityTypes.IdentityRecord memory record = _identityRegistry.getIdentityRecord(personId);
        if (
            record.personId != bytes32(0)
                && (record.finalSuspension
                    || (record.citizenshipStatus != IdentityTypes.CitizenshipStatus.None
                        && record.citizenshipStatus != IdentityTypes.CitizenshipStatus.EResident))
        ) revert IdentityCannotBeAdmitted(personId);

        address activeWallet = _identityRegistry.activeWalletOf(personId);
        if (activeWallet == address(0)) {
            _requireUnusedWallet(wallet);
        } else if (wallet != activeWallet) {
            revert ActiveWalletChanged(personId, wallet, activeWallet);
        }

        IdentityTypes.IdentityRecordInput memory input =
            _withCitizenship(record, IdentityTypes.CitizenshipStatus.Citizen);
        if (record.personId == bytes32(0)) input.metadataHash = evidenceHash;
        input.verificationStatus = IdentityTypes.VerificationStatus.Verified;
        input.ageClass = ageClass;
        _identityRegistry.setIdentityRecord(personId, input);
        if (activeWallet == address(0)) {
            _identityRegistry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        }
        emit CitizenshipAdmitted(personId, wallet, evidenceHash);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function executeAnnulment(bytes32 personId) external {
        _requireJusticeAuthority();
        _changeCitizenStatus(personId, IdentityTypes.CitizenshipStatus.Revoked);
        emit CitizenshipAnnulled(personId);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function executeCitizenshipRestoration(bytes32 personId) external {
        _requireJusticeAuthority();
        IdentityTypes.IdentityRecord memory record = _identityRegistry.getIdentityRecord(personId);
        if (record.citizenshipStatus != IdentityTypes.CitizenshipStatus.Revoked) revert IdentityNotRevoked(personId);
        _identityRegistry.setIdentityRecord(personId, _withCitizenship(record, IdentityTypes.CitizenshipStatus.Citizen));
        emit CitizenshipRestored(personId);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function executeAdulthood(bytes32 personId) external {
        _requireJusticeAuthority();
        IdentityTypes.IdentityRecord memory record = _identityRegistry.getIdentityRecord(personId);
        if (
            record.personId == bytes32(0) || record.verificationStatus != IdentityTypes.VerificationStatus.Verified
                || record.ageClass != IdentityTypes.AgeClass.Minor
                || (record.citizenshipStatus != IdentityTypes.CitizenshipStatus.Citizen
                    && record.citizenshipStatus != IdentityTypes.CitizenshipStatus.EResident)
        ) revert IdentityCannotRecognizeAdulthood(personId);
        IdentityTypes.IdentityRecordInput memory input = _withCitizenship(record, record.citizenshipStatus);
        input.ageClass = IdentityTypes.AgeClass.Adult;
        _identityRegistry.setIdentityRecord(personId, input);
        emit AdulthoodRecognized(personId);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function executeRecovery(bytes32 personId, address expectedOld, address newWallet) external {
        _requireJusticeAuthority();
        _replaceWallet(personId, expectedOld, newWallet);
        emit WalletRecovered(personId, expectedOld, newWallet);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function renounceCitizenship() external {
        _requireCurrentAuthority();
        bytes32 personId = _requireActivePerson(msg.sender);
        _changeCitizenStatus(personId, IdentityTypes.CitizenshipStatus.None);
        emit CitizenshipRenounced(personId, msg.sender);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function requestWalletMigration(address newWallet, uint64 expiresAt) external returns (bytes32 requestId) {
        _requireCurrentAuthority();
        bytes32 personId = _requireActivePerson(msg.sender);
        _requireUnusedWallet(newWallet);
        if (block.timestamp >= expiresAt) revert WalletMigrationExpired(expiresAt);

        uint256 nonce = _walletMigrations[personId].nonce + 1;
        WalletMigrationRequest memory request =
            WalletMigrationRequest({oldWallet: msg.sender, expiresAt: expiresAt, newWallet: newWallet, nonce: nonce});
        _walletMigrations[personId] = request;
        requestId = _migrationId(personId, request);
        emit WalletMigrationRequested(personId, requestId, msg.sender, newWallet, expiresAt);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function getWalletMigration(bytes32 personId)
        external
        view
        returns (WalletMigrationRequest memory request, bytes32 requestId)
    {
        request = _walletMigrations[personId];
        if (request.oldWallet != address(0)) requestId = _migrationId(personId, request);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function acceptWalletMigration(bytes32 personId, bytes32 requestId) external {
        _requireCurrentAuthority();
        WalletMigrationRequest memory request = _requireMigration(personId, requestId);
        if (msg.sender != request.newWallet) revert WalletMigrationDestinationOnly(msg.sender, request.newWallet);
        if (block.timestamp >= request.expiresAt) revert WalletMigrationExpired(request.expiresAt);

        _replaceWallet(personId, request.oldWallet, request.newWallet);
        emit WalletMigrationExecuted(personId, requestId, request.oldWallet, request.newWallet);
    }

    /// @inheritdoc IJusticeIdentityWriter
    function cancelWalletMigration(bytes32 personId, bytes32 requestId) external {
        _requireCurrentAuthority();
        WalletMigrationRequest memory request = _requireMigration(personId, requestId);
        if (msg.sender != request.oldWallet) revert WalletMigrationSourceOnly(msg.sender, request.oldWallet);
        _requireExpectedWallet(personId, request.oldWallet);
        _clearMigration(personId);
        emit WalletMigrationCancelled(personId, requestId);
    }

    function _replaceWallet(bytes32 personId, address expectedOld, address newWallet) private {
        _requireExpectedWallet(personId, expectedOld);
        _requireUnusedWallet(newWallet);

        if (_walletMigrations[personId].oldWallet != address(0)) _clearMigration(personId);
        _identityRegistry.setWalletLink(personId, expectedOld, IdentityTypes.WalletLinkStatus.Revoked);
        _identityRegistry.setWalletLink(personId, newWallet, IdentityTypes.WalletLinkStatus.Active);
    }

    function _requireUnusedWallet(address wallet) private view {
        if (wallet == address(0)) revert InvalidDestinationWallet(wallet);
        if (_identityRegistry.resolveWalletToPersonId(wallet) != bytes32(0)) {
            revert DestinationWalletAlreadyLinked(wallet);
        }
    }

    function _requireExpectedWallet(bytes32 personId, address expectedOld) private view {
        address actual = _identityRegistry.activeWalletOf(personId);
        if (expectedOld == address(0) || actual != expectedOld) {
            revert ActiveWalletChanged(personId, expectedOld, actual);
        }
    }

    function _requireActivePerson(address wallet) private view returns (bytes32 personId) {
        personId = _identityRegistry.resolveWalletToPersonId(wallet);
        if (personId == bytes32(0) || _identityRegistry.activeWalletOf(personId) != wallet) {
            revert InactiveWallet(wallet);
        }
    }

    function _requireMigration(bytes32 personId, bytes32 requestId)
        private
        view
        returns (WalletMigrationRequest memory request)
    {
        request = _walletMigrations[personId];
        if (request.oldWallet == address(0) || _migrationId(personId, request) != requestId) {
            revert InvalidWalletMigrationRequest(personId, requestId);
        }
    }

    function _migrationId(bytes32 personId, WalletMigrationRequest memory request) private view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), personId, request));
    }

    function _clearMigration(bytes32 personId) private {
        WalletMigrationRequest storage request = _walletMigrations[personId];
        delete request.oldWallet;
        delete request.expiresAt;
        delete request.newWallet;
    }

    function _changeCitizenStatus(bytes32 personId, IdentityTypes.CitizenshipStatus newStatus) private {
        IdentityTypes.IdentityRecord memory record = _identityRegistry.getIdentityRecord(personId);
        if (record.citizenshipStatus != IdentityTypes.CitizenshipStatus.Citizen) revert IdentityNotCitizen(personId);
        _identityRegistry.setIdentityRecord(personId, _withCitizenship(record, newStatus));
    }

    function _withCitizenship(IdentityTypes.IdentityRecord memory record, IdentityTypes.CitizenshipStatus status)
        private
        pure
        returns (IdentityTypes.IdentityRecordInput memory)
    {
        return IdentityTypes.IdentityRecordInput({
            metadataHash: record.metadataHash,
            metadataURI: record.metadataURI,
            verificationStatus: record.verificationStatus,
            citizenshipStatus: status,
            ageClass: record.ageClass,
            correctionFlag: record.correctionFlag,
            finalSuspension: record.finalSuspension
        });
    }

    function _requireJusticeAuthority() private view {
        if (!_isModuleCaller(KernelModuleIds.JUSTICE_APP, msg.sender)) revert UnauthorizedJusticeApp(msg.sender);
        _requireCurrentAuthority();
    }

    function _requireCurrentAuthority() private view {
        if (!_isModuleCaller(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this))) {
            revert IdentityWriterNotCurrent(address(this));
        }
        if (!_isModuleCaller(KernelModuleIds.IDENTITY_REGISTRY, address(_identityRegistry))) {
            revert IdentityRegistryNotCurrent(address(_identityRegistry));
        }
    }

    function _identityKernel(address identityRegistryAddress) private view returns (address) {
        if (identityRegistryAddress.code.length == 0) revert InvalidIdentityRegistry(identityRegistryAddress);
        return IIdentityRegistry(identityRegistryAddress).kernel();
    }
}
