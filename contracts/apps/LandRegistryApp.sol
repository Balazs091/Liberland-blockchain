// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILandPartyPolicy} from "../interfaces/ILandPartyPolicy.sol";
import {ILandRegistry} from "../interfaces/ILandRegistry.sol";
import {ILandRegistryApp} from "../interfaces/ILandRegistryApp.sol";
import {IOfficePermissionPolicy} from "../interfaces/IOfficePermissionPolicy.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {LandTypes} from "../types/LandTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title LandRegistryApp
/// @notice Cadastral workflows with clerk preparation, registrar finalization, and dual-consent title transfers.
/// @dev The app is replaceable. Future settlement, fee, insurance, ownership-group, or judicial modules can be
///      composed in a reviewed replacement without adding a bypass to the stable registry.
contract LandRegistryApp is ILandRegistryApp, EIP712 {
    bytes32 private constant _TITLE_TRANSFER_TYPEHASH = keccak256(
        "TitleTransfer(bytes32 titleId,bytes32 expectedVersionHash,bytes32 expectedParcelVersionHash,bytes32 sellerPartyKey,bytes32 newHolderPartyKey,bytes32 anchorHash,bytes32 transactionId,uint256 nonce,uint64 deadline)"
    );
    uint256 private constant _MAX_DISPUTE_APPROVAL_DURATION = 14 days;

    ILandRegistry private immutable _landRegistry;
    IOfficeRegistry private immutable _officeRegistry;
    bytes32 private immutable _landOfficeId;
    mapping(bytes32 titleId => uint256 nonce) private _titleTransferNonces;
    mapping(bytes32 disputeId => mapping(address clerk => DisputeApproval approval)) private _disputeApprovals;

    constructor(
        address landRegistryAddress,
        address officeRegistryAddress,
        address officePermissionPolicyAddress,
        address landPartyPolicyAddress,
        bytes32 landOfficeId_
    ) EIP712("Liberland Land Registry", "1") {
        if (landRegistryAddress == address(0) || landRegistryAddress.code.length == 0) {
            revert InvalidLandRegistry(landRegistryAddress);
        }
        if (officeRegistryAddress == address(0) || officeRegistryAddress.code.length == 0) {
            revert InvalidOfficeRegistry(officeRegistryAddress);
        }
        if (officePermissionPolicyAddress == address(0) || officePermissionPolicyAddress.code.length == 0) {
            revert InvalidOfficePermissionPolicy(officePermissionPolicyAddress);
        }
        if (landPartyPolicyAddress == address(0) || landPartyPolicyAddress.code.length == 0) {
            revert InvalidLandPartyPolicy(landPartyPolicyAddress);
        }
        if (landOfficeId_ == bytes32(0)) {
            revert InvalidLandRegistryOffice(landOfficeId_);
        }

        _landRegistry = ILandRegistry(landRegistryAddress);
        _officeRegistry = IOfficeRegistry(officeRegistryAddress);
        _landOfficeId = landOfficeId_;
    }

    /// @inheritdoc ILandRegistryApp
    function landRegistry() external view returns (address registryAddress) {
        return address(_landRegistry);
    }

    /// @inheritdoc ILandRegistryApp
    function officeRegistry() external view returns (address registryAddress) {
        return address(_officeRegistry);
    }

    /// @inheritdoc ILandRegistryApp
    function officePermissionPolicy() external view returns (address policyAddress) {
        return address(_currentOfficePermissionPolicy());
    }

    /// @inheritdoc ILandRegistryApp
    function landPartyPolicy() external view returns (address policyAddress) {
        return address(_currentLandPartyPolicy());
    }

    /// @inheritdoc ILandRegistryApp
    function landOfficeId() external view returns (bytes32 officeId) {
        return _landOfficeId;
    }

    /// @inheritdoc ILandRegistryApp
    function titleTransferNonce(bytes32 titleId) external view returns (uint256 nonce) {
        return _titleTransferNonces[titleId];
    }

    /// @inheritdoc ILandRegistryApp
    function hashTitleTransferAuthorization(LandTypes.TitleTransferRequest calldata request)
        external
        view
        returns (bytes32 digest)
    {
        return _hashTitleTransferAuthorization(request, _landRegistry.getTitle(request.titleId).holder);
    }

    /// @inheritdoc ILandRegistryApp
    function submitParcelDraft(bytes32 parcelId, LandTypes.ParcelInput calldata input, bytes32 transactionId) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.PrepareLandRecords);
        _landRegistry.createParcelDraft(parcelId, input, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function updateParcelDraft(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.ParcelInput calldata input,
        bytes32 transactionId
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.PrepareLandRecords);
        _landRegistry.updateParcelDraft(parcelId, expectedRevision, input, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function activateParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.RecordAnchor calldata finalAnchor,
        bytes32 transactionId
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        _landRegistry.activateParcel(parcelId, expectedRevision, finalAnchor, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function reviseParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.ParcelInput calldata input,
        bytes32 transactionId
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        _landRegistry.reviseParcel(parcelId, expectedRevision, input, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function retireParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.RecordAnchor calldata retirementAnchor,
        bytes32 transactionId
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        _landRegistry.retireParcel(parcelId, expectedRevision, retirementAnchor, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function registerTitle(bytes32 titleId, LandTypes.TitleInput calldata input, bytes32 transactionId) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        if (!_currentLandPartyPolicy().canAcquireLand(input.holder)) {
            revert InvalidParty(input.holder);
        }
        _landRegistry.registerTitle(titleId, input, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function transferTitle(
        LandTypes.TitleTransferRequest calldata request,
        address sellerSigner,
        bytes calldata sellerSignature,
        address buyerSigner,
        bytes calldata buyerSignature
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        if (request.deadline < block.timestamp) {
            revert InvalidTransferDeadline(request.deadline, uint64(block.timestamp));
        }

        uint256 expectedNonce = _titleTransferNonces[request.titleId];
        if (request.nonce != expectedNonce) {
            revert InvalidTransferNonce(request.titleId, request.nonce, expectedNonce);
        }

        LandTypes.TitleRecord memory titleRecord = _landRegistry.getTitle(request.titleId);
        _requireTransferParcelVersion(request, titleRecord.parcelId);
        ILandPartyPolicy partyPolicy = _currentLandPartyPolicy();
        if (!partyPolicy.partyExists(titleRecord.holder)) {
            revert InvalidParty(titleRecord.holder);
        }
        if (!partyPolicy.canAcquireLand(request.newHolder)) {
            revert InvalidParty(request.newHolder);
        }

        bytes32 sellerPartyKey = _partyKey(titleRecord.holder);
        bytes32 buyerPartyKey = _partyKey(request.newHolder);
        if (!partyPolicy.isAuthorizedSigner(titleRecord.holder, sellerSigner)) {
            revert InvalidPartySigner(sellerPartyKey, sellerSigner);
        }
        if (!partyPolicy.isAuthorizedSigner(request.newHolder, buyerSigner)) {
            revert InvalidPartySigner(buyerPartyKey, buyerSigner);
        }

        bytes32 digest = _hashTitleTransferAuthorization(request, titleRecord.holder);
        if (!SignatureChecker.isValidSignatureNowCalldata(sellerSigner, digest, sellerSignature)) {
            revert InvalidSignature(sellerPartyKey, sellerSigner);
        }
        if (!SignatureChecker.isValidSignatureNowCalldata(buyerSigner, digest, buyerSignature)) {
            revert InvalidSignature(buyerPartyKey, buyerSigner);
        }

        _titleTransferNonces[request.titleId] = expectedNonce + 1;
        _writeTitleTransfer(request);
    }

    /// @inheritdoc ILandRegistryApp
    function closeExpiredLease(
        bytes32 parcelId,
        bytes32 titleId,
        bytes32 expectedVersionHash,
        LandTypes.RecordAnchor calldata closingAnchor,
        bytes32 transactionId
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        LandTypes.TitleRecord memory titleRecord = _landRegistry.getTitle(titleId);
        if (
            !titleRecord.active || titleRecord.parcelId != parcelId
                || titleRecord.tenureType != LandTypes.TenureType.Leasehold
                || titleRecord.leaseExpiresAt > block.timestamp
        ) {
            revert TitleNotExpiredLease(titleId);
        }
        _landRegistry.closeTitle(parcelId, titleId, expectedVersionHash, closingAnchor, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function subdivideParcel(
        bytes32 parentParcelId,
        uint64 expectedParentRevision,
        LandTypes.SubdivisionChild[] calldata children,
        bytes32 transactionId
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        _landRegistry.subdivideParcel(parentParcelId, expectedParentRevision, children, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function mergeParcels(
        bytes32[] calldata sourceParcelIds,
        uint64[] calldata expectedRevisions,
        LandTypes.MergeResult calldata result,
        bytes32 transactionId
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        _landRegistry.mergeParcels(sourceParcelIds, expectedRevisions, result, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function adjustBoundary(
        LandTypes.ParcelRevisionInput calldata first,
        LandTypes.ParcelRevisionInput calldata second,
        bytes32 transactionId
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        _landRegistry.adjustBoundary(first, second, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function fileDispute(
        bytes32 disputeId,
        bytes32 parcelId,
        LandTypes.PartyRef calldata claimant,
        bytes32 evidenceHash,
        bytes32 transactionId
    ) external {
        ILandPartyPolicy partyPolicy = _currentLandPartyPolicy();
        bytes32 claimantPartyKey = _partyKey(claimant);
        if (!partyPolicy.partyExists(claimant)) {
            revert InvalidParty(claimant);
        }
        if (!partyPolicy.isAuthorizedSigner(claimant, msg.sender)) {
            revert InvalidPartySigner(claimantPartyKey, msg.sender);
        }
        _landRegistry.fileDispute(disputeId, parcelId, claimant, evidenceHash, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function hashDisputeAction(DisputeAction action, bytes32 disputeId, bytes32 recordHash, bytes32 transactionId)
        public
        pure
        returns (bytes32 actionHash)
    {
        return keccak256(abi.encode(action, disputeId, recordHash, transactionId));
    }

    /// @inheritdoc ILandRegistryApp
    function disputeStateHash(bytes32 disputeId) public view returns (bytes32 stateHash) {
        LandTypes.DisputeRecord memory dispute = _landRegistry.getDispute(disputeId);
        if (dispute.disputeId == bytes32(0)) revert ILandRegistry.DisputeNotFound(disputeId);
        if (dispute.status != LandTypes.DisputeStatus.Filed && dispute.status != LandTypes.DisputeStatus.Accepted) {
            revert ILandRegistry.InvalidDisputeStatus(dispute.status);
        }
        bytes32 parcelId = dispute.parcelId;
        bytes32 titleId = _landRegistry.activeTitleOfParcel(parcelId);
        bytes32 titleVersion = titleId == bytes32(0) ? bytes32(0) : _landRegistry.getTitle(titleId).versionHash;
        return keccak256(
            abi.encode(
                dispute,
                _landRegistry.getParcel(parcelId).versionHash,
                titleVersion,
                _landRegistry.activeDisputeCountOf(parcelId)
            )
        );
    }

    /// @inheritdoc ILandRegistryApp
    function getDisputeApproval(bytes32 disputeId, address clerk)
        external
        view
        returns (DisputeApproval memory approval)
    {
        return _disputeApprovals[disputeId][clerk];
    }

    /// @inheritdoc ILandRegistryApp
    function approveDisputeAction(bytes32 disputeId, bytes32 actionHash, bytes32 expectedStateHash, uint64 expiresAt)
        external
    {
        if (_officeRegistry.roleOf(_landOfficeId, msg.sender) != OfficeTypes.OfficeRole.Clerk) {
            revert InvalidLandDisputeOfficer(msg.sender);
        }
        if (actionHash == bytes32(0)) revert InvalidDisputeActionHash();
        if (expiresAt <= block.timestamp || expiresAt > block.timestamp + _MAX_DISPUTE_APPROVAL_DURATION) {
            revert InvalidDisputeApprovalExpiry(expiresAt);
        }
        bytes32 currentStateHash = disputeStateHash(disputeId);
        if (expectedStateHash != currentStateHash) {
            revert StaleDisputeApprovalState(disputeId, expectedStateHash, currentStateHash);
        }
        (IIdentityRegistry identityRegistry, uint64 activatedAt) = _disputeAuthorityContext();
        if (block.timestamp <= activatedAt) revert InactiveLandDisputeAuthority(address(this));
        bytes32 personId = _verifiedOfficerPerson(identityRegistry, msg.sender);
        _disputeApprovals[disputeId][msg.sender] = DisputeApproval({
            expiresAt: expiresAt,
            actionHash: actionHash,
            stateHash: currentStateHash,
            authorizationHash: _disputeClerkAuthorization(identityRegistry, msg.sender, personId, activatedAt)
        });
        emit DisputeActionApproved(disputeId, actionHash, msg.sender, currentStateHash, expiresAt);
    }

    /// @inheritdoc ILandRegistryApp
    function withdrawDisputeApproval(bytes32 disputeId, bytes32 expectedActionHash) external {
        DisputeApproval storage approval = _disputeApprovals[disputeId][msg.sender];
        if (approval.expiresAt == 0 || approval.actionHash != expectedActionHash) {
            revert MissingDisputeApproval(disputeId, expectedActionHash);
        }
        delete _disputeApprovals[disputeId][msg.sender];
        emit DisputeApprovalWithdrawn(disputeId, expectedActionHash, msg.sender);
    }

    /// @inheritdoc ILandRegistryApp
    function acceptDispute(bytes32 disputeId, bytes32 evidenceHash, bytes32 transactionId, address clerk) external {
        _consumeDisputeApproval(
            disputeId, hashDisputeAction(DisputeAction.Accept, disputeId, evidenceHash, transactionId), clerk
        );
        _landRegistry.acceptDispute(disputeId, evidenceHash, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function resolveDispute(
        bytes32 disputeId,
        bytes32 resolutionHash,
        bool claimAccepted,
        bytes32 transactionId,
        address clerk
    ) external {
        DisputeAction action = claimAccepted ? DisputeAction.Uphold : DisputeAction.Dismiss;
        _consumeDisputeApproval(disputeId, hashDisputeAction(action, disputeId, resolutionHash, transactionId), clerk);
        _landRegistry.resolveDispute(disputeId, resolutionHash, claimAccepted, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function registerEncumbrance(
        bytes32 encumbranceId,
        LandTypes.EncumbranceInput calldata input,
        bytes32 transactionId
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        if (!_isEmptyParty(input.beneficiary) && !_isCompleteParty(input.beneficiary)) {
            revert InvalidParty(input.beneficiary);
        }
        if (_isCompleteParty(input.beneficiary) && !_currentLandPartyPolicy().partyExists(input.beneficiary)) {
            revert InvalidParty(input.beneficiary);
        }
        _landRegistry.registerEncumbrance(encumbranceId, input, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function releaseEncumbrance(
        bytes32 encumbranceId,
        LandTypes.RecordAnchor calldata releaseAnchor,
        bytes32 transactionId
    ) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.FinalizeLandRecords);
        _landRegistry.releaseEncumbrance(encumbranceId, releaseAnchor, transactionId);
    }

    function _consumeDisputeApproval(bytes32 disputeId, bytes32 actionHash, address clerk) private {
        OfficeTypes.OfficeRole role =
            _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.ResolveLandDisputes);
        if (role != OfficeTypes.OfficeRole.Admin) revert InvalidLandDisputeOfficer(msg.sender);
        DisputeApproval memory approval = _disputeApprovals[disputeId][clerk];
        if (approval.expiresAt == 0 || approval.actionHash != actionHash) {
            revert MissingDisputeApproval(disputeId, actionHash);
        }
        if (block.timestamp >= approval.expiresAt) revert ExpiredDisputeApproval(disputeId, approval.expiresAt);
        bytes32 currentStateHash = disputeStateHash(disputeId);
        if (approval.stateHash != currentStateHash) {
            revert StaleDisputeApprovalState(disputeId, approval.stateHash, currentStateHash);
        }
        (IIdentityRegistry identityRegistry, uint64 activatedAt) = _disputeAuthorityContext();
        bytes32 clerkPersonId = _verifiedOfficerPerson(identityRegistry, clerk);
        if (clerkPersonId == _verifiedOfficerPerson(identityRegistry, msg.sender)) {
            revert DistinctLandDisputeOfficersRequired(disputeId);
        }
        bytes32 currentAuthorization = _disputeClerkAuthorization(identityRegistry, clerk, clerkPersonId, activatedAt);
        if (approval.authorizationHash != currentAuthorization) {
            revert StaleDisputeClerkAuthorization(disputeId, clerk);
        }
        delete _disputeApprovals[disputeId][clerk];
        emit DisputeApprovalUsed(disputeId, actionHash, clerk, msg.sender);
    }

    function _disputeAuthorityContext() private view returns (IIdentityRegistry identityRegistry, uint64 activatedAt) {
        IConstitutionKernel kernel = IConstitutionKernel(_landRegistry.kernel());
        GovernanceTypes.ModuleRecord memory authority = kernel.getModuleRecord(KernelModuleIds.LAND_REGISTRY_AUTHORITY);
        GovernanceTypes.ModuleRecord memory land = kernel.getModuleRecord(KernelModuleIds.LAND_REGISTRY);
        GovernanceTypes.ModuleRecord memory office = kernel.getModuleRecord(KernelModuleIds.OFFICE_REGISTRY);
        if (
            authority.moduleAddress != address(this) || land.moduleAddress != address(_landRegistry)
                || office.moduleAddress != address(_officeRegistry)
        ) revert InactiveLandDisputeAuthority(address(this));

        GovernanceTypes.ModuleRecord memory identity = kernel.getModuleRecord(KernelModuleIds.IDENTITY_REGISTRY);
        activatedAt = authority.activatedAt;
        if (land.activatedAt > activatedAt) activatedAt = land.activatedAt;
        if (office.activatedAt > activatedAt) activatedAt = office.activatedAt;
        if (identity.activatedAt > activatedAt) activatedAt = identity.activatedAt;
        return (IIdentityRegistry(identity.moduleAddress), activatedAt);
    }

    function _verifiedOfficerPerson(IIdentityRegistry identityRegistry, address officer)
        private
        view
        returns (bytes32 personId)
    {
        IdentityTypes.WalletLink memory link = identityRegistry.getWalletLink(officer);
        if (link.personId == bytes32(0) || link.status != IdentityTypes.WalletLinkStatus.Active) {
            revert InvalidLandDisputeOfficer(officer);
        }
        (IdentityTypes.VerificationStatus verificationStatus,,,) = identityRegistry.getCitizenshipSummary(link.personId);
        if (verificationStatus != IdentityTypes.VerificationStatus.Verified) revert InvalidLandDisputeOfficer(officer);
        return link.personId;
    }

    function _disputeClerkAuthorization(
        IIdentityRegistry identityRegistry,
        address clerk,
        bytes32 clerkPersonId,
        uint64 activatedAt
    ) private view returns (bytes32 authorizationHash) {
        return keccak256(
            abi.encode(
                _officeRegistry.authorizationId(_landOfficeId, clerk),
                address(identityRegistry),
                clerkPersonId,
                identityRegistry.electorateRevisionOf(clerkPersonId),
                activatedAt
            )
        );
    }

    function _requireTransferParcelVersion(LandTypes.TitleTransferRequest calldata request, bytes32 parcelId)
        private
        view
    {
        bytes32 parcelVersionHash = _landRegistry.getParcel(parcelId).versionHash;
        if (request.expectedParcelVersionHash != parcelVersionHash) {
            revert StaleTransferParcelVersion(parcelId, request.expectedParcelVersionHash, parcelVersionHash);
        }
    }

    function _hashTitleTransferAuthorization(
        LandTypes.TitleTransferRequest calldata request,
        LandTypes.PartyRef memory seller
    ) private view returns (bytes32 digest) {
        bytes32 structHash = keccak256(
            abi.encode(
                _TITLE_TRANSFER_TYPEHASH,
                request.titleId,
                request.expectedVersionHash,
                request.expectedParcelVersionHash,
                _partyKey(seller),
                _partyKey(request.newHolder),
                _anchorHash(request.anchor),
                request.transactionId,
                request.nonce,
                request.deadline
            )
        );
        return _hashTypedDataV4(structHash);
    }

    function _writeTitleTransfer(LandTypes.TitleTransferRequest calldata request) private {
        _landRegistry.transferTitle(
            request.titleId, request.expectedVersionHash, request.newHolder, request.anchor, request.transactionId
        );
    }

    function _anchorHash(LandTypes.RecordAnchor calldata anchor) private pure returns (bytes32 hash) {
        return keccak256(
            abi.encode(
                anchor.schemaId, anchor.schemaVersion, anchor.contentHash, anchor.sourceDocumentHash, anchor.lineageHash
            )
        );
    }

    function _partyKey(LandTypes.PartyRef memory party) private pure returns (bytes32 key) {
        return keccak256(abi.encode(party.namespace, party.id));
    }

    function _isEmptyParty(LandTypes.PartyRef calldata party) private pure returns (bool empty) {
        return party.namespace == bytes32(0) && party.id == bytes32(0);
    }

    function _isCompleteParty(LandTypes.PartyRef calldata party) private pure returns (bool complete) {
        return party.namespace != bytes32(0) && party.id != bytes32(0);
    }

    function _requireLandOfficeAction(address caller, OfficeTypes.OfficeActionClass actionClass)
        private
        view
        returns (OfficeTypes.OfficeRole officeRole)
    {
        OfficeTypes.OfficeRecord memory officeRecord = _officeRegistry.getOfficeRecord(_landOfficeId);
        if (officeRecord.officeId == bytes32(0) || officeRecord.kind != OfficeTypes.OfficeKind.LandRegistryOffice) {
            revert InvalidLandRegistryOffice(_landOfficeId);
        }

        officeRole = _officeRegistry.roleOf(_landOfficeId, caller);
        if (!_currentOfficePermissionPolicy().isActionAuthorized(officeRecord.kind, officeRole, actionClass)) {
            revert UnauthorizedLandRegistryOfficeAction(caller, _landOfficeId, actionClass);
        }
    }

    function _currentOfficePermissionPolicy() private view returns (IOfficePermissionPolicy policy) {
        return IOfficePermissionPolicy(
            IConstitutionKernel(_landRegistry.kernel()).getModule(KernelModuleIds.OFFICE_PERMISSION_POLICY)
        );
    }

    function _currentLandPartyPolicy() private view returns (ILandPartyPolicy policy) {
        return
            ILandPartyPolicy(IConstitutionKernel(_landRegistry.kernel()).getModule(KernelModuleIds.LAND_PARTY_POLICY));
    }
}
