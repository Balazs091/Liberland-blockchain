// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title LandOperationIds
/// @notice Stable operation identifiers emitted by cadastral version events.
library LandOperationIds {
    bytes32 internal constant PARCEL_DRAFT_CREATED = keccak256("land.parcel-draft-created");
    bytes32 internal constant PARCEL_DRAFT_UPDATED = keccak256("land.parcel-draft-updated");
    bytes32 internal constant PARCEL_ACTIVATED = keccak256("land.parcel-activated");
    bytes32 internal constant PARCEL_REVISED = keccak256("land.parcel-revised");
    bytes32 internal constant PARCEL_RETIRED = keccak256("land.parcel-retired");
    bytes32 internal constant TITLE_REGISTERED = keccak256("land.title-registered");
    bytes32 internal constant TITLE_TRANSFERRED = keccak256("land.title-transferred");
    bytes32 internal constant TITLE_CLOSED = keccak256("land.title-closed");
    bytes32 internal constant PARCEL_SUBDIVIDED = keccak256("land.parcel-subdivided");
    bytes32 internal constant PARCELS_MERGED = keccak256("land.parcels-merged");
    bytes32 internal constant BOUNDARY_ADJUSTED = keccak256("land.boundary-adjusted");
    bytes32 internal constant DISPUTE_ACCEPTED = keccak256("land.dispute-accepted");
    bytes32 internal constant DISPUTE_RESOLVED = keccak256("land.dispute-resolved");
}
