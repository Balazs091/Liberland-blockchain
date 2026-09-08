// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IIdentityApp} from "../interfaces/IIdentityApp.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ICivicAppealReview} from "../interfaces/ICivicAppealReview.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title IdentityApp
/// @notice Standing governed identity authority. Registered as the kernel identity-registry authority, it is the
///         only live mutator of the identity registry after genesis: it drives the office-gated citizenship
///         lifecycle, honors caller-initiated citizenship renunciation, and executes timelocked, office-approved
///         single-active-wallet migrations that keep person-keyed stake intact.
contract IdentityApp is IIdentityApp {
    /// @notice Minimum public challenge/notice period for exceptional recovery and civic changes.
    uint64 public constant EXCEPTIONAL_DELAY = 7 days;
    /// @notice Maximum review window after an appeal is filed; silence dismisses the request.
    uint64 public constant APPEAL_REVIEW_PERIOD = 30 days;
    /// @notice Public delay between an upheld appeal ruling and execution.
    uint64 public constant APPEAL_EXECUTION_DELAY = 2 days;
    IIdentityRegistry private immutable _identityRegistry;
    IOfficeRegistry private immutable _officeRegistry;
    address private immutable _kernel;
    bytes32 private immutable _identityOfficeId;
    uint64 private immutable _migrationDelay;

    mapping(bytes32 personId => IdentityTypes.MigrationRequest migration) private _migrations;
    mapping(bytes32 personId => uint256 nonce) private _requestNonces;
    mapping(bytes32 personId => bool enabled) private _onboarding;
    mapping(bytes32 personId => bool available) private _initialCitizenshipGrantAvailable;
    mapping(bytes32 personId => address wallet) private _initialWallets;
    mapping(bytes32 personId => IdentityTypes.CivicChangeRequest request) private _civicChanges;

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
        if (_identityRegistry.getIdentityRecord(personId).personId != bytes32(0)) {
            revert IdentityAlreadyRegistered(personId);
        }
        if (
            input.finalSuspension
                || (input.citizenshipStatus != IdentityTypes.CitizenshipStatus.None
                    && input.citizenshipStatus != IdentityTypes.CitizenshipStatus.EResident)
        ) {
            revert UseCivicChangeProcedure(personId);
        }
        _onboarding[personId] = true;
        _initialCitizenshipGrantAvailable[personId] = true;
        _identityRegistry.setIdentityRecord(personId, input);
    }

    /// @inheritdoc IIdentityApp
    function linkWallet(bytes32 personId, address wallet, IdentityTypes.WalletLinkStatus status) external {
        _requireIdentityOfficeAdmin(msg.sender);
        if (
            !_onboarding[personId] || _initialWallets[personId] != address(0)
                || _identityRegistry.activeWalletOf(personId) != address(0)
                || status != IdentityTypes.WalletLinkStatus.Active
        ) {
            revert InitialWalletOnly(personId);
        }
        if (wallet == address(0)) revert InvalidNewWallet(wallet);
        _requireWalletUnlinked(wallet);
        _initialWallets[personId] = wallet;
        emit InitialWalletProposed(personId, wallet);
    }

    /// @inheritdoc IIdentityApp
    function acceptInitialWallet(bytes32 personId) external {
        if (!_onboarding[personId] || _initialWallets[personId] != msg.sender) {
            revert DestinationConsentRequired(personId);
        }
        _requireWalletUnlinked(msg.sender);
        delete _onboarding[personId];
        delete _initialWallets[personId];
        _identityRegistry.setWalletLink(personId, msg.sender, IdentityTypes.WalletLinkStatus.Active);
        emit InitialWalletAccepted(personId, msg.sender);
    }

    /// @inheritdoc IIdentityApp
    function correctMetadata(bytes32 personId, bytes32 metadataHash, string calldata metadataURI) external {
        _requireIdentityOfficeAdmin(msg.sender);
        IdentityTypes.IdentityRecord memory record = _requireRecord(personId);
        IdentityTypes.IdentityRecordInput memory input = _rewriteCitizenship(record, record.citizenshipStatus);
        input.metadataHash = metadataHash;
        input.metadataURI = metadataURI;
        _identityRegistry.setIdentityRecord(personId, input);
    }

    /// @inheritdoc IIdentityApp
    function setCitizenship(bytes32 personId, IdentityTypes.CitizenshipStatus status) external {
        _requireIdentityOfficeAdmin(msg.sender);

        IdentityTypes.IdentityRecord memory record = _requireRecord(personId);
        if (
            status != IdentityTypes.CitizenshipStatus.Citizen || record.finalSuspension
                || !_initialCitizenshipGrantAvailable[personId]
                || record.verificationStatus != IdentityTypes.VerificationStatus.Verified
                || record.ageClass != IdentityTypes.AgeClass.Adult
                || (record.citizenshipStatus != IdentityTypes.CitizenshipStatus.None
                    && record.citizenshipStatus != IdentityTypes.CitizenshipStatus.EResident)
        ) {
            revert UseCivicChangeProcedure(personId);
        }
        if (_civicChanges[personId].requestId != bytes32(0)) revert CivicChangePending(personId);
        delete _initialCitizenshipGrantAvailable[personId];
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
        delete _initialCitizenshipGrantAvailable[personId];
        if (_civicChanges[personId].requestId != bytes32(0)) _cancelCivicChange(personId);
        _identityRegistry.setIdentityRecord(personId, _rewriteCitizenship(record, IdentityTypes.CitizenshipStatus.None));

        emit CitizenshipRenounced(personId, msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc IIdentityApp
    function requestWalletMigration(address newWallet) external {
        bytes32 personId = _requireActiveWallet(msg.sender);
        _requestMigration(personId, msg.sender, newWallet, false, bytes32(0));
    }

    /// @inheritdoc IIdentityApp
    function proposeWalletRecovery(bytes32 personId, address newWallet, bytes32 evidenceHash) external {
        _requireIdentityOfficeAdmin(msg.sender);
        if (evidenceHash == bytes32(0)) revert InvalidEvidenceHash();
        _requireRecord(personId);
        _requestMigration(personId, _identityRegistry.activeWalletOf(personId), newWallet, true, evidenceHash);
    }

    function _requestMigration(
        bytes32 personId,
        address oldWallet,
        address newWallet,
        bool recovery,
        bytes32 evidenceHash
    ) private {
        if (newWallet == address(0) || newWallet == oldWallet) {
            revert InvalidNewWallet(newWallet);
        }
        _requireWalletUnlinked(newWallet);
        if (_migrations[personId].exists) {
            revert MigrationAlreadyPending(personId);
        }

        uint64 requestedAt = uint64(block.timestamp);
        _migrations[personId] = IdentityTypes.MigrationRequest({
            oldWallet: oldWallet,
            newWallet: newWallet,
            requestedAt: requestedAt,
            approvedAt: 0,
            approved: false,
            exists: true,
            nonce: ++_requestNonces[personId],
            accepted: false,
            recovery: recovery,
            proposer: msg.sender,
            approver: address(0),
            evidenceHash: evidenceHash,
            proposerAuthorizationId: recovery
                ? _officeRegistry.authorizationId(_identityOfficeId, msg.sender)
                : bytes32(0),
            approverAuthorizationId: bytes32(0)
        });

        emit WalletMigrationRequested(personId, oldWallet, newWallet, requestedAt);
        emit MigrationProposalBound(
            personId, walletMigrationId(personId), _requestNonces[personId], recovery, evidenceHash
        );
    }

    /// @inheritdoc IIdentityApp
    function walletMigrationId(bytes32 personId) public view returns (bytes32 requestId) {
        IdentityTypes.MigrationRequest storage m = _migrations[personId];
        if (!m.exists) return bytes32(0);
        return keccak256(
            abi.encode(
                block.chainid, address(this), personId, m.oldWallet, m.newWallet, m.nonce, m.recovery, m.evidenceHash
            )
        );
    }

    /// @inheritdoc IIdentityApp
    function acceptWalletMigration(bytes32 personId, bytes32 requestId) external {
        _requireMigrationId(personId, requestId);
        IdentityTypes.MigrationRequest storage m = _migrations[personId];
        if (msg.sender != m.newWallet) revert DestinationConsentRequired(personId);
        _requireWalletUnlinked(msg.sender);
        m.accepted = true;
        emit MigrationConsent(personId, requestId, msg.sender);
    }

    /// @inheritdoc IIdentityApp
    function approveWalletMigration(bytes32 personId, bytes32 requestId) external {
        _requireIdentityOfficer(msg.sender);
        _requireMigrationId(personId, requestId);

        IdentityTypes.MigrationRequest storage migration = _migrations[personId];
        if (!migration.exists) {
            revert MigrationNotFound(personId);
        }
        if (migration.approved) {
            revert MigrationAlreadyApproved(personId);
        }
        if (!migration.accepted) revert DestinationConsentRequired(personId);
        if (migration.recovery) {
            _requireDistinctOfficers(msg.sender, migration.proposer);
            _requireIdentityOfficeAdmin(migration.proposer);
            _requireOfficerAuthorization(migration.proposer, migration.proposerAuthorizationId);
        }

        uint64 approvedAt = uint64(block.timestamp);
        migration.approved = true;
        migration.approvedAt = approvedAt;
        migration.approver = msg.sender;
        migration.approverAuthorizationId = _officeRegistry.authorizationId(_identityOfficeId, msg.sender);

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

        uint64 readyAt = migration.approvedAt + (migration.recovery ? EXCEPTIONAL_DELAY : _migrationDelay);
        if (block.timestamp < readyAt) {
            revert MigrationDelayNotElapsed(personId, readyAt);
        }

        // Re-validate the swap is still safe at execution time.
        _requireIdentityOfficer(migration.approver);
        _requireOfficerAuthorization(migration.approver, migration.approverAuthorizationId);
        if (migration.recovery) {
            _requireIdentityOfficeAdmin(migration.proposer);
            _requireOfficerAuthorization(migration.proposer, migration.proposerAuthorizationId);
            _requireDistinctOfficers(migration.proposer, migration.approver);
        }
        if (_identityRegistry.activeWalletOf(personId) != migration.oldWallet) {
            revert MigrationOldWalletInactive(personId, migration.oldWallet);
        }
        _requireWalletUnlinked(migration.newWallet);

        delete _migrations[personId];

        // Revoke first so the person's active-wallet count returns to zero, then activate the new wallet. The
        // one-active-wallet invariant in the registry passes precisely because of this ordering, and staked LLM
        // stays with personId (never touched here).
        if (migration.oldWallet != address(0)) {
            _identityRegistry.setWalletLink(personId, migration.oldWallet, IdentityTypes.WalletLinkStatus.Revoked);
        }
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
            msg.sender != migration.oldWallet && msg.sender != migration.newWallet
                && _officeRegistry.roleOf(_identityOfficeId, msg.sender) == OfficeTypes.OfficeRole.None
        ) {
            revert UnauthorizedMigrationCanceller(msg.sender, personId);
        }

        delete _migrations[personId];

        emit WalletMigrationCancelled(personId, msg.sender, uint64(block.timestamp));
    }

    function _requireMigrationId(bytes32 personId, bytes32 requestId) private view {
        bytes32 expected = walletMigrationId(personId);
        if (expected == bytes32(0)) revert MigrationNotFound(personId);
        if (requestId != expected) revert StaleRequest(expected, requestId);
    }

    function _requireRecord(bytes32 personId) private view returns (IdentityTypes.IdentityRecord memory record) {
        record = _identityRegistry.getIdentityRecord(personId);
        if (record.personId == bytes32(0)) revert IdentityNotRegistered(personId);
    }

    /// @inheritdoc IIdentityApp
    function proposeCivicChange(
        bytes32 personId,
        IdentityTypes.CivicStatusInput calldata proposed,
        bytes32 evidenceHash
    ) external returns (bytes32 requestId) {
        _requireIdentityOfficeAdmin(msg.sender);
        if (evidenceHash == bytes32(0)) revert InvalidEvidenceHash();
        IdentityTypes.IdentityRecord memory record = _requireRecord(personId);
        if (_civicChanges[personId].requestId != bytes32(0)) revert CivicChangePending(personId);
        bytes32 previous = _civicStateHash(record);
        requestId = keccak256(
            abi.encode(
                block.chainid,
                address(this),
                "CIVIC_CHANGE",
                personId,
                ++_requestNonces[personId],
                previous,
                proposed,
                evidenceHash
            )
        );
        _civicChanges[personId] = IdentityTypes.CivicChangeRequest({
            requestId: requestId,
            previousStateHash: previous,
            evidenceHash: evidenceHash,
            proposer: msg.sender,
            approver: address(0),
            readyAt: 0,
            proposed: proposed,
            appealAuthority: address(0),
            appealEvidenceHash: bytes32(0),
            appealDeadline: 0,
            appealResolved: false,
            proposerAuthorizationId: _officeRegistry.authorizationId(_identityOfficeId, msg.sender),
            approverAuthorizationId: bytes32(0)
        });
        emit CivicChangeProposed(personId, requestId, msg.sender, evidenceHash);
    }

    /// @inheritdoc IIdentityApp
    function approveCivicChange(bytes32 personId, bytes32 requestId) external {
        _requireIdentityOfficer(msg.sender);
        IdentityTypes.CivicChangeRequest storage request = _requireCivicRequest(personId, requestId);
        _requireDistinctOfficers(request.proposer, msg.sender);
        _requireIdentityOfficeAdmin(request.proposer);
        _requireOfficerAuthorization(request.proposer, request.proposerAuthorizationId);
        if (request.approver != address(0)) revert CivicChangeNotReady(personId);
        if (request.previousStateHash != _civicStateHash(_requireRecord(personId))) {
            revert CivicChangeNotReady(personId);
        }
        address reviewer = IConstitutionKernel(_kernel).getModule(KernelModuleIds.CIVIC_APPEAL_AUTHORITY);
        if (ICivicAppealReview(reviewer).identityApp() != address(this)) revert UnauthorizedCivicReviewer(reviewer);
        request.appealAuthority = reviewer;
        request.approver = msg.sender;
        request.approverAuthorizationId = _officeRegistry.authorizationId(_identityOfficeId, msg.sender);
        request.readyAt = uint64(block.timestamp) + EXCEPTIONAL_DELAY;
        emit CivicAppealAuthorityPinned(personId, requestId, reviewer);
        emit CivicChangeApproved(personId, requestId, msg.sender, request.readyAt);
    }

    /// @inheritdoc IIdentityApp
    function getCivicChange(bytes32 personId) external view returns (IdentityTypes.CivicChangeRequest memory request) {
        return _civicChanges[personId];
    }

    /// @inheritdoc IIdentityApp
    function finalizeCivicChange(bytes32 personId, bytes32 requestId) external {
        IdentityTypes.CivicChangeRequest memory request = _requireCivicRequest(personId, requestId);
        if (request.approver == address(0) || block.timestamp < request.readyAt) revert CivicChangeNotReady(personId);
        if (request.appealEvidenceHash != bytes32(0) && !request.appealResolved) revert CivicChangeNotReady(personId);
        _requireIdentityOfficeAdmin(request.proposer);
        _requireIdentityOfficer(request.approver);
        _requireOfficerAuthorization(request.proposer, request.proposerAuthorizationId);
        _requireOfficerAuthorization(request.approver, request.approverAuthorizationId);
        _requireDistinctOfficers(request.proposer, request.approver);
        IdentityTypes.IdentityRecord memory record = _requireRecord(personId);
        if (request.previousStateHash != _civicStateHash(record)) revert CivicChangeNotReady(personId);
        delete _civicChanges[personId];
        // Any adjudicated civic outcome retires the one-time onboarding grant path, including adverse decisions.
        delete _initialCitizenshipGrantAvailable[personId];
        _identityRegistry.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: record.metadataHash,
                metadataURI: record.metadataURI,
                verificationStatus: request.proposed.verificationStatus,
                citizenshipStatus: request.proposed.citizenshipStatus,
                ageClass: request.proposed.ageClass,
                correctionFlag: request.proposed.correctionFlag,
                finalSuspension: request.proposed.finalSuspension
            })
        );
        emit CivicChangeFinalized(personId, requestId);
    }

    /// @inheritdoc IIdentityApp
    function cancelCivicChange(bytes32 personId, bytes32 requestId) external {
        _requireCivicRequest(personId, requestId);
        _requireIdentityOfficer(msg.sender);
        if (_identityRegistry.resolveWalletToPersonId(msg.sender) == personId) revert CivicAppealNotOpen(personId);
        _cancelCivicChange(personId);
    }

    /// @inheritdoc IIdentityApp
    function appealCivicChange(bytes32 personId, bytes32 requestId, bytes32 evidenceHash) external {
        IdentityTypes.CivicChangeRequest storage request = _requireCivicRequest(personId, requestId);
        if (
            _identityRegistry.activeWalletOf(personId) != msg.sender || request.approver == address(0)
                || block.timestamp >= request.readyAt || request.appealEvidenceHash != bytes32(0)
        ) revert CivicAppealNotOpen(personId);
        if (evidenceHash == bytes32(0)) revert InvalidEvidenceHash();
        request.appealEvidenceHash = evidenceHash;
        request.appealDeadline = uint64(block.timestamp) + APPEAL_REVIEW_PERIOD;
        emit CivicChangeAppealed(personId, requestId, evidenceHash, request.appealDeadline);
    }

    /// @inheritdoc IIdentityApp
    function resolveCivicAppeal(bytes32 personId, bytes32 requestId, bool uphold, bytes32 rulingEvidenceHash) external {
        IdentityTypes.CivicChangeRequest storage request = _requireOpenAppeal(personId, requestId);
        if (msg.sender != request.appealAuthority) revert UnauthorizedCivicReviewer(msg.sender);
        if (block.timestamp >= request.appealDeadline) revert CivicAppealNotOpen(personId);
        if (rulingEvidenceHash == bytes32(0)) revert InvalidEvidenceHash();
        if (uphold) {
            request.appealResolved = true;
            uint64 rulingReadyAt = uint64(block.timestamp) + APPEAL_EXECUTION_DELAY;
            if (rulingReadyAt > request.readyAt) request.readyAt = rulingReadyAt;
            emit CivicAppealResolved(personId, requestId, true, rulingEvidenceHash, request.readyAt);
        } else {
            delete _civicChanges[personId];
            emit CivicAppealResolved(personId, requestId, false, rulingEvidenceHash, 0);
        }
    }

    /// @inheritdoc IIdentityApp
    function expireCivicAppeal(bytes32 personId, bytes32 requestId) external {
        IdentityTypes.CivicChangeRequest storage request = _requireOpenAppeal(personId, requestId);
        if (block.timestamp < request.appealDeadline) revert CivicAppealNotOpen(personId);
        delete _civicChanges[personId];
        emit CivicAppealExpired(personId, requestId);
    }

    function _requireOpenAppeal(bytes32 personId, bytes32 requestId)
        private
        view
        returns (IdentityTypes.CivicChangeRequest storage request)
    {
        request = _requireCivicRequest(personId, requestId);
        if (request.appealEvidenceHash == bytes32(0) || request.appealResolved) revert CivicAppealNotOpen(personId);
    }

    function _cancelCivicChange(bytes32 personId) private {
        bytes32 requestId = _civicChanges[personId].requestId;
        delete _civicChanges[personId];
        emit CivicChangeCancelled(personId, requestId, msg.sender);
    }

    function _requireCivicRequest(bytes32 personId, bytes32 requestId)
        private
        view
        returns (IdentityTypes.CivicChangeRequest storage request)
    {
        request = _civicChanges[personId];
        if (request.requestId == bytes32(0) || request.requestId != requestId) {
            revert StaleRequest(request.requestId, requestId);
        }
    }

    function _civicStateHash(IdentityTypes.IdentityRecord memory record) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                record.verificationStatus,
                record.citizenshipStatus,
                record.ageClass,
                record.correctionFlag,
                record.finalSuspension
            )
        );
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

    function _requireOfficerAuthorization(address officer, bytes32 expected) private view {
        if (expected == bytes32(0) || _officeRegistry.authorizationId(_identityOfficeId, officer) != expected) {
            revert StaleOfficerAuthorization(officer);
        }
    }

    function _requireDistinctOfficers(address first, address second) private view {
        bytes32 firstPerson = _identityRegistry.resolveWalletToPersonId(first);
        if (
            first == second
                || (firstPerson != bytes32(0) && firstPerson == _identityRegistry.resolveWalletToPersonId(second))
        ) {
            revert DistinctOfficerRequired();
        }
    }

    function _requireIdentityOfficer(address caller) private view {
        OfficeTypes.OfficeRole role = _officeRegistry.roleOf(_identityOfficeId, caller);
        if (role != OfficeTypes.OfficeRole.Admin && role != OfficeTypes.OfficeRole.Clerk) {
            revert UnauthorizedIdentityOfficer(caller, _identityOfficeId);
        }
    }
}
