// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ILandRegistry} from "../interfaces/ILandRegistry.sol";
import {KernelModule} from "../base/KernelModule.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {LandTypes} from "../types/LandTypes.sol";

/// @title LandRegistry
/// @notice Stable fact registry for parcel, title, dispute, and encumbrance records.
contract LandRegistry is ILandRegistry, KernelModule {
    mapping(bytes32 parcelId => LandTypes.ParcelRecord parcelRecord) private _parcels;
    mapping(bytes32 parcelNumberHash => bytes32 parcelId) private _parcelByNumberHash;
    mapping(bytes32 titleId => LandTypes.TitleRecord titleRecord) private _titles;
    mapping(bytes32 parcelId => bytes32 titleId) private _activeTitleOfParcel;
    mapping(bytes32 disputeId => LandTypes.DisputeRecord disputeRecord) private _disputes;
    mapping(bytes32 encumbranceId => LandTypes.EncumbranceRecord encumbranceRecord) private _encumbrances;
    mapping(bytes32 parcelId => uint256 count) private _activeDisputeCounts;
    mapping(bytes32 parcelId => uint256 count) private _activeEncumbranceCounts;
    bytes32[] private _parcelIds;

    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc ILandRegistry
    function getParcel(bytes32 parcelId) external view returns (LandTypes.ParcelRecord memory record) {
        return _parcels[parcelId];
    }

    /// @inheritdoc ILandRegistry
    function getTitle(bytes32 titleId) external view returns (LandTypes.TitleRecord memory record) {
        return _titles[titleId];
    }

    /// @inheritdoc ILandRegistry
    function getDispute(bytes32 disputeId) external view returns (LandTypes.DisputeRecord memory record) {
        return _disputes[disputeId];
    }

    /// @inheritdoc ILandRegistry
    function getEncumbrance(bytes32 encumbranceId) external view returns (LandTypes.EncumbranceRecord memory record) {
        return _encumbrances[encumbranceId];
    }

    /// @inheritdoc ILandRegistry
    function parcelExists(bytes32 parcelId) public view returns (bool exists) {
        return _parcels[parcelId].parcelId != bytes32(0);
    }

    /// @inheritdoc ILandRegistry
    function titleExists(bytes32 titleId) public view returns (bool exists) {
        return _titles[titleId].titleId != bytes32(0);
    }

    /// @inheritdoc ILandRegistry
    function activeTitleOfParcel(bytes32 parcelId) external view returns (bytes32 titleId) {
        return _activeTitleOfParcel[parcelId];
    }

    /// @inheritdoc ILandRegistry
    function activeDisputeCountOf(bytes32 parcelId) external view returns (uint256 count) {
        return _activeDisputeCounts[parcelId];
    }

    /// @inheritdoc ILandRegistry
    function activeEncumbranceCountOf(bytes32 parcelId) external view returns (uint256 count) {
        return _activeEncumbranceCounts[parcelId];
    }

    /// @inheritdoc ILandRegistry
    function totalParcelCount() external view returns (uint256 count) {
        return _parcelIds.length;
    }

    /// @inheritdoc ILandRegistry
    function parcelIdAt(uint256 index) external view returns (bytes32 parcelId) {
        return _parcelIds[index];
    }

    /// @inheritdoc ILandRegistry
    function createParcel(bytes32 parcelId, LandTypes.ParcelInput calldata input) external {
        _requireRegistryAuthority(msg.sender);
        _validateNewParcel(parcelId, input);

        uint64 currentTimestamp = uint64(block.timestamp);
        _parcels[parcelId] = LandTypes.ParcelRecord({
            parcelId: parcelId,
            parcelNumberHash: input.parcelNumberHash,
            districtHash: input.districtHash,
            metadataHash: input.metadataHash,
            spatialDataHash: input.spatialDataHash,
            documentHash: input.documentHash,
            spatialType: input.spatialType,
            status: LandTypes.ParcelStatus.Draft,
            areaSquareMeters: input.areaSquareMeters,
            createdAt: currentTimestamp,
            updatedAt: currentTimestamp
        });
        _parcelByNumberHash[input.parcelNumberHash] = parcelId;
        _parcelIds.push(parcelId);

        emit ParcelRegistered(parcelId, input.parcelNumberHash, currentTimestamp, msg.sender);
    }

    /// @inheritdoc ILandRegistry
    function updateParcel(bytes32 parcelId, LandTypes.ParcelInput calldata input) external {
        _requireRegistryAuthority(msg.sender);
        _validateExistingParcelUpdate(parcelId, input);

        LandTypes.ParcelRecord storage parcelRecord = _parcels[parcelId];
        if (parcelRecord.parcelNumberHash != input.parcelNumberHash) {
            delete _parcelByNumberHash[parcelRecord.parcelNumberHash];
            _parcelByNumberHash[input.parcelNumberHash] = parcelId;
        }

        parcelRecord.parcelNumberHash = input.parcelNumberHash;
        parcelRecord.districtHash = input.districtHash;
        parcelRecord.metadataHash = input.metadataHash;
        parcelRecord.spatialDataHash = input.spatialDataHash;
        parcelRecord.documentHash = input.documentHash;
        parcelRecord.spatialType = input.spatialType;
        parcelRecord.areaSquareMeters = input.areaSquareMeters;
        parcelRecord.updatedAt = uint64(block.timestamp);

        emit ParcelUpdated(parcelId, parcelRecord.status, parcelRecord.updatedAt, msg.sender);
    }

    /// @inheritdoc ILandRegistry
    function activateParcel(bytes32 parcelId, bytes32 documentHash) external {
        _requireRegistryAuthority(msg.sender);
        LandTypes.ParcelRecord storage parcelRecord = _getParcelRecord(parcelId);
        if (parcelRecord.status != LandTypes.ParcelStatus.Draft) {
            revert InvalidParcelStatus(parcelRecord.status);
        }
        if (documentHash == bytes32(0)) {
            revert InvalidParcelPayload(parcelId);
        }

        parcelRecord.status = LandTypes.ParcelStatus.Active;
        parcelRecord.documentHash = documentHash;
        parcelRecord.updatedAt = uint64(block.timestamp);

        emit ParcelUpdated(parcelId, parcelRecord.status, parcelRecord.updatedAt, msg.sender);
    }

    /// @inheritdoc ILandRegistry
    function retireParcel(bytes32 parcelId, bytes32 documentHash) external {
        _requireRegistryAuthority(msg.sender);
        LandTypes.ParcelRecord storage parcelRecord = _getParcelRecord(parcelId);
        if (parcelRecord.status == LandTypes.ParcelStatus.Retired) {
            revert InvalidParcelStatus(parcelRecord.status);
        }
        if (_activeTitleOfParcel[parcelId] != bytes32(0) || documentHash == bytes32(0)) {
            revert InvalidParcelPayload(parcelId);
        }
        // L4: a parcel with an open accepted dispute — or an unreleased active encumbrance — cannot be retired
        // until those are cleared, so no encumbrance is ever left dangling against a retired parcel.
        if (_activeDisputeCounts[parcelId] != 0 || _activeEncumbranceCounts[parcelId] != 0) {
            revert ParcelTransferLocked(parcelId);
        }

        parcelRecord.status = LandTypes.ParcelStatus.Retired;
        parcelRecord.documentHash = documentHash;
        parcelRecord.updatedAt = uint64(block.timestamp);

        emit ParcelUpdated(parcelId, parcelRecord.status, parcelRecord.updatedAt, msg.sender);
    }

    /// @inheritdoc ILandRegistry
    function registerTitle(bytes32 titleId, LandTypes.TitleInput calldata input) external {
        _requireRegistryAuthority(msg.sender);
        _validateTitleInput(titleId, input);

        LandTypes.ParcelRecord storage parcelRecord = _getParcelRecord(input.parcelId);
        if (parcelRecord.status != LandTypes.ParcelStatus.Active) {
            revert InvalidParcelStatus(parcelRecord.status);
        }

        bytes32 activeTitleId = _activeTitleOfParcel[input.parcelId];
        if (activeTitleId != bytes32(0)) {
            revert ParcelAlreadyTitled(input.parcelId, activeTitleId);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        _titles[titleId] = LandTypes.TitleRecord({
            titleId: titleId,
            parcelId: input.parcelId,
            holder: input.holder,
            tenureType: input.tenureType,
            leaseExpiresAt: input.leaseExpiresAt,
            documentHash: input.documentHash,
            active: true,
            registeredAt: currentTimestamp,
            updatedAt: currentTimestamp
        });
        _activeTitleOfParcel[input.parcelId] = titleId;

        emit TitleRegistered(titleId, input.parcelId, input.holder, currentTimestamp);
    }

    /// @inheritdoc ILandRegistry
    function transferTitle(bytes32 titleId, address newHolder, bytes32 documentHash) external {
        _requireRegistryAuthority(msg.sender);
        LandTypes.TitleRecord storage titleRecord = _getTitleRecord(titleId);
        if (!titleRecord.active || newHolder == address(0) || documentHash == bytes32(0)) {
            revert InvalidTitlePayload(titleId);
        }
        if (titleRecord.tenureType == LandTypes.TenureType.Leasehold && titleRecord.leaseExpiresAt <= block.timestamp) {
            revert InvalidTitlePayload(titleId);
        }
        _requireParcelTransferable(titleRecord.parcelId);

        address previousHolder = titleRecord.holder;
        titleRecord.holder = newHolder;
        titleRecord.documentHash = documentHash;
        titleRecord.updatedAt = uint64(block.timestamp);

        emit TitleTransferred(titleId, previousHolder, newHolder, titleRecord.updatedAt);
    }

    /// @inheritdoc ILandRegistry
    function closeTitle(bytes32 parcelId, bytes32 titleId, bytes32 documentHash) external {
        _requireRegistryAuthority(msg.sender);
        LandTypes.TitleRecord storage titleRecord = _getTitleRecord(titleId);
        if (!titleRecord.active || titleRecord.parcelId != parcelId || documentHash == bytes32(0)) {
            revert InvalidTitlePayload(titleId);
        }
        // Encumbrances must be released before the title is closed, otherwise the parcel's active-encumbrance count
        // would outlive the title and wrongly lock an unrelated future titleholder's transfer.
        if (_activeEncumbranceCounts[parcelId] != 0) {
            revert ParcelTransferLocked(parcelId);
        }

        // L4: retire the title record and release the parcel's active-title slot so the parcel can later be
        // retired or re-titled.
        titleRecord.active = false;
        titleRecord.documentHash = documentHash;
        titleRecord.updatedAt = uint64(block.timestamp);

        if (_activeTitleOfParcel[parcelId] == titleId) {
            delete _activeTitleOfParcel[parcelId];
        }

        emit TitleClosed(titleId, parcelId, titleRecord.updatedAt, msg.sender);
    }

    /// @inheritdoc ILandRegistry
    function fileDispute(bytes32 disputeId, bytes32 parcelId, address claimant, bytes32 evidenceHash) external {
        _requireRegistryAuthority(msg.sender);
        if (disputeId == bytes32(0) || !parcelExists(parcelId) || claimant == address(0) || evidenceHash == bytes32(0))
        {
            revert InvalidDisputePayload(disputeId);
        }
        if (_disputes[disputeId].disputeId != bytes32(0)) {
            revert DisputeAlreadyRegistered(disputeId);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        _disputes[disputeId] = LandTypes.DisputeRecord({
            disputeId: disputeId,
            parcelId: parcelId,
            claimant: claimant,
            status: LandTypes.DisputeStatus.Filed,
            evidenceHash: evidenceHash,
            resolutionHash: bytes32(0),
            filedAt: currentTimestamp,
            updatedAt: currentTimestamp
        });

        emit DisputeFiled(disputeId, parcelId, claimant, currentTimestamp);
    }

    /// @inheritdoc ILandRegistry
    function acceptDispute(bytes32 disputeId, bytes32 evidenceHash) external {
        _requireRegistryAuthority(msg.sender);
        LandTypes.DisputeRecord storage disputeRecord = _getDisputeRecord(disputeId);
        if (disputeRecord.status != LandTypes.DisputeStatus.Filed) {
            revert InvalidDisputeStatus(disputeRecord.status);
        }

        LandTypes.ParcelRecord storage parcelRecord = _getParcelRecord(disputeRecord.parcelId);
        if (
            parcelRecord.status != LandTypes.ParcelStatus.Active
                && parcelRecord.status != LandTypes.ParcelStatus.Disputed
        ) {
            revert InvalidParcelStatus(parcelRecord.status);
        }

        disputeRecord.status = LandTypes.DisputeStatus.Accepted;
        if (evidenceHash != bytes32(0)) {
            disputeRecord.evidenceHash = evidenceHash;
        }
        disputeRecord.updatedAt = uint64(block.timestamp);
        _activeDisputeCounts[disputeRecord.parcelId] += 1;

        parcelRecord.status = LandTypes.ParcelStatus.Disputed;
        parcelRecord.updatedAt = disputeRecord.updatedAt;

        emit DisputeStatusUpdated(disputeId, disputeRecord.status, disputeRecord.updatedAt, msg.sender);
        emit ParcelUpdated(disputeRecord.parcelId, parcelRecord.status, parcelRecord.updatedAt, msg.sender);
    }

    /// @inheritdoc ILandRegistry
    function resolveDispute(bytes32 disputeId, bytes32 resolutionHash, bool claimAccepted) external {
        _requireRegistryAuthority(msg.sender);
        LandTypes.DisputeRecord storage disputeRecord = _getDisputeRecord(disputeId);
        if (
            disputeRecord.status != LandTypes.DisputeStatus.Filed
                && disputeRecord.status != LandTypes.DisputeStatus.Accepted
        ) {
            revert InvalidDisputeStatus(disputeRecord.status);
        }
        if (resolutionHash == bytes32(0)) {
            revert InvalidDisputePayload(disputeId);
        }

        bool wasAccepted = disputeRecord.status == LandTypes.DisputeStatus.Accepted;
        disputeRecord.status = claimAccepted ? LandTypes.DisputeStatus.Resolved : LandTypes.DisputeStatus.Dismissed;
        disputeRecord.resolutionHash = resolutionHash;
        disputeRecord.updatedAt = uint64(block.timestamp);

        if (wasAccepted) {
            bytes32 parcelId = disputeRecord.parcelId;
            uint256 remainingDisputes = _activeDisputeCounts[parcelId] - 1;
            _activeDisputeCounts[parcelId] = remainingDisputes;
            LandTypes.ParcelRecord storage parcelRecord = _parcels[parcelId];
            if (remainingDisputes == 0 && parcelRecord.status == LandTypes.ParcelStatus.Disputed) {
                parcelRecord.status = LandTypes.ParcelStatus.Active;
                parcelRecord.updatedAt = disputeRecord.updatedAt;
                emit ParcelUpdated(parcelId, parcelRecord.status, parcelRecord.updatedAt, msg.sender);
            }
        }

        emit DisputeStatusUpdated(disputeId, disputeRecord.status, disputeRecord.updatedAt, msg.sender);
    }

    /// @inheritdoc ILandRegistry
    function registerEncumbrance(bytes32 encumbranceId, bytes32 titleId, bytes32 documentHash) external {
        _requireRegistryAuthority(msg.sender);
        LandTypes.TitleRecord storage titleRecord = _getTitleRecord(titleId);
        if (encumbranceId == bytes32(0) || !titleRecord.active || documentHash == bytes32(0)) {
            revert InvalidEncumbrancePayload(encumbranceId);
        }
        if (_encumbrances[encumbranceId].encumbranceId != bytes32(0)) {
            revert EncumbranceAlreadyRegistered(encumbranceId);
        }
        bytes32 parcelId = titleRecord.parcelId;
        _requireParcelActiveAndNotDisputed(parcelId);

        uint64 currentTimestamp = uint64(block.timestamp);
        _encumbrances[encumbranceId] = LandTypes.EncumbranceRecord({
            encumbranceId: encumbranceId,
            parcelId: parcelId,
            titleId: titleId,
            status: LandTypes.EncumbranceStatus.Active,
            documentHash: documentHash,
            registeredAt: currentTimestamp,
            releasedAt: 0
        });
        _activeEncumbranceCounts[parcelId] += 1;

        emit EncumbranceRegistered(encumbranceId, parcelId, titleId, currentTimestamp);
    }

    /// @inheritdoc ILandRegistry
    function releaseEncumbrance(bytes32 encumbranceId, bytes32 documentHash) external {
        _requireRegistryAuthority(msg.sender);
        LandTypes.EncumbranceRecord storage encumbranceRecord = _encumbrances[encumbranceId];
        if (encumbranceRecord.encumbranceId == bytes32(0)) {
            revert EncumbranceNotFound(encumbranceId);
        }
        if (encumbranceRecord.status != LandTypes.EncumbranceStatus.Active || documentHash == bytes32(0)) {
            revert InvalidEncumbrancePayload(encumbranceId);
        }

        encumbranceRecord.status = LandTypes.EncumbranceStatus.Released;
        encumbranceRecord.documentHash = documentHash;
        encumbranceRecord.releasedAt = uint64(block.timestamp);
        _activeEncumbranceCounts[encumbranceRecord.parcelId] -= 1;

        emit EncumbranceReleased(encumbranceId, encumbranceRecord.parcelId, encumbranceRecord.releasedAt, msg.sender);
    }

    function _validateNewParcel(bytes32 parcelId, LandTypes.ParcelInput calldata input) private view {
        if (parcelId == bytes32(0) || parcelExists(parcelId) || !_isValidParcelInput(input)) {
            revert InvalidParcelPayload(parcelId);
        }
        bytes32 existingParcelId = _parcelByNumberHash[input.parcelNumberHash];
        if (existingParcelId != bytes32(0)) {
            revert ParcelAlreadyRegistered(existingParcelId);
        }
    }

    function _validateExistingParcelUpdate(bytes32 parcelId, LandTypes.ParcelInput calldata input) private view {
        LandTypes.ParcelRecord storage parcelRecord = _parcels[parcelId];
        if (parcelRecord.parcelId == bytes32(0)) {
            revert ParcelNotFound(parcelId);
        }
        if (parcelRecord.status == LandTypes.ParcelStatus.Retired || !_isValidParcelInput(input)) {
            revert InvalidParcelPayload(parcelId);
        }
        bytes32 existingParcelId = _parcelByNumberHash[input.parcelNumberHash];
        if (existingParcelId != bytes32(0) && existingParcelId != parcelId) {
            revert ParcelAlreadyRegistered(existingParcelId);
        }
    }

    function _isValidParcelInput(LandTypes.ParcelInput calldata input) private pure returns (bool valid) {
        return input.parcelNumberHash != bytes32(0) && input.districtHash != bytes32(0)
            && input.metadataHash != bytes32(0) && input.spatialDataHash != bytes32(0)
            && input.documentHash != bytes32(0) && input.spatialType != LandTypes.SpatialType.Undefined;
    }

    function _validateTitleInput(bytes32 titleId, LandTypes.TitleInput calldata input) private view {
        if (
            titleId == bytes32(0) || titleExists(titleId) || input.parcelId == bytes32(0) || input.holder == address(0)
                || input.tenureType == LandTypes.TenureType.Undefined || input.documentHash == bytes32(0)
        ) {
            revert InvalidTitlePayload(titleId);
        }
        if (input.tenureType == LandTypes.TenureType.Leasehold) {
            if (input.leaseExpiresAt == 0 || input.leaseExpiresAt <= block.timestamp) {
                revert InvalidTitlePayload(titleId);
            }
        } else if (input.leaseExpiresAt != 0) {
            revert InvalidTitlePayload(titleId);
        }
    }

    function _requireParcelTransferable(bytes32 parcelId) private view {
        _requireParcelActiveAndNotDisputed(parcelId);
        if (_activeEncumbranceCounts[parcelId] != 0) {
            revert ParcelTransferLocked(parcelId);
        }
    }

    function _requireParcelActiveAndNotDisputed(bytes32 parcelId) private view {
        LandTypes.ParcelRecord storage parcelRecord = _parcels[parcelId];
        if (parcelRecord.status != LandTypes.ParcelStatus.Active) {
            revert InvalidParcelStatus(parcelRecord.status);
        }
        if (_activeDisputeCounts[parcelId] != 0) {
            revert ParcelTransferLocked(parcelId);
        }
    }

    function _getParcelRecord(bytes32 parcelId) private view returns (LandTypes.ParcelRecord storage parcelRecord) {
        parcelRecord = _parcels[parcelId];
        if (parcelRecord.parcelId == bytes32(0)) {
            revert ParcelNotFound(parcelId);
        }
    }

    function _getTitleRecord(bytes32 titleId) private view returns (LandTypes.TitleRecord storage titleRecord) {
        titleRecord = _titles[titleId];
        if (titleRecord.titleId == bytes32(0)) {
            revert TitleNotFound(titleId);
        }
    }

    function _getDisputeRecord(bytes32 disputeId) private view returns (LandTypes.DisputeRecord storage disputeRecord) {
        disputeRecord = _disputes[disputeId];
        if (disputeRecord.disputeId == bytes32(0)) {
            revert DisputeNotFound(disputeId);
        }
    }

    function _requireRegistryAuthority(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY)) {
            revert UnauthorizedLandRegistryCaller(caller);
        }
    }
}
