// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title SenateTypes
/// @notice Shared structs for bounded Senate seat state and negative-control support tracking.
library SenateTypes {
    struct SenateSeatRecord {
        uint32 seatIndex;
        address holder;
        bytes32 holderPersonId;
        address nominatedSuccessor;
        bytes32 nominatedSuccessorPersonId;
        uint32 transferCount;
        uint64 occupancyNonce;
        uint64 assignedAt;
        uint64 vacatedAt;
        uint64 successorNominatedAt;
        bool vacant;
    }

    struct ActionCancellationRecord {
        bytes32 actionId;
        uint32 supportSnapshot;
        uint64 createdAt;
        uint64 canceledAt;
        bool exists;
        bool canceled;
    }

    struct ActionCancellationSupport {
        bool supported;
        uint64 seatOccupancyNonce;
        uint64 updatedAt;
    }
}
