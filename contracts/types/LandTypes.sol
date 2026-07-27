// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title LandTypes
/// @notice Shared enums and structs for the land registry domain.
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

    struct ParcelInput {
        bytes32 parcelNumberHash;
        bytes32 districtHash;
        bytes32 metadataHash;
        bytes32 spatialDataHash;
        bytes32 documentHash;
        SpatialType spatialType;
        uint64 areaSquareMeters;
    }

    struct ParcelRecord {
        bytes32 parcelId;
        bytes32 parcelNumberHash;
        bytes32 districtHash;
        bytes32 metadataHash;
        bytes32 spatialDataHash;
        bytes32 documentHash;
        SpatialType spatialType;
        ParcelStatus status;
        uint64 areaSquareMeters;
        uint64 createdAt;
        uint64 updatedAt;
    }

    struct TitleInput {
        bytes32 parcelId;
        address holder;
        TenureType tenureType;
        uint64 leaseExpiresAt;
        bytes32 documentHash;
    }

    struct TitleRecord {
        bytes32 titleId;
        bytes32 parcelId;
        address holder;
        TenureType tenureType;
        uint64 leaseExpiresAt;
        bytes32 documentHash;
        bool active;
        uint64 registeredAt;
        uint64 updatedAt;
    }

    struct DisputeRecord {
        bytes32 disputeId;
        bytes32 parcelId;
        address claimant;
        DisputeStatus status;
        bytes32 evidenceHash;
        bytes32 resolutionHash;
        uint64 filedAt;
        uint64 updatedAt;
    }

    struct EncumbranceRecord {
        bytes32 encumbranceId;
        bytes32 parcelId;
        bytes32 titleId;
        bytes32 documentHash;
        // `status` packs into the trailing timestamp slot.
        EncumbranceStatus status;
        uint64 registeredAt;
        uint64 releasedAt;
    }
}
