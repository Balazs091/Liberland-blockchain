// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title ElectionTypes
/// @notice Shared enums and structs for election cycles, candidacies, and results.
library ElectionTypes {
    enum ElectionType {
        Undefined,
        CongressGeneral,
        CongressSpecial,
        SenateSuccession
    }

    enum ElectionStatus {
        Undefined,
        Scheduled,
        CandidateRegistration,
        Voting,
        Finalized,
        Canceled
    }

    enum CandidateStatus {
        Undefined,
        Applied,
        Accepted,
        Rejected,
        Withdrawn,
        Elected,
        RunnerUp,
        Disqualified,
        Lost
    }

    enum BallotType {
        Undefined,
        SingleChoice,
        Approval,
        RankedChoice
    }

    struct ElectionCycle {
        uint256 cycleId;
        ElectionType electionType;
        ElectionStatus status;
        BallotType ballotType;
        uint64 nominationStart;
        uint64 votingStart;
        uint64 votingEnd;
        uint32 seats;
        bytes32 policyReference;
    }

    struct CandidateRecord {
        uint256 cycleId;
        address candidate;
        CandidateStatus status;
        bytes32 applicationHash;
        string applicationURI;
        uint64 appliedAt;
    }

    struct ElectionResult {
        uint256 cycleId;
        address candidate;
        uint256 votes;
        uint32 rank;
    }

    struct CongressCycleInput {
        uint64 nominationStart;
        uint64 votingStart;
        uint64 votingEnd;
        uint48 votingPowerSnapshotBlock;
        uint32 seatCount;
        uint32 runnerUpCount;
        uint32 maxCandidateCount;
        address policy;
        bytes32 policyReference;
    }

    struct CongressCycleRecord {
        uint256 cycleId;
        ElectionStatus status;
        uint64 nominationStart;
        uint64 votingStart;
        uint64 votingEnd;
        uint64 finalizedAt;
        uint48 votingPowerSnapshotBlock;
        uint32 seatCount;
        uint32 runnerUpCount;
        uint32 maxCandidateCount;
        uint32 candidateCount;
        uint32 electedCount;
        uint32 runnerUpSlotCount;
        address policy;
        bytes32 policyReference;
    }

    struct CongressCandidateRecord {
        uint256 cycleId;
        address candidate;
        bytes32 personId;
        CandidateStatus status;
        bytes32 applicationHash;
        string applicationURI;
        uint64 appliedAt;
        uint64 updatedAt;
        int256 voteTotal;
        uint32 rank;
    }

    struct BallotAllocation {
        address candidate;
        int256 amount;
    }

    struct BallotReceipt {
        uint256 cycleId;
        address voter;
        uint256 ballotWeight;
        uint256 positiveAllocationTotal;
        uint256 negativeAllocationTotal;
        uint32 allocationCount;
        uint64 updatedAt;
    }

    /// @notice Authority-supplied identity and policy limits for storing one Congress ballot.
    struct CongressBallotInput {
        uint256 cycleId;
        bytes32 voterPersonId;
        address voter;
        uint256 ballotWeight;
        uint32 maxPositiveCandidates;
        uint256 maxNegativeAllocation;
    }

    struct CongressFinalizationInput {
        address[] rankedCandidates;
        int256[] rankedVoteTotals;
        uint32 electedCount;
        uint32 runnerUpCount;
    }

    struct CongressOfficeTerm {
        uint256 cycleId;
        uint32 seatCount;
        uint32 occupiedSeatCount;
        uint32 runnerUpCount;
        uint32 nextRunnerUpIndex;
        uint64 activatedAt;
        uint64 updatedAt;
    }

    struct CongressSeatRecord {
        uint256 cycleId;
        address holder;
        bytes32 holderPersonId;
        uint32 seatIndex;
        uint32 sourceRank;
        bool filledFromRunnerUp;
        uint64 assignedAt;
        uint64 vacatedAt;
    }
}
