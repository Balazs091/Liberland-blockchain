// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ILandRegistry} from "../interfaces/ILandRegistry.sol";
import {KernelModule} from "../base/KernelModule.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {LandOperationIds} from "../libraries/LandOperationIds.sol";
import {LandTypes} from "../types/LandTypes.sol";

/// @title LandRegistry
/// @notice Stable cadastral facts with content-addressed revisions and bounded atomic parcel operations.
/// @dev Geometry, legal documents, fees, insurance, and adjudication remain outside this state contract. The
///      governed authority app validates those workflows before writing their canonical hashes here.
contract LandRegistry is ILandRegistry, KernelModule {
    uint256 public constant MAX_PARCELS_PER_OPERATION = 16;

    bytes32 private constant _PARCEL_VERSION_TYPEHASH = keccak256(
        "ParcelVersion(uint256 chainId,address registry,bytes32 parcelId,uint64 revision,bytes32 previousVersionHash,bytes32 payloadHash,bytes32 operationType,bytes32 transactionId)"
    );
    bytes32 private constant _TITLE_VERSION_TYPEHASH = keccak256(
        "TitleVersion(uint256 chainId,address registry,bytes32 titleId,uint64 revision,bytes32 previousVersionHash,bytes32 payloadHash,bytes32 operationType,bytes32 transactionId)"
    );

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
    function createParcelDraft(bytes32 parcelId, LandTypes.ParcelInput calldata input, bytes32 transactionId) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        _validateNewParcel(parcelId, input);

        LandTypes.ParcelRecord storage parcelRecord = _createParcelRecord(parcelId, input, LandTypes.ParcelStatus.Draft);
        emit ParcelRegistered(parcelId, input.parcelNumberHash, parcelRecord.createdAt, msg.sender);
        _recordParcelVersion(parcelRecord, LandOperationIds.PARCEL_DRAFT_CREATED, transactionId, parcelRecord.createdAt);
    }

    /// @inheritdoc ILandRegistry
    function updateParcelDraft(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.ParcelInput calldata input,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        LandTypes.ParcelRecord storage parcelRecord = _requireParcelRevision(parcelId, expectedRevision);
        if (parcelRecord.status != LandTypes.ParcelStatus.Draft) {
            revert InvalidParcelStatus(parcelRecord.status);
        }
        _requireLineage(input.anchor.lineageHash, parcelRecord.versionHash);
        _validateExistingParcelUpdate(parcelId, input);
        _writeParcelInput(parcelRecord, input);
        _recordParcelVersion(
            parcelRecord, LandOperationIds.PARCEL_DRAFT_UPDATED, transactionId, uint64(block.timestamp)
        );
    }

    /// @inheritdoc ILandRegistry
    function activateParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.RecordAnchor calldata finalAnchor,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        LandTypes.ParcelRecord storage parcelRecord = _requireParcelRevision(parcelId, expectedRevision);
        if (parcelRecord.status != LandTypes.ParcelStatus.Draft) {
            revert InvalidParcelStatus(parcelRecord.status);
        }
        _validateAnchor(finalAnchor);
        _requireLineage(finalAnchor.lineageHash, parcelRecord.versionHash);

        parcelRecord.anchor = finalAnchor;
        parcelRecord.status = LandTypes.ParcelStatus.Active;
        _recordParcelVersion(parcelRecord, LandOperationIds.PARCEL_ACTIVATED, transactionId, uint64(block.timestamp));
    }

    /// @inheritdoc ILandRegistry
    function reviseParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.ParcelInput calldata input,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        LandTypes.ParcelRecord storage parcelRecord = _requireParcelRevision(parcelId, expectedRevision);
        if (parcelRecord.status != LandTypes.ParcelStatus.Active) {
            revert InvalidParcelStatus(parcelRecord.status);
        }
        _requireLineage(input.anchor.lineageHash, parcelRecord.versionHash);
        _validateExistingParcelUpdate(parcelId, input);
        _writeParcelInput(parcelRecord, input);
        _recordParcelVersion(parcelRecord, LandOperationIds.PARCEL_REVISED, transactionId, uint64(block.timestamp));
    }

    /// @inheritdoc ILandRegistry
    function retireParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.RecordAnchor calldata retirementAnchor,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        LandTypes.ParcelRecord storage parcelRecord = _requireParcelRevision(parcelId, expectedRevision);
        if (parcelRecord.status == LandTypes.ParcelStatus.Retired) {
            revert InvalidParcelStatus(parcelRecord.status);
        }
        if (_activeTitleOfParcel[parcelId] != bytes32(0)) {
            revert InvalidParcelPayload(parcelId);
        }
        _requireParcelUnlocked(parcelId);
        _validateAnchor(retirementAnchor);
        _requireLineage(retirementAnchor.lineageHash, parcelRecord.versionHash);

        parcelRecord.anchor = retirementAnchor;
        parcelRecord.status = LandTypes.ParcelStatus.Retired;
        _recordParcelVersion(parcelRecord, LandOperationIds.PARCEL_RETIRED, transactionId, uint64(block.timestamp));
    }

    /// @inheritdoc ILandRegistry
    function registerTitle(bytes32 titleId, LandTypes.TitleInput calldata input, bytes32 transactionId) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        _validateNewTitle(titleId, input);
        LandTypes.ParcelRecord storage parcelRecord = _getParcelRecord(input.parcelId);
        if (parcelRecord.status != LandTypes.ParcelStatus.Active) {
            revert InvalidParcelStatus(parcelRecord.status);
        }
        _requireLineage(input.anchor.lineageHash, parcelRecord.versionHash);

        LandTypes.TitleRecord storage titleRecord = _createTitleRecord(titleId, input, uint64(block.timestamp));
        emit TitleRegistered(titleId, input.parcelId, _partyKey(input.holder), titleRecord.registeredAt);
        _recordTitleVersion(titleRecord, LandOperationIds.TITLE_REGISTERED, transactionId, titleRecord.registeredAt);
    }

    /// @inheritdoc ILandRegistry
    function transferTitle(
        bytes32 titleId,
        bytes32 expectedVersionHash,
        LandTypes.PartyRef calldata newHolder,
        LandTypes.RecordAnchor calldata anchor,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        LandTypes.TitleRecord storage titleRecord = _requireTitleVersion(titleId, expectedVersionHash);
        if (!titleRecord.active) {
            revert InvalidTitlePayload(titleId);
        }
        _validateParty(newHolder);
        _validateAnchor(anchor);
        _requireLineage(anchor.lineageHash, titleRecord.versionHash);
        _requireLeaseCurrent(titleRecord);
        _requireParcelTransferable(titleRecord.parcelId);

        bytes32 previousHolderPartyKey = _partyKey(titleRecord.holder);
        titleRecord.holder = newHolder;
        titleRecord.anchor = anchor;
        uint64 currentTimestamp = uint64(block.timestamp);
        _recordTitleVersion(titleRecord, LandOperationIds.TITLE_TRANSFERRED, transactionId, currentTimestamp);

        emit TitleTransferred(titleId, previousHolderPartyKey, _partyKey(newHolder), currentTimestamp);
    }

    /// @inheritdoc ILandRegistry
    function closeTitle(
        bytes32 parcelId,
        bytes32 titleId,
        bytes32 expectedVersionHash,
        LandTypes.RecordAnchor calldata closingAnchor,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        LandTypes.TitleRecord storage titleRecord = _requireTitleVersion(titleId, expectedVersionHash);
        if (!titleRecord.active || titleRecord.parcelId != parcelId) {
            revert InvalidTitlePayload(titleId);
        }
        _requireParcelUnlocked(parcelId);
        _validateAnchor(closingAnchor);
        _requireLineage(closingAnchor.lineageHash, titleRecord.versionHash);

        titleRecord.anchor = closingAnchor;
        _closeTitleRecord(titleRecord, LandOperationIds.TITLE_CLOSED, transactionId, uint64(block.timestamp));
    }

    /// @inheritdoc ILandRegistry
    function subdivideParcel(
        bytes32 parentParcelId,
        uint64 expectedParentRevision,
        LandTypes.SubdivisionChild[] calldata children,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        uint256 childCount = children.length;
        _requireOperationLength(childCount, 2);

        LandTypes.ParcelRecord storage parent = _requireParcelRevision(parentParcelId, expectedParentRevision);
        _requireParcelActive(parent);
        _requireParcelUnlocked(parentParcelId);
        LandTypes.TitleRecord storage parentTitle = _getActiveTitle(parentParcelId);
        _requireLeaseCurrent(parentTitle);

        _validateSubdivisionChildren(children, parent.versionHash, parentTitle.versionHash);

        uint64 currentTimestamp = uint64(block.timestamp);
        _closeTitleRecord(parentTitle, LandOperationIds.PARCEL_SUBDIVIDED, transactionId, currentTimestamp);
        parent.status = LandTypes.ParcelStatus.Retired;
        _recordParcelVersion(parent, LandOperationIds.PARCEL_SUBDIVIDED, transactionId, currentTimestamp);

        for (uint256 index = 0; index < childCount; ++index) {
            LandTypes.SubdivisionChild calldata child = children[index];
            LandTypes.ParcelRecord storage childParcel =
                _createParcelRecord(child.parcelId, child.parcel, LandTypes.ParcelStatus.Active);
            LandTypes.TitleInput memory childTitleInput = LandTypes.TitleInput({
                parcelId: child.parcelId,
                holder: parentTitle.holder,
                anchor: child.titleAnchor,
                tenureType: parentTitle.tenureType,
                leaseExpiresAt: parentTitle.leaseExpiresAt
            });
            LandTypes.TitleRecord storage childTitle =
                _createTitleRecordFromMemory(child.titleId, childTitleInput, currentTimestamp);

            emit ParcelRegistered(child.parcelId, child.parcel.parcelNumberHash, currentTimestamp, msg.sender);
            _recordParcelVersion(childParcel, LandOperationIds.PARCEL_SUBDIVIDED, transactionId, currentTimestamp);
            emit TitleRegistered(child.titleId, child.parcelId, _partyKey(parentTitle.holder), currentTimestamp);
            _recordTitleVersion(childTitle, LandOperationIds.PARCEL_SUBDIVIDED, transactionId, currentTimestamp);
        }

        emit ParcelSubdivided(parentParcelId, transactionId, childCount, msg.sender);
    }

    /// @inheritdoc ILandRegistry
    function mergeParcels(
        bytes32[] calldata sourceParcelIds,
        uint64[] calldata expectedRevisions,
        LandTypes.MergeResult calldata result,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        uint256 sourceCount = sourceParcelIds.length;
        _requireOperationLength(sourceCount, 2);
        if (sourceCount != expectedRevisions.length) {
            revert MismatchedOperationArrays(sourceCount, expectedRevisions.length);
        }

        _validateNewParcel(result.parcelId, result.parcel);
        if (result.titleId == bytes32(0) || titleExists(result.titleId)) {
            revert InvalidTitlePayload(result.titleId);
        }
        _validateAnchor(result.titleAnchor);

        (LandTypes.PartyRef memory holder, LandTypes.TenureType tenureType, uint64 leaseExpiresAt) =
            _validateMergeSources(sourceParcelIds, expectedRevisions, result);

        uint64 currentTimestamp = uint64(block.timestamp);
        for (uint256 index = 0; index < sourceCount; ++index) {
            LandTypes.ParcelRecord storage sourceParcel = _parcels[sourceParcelIds[index]];
            LandTypes.TitleRecord storage sourceTitle = _getActiveTitle(sourceParcelIds[index]);
            _closeTitleRecord(sourceTitle, LandOperationIds.PARCELS_MERGED, transactionId, currentTimestamp);
            sourceParcel.status = LandTypes.ParcelStatus.Retired;
            _recordParcelVersion(sourceParcel, LandOperationIds.PARCELS_MERGED, transactionId, currentTimestamp);
        }

        LandTypes.ParcelRecord storage mergedParcel =
            _createParcelRecord(result.parcelId, result.parcel, LandTypes.ParcelStatus.Active);
        LandTypes.TitleInput memory mergedTitleInput = LandTypes.TitleInput({
            parcelId: result.parcelId,
            holder: holder,
            anchor: result.titleAnchor,
            tenureType: tenureType,
            leaseExpiresAt: leaseExpiresAt
        });
        LandTypes.TitleRecord storage mergedTitle =
            _createTitleRecordFromMemory(result.titleId, mergedTitleInput, currentTimestamp);

        emit ParcelRegistered(result.parcelId, result.parcel.parcelNumberHash, currentTimestamp, msg.sender);
        _recordParcelVersion(mergedParcel, LandOperationIds.PARCELS_MERGED, transactionId, currentTimestamp);
        emit TitleRegistered(result.titleId, result.parcelId, _partyKey(holder), currentTimestamp);
        _recordTitleVersion(mergedTitle, LandOperationIds.PARCELS_MERGED, transactionId, currentTimestamp);
        emit ParcelsMerged(result.parcelId, transactionId, sourceCount, msg.sender);
    }

    /// @inheritdoc ILandRegistry
    function adjustBoundary(
        LandTypes.ParcelRevisionInput calldata first,
        LandTypes.ParcelRevisionInput calldata second,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        if (first.parcelId == second.parcelId) {
            revert SourceParcelDuplicated(first.parcelId);
        }

        LandTypes.ParcelRecord storage firstRecord = _requireParcelRevision(first.parcelId, first.expectedRevision);
        LandTypes.ParcelRecord storage secondRecord = _requireParcelRevision(second.parcelId, second.expectedRevision);
        _requireParcelActive(firstRecord);
        _requireParcelActive(secondRecord);
        _requireParcelUnlocked(first.parcelId);
        _requireParcelUnlocked(second.parcelId);
        _validateBoundaryRevision(firstRecord, first.parcel);
        _validateBoundaryRevision(secondRecord, second.parcel);

        uint64 currentTimestamp = uint64(block.timestamp);
        _writeParcelInput(firstRecord, first.parcel);
        _writeParcelInput(secondRecord, second.parcel);
        _recordParcelVersion(firstRecord, LandOperationIds.BOUNDARY_ADJUSTED, transactionId, currentTimestamp);
        _recordParcelVersion(secondRecord, LandOperationIds.BOUNDARY_ADJUSTED, transactionId, currentTimestamp);
        emit BoundaryAdjusted(first.parcelId, second.parcelId, transactionId, msg.sender);
    }

    /// @inheritdoc ILandRegistry
    function fileDispute(
        bytes32 disputeId,
        bytes32 parcelId,
        LandTypes.PartyRef calldata claimant,
        bytes32 evidenceHash,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        _validateParty(claimant);
        if (disputeId == bytes32(0) || !parcelExists(parcelId) || evidenceHash == bytes32(0)) {
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
            transactionId: transactionId,
            filedAt: currentTimestamp,
            updatedAt: currentTimestamp
        });

        emit DisputeFiled(disputeId, parcelId, _partyKey(claimant), transactionId, currentTimestamp);
    }

    /// @inheritdoc ILandRegistry
    function acceptDispute(bytes32 disputeId, bytes32 evidenceHash, bytes32 transactionId) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
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
        disputeRecord.transactionId = transactionId;
        disputeRecord.updatedAt = uint64(block.timestamp);
        _activeDisputeCounts[disputeRecord.parcelId] += 1;

        parcelRecord.status = LandTypes.ParcelStatus.Disputed;
        _recordParcelVersion(parcelRecord, LandOperationIds.DISPUTE_ACCEPTED, transactionId, disputeRecord.updatedAt);

        emit DisputeStatusUpdated(
            disputeId,
            disputeRecord.status,
            transactionId,
            disputeRecord.evidenceHash,
            bytes32(0),
            disputeRecord.updatedAt,
            msg.sender
        );
    }

    /// @inheritdoc ILandRegistry
    function resolveDispute(bytes32 disputeId, bytes32 resolutionHash, bool claimAccepted, bytes32 transactionId)
        external
    {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
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
        disputeRecord.transactionId = transactionId;
        disputeRecord.updatedAt = uint64(block.timestamp);

        if (wasAccepted) {
            bytes32 parcelId = disputeRecord.parcelId;
            uint256 remainingDisputes = _activeDisputeCounts[parcelId] - 1;
            _activeDisputeCounts[parcelId] = remainingDisputes;
            LandTypes.ParcelRecord storage parcelRecord = _parcels[parcelId];
            if (remainingDisputes == 0 && parcelRecord.status == LandTypes.ParcelStatus.Disputed) {
                parcelRecord.status = LandTypes.ParcelStatus.Active;
                _recordParcelVersion(
                    parcelRecord, LandOperationIds.DISPUTE_RESOLVED, transactionId, disputeRecord.updatedAt
                );
            }
        }

        emit DisputeStatusUpdated(
            disputeId,
            disputeRecord.status,
            transactionId,
            disputeRecord.evidenceHash,
            resolutionHash,
            disputeRecord.updatedAt,
            msg.sender
        );
    }

    /// @inheritdoc ILandRegistry
    function registerEncumbrance(
        bytes32 encumbranceId,
        LandTypes.EncumbranceInput calldata input,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        LandTypes.TitleRecord storage titleRecord = _getTitleRecord(input.titleId);
        if (
            encumbranceId == bytes32(0) || !titleRecord.active || input.typeCode == bytes32(0)
                || !_isValidAnchor(input.anchor) || (input.validUntil != 0 && input.validUntil <= block.timestamp)
                || !_isValidOptionalParty(input.beneficiary)
        ) {
            revert InvalidEncumbrancePayload(encumbranceId);
        }
        if (_encumbrances[encumbranceId].encumbranceId != bytes32(0)) {
            revert EncumbranceAlreadyRegistered(encumbranceId);
        }
        _requireLineage(input.anchor.lineageHash, titleRecord.versionHash);
        bytes32 parcelId = titleRecord.parcelId;
        _requireParcelActiveAndNotDisputed(parcelId);

        uint64 currentTimestamp = uint64(block.timestamp);
        _encumbrances[encumbranceId] = LandTypes.EncumbranceRecord({
            encumbranceId: encumbranceId,
            parcelId: parcelId,
            titleId: input.titleId,
            typeCode: input.typeCode,
            beneficiary: input.beneficiary,
            anchor: input.anchor,
            status: LandTypes.EncumbranceStatus.Active,
            validUntil: input.validUntil,
            registeredAt: currentTimestamp,
            releasedAt: 0
        });
        _activeEncumbranceCounts[parcelId] += 1;

        emit EncumbranceRegistered(
            encumbranceId,
            parcelId,
            input.titleId,
            input.typeCode,
            _optionalPartyKey(input.beneficiary),
            transactionId,
            currentTimestamp
        );
    }

    /// @inheritdoc ILandRegistry
    function releaseEncumbrance(
        bytes32 encumbranceId,
        LandTypes.RecordAnchor calldata releaseAnchor,
        bytes32 transactionId
    ) external {
        _requireRegistryAuthority(msg.sender);
        _requireTransactionId(transactionId);
        LandTypes.EncumbranceRecord storage encumbranceRecord = _encumbrances[encumbranceId];
        if (encumbranceRecord.encumbranceId == bytes32(0)) {
            revert EncumbranceNotFound(encumbranceId);
        }
        if (encumbranceRecord.status != LandTypes.EncumbranceStatus.Active || !_isValidAnchor(releaseAnchor)) {
            revert InvalidEncumbrancePayload(encumbranceId);
        }
        _requireLineage(releaseAnchor.lineageHash, encumbranceRecord.anchor.contentHash);

        encumbranceRecord.status = LandTypes.EncumbranceStatus.Released;
        encumbranceRecord.anchor = releaseAnchor;
        encumbranceRecord.releasedAt = uint64(block.timestamp);
        _activeEncumbranceCounts[encumbranceRecord.parcelId] -= 1;

        emit EncumbranceReleased(
            encumbranceId, encumbranceRecord.parcelId, transactionId, encumbranceRecord.releasedAt, msg.sender
        );
    }

    function _validateSubdivisionChildren(
        LandTypes.SubdivisionChild[] calldata children,
        bytes32 parentParcelVersion,
        bytes32 parentTitleVersion
    ) private view {
        uint256 childCount = children.length;
        for (uint256 index = 0; index < childCount; ++index) {
            LandTypes.SubdivisionChild calldata child = children[index];
            _validateNewParcel(child.parcelId, child.parcel);
            if (child.titleId == bytes32(0) || titleExists(child.titleId)) {
                revert InvalidTitlePayload(child.titleId);
            }
            _validateAnchor(child.titleAnchor);
            _requireLineage(child.parcel.anchor.lineageHash, parentParcelVersion);
            _requireLineage(child.titleAnchor.lineageHash, parentTitleVersion);
            for (uint256 prior = 0; prior < index; ++prior) {
                if (children[prior].parcelId == child.parcelId) {
                    revert SourceParcelDuplicated(child.parcelId);
                }
                if (children[prior].titleId == child.titleId) {
                    revert InvalidTitlePayload(child.titleId);
                }
                if (children[prior].parcel.parcelNumberHash == child.parcel.parcelNumberHash) {
                    revert ParcelAlreadyRegistered(child.parcelId);
                }
            }
        }
    }

    function _validateMergeSources(
        bytes32[] calldata sourceParcelIds,
        uint64[] calldata expectedRevisions,
        LandTypes.MergeResult calldata result
    ) private view returns (LandTypes.PartyRef memory holder, LandTypes.TenureType tenureType, uint64 leaseExpiresAt) {
        uint256 sourceCount = sourceParcelIds.length;
        bytes32[] memory parcelVersions = new bytes32[](sourceCount);
        bytes32[] memory titleVersions = new bytes32[](sourceCount);
        bytes32 firstTitleId = bytes32(0);

        for (uint256 index = 0; index < sourceCount; ++index) {
            bytes32 parcelId = sourceParcelIds[index];
            for (uint256 prior = 0; prior < index; ++prior) {
                if (sourceParcelIds[prior] == parcelId) {
                    revert SourceParcelDuplicated(parcelId);
                }
            }

            LandTypes.ParcelRecord storage parcelRecord = _requireParcelRevision(parcelId, expectedRevisions[index]);
            _requireParcelActive(parcelRecord);
            _requireParcelUnlocked(parcelId);
            LandTypes.TitleRecord storage titleRecord = _getActiveTitle(parcelId);
            _requireLeaseCurrent(titleRecord);

            if (index == 0) {
                holder = titleRecord.holder;
                tenureType = titleRecord.tenureType;
                leaseExpiresAt = titleRecord.leaseExpiresAt;
                firstTitleId = titleRecord.titleId;
            } else if (
                !_sameParty(holder, titleRecord.holder) || tenureType != titleRecord.tenureType
                    || leaseExpiresAt != titleRecord.leaseExpiresAt
            ) {
                revert SourceTitlesDiffer(firstTitleId, titleRecord.titleId);
            }
            parcelVersions[index] = parcelRecord.versionHash;
            titleVersions[index] = titleRecord.versionHash;
        }

        _requireLineage(result.parcel.anchor.lineageHash, keccak256(abi.encode(parcelVersions)));
        _requireLineage(result.titleAnchor.lineageHash, keccak256(abi.encode(titleVersions)));
    }

    function _validateBoundaryRevision(
        LandTypes.ParcelRecord storage parcelRecord,
        LandTypes.ParcelInput calldata input
    ) private view {
        if (
            parcelRecord.parcelNumberHash != input.parcelNumberHash || parcelRecord.districtHash != input.districtHash
                || !_isValidParcelInput(input)
        ) {
            revert InvalidParcelPayload(parcelRecord.parcelId);
        }
        _requireLineage(input.anchor.lineageHash, parcelRecord.versionHash);
    }

    function _createParcelRecord(bytes32 parcelId, LandTypes.ParcelInput calldata input, LandTypes.ParcelStatus status)
        private
        returns (LandTypes.ParcelRecord storage parcelRecord)
    {
        uint64 currentTimestamp = uint64(block.timestamp);
        parcelRecord = _parcels[parcelId];
        parcelRecord.parcelId = parcelId;
        parcelRecord.status = status;
        parcelRecord.createdAt = currentTimestamp;
        parcelRecord.updatedAt = currentTimestamp;
        _writeParcelInput(parcelRecord, input);
        _parcelByNumberHash[input.parcelNumberHash] = parcelId;
        _parcelIds.push(parcelId);
    }

    function _createTitleRecord(bytes32 titleId, LandTypes.TitleInput calldata input, uint64 currentTimestamp)
        private
        returns (LandTypes.TitleRecord storage titleRecord)
    {
        titleRecord = _titles[titleId];
        titleRecord.titleId = titleId;
        titleRecord.parcelId = input.parcelId;
        titleRecord.holder = input.holder;
        titleRecord.anchor = input.anchor;
        titleRecord.tenureType = input.tenureType;
        titleRecord.leaseExpiresAt = input.leaseExpiresAt;
        titleRecord.active = true;
        titleRecord.registeredAt = currentTimestamp;
        titleRecord.updatedAt = currentTimestamp;
        _activeTitleOfParcel[input.parcelId] = titleId;
    }

    function _createTitleRecordFromMemory(bytes32 titleId, LandTypes.TitleInput memory input, uint64 currentTimestamp)
        private
        returns (LandTypes.TitleRecord storage titleRecord)
    {
        titleRecord = _titles[titleId];
        titleRecord.titleId = titleId;
        titleRecord.parcelId = input.parcelId;
        titleRecord.holder = input.holder;
        titleRecord.anchor = input.anchor;
        titleRecord.tenureType = input.tenureType;
        titleRecord.leaseExpiresAt = input.leaseExpiresAt;
        titleRecord.active = true;
        titleRecord.registeredAt = currentTimestamp;
        titleRecord.updatedAt = currentTimestamp;
        _activeTitleOfParcel[input.parcelId] = titleId;
    }

    function _closeTitleRecord(
        LandTypes.TitleRecord storage titleRecord,
        bytes32 operationType,
        bytes32 transactionId,
        uint64 currentTimestamp
    ) private {
        titleRecord.active = false;
        if (_activeTitleOfParcel[titleRecord.parcelId] == titleRecord.titleId) {
            delete _activeTitleOfParcel[titleRecord.parcelId];
        }
        _recordTitleVersion(titleRecord, operationType, transactionId, currentTimestamp);
        emit TitleClosed(titleRecord.titleId, titleRecord.parcelId, currentTimestamp, msg.sender);
    }

    function _writeParcelInput(LandTypes.ParcelRecord storage parcelRecord, LandTypes.ParcelInput calldata input)
        private
    {
        if (parcelRecord.parcelNumberHash != input.parcelNumberHash) {
            delete _parcelByNumberHash[parcelRecord.parcelNumberHash];
            _parcelByNumberHash[input.parcelNumberHash] = parcelRecord.parcelId;
        }
        parcelRecord.parcelNumberHash = input.parcelNumberHash;
        parcelRecord.districtHash = input.districtHash;
        parcelRecord.anchor = input.anchor;
        parcelRecord.spatialDataHash = input.spatialDataHash;
        parcelRecord.coordinateReferenceSystemHash = input.coordinateReferenceSystemHash;
        parcelRecord.spatialType = input.spatialType;
        parcelRecord.areaSquareMeters = input.areaSquareMeters;
    }

    function _recordParcelVersion(
        LandTypes.ParcelRecord storage parcelRecord,
        bytes32 operationType,
        bytes32 transactionId,
        uint64 recordedAt
    ) private {
        bytes32 previousVersionHash = parcelRecord.versionHash;
        uint64 revision = parcelRecord.revision + 1;
        bytes32 payloadHash = _parcelPayloadHash(parcelRecord);
        bytes32 versionHash = keccak256(
            abi.encode(
                _PARCEL_VERSION_TYPEHASH,
                block.chainid,
                address(this),
                parcelRecord.parcelId,
                revision,
                previousVersionHash,
                payloadHash,
                operationType,
                transactionId
            )
        );
        parcelRecord.revision = revision;
        parcelRecord.versionHash = versionHash;
        parcelRecord.lastTransactionId = transactionId;
        parcelRecord.updatedAt = recordedAt;

        _emitParcelVersion(parcelRecord, previousVersionHash, operationType, transactionId, recordedAt);
    }

    function _recordTitleVersion(
        LandTypes.TitleRecord storage titleRecord,
        bytes32 operationType,
        bytes32 transactionId,
        uint64 recordedAt
    ) private {
        bytes32 previousVersionHash = titleRecord.versionHash;
        uint64 revision = titleRecord.revision + 1;
        bytes32 payloadHash = _titlePayloadHash(titleRecord);
        bytes32 versionHash = keccak256(
            abi.encode(
                _TITLE_VERSION_TYPEHASH,
                block.chainid,
                address(this),
                titleRecord.titleId,
                revision,
                previousVersionHash,
                payloadHash,
                operationType,
                transactionId
            )
        );
        titleRecord.revision = revision;
        titleRecord.versionHash = versionHash;
        titleRecord.lastTransactionId = transactionId;
        titleRecord.updatedAt = recordedAt;

        _emitTitleVersion(titleRecord, previousVersionHash, operationType, transactionId, recordedAt);
    }

    function _emitParcelVersion(
        LandTypes.ParcelRecord storage parcelRecord,
        bytes32 previousVersionHash,
        bytes32 operationType,
        bytes32 transactionId,
        uint64 recordedAt
    ) private {
        emit ParcelVersionRecorded(
            parcelRecord.parcelId,
            parcelRecord.revision,
            parcelRecord.versionHash,
            previousVersionHash,
            operationType,
            transactionId,
            parcelRecord.anchor.contentHash,
            parcelRecord.anchor.sourceDocumentHash,
            recordedAt,
            msg.sender
        );
    }

    function _emitTitleVersion(
        LandTypes.TitleRecord storage titleRecord,
        bytes32 previousVersionHash,
        bytes32 operationType,
        bytes32 transactionId,
        uint64 recordedAt
    ) private {
        emit TitleVersionRecorded(
            titleRecord.titleId,
            titleRecord.revision,
            titleRecord.versionHash,
            previousVersionHash,
            operationType,
            transactionId,
            _partyKey(titleRecord.holder),
            titleRecord.anchor.contentHash,
            titleRecord.anchor.sourceDocumentHash,
            recordedAt,
            msg.sender
        );
    }

    function _parcelPayloadHash(LandTypes.ParcelRecord storage parcelRecord) private view returns (bytes32 hash) {
        return keccak256(
            abi.encode(
                parcelRecord.parcelNumberHash,
                parcelRecord.districtHash,
                _anchorHash(parcelRecord.anchor),
                parcelRecord.spatialDataHash,
                parcelRecord.coordinateReferenceSystemHash,
                parcelRecord.spatialType,
                parcelRecord.status,
                parcelRecord.areaSquareMeters
            )
        );
    }

    function _titlePayloadHash(LandTypes.TitleRecord storage titleRecord) private view returns (bytes32 hash) {
        return keccak256(
            abi.encode(
                titleRecord.parcelId,
                _partyKey(titleRecord.holder),
                _anchorHash(titleRecord.anchor),
                titleRecord.tenureType,
                titleRecord.leaseExpiresAt,
                titleRecord.active
            )
        );
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
        if (!_isValidParcelInput(input)) {
            revert InvalidParcelPayload(parcelId);
        }
        bytes32 existingParcelId = _parcelByNumberHash[input.parcelNumberHash];
        if (existingParcelId != bytes32(0) && existingParcelId != parcelId) {
            revert ParcelAlreadyRegistered(existingParcelId);
        }
    }

    function _isValidParcelInput(LandTypes.ParcelInput calldata input) private pure returns (bool valid) {
        return input.parcelNumberHash != bytes32(0) && input.districtHash != bytes32(0) && _isValidAnchor(input.anchor)
            && input.spatialDataHash != bytes32(0) && input.coordinateReferenceSystemHash != bytes32(0)
            && input.spatialType != LandTypes.SpatialType.Undefined && input.areaSquareMeters != 0;
    }

    function _validateNewTitle(bytes32 titleId, LandTypes.TitleInput calldata input) private view {
        if (
            titleId == bytes32(0) || titleExists(titleId) || input.parcelId == bytes32(0)
                || !_isValidParty(input.holder) || !_isValidAnchor(input.anchor)
                || input.tenureType == LandTypes.TenureType.Undefined
        ) {
            revert InvalidTitlePayload(titleId);
        }
        bytes32 activeTitleId = _activeTitleOfParcel[input.parcelId];
        if (activeTitleId != bytes32(0)) {
            revert ParcelAlreadyTitled(input.parcelId, activeTitleId);
        }
        _validateLease(input.tenureType, input.leaseExpiresAt, titleId);
    }

    function _validateLease(LandTypes.TenureType tenureType, uint64 leaseExpiresAt, bytes32 titleId) private view {
        if (tenureType == LandTypes.TenureType.Leasehold) {
            if (leaseExpiresAt == 0 || leaseExpiresAt <= block.timestamp) {
                revert InvalidTitlePayload(titleId);
            }
        } else if (leaseExpiresAt != 0) {
            revert InvalidTitlePayload(titleId);
        }
    }

    function _requireLeaseCurrent(LandTypes.TitleRecord storage titleRecord) private view {
        if (titleRecord.tenureType == LandTypes.TenureType.Leasehold && titleRecord.leaseExpiresAt <= block.timestamp) {
            revert InvalidTitlePayload(titleRecord.titleId);
        }
    }

    function _validateAnchor(LandTypes.RecordAnchor calldata anchor) private pure {
        if (!_isValidAnchor(anchor)) {
            revert InvalidRecordAnchor();
        }
    }

    function _isValidAnchor(LandTypes.RecordAnchor calldata anchor) private pure returns (bool valid) {
        return anchor.schemaId != bytes32(0) && anchor.schemaVersion != 0 && anchor.contentHash != bytes32(0)
            && anchor.sourceDocumentHash != bytes32(0) && anchor.lineageHash != bytes32(0);
    }

    function _anchorHash(LandTypes.RecordAnchor storage anchor) private view returns (bytes32 hash) {
        return keccak256(
            abi.encode(
                anchor.schemaId, anchor.schemaVersion, anchor.contentHash, anchor.sourceDocumentHash, anchor.lineageHash
            )
        );
    }

    function _requireLineage(bytes32 providedLineageHash, bytes32 expectedLineageHash) private pure {
        if (providedLineageHash != expectedLineageHash) {
            revert InvalidLineage(expectedLineageHash, providedLineageHash);
        }
    }

    function _validateParty(LandTypes.PartyRef calldata party) private pure {
        if (!_isValidParty(party)) {
            revert InvalidParty(party);
        }
    }

    function _isValidParty(LandTypes.PartyRef calldata party) private pure returns (bool valid) {
        return party.namespace != bytes32(0) && party.id != bytes32(0);
    }

    function _isValidOptionalParty(LandTypes.PartyRef calldata party) private pure returns (bool valid) {
        return (party.namespace == bytes32(0)) == (party.id == bytes32(0));
    }

    function _partyKey(LandTypes.PartyRef memory party) private pure returns (bytes32 key) {
        return keccak256(abi.encode(party.namespace, party.id));
    }

    function _optionalPartyKey(LandTypes.PartyRef memory party) private pure returns (bytes32 key) {
        if (party.namespace == bytes32(0) && party.id == bytes32(0)) {
            return bytes32(0);
        }
        return _partyKey(party);
    }

    function _sameParty(LandTypes.PartyRef memory first, LandTypes.PartyRef storage second)
        private
        view
        returns (bool same)
    {
        return first.namespace == second.namespace && first.id == second.id;
    }

    function _requireTransactionId(bytes32 transactionId) private pure {
        if (transactionId == bytes32(0)) {
            revert InvalidTransactionId(transactionId);
        }
    }

    function _requireOperationLength(uint256 length, uint256 minimum) private pure {
        if (length < minimum || length > MAX_PARCELS_PER_OPERATION) {
            revert InvalidOperationLength(length, MAX_PARCELS_PER_OPERATION);
        }
    }

    function _requireParcelRevision(bytes32 parcelId, uint64 expectedRevision)
        private
        view
        returns (LandTypes.ParcelRecord storage parcelRecord)
    {
        parcelRecord = _getParcelRecord(parcelId);
        if (parcelRecord.revision != expectedRevision) {
            revert StaleParcelRevision(parcelId, expectedRevision, parcelRecord.revision);
        }
    }

    function _requireTitleVersion(bytes32 titleId, bytes32 expectedVersionHash)
        private
        view
        returns (LandTypes.TitleRecord storage titleRecord)
    {
        titleRecord = _getTitleRecord(titleId);
        if (titleRecord.versionHash != expectedVersionHash) {
            revert StaleTitleVersion(titleId, expectedVersionHash, titleRecord.versionHash);
        }
    }

    function _requireParcelTransferable(bytes32 parcelId) private view {
        _requireParcelActiveAndNotDisputed(parcelId);
        if (_activeEncumbranceCounts[parcelId] != 0) {
            revert ParcelTransferLocked(parcelId);
        }
    }

    function _requireParcelUnlocked(bytes32 parcelId) private view {
        if (_activeDisputeCounts[parcelId] != 0 || _activeEncumbranceCounts[parcelId] != 0) {
            revert ParcelTransferLocked(parcelId);
        }
    }

    function _requireParcelActiveAndNotDisputed(bytes32 parcelId) private view {
        LandTypes.ParcelRecord storage parcelRecord = _getParcelRecord(parcelId);
        _requireParcelActive(parcelRecord);
        if (_activeDisputeCounts[parcelId] != 0) {
            revert ParcelTransferLocked(parcelId);
        }
    }

    function _requireParcelActive(LandTypes.ParcelRecord storage parcelRecord) private view {
        if (parcelRecord.status != LandTypes.ParcelStatus.Active) {
            revert InvalidParcelStatus(parcelRecord.status);
        }
    }

    function _getActiveTitle(bytes32 parcelId) private view returns (LandTypes.TitleRecord storage titleRecord) {
        bytes32 titleId = _activeTitleOfParcel[parcelId];
        if (titleId == bytes32(0)) {
            revert InvalidParcelPayload(parcelId);
        }
        titleRecord = _getTitleRecord(titleId);
        if (!titleRecord.active) {
            revert InvalidTitlePayload(titleId);
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
