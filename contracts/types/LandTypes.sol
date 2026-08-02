// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title LandTypes
/// @notice Shared value types for cadastral facts and typed land workflows.
library LandTypes {
    enum ParcelStatus {
        Undefined,
        Draft,
        Active,
        Disputed,
        Retired
    }

    enum SpatialType {
        Undefined,
        Polygon,
        BoundingBox,
        PointRadius,
        Text
    }

    enum TenureType {
        Undefined,
        Freehold,
        Leasehold,
        Customary,
        Provisional,
        Communal
    }

    enum DisputeStatus {
        Undefined,
        Filed,
        Accepted,
        Resolved,
        Dismissed
    }

    enum EncumbranceStatus {
        Undefined,
        Active,
        Released
    }

    /// @notice Stable reference to a person, company, public office, or a future party namespace.
    /// @dev The namespace keeps title state extensible without reducing legal ownership to a wallet address.
    struct PartyRef {
        bytes32 namespace;
        bytes32 id;
    }

    /// @notice Content-addressed reference to a versioned off-chain legal or geospatial record.
    /// @dev Large documents and geometry stay off-chain; their canonical form and lineage are anchored here.
    struct RecordAnchor {
        bytes32 schemaId;
        bytes32 contentHash;
        bytes32 sourceDocumentHash;
        bytes32 lineageHash;
        uint32 schemaVersion;
    }

    struct ParcelInput {
        bytes32 parcelNumberHash;
        bytes32 districtHash;
        RecordAnchor anchor;
        bytes32 spatialDataHash;
        bytes32 coordinateReferenceSystemHash;
        SpatialType spatialType;
        uint64 areaSquareMeters;
    }

    struct ParcelRecord {
        bytes32 parcelId;
        bytes32 parcelNumberHash;
        bytes32 districtHash;
        RecordAnchor anchor;
        bytes32 spatialDataHash;
        bytes32 coordinateReferenceSystemHash;
        bytes32 versionHash;
        bytes32 lastTransactionId;
        SpatialType spatialType;
        ParcelStatus status;
        uint64 areaSquareMeters;
        uint64 revision;
        uint64 createdAt;
        uint64 updatedAt;
    }

    struct TitleInput {
        bytes32 parcelId;
        PartyRef holder;
        RecordAnchor anchor;
        TenureType tenureType;
        uint64 leaseExpiresAt;
    }

    struct TitleRecord {
        bytes32 titleId;
        bytes32 parcelId;
        PartyRef holder;
        RecordAnchor anchor;
        bytes32 versionHash;
        bytes32 lastTransactionId;
        TenureType tenureType;
        bool active;
        uint64 leaseExpiresAt;
        uint64 revision;
        uint64 registeredAt;
        uint64 updatedAt;
    }

    /// @notice Fully bound transfer intent signed by the current and prospective title parties.
    struct TitleTransferRequest {
        bytes32 titleId;
        bytes32 expectedVersionHash;
        PartyRef newHolder;
        RecordAnchor anchor;
        bytes32 transactionId;
        uint256 nonce;
        uint64 deadline;
    }

    /// @notice One child parcel and title created by an atomic subdivision.
    struct SubdivisionChild {
        bytes32 parcelId;
        bytes32 titleId;
        ParcelInput parcel;
        RecordAnchor titleAnchor;
    }

    /// @notice The single parcel and title created by an atomic merge.
    struct MergeResult {
        bytes32 parcelId;
        bytes32 titleId;
        ParcelInput parcel;
        RecordAnchor titleAnchor;
    }

    /// @notice Expected revision and replacement data for one side of a boundary adjustment.
    struct ParcelRevisionInput {
        bytes32 parcelId;
        uint64 expectedRevision;
        ParcelInput parcel;
    }

    struct DisputeRecord {
        bytes32 disputeId;
        bytes32 parcelId;
        PartyRef claimant;
        DisputeStatus status;
        bytes32 evidenceHash;
        bytes32 resolutionHash;
        bytes32 transactionId;
        uint64 filedAt;
        uint64 updatedAt;
    }

    struct EncumbranceInput {
        bytes32 titleId;
        bytes32 typeCode;
        PartyRef beneficiary;
        RecordAnchor anchor;
        uint64 validUntil;
    }

    struct EncumbranceRecord {
        bytes32 encumbranceId;
        bytes32 parcelId;
        bytes32 titleId;
        bytes32 typeCode;
        PartyRef beneficiary;
        RecordAnchor anchor;
        EncumbranceStatus status;
        uint64 validUntil;
        uint64 registeredAt;
        uint64 releasedAt;
    }
}
