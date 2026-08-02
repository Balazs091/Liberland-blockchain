// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ILandPartyPolicy} from "../interfaces/ILandPartyPolicy.sol";
import {ILandRegistry} from "../interfaces/ILandRegistry.sol";
import {ILandRegistryApp} from "../interfaces/ILandRegistryApp.sol";
import {IOfficePermissionPolicy} from "../interfaces/IOfficePermissionPolicy.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {LandTypes} from "../types/LandTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title LandRegistryApp
/// @notice Cadastral workflows with clerk preparation, registrar finalization, and dual-consent title transfers.
/// @dev The app is replaceable. Future settlement, fee, insurance, ownership-group, or judicial modules can be
///      composed in a reviewed replacement without adding a bypass to the stable registry.
contract LandRegistryApp is ILandRegistryApp, EIP712 {
    bytes32 private constant _TITLE_TRANSFER_TYPEHASH = keccak256(
        "TitleTransfer(bytes32 titleId,bytes32 expectedVersionHash,bytes32 sellerPartyKey,bytes32 newHolderPartyKey,bytes32 anchorHash,bytes32 transactionId,uint256 nonce,uint64 deadline)"
    );

    ILandRegistry private immutable _landRegistry;
    IOfficeRegistry private immutable _officeRegistry;
    bytes32 private immutable _landOfficeId;
    mapping(bytes32 titleId => uint256 nonce) private _titleTransferNonces;

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
    function acceptDispute(bytes32 disputeId, bytes32 evidenceHash, bytes32 transactionId) external {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.ResolveLandDisputes);
        _landRegistry.acceptDispute(disputeId, evidenceHash, transactionId);
    }

    /// @inheritdoc ILandRegistryApp
    function resolveDispute(bytes32 disputeId, bytes32 resolutionHash, bool claimAccepted, bytes32 transactionId)
        external
    {
        _requireLandOfficeAction(msg.sender, OfficeTypes.OfficeActionClass.ResolveLandDisputes);
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

    function _hashTitleTransferAuthorization(
        LandTypes.TitleTransferRequest calldata request,
        LandTypes.PartyRef memory seller
    ) private view returns (bytes32 digest) {
        bytes32 structHash = keccak256(
            abi.encode(
                _TITLE_TRANSFER_TYPEHASH,
                request.titleId,
                request.expectedVersionHash,
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

    function _requireLandOfficeAction(address caller, OfficeTypes.OfficeActionClass actionClass) private view {
        OfficeTypes.OfficeRecord memory officeRecord = _officeRegistry.getOfficeRecord(_landOfficeId);
        if (officeRecord.officeId == bytes32(0) || officeRecord.kind != OfficeTypes.OfficeKind.LandRegistryOffice) {
            revert InvalidLandRegistryOffice(_landOfficeId);
        }

        OfficeTypes.OfficeRole officeRole = _officeRegistry.roleOf(_landOfficeId, caller);
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
