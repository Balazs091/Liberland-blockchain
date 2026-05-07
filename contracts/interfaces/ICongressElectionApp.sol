// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title ICongressElectionApp
/// @notice User-facing interface for Congress election scheduling, candidacy, voting, finalization, and vacancies.
interface ICongressElectionApp {
    error ActiveCycleExists(uint256 cycleId);
    error CandidateRegistrationClosed(uint256 cycleId, uint64 nominationStart, uint64 votingStart, uint64 currentTime);
    error ElectionNotEnded(uint256 cycleId, uint64 votingEnd, uint64 currentTime);
    error InvalidBallotLength(uint256 candidateCount, uint256 allocationCount);
    error InvalidPolicy(address policyAddress);
    error InvalidRegistry(address registryAddress);
    error InvalidElectionWindow(uint64 nominationStart, uint64 votingStart, uint64 votingEnd);
    error InvalidRecurringElectionWindow(
        uint64 nominationStart,
        uint64 votingStart,
        uint64 votingEnd,
        uint64 expectedNominationStart,
        uint64 expectedVotingStart,
        uint64 expectedVotingEnd
    );
    error InvalidScheduleLead(uint64 votingStart, uint64 latestVotingStart);
    error NoVotingPower(address voter);
    error NotActiveCongressMember(address wallet);
    error NotEligibleCandidate(address candidate);
    error UnknownCandidateReference(address candidate);
    error VotingClosed(uint256 cycleId, uint64 votingStart, uint64 votingEnd, uint64 currentTime);

    /// @notice Returns the configured identity registry address.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured Congress candidate registry address.
    /// @return registryAddress The Congress candidate registry address.
    function congressCandidateRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured candidate eligibility policy address.
    /// @return policyAddress The candidate eligibility policy address.
    function candidateEligibilityPolicy() external view returns (address policyAddress);

    /// @notice Returns the configured Congress election policy address.
    /// @return policyAddress The Congress election policy address.
    function congressElectionPolicy() external view returns (address policyAddress);

    /// @notice Returns the configured voting power policy address used by the Congress election policy.
    /// @return policyAddress The voting power policy address.
    function votingPowerPolicy() external view returns (address policyAddress);

    /// @notice Returns the currently active Congress office cycle identifier, or zero when no term is active.
    /// @return cycleId The currently active Congress office cycle identifier.
    function currentCongressCycleId() external view returns (uint256 cycleId);

    /// @notice Returns true when a wallet currently occupies a Congress seat.
    /// @param wallet The wallet to evaluate.
    /// @return active Whether the wallet currently occupies a seat.
    function isCongressMember(address wallet) external view returns (bool active);

    /// @notice Creates the next sequential Congress election cycle using the policy's bounded configuration.
    /// @param nominationStart The nomination window start time.
    /// @param votingStart The voting window start time.
    /// @param votingEnd The voting window end time.
    /// @return cycleId The created cycle identifier.
    function createElectionCycle(uint64 nominationStart, uint64 votingStart, uint64 votingEnd)
        external
        returns (uint256 cycleId);

    /// @notice Creates the next recurring Congress election cycle using the policy-defined cadence.
    /// @return cycleId The created cycle identifier.
    function createNextElectionCycle() external returns (uint256 cycleId);

    /// @notice Previews the next recurring Congress election window under the current policy.
    /// @return nominationStart The deterministic nomination start timestamp.
    /// @return votingStart The deterministic voting start timestamp.
    /// @return votingEnd The deterministic voting end timestamp.
    function previewNextElectionWindow()
        external
        view
        returns (uint64 nominationStart, uint64 votingStart, uint64 votingEnd);

    /// @notice Applies the caller as a candidate for a cycle.
    /// @param cycleId The cycle identifier to join.
    /// @param applicationHash The off-chain application metadata hash.
    /// @param applicationURI The off-chain application metadata URI.
    function applyAsCandidate(uint256 cycleId, bytes32 applicationHash, string calldata applicationURI) external;

    /// @notice Withdraws the caller's candidacy from a cycle before voting starts.
    /// @param cycleId The cycle identifier to update.
    function withdrawCandidacy(uint256 cycleId) external;

    /// @notice Casts or replaces the caller's full signed ballot in a cycle.
    /// @param cycleId The cycle identifier to vote in.
    /// @param candidates The candidate wallets referenced by the ballot allocations.
    /// @param allocations The signed ballot allocations for each candidate.
    function castBallot(uint256 cycleId, address[] calldata candidates, int256[] calldata allocations) external;

    /// @notice Clears the caller's full ballot from an active cycle.
    /// @param cycleId The cycle identifier to update.
    function clearBallot(uint256 cycleId) external;

    /// @notice Finalizes a completed election cycle and stores the ranked outcome.
    /// @param cycleId The cycle identifier to finalize.
    function finalizeElection(uint256 cycleId) external;

    /// @notice Vacates the caller's current seat and promotes the next runner-up when available.
    /// @return seatIndex The vacated seat index.
    /// @return replacementCandidate The promoted runner-up, or zero if none remains.
    function resignSeat() external returns (uint32 seatIndex, address replacementCandidate);
}
