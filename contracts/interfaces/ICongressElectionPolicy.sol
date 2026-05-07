// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title ICongressElectionPolicy
/// @notice Policy interface for Congress election eligibility, weighting, and bounded cycle configuration.
interface ICongressElectionPolicy {
    /// @notice Returns the configured candidate eligibility policy address.
    /// @return policyAddress The candidate eligibility policy address.
    function candidateEligibilityPolicy() external view returns (address policyAddress);

    /// @notice Returns the configured voting power policy address.
    /// @return policyAddress The voting power policy address.
    function votingPowerPolicy() external view returns (address policyAddress);

    /// @notice Returns the number of Congress seats to award each cycle.
    /// @return seats The configured seat count.
    function seatCount() external view returns (uint32 seats);

    /// @notice Returns the number of runner-up slots to retain each cycle.
    /// @return seats The configured runner-up count.
    function runnerUpCount() external view returns (uint32 seats);

    /// @notice Returns the maximum number of active candidates permitted in one cycle.
    /// @return count The configured candidate cap.
    function maxCandidateCount() external view returns (uint32 count);

    /// @notice Returns the minimum active stake required to stand as a bonded Congress candidate.
    /// @return amount The bonded stake requirement.
    function candidateBondRequirement() external view returns (uint256 amount);

    /// @notice Returns the minimum nomination duration enforced for each election cycle.
    /// @return duration The minimum nomination duration.
    function minimumNominationDuration() external view returns (uint64 duration);

    /// @notice Returns the minimum voting duration enforced for each election cycle.
    /// @return duration The minimum voting duration.
    function minimumVotingDuration() external view returns (uint64 duration);

    /// @notice Returns the maximum lead time permitted between scheduling and voting start.
    /// @return duration The maximum scheduling lead time.
    function maxScheduleLeadTime() external view returns (uint64 duration);

    /// @notice Returns the total recurring election cycle duration.
    /// @return duration The duration between consecutive election end timestamps.
    function cycleDuration() external view returns (uint64 duration);

    /// @notice Returns true when a wallet may stand as a candidate.
    /// @param wallet The wallet to evaluate.
    /// @return eligible Whether the wallet may stand.
    function isEligibleCandidate(address wallet) external view returns (bool eligible);

    /// @notice Returns true when a wallet may cast a weighted Congress ballot.
    /// @param wallet The wallet to evaluate.
    /// @return eligible Whether the wallet may vote.
    function isEligibleVoter(address wallet) external view returns (bool eligible);

    /// @notice Returns the weighted Congress ballot power for a wallet.
    /// @param wallet The wallet to evaluate.
    /// @return weight The configured ballot weight.
    function votingWeight(address wallet) external view returns (uint256 weight);

    /// @notice Returns the maximum number of positively allocated candidates permitted in a ballot.
    /// @return count The maximum number of positive ballot targets.
    function maxPositiveCandidates() external view returns (uint32 count);

    /// @notice Returns the maximum negative allocation allowed for a ballot weight.
    /// @param wallet The wallet to evaluate.
    /// @return amount The maximum absolute negative allocation permitted.
    function maxNegativeAllocation(address wallet) external view returns (uint256 amount);
}
