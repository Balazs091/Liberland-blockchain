// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title SenateTypes
/// @notice Shared structs for bounded Senate seat state and negative-control support tracking.
library SenateTypes {
    enum VoteOption {
        Undefined,
        Against,
        For
    }

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
        uint32 presidentProxySupportSnapshot;
        uint64 createdAt;
        uint64 deadline;
        uint64 finalizedAt;
        uint64 canceledAt;
        bool exists;
        bool finalized;
        bool canceled;
    }

    struct ReferendumVetoRecord {
        bytes32 referendumId;
        uint64 createdAt;
        uint64 deadline;
        uint64 finalizedAt;
        uint64 vetoedAt;
        uint32 supportSnapshot;
        uint32 presidentProxySupportSnapshot;
        bool exists;
        bool finalized;
        bool vetoed;
    }

    struct SubLegalMeasureRepealRecord {
        bytes32 measureId;
        bytes32 repealId;
        uint64 attemptNonce;
        uint64 createdAt;
        uint64 deadline;
        uint64 finalizedAt;
        uint64 repealedAt;
        uint32 supportSnapshot;
        uint32 presidentProxySupportSnapshot;
        bool exists;
        bool finalized;
        bool repealed;
    }

    /// @notice Unified per-seat support receipt shared by every Senate negative-control process (action
    ///         cancellation, referendum veto, sub-legal repeal, and disbursement suspension). `attemptNonce` is only
    ///         meaningful for the repeatable sub-legal repeal process; the other processes always leave it zero.
    struct VoteSupport {
        bool supported;
        VoteOption option;
        uint64 attemptNonce;
        uint64 seatOccupancyNonce;
        uint64 updatedAt;
    }

    struct PresidentProxyVote {
        VoteOption option;
        uint64 updatedAt;
    }

    struct DisbursementSuspension {
        bool exists;
        uint64 suspendedUntil;
        uint32 renewalCount;
    }
}
