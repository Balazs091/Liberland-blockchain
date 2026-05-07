// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ElectionTypes} from "../types/ElectionTypes.sol";

/// @title ICongressCandidateRegistry
/// @notice Stable fact registry for Congress election cycles, candidates, votes, and active seat occupancy.
interface ICongressCandidateRegistry {
    error DuplicateBallotCandidate(uint256 cycleId, address voter, address candidate);
    error CandidateAlreadyExists(uint256 cycleId, address candidate);
    error CandidateNotActive(uint256 cycleId, address candidate);
    error CandidateNotFound(uint256 cycleId, address candidate);
    error ElectionCycleAlreadyExists(uint256 cycleId);
    error ElectionCycleAlreadyFinalized(uint256 cycleId);
    error ElectionCycleNotFound(uint256 cycleId);
    error InvalidApplicationHash(bytes32 applicationHash);
    error InvalidCandidate(address candidate);
    error InvalidCandidateCount(uint256 candidateCount, uint256 maxCandidateCount);
    error InvalidCycleId(uint256 cycleId);
    error InvalidFinalizationShape(uint256 rankedCandidateCount, uint256 rankedVoteCount);
    error InvalidNegativeAllocation(uint256 negativeAllocationTotal, uint256 maxNegativeAllocation);
    error InvalidOutcomeCount(uint32 electedCount, uint32 runnerUpCount, uint256 candidateCount);
    error InvalidPersonId(bytes32 personId);
    error InvalidPolicyReference(bytes32 policyReference);
    error InvalidPositiveCandidateCount(uint256 positiveCandidateCount, uint256 maxPositiveCandidates);
    error InvalidRunnerUpCount(uint32 runnerUpCount);
    error InvalidSeatCount(uint32 seatCount);
    error InvalidSeatIndex(uint32 seatIndex);
    error InvalidSignedAllocation(address candidate, int256 allocation);
    error InvalidTotalAllocation(uint256 totalAllocation, uint256 ballotWeight);
    error InvalidVoteSnapshot(uint256 cycleId, address candidate, int256 providedVoteTotal, int256 expectedVoteTotal);
    error InvalidVoter(address voter);
    error InvalidVotingWeight(address voter, uint256 weight);
    error InvalidVotingWindow(uint64 nominationStart, uint64 votingStart, uint64 votingEnd);
    error NotActiveCongressMember(address wallet);
    error UnauthorizedCongressCandidateRegistryCaller(address caller);
    error UnexpectedCycleId(uint256 expectedCycleId, uint256 providedCycleId);
    error VoteNotFound(uint256 cycleId, address voter);

    event CongressElectionCycleCreated(
        uint256 indexed cycleId,
        uint64 nominationStart,
        uint64 votingStart,
        uint64 votingEnd,
        uint32 seatCount,
        uint32 runnerUpCount,
        uint32 maxCandidateCount,
        bytes32 policyReference,
        address indexed createdBy
    );

    event CongressCandidateRegistered(
        uint256 indexed cycleId,
        address indexed candidate,
        bytes32 indexed personId,
        bytes32 applicationHash,
        string applicationURI,
        uint64 appliedAt,
        address registeredBy
    );

    event CongressCandidateWithdrawn(
        uint256 indexed cycleId, address indexed candidate, uint64 withdrawnAt, address indexed withdrawnBy
    );

    event CongressBallotRecorded(
        uint256 indexed cycleId,
        address indexed voter,
        uint256 ballotWeight,
        uint256 positiveAllocationTotal,
        uint256 negativeAllocationTotal,
        uint32 allocationCount,
        uint64 updatedAt,
        address recordedBy
    );

    event CongressBallotAllocationRecorded(
        uint256 indexed cycleId,
        address indexed voter,
        address indexed candidate,
        int256 allocation,
        int256 candidateVoteTotal,
        uint64 updatedAt,
        address recordedBy
    );

    event CongressBallotCleared(
        uint256 indexed cycleId,
        address indexed voter,
        uint256 ballotWeight,
        uint64 clearedAt,
        address indexed clearedBy
    );

    event CongressCandidateRanked(
        uint256 indexed cycleId,
        address indexed candidate,
        ElectionTypes.CandidateStatus status,
        uint32 rank,
        int256 voteTotal,
        uint64 updatedAt,
        address indexed updatedBy
    );

    event CongressElectionCycleFinalized(
        uint256 indexed cycleId,
        uint32 electedCount,
        uint32 runnerUpCount,
        uint64 finalizedAt,
        address indexed finalizedBy
    );

    event CongressSeatAssigned(
        uint256 indexed cycleId,
        uint32 indexed seatIndex,
        address indexed holder,
        uint32 sourceRank,
        bool filledFromRunnerUp,
        uint64 assignedAt,
        address assignedBy
    );

    event CongressSeatVacated(
        uint256 indexed cycleId,
        uint32 indexed seatIndex,
        address indexed previousHolder,
        uint64 vacatedAt,
        address vacatedBy
    );

    event CongressSeatLeftVacant(
        uint256 indexed cycleId, uint32 indexed seatIndex, uint64 vacatedAt, address indexed handledBy
    );

    /// @notice Returns the kernel used for narrow write authorization.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress);

    /// @notice Returns the latest sequential election cycle identifier created in the registry.
    /// @return cycleId The latest stored cycle identifier, or zero when none exists.
    function latestCycleId() external view returns (uint256 cycleId);

    /// @notice Returns the stored cycle record for a Congress election cycle.
    /// @param cycleId The cycle identifier to query.
    /// @return record The stored cycle record, or an empty record if unset.
    function getCycle(uint256 cycleId) external view returns (ElectionTypes.CongressCycleRecord memory record);

    /// @notice Returns the stored candidate record for a wallet within a cycle.
    /// @param cycleId The cycle identifier to query.
    /// @param candidate The candidate wallet to query.
    /// @return record The stored candidate record, or an empty record if unset.
    function getCandidate(uint256 cycleId, address candidate)
        external
        view
        returns (ElectionTypes.CongressCandidateRecord memory record);

    /// @notice Returns the stored signed ballot receipt for a voter within a cycle.
    /// @param cycleId The cycle identifier to query.
    /// @param voter The voter wallet to query.
    /// @return receipt The stored ballot receipt, or an empty receipt if unset.
    function getBallotReceipt(uint256 cycleId, address voter)
        external
        view
        returns (ElectionTypes.BallotReceipt memory receipt);

    /// @notice Returns the number of signed ballot allocations recorded for a voter in a cycle.
    /// @param cycleId The cycle identifier to query.
    /// @param voter The voter wallet to query.
    /// @return count The number of ballot allocations stored.
    function getBallotAllocationCount(uint256 cycleId, address voter) external view returns (uint256 count);

    /// @notice Returns a signed ballot allocation recorded for a voter in a cycle.
    /// @param cycleId The cycle identifier to query.
    /// @param voter The voter wallet to query.
    /// @param index The allocation index to query.
    /// @return allocation The stored signed ballot allocation.
    function getBallotAllocationAt(uint256 cycleId, address voter, uint256 index)
        external
        view
        returns (ElectionTypes.BallotAllocation memory allocation);

    /// @notice Returns the currently active Congress office term snapshot.
    /// @return term The current office term snapshot.
    function getCurrentOfficeTerm() external view returns (ElectionTypes.CongressOfficeTerm memory term);

    /// @notice Returns the stored seat record for a current Congress seat index.
    /// @param seatIndex The seat index to query.
    /// @return seatRecord The stored seat record, or an empty record if the seat is currently unoccupied.
    function getSeatRecord(uint32 seatIndex) external view returns (ElectionTypes.CongressSeatRecord memory seatRecord);

    /// @notice Returns the number of currently active candidates stored for a cycle.
    /// @param cycleId The cycle identifier to query.
    /// @return count The number of active candidates.
    function getCycleCandidateCount(uint256 cycleId) external view returns (uint256 count);

    /// @notice Returns the candidate wallet stored at an index within the active cycle candidate list.
    /// @param cycleId The cycle identifier to query.
    /// @param index The active candidate list index.
    /// @return candidate The candidate wallet stored at the index.
    function getCycleCandidateAt(uint256 cycleId, uint256 index) external view returns (address candidate);

    /// @notice Returns the number of elected candidates stored for a finalized cycle.
    /// @param cycleId The cycle identifier to query.
    /// @return count The number of elected candidates.
    function getElectedCandidateCount(uint256 cycleId) external view returns (uint256 count);

    /// @notice Returns the elected candidate stored at an index for a finalized cycle.
    /// @param cycleId The cycle identifier to query.
    /// @param index The elected candidate index.
    /// @return candidate The elected candidate wallet.
    function getElectedCandidateAt(uint256 cycleId, uint256 index) external view returns (address candidate);

    /// @notice Returns the number of runner-up candidates stored for a finalized cycle.
    /// @param cycleId The cycle identifier to query.
    /// @return count The number of runner-up candidates.
    function getRunnerUpCount(uint256 cycleId) external view returns (uint256 count);

    /// @notice Returns the runner-up candidate stored at an index for a finalized cycle.
    /// @param cycleId The cycle identifier to query.
    /// @param index The runner-up index.
    /// @return candidate The runner-up candidate wallet.
    function getRunnerUpAt(uint256 cycleId, uint256 index) external view returns (address candidate);

    /// @notice Returns true when a cycle record exists.
    /// @param cycleId The cycle identifier to query.
    /// @return exists Whether the cycle exists.
    function cycleExists(uint256 cycleId) external view returns (bool exists);

    /// @notice Returns true when a wallet currently occupies a Congress seat.
    /// @param wallet The wallet to query.
    /// @return active Whether the wallet currently occupies a seat.
    function isActiveCongressMember(address wallet) external view returns (bool active);

    /// @notice Stores a newly created Congress election cycle record.
    /// @param cycleId The sequential cycle identifier to create.
    /// @param cycleInput The cycle schedule and bounded configuration snapshot to store.
    function createCycle(uint256 cycleId, ElectionTypes.CongressCycleInput calldata cycleInput) external;

    /// @notice Stores a candidate application and activates the candidate for the cycle.
    /// @param cycleId The cycle identifier to update.
    /// @param candidate The candidate wallet.
    /// @param personId The resolved person identifier linked to the candidate wallet.
    /// @param applicationHash The off-chain application metadata hash.
    /// @param applicationURI The off-chain application metadata URI.
    function registerCandidate(
        uint256 cycleId,
        address candidate,
        bytes32 personId,
        bytes32 applicationHash,
        string calldata applicationURI
    ) external;

    /// @notice Withdraws an active candidate from a cycle before voting begins.
    /// @param cycleId The cycle identifier to update.
    /// @param candidate The candidate wallet to withdraw.
    function withdrawCandidate(uint256 cycleId, address candidate) external;

    /// @notice Stores or replaces a voter's full signed ballot in a cycle.
    /// @param cycleId The cycle identifier to update.
    /// @param voter The voting wallet.
    /// @param candidates The candidate wallets referenced by the ballot.
    /// @param allocations The signed ballot allocations to apply.
    /// @param ballotWeight The voting power backing the ballot.
    /// @param maxPositiveCandidates The positive-allocation cap enforced by policy.
    /// @param maxNegativeAllocation The maximum total absolute negative allocation allowed by policy.
    function recordBallot(
        uint256 cycleId,
        address voter,
        address[] calldata candidates,
        int256[] calldata allocations,
        uint256 ballotWeight,
        uint32 maxPositiveCandidates,
        uint256 maxNegativeAllocation
    ) external;

    /// @notice Clears a voter's full signed ballot from a cycle.
    /// @param cycleId The cycle identifier to update.
    /// @param voter The voting wallet.
    function clearBallot(uint256 cycleId, address voter) external;

    /// @notice Stores the finalized ranking, elected cohort, runner-up cohort, and active seat occupancy for a cycle.
    /// @param cycleId The cycle identifier to finalize.
    /// @param finalizationInput The sorted candidate ranking and cohort counts to store.
    function finalizeCycle(uint256 cycleId, ElectionTypes.CongressFinalizationInput calldata finalizationInput) external;

    /// @notice Vacates an occupied Congress seat and immediately fills it from the next runner-up when available.
    /// @param vacatingMember The current seat holder leaving office.
    /// @return seatIndex The vacated seat index.
    /// @return replacementCandidate The runner-up promoted into the seat, or zero if no runner-up remains.
    function vacateAndFillSeat(address vacatingMember) external returns (uint32 seatIndex, address replacementCandidate);
}
