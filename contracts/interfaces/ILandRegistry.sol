// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IKernelModule} from "./IKernelModule.sol";
import {LandTypes} from "../types/LandTypes.sol";

/// @title ILandRegistry
/// @notice Stable fact registry interface for versioned parcels, titles, disputes, and encumbrances.
interface ILandRegistry is IKernelModule {
    error DisputeAlreadyRegistered(bytes32 disputeId);
    error DisputeNotFound(bytes32 disputeId);
    error EncumbranceAlreadyRegistered(bytes32 encumbranceId);
    error EncumbranceNotFound(bytes32 encumbranceId);
    error InvalidDisputePayload(bytes32 disputeId);
    error InvalidDisputeStatus(LandTypes.DisputeStatus status);
    error InvalidEncumbrancePayload(bytes32 encumbranceId);
    error InvalidLineage(bytes32 expectedLineageHash, bytes32 providedLineageHash);
    error InvalidOperationLength(uint256 length, uint256 maximum);
    error InvalidParcelPayload(bytes32 parcelId);
    error InvalidParcelStatus(LandTypes.ParcelStatus status);
    error InvalidParty(LandTypes.PartyRef party);
    error InvalidRecordAnchor();
    error InvalidTitlePayload(bytes32 titleId);
    error InvalidTransactionId(bytes32 transactionId);
    error MismatchedOperationArrays(uint256 leftLength, uint256 rightLength);
    error ParcelAlreadyRegistered(bytes32 parcelId);
    error ParcelAlreadyTitled(bytes32 parcelId, bytes32 activeTitleId);
    error ParcelNotFound(bytes32 parcelId);
    error ParcelTransferLocked(bytes32 parcelId);
    error SourceParcelDuplicated(bytes32 parcelId);
    error SourceTitlesDiffer(bytes32 firstTitleId, bytes32 otherTitleId);
    error StaleParcelRevision(bytes32 parcelId, uint64 expectedRevision, uint64 actualRevision);
    error StaleTitleVersion(bytes32 titleId, bytes32 expectedVersionHash, bytes32 actualVersionHash);
    error TitleAlreadyRegistered(bytes32 titleId);
    error TitleNotFound(bytes32 titleId);
    error UnauthorizedLandRegistryCaller(address caller);

    event ParcelRegistered(
        bytes32 indexed parcelId, bytes32 indexed parcelNumberHash, uint64 registeredAt, address indexed recordedBy
    );
    event ParcelVersionRecorded(
        bytes32 indexed parcelId,
        uint64 indexed revision,
        bytes32 indexed versionHash,
        bytes32 previousVersionHash,
        bytes32 operationType,
        bytes32 transactionId,
        bytes32 contentHash,
        bytes32 sourceDocumentHash,
        uint64 recordedAt,
        address recordedBy
    );
    event TitleRegistered(
        bytes32 indexed titleId, bytes32 indexed parcelId, bytes32 indexed holderPartyKey, uint64 registeredAt
    );
    event TitleVersionRecorded(
        bytes32 indexed titleId,
        uint64 indexed revision,
        bytes32 indexed versionHash,
        bytes32 previousVersionHash,
        bytes32 operationType,
        bytes32 transactionId,
        bytes32 holderPartyKey,
        bytes32 contentHash,
        bytes32 sourceDocumentHash,
        uint64 recordedAt,
        address recordedBy
    );
    event TitleTransferred(
        bytes32 indexed titleId,
        bytes32 indexed previousHolderPartyKey,
        bytes32 indexed newHolderPartyKey,
        uint64 transferredAt
    );
    event TitleClosed(bytes32 indexed titleId, bytes32 indexed parcelId, uint64 closedAt, address indexed recordedBy);
    event ParcelSubdivided(
        bytes32 indexed parentParcelId, bytes32 indexed transactionId, uint256 childCount, address indexed recordedBy
    );
    event ParcelsMerged(
        bytes32 indexed newParcelId, bytes32 indexed transactionId, uint256 sourceCount, address indexed recordedBy
    );
    event BoundaryAdjusted(
        bytes32 indexed firstParcelId, bytes32 indexed secondParcelId, bytes32 indexed transactionId, address recordedBy
    );
    event DisputeFiled(
        bytes32 indexed disputeId,
        bytes32 indexed parcelId,
        bytes32 indexed claimantPartyKey,
        bytes32 transactionId,
        uint64 filedAt
    );
    event DisputeStatusUpdated(
        bytes32 indexed disputeId,
        LandTypes.DisputeStatus indexed status,
        bytes32 indexed transactionId,
        bytes32 evidenceHash,
        bytes32 resolutionHash,
        uint64 updatedAt,
        address recordedBy
    );
    event EncumbranceRegistered(
        bytes32 indexed encumbranceId,
        bytes32 indexed parcelId,
        bytes32 indexed titleId,
        bytes32 typeCode,
        bytes32 beneficiaryPartyKey,
        uint64 registeredAt
    );
    event EncumbranceReleased(
        bytes32 indexed encumbranceId,
        bytes32 indexed parcelId,
        bytes32 indexed transactionId,
        uint64 releasedAt,
        address recordedBy
    );

    /// @notice Returns the maximum source/child count for one structural parcel operation.
    function MAX_PARCELS_PER_OPERATION() external view returns (uint256 maximum);

    /// @notice Returns the canonical parcel record, or an empty record when absent.
    function getParcel(bytes32 parcelId) external view returns (LandTypes.ParcelRecord memory record);

    /// @notice Returns the canonical title record, or an empty record when absent.
    function getTitle(bytes32 titleId) external view returns (LandTypes.TitleRecord memory record);

    /// @notice Returns the canonical dispute record, or an empty record when absent.
    function getDispute(bytes32 disputeId) external view returns (LandTypes.DisputeRecord memory record);

    /// @notice Returns the canonical encumbrance record, or an empty record when absent.
    function getEncumbrance(bytes32 encumbranceId) external view returns (LandTypes.EncumbranceRecord memory record);

    /// @notice Reports whether a parcel identifier has ever been registered.
    function parcelExists(bytes32 parcelId) external view returns (bool exists);

    /// @notice Reports whether a title identifier has ever been registered.
    function titleExists(bytes32 titleId) external view returns (bool exists);

    /// @notice Returns the active title identifier for a parcel, or zero when untitled.
    function activeTitleOfParcel(bytes32 parcelId) external view returns (bytes32 titleId);

    /// @notice Returns the number of accepted unresolved disputes locking a parcel.
    function activeDisputeCountOf(bytes32 parcelId) external view returns (uint256 count);

    /// @notice Returns the number of unreleased encumbrances locking a parcel.
    function activeEncumbranceCountOf(bytes32 parcelId) external view returns (uint256 count);

    /// @notice Returns the number of parcel identifiers ever registered.
    function totalParcelCount() external view returns (uint256 count);

    /// @notice Returns the parcel identifier at the zero-based enumeration index.
    function parcelIdAt(uint256 index) external view returns (bytes32 parcelId);

    /// @notice Creates a new parcel in draft status.
    function createParcelDraft(bytes32 parcelId, LandTypes.ParcelInput calldata input, bytes32 transactionId) external;

    /// @notice Replaces a parcel draft at its expected revision.
    function updateParcelDraft(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.ParcelInput calldata input,
        bytes32 transactionId
    ) external;
    /// @notice Activates a parcel draft with a final anchored record.
    function activateParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.RecordAnchor calldata finalAnchor,
        bytes32 transactionId
    ) external;
    /// @notice Records a chained revision of an active parcel.
    function reviseParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.ParcelInput calldata input,
        bytes32 transactionId
    ) external;
    /// @notice Retires an untitled and unlocked parcel.
    function retireParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.RecordAnchor calldata retirementAnchor,
        bytes32 transactionId
    ) external;
    /// @notice Registers the initial active title for an active untitled parcel.
    function registerTitle(bytes32 titleId, LandTypes.TitleInput calldata input, bytes32 transactionId) external;

    /// @notice Records an authorized transfer against the expected title version.
    function transferTitle(
        bytes32 titleId,
        bytes32 expectedVersionHash,
        LandTypes.PartyRef calldata newHolder,
        LandTypes.RecordAnchor calldata anchor,
        bytes32 transactionId
    ) external;
    /// @notice Closes an active title through the current registry authority.
    /// @dev The stable registry supports future typed legal workflows; the current app exposes only expired leases.
    function closeTitle(
        bytes32 parcelId,
        bytes32 titleId,
        bytes32 expectedVersionHash,
        LandTypes.RecordAnchor calldata closingAnchor,
        bytes32 transactionId
    ) external;
    /// @notice Atomically retires a parent parcel/title and creates bounded child parcels/titles.
    function subdivideParcel(
        bytes32 parentParcelId,
        uint64 expectedParentRevision,
        LandTypes.SubdivisionChild[] calldata children,
        bytes32 transactionId
    ) external;
    /// @notice Atomically retires compatible source parcels/titles and creates one replacement.
    function mergeParcels(
        bytes32[] calldata sourceParcelIds,
        uint64[] calldata expectedRevisions,
        LandTypes.MergeResult calldata result,
        bytes32 transactionId
    ) external;
    /// @notice Atomically revises exactly two active parcel records.
    function adjustBoundary(
        LandTypes.ParcelRevisionInput calldata first,
        LandTypes.ParcelRevisionInput calldata second,
        bytes32 transactionId
    ) external;

    /// @notice Files an unlocked dispute record for a stable claimant party.
    function fileDispute(
        bytes32 disputeId,
        bytes32 parcelId,
        LandTypes.PartyRef calldata claimant,
        bytes32 evidenceHash,
        bytes32 transactionId
    ) external;
    /// @notice Accepts a dispute and activates its parcel lock.
    function acceptDispute(bytes32 disputeId, bytes32 evidenceHash, bytes32 transactionId) external;

    /// @notice Resolves or dismisses a filed or accepted dispute.
    function resolveDispute(bytes32 disputeId, bytes32 resolutionHash, bool claimAccepted, bytes32 transactionId)
        external;

    /// @notice Registers an active encumbrance against an active title.
    function registerEncumbrance(
        bytes32 encumbranceId,
        LandTypes.EncumbranceInput calldata input,
        bytes32 transactionId
    ) external;
    /// @notice Releases an active encumbrance with a chained record anchor.
    function releaseEncumbrance(
        bytes32 encumbranceId,
        LandTypes.RecordAnchor calldata releaseAnchor,
        bytes32 transactionId
    ) external;
}
