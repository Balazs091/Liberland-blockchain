// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ICandidateEligibilityPolicy} from "../interfaces/ICandidateEligibilityPolicy.sol";
import {ICongressElectionPolicy} from "../interfaces/ICongressElectionPolicy.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IVotingPowerPolicy} from "../interfaces/IVotingPowerPolicy.sol";

/// @title CongressElectionPolicy
/// @notice Defines bounded Congress election configuration, candidate eligibility, and vote weighting.
contract CongressElectionPolicy is ICongressElectionPolicy {
    error InvalidCandidateCount(uint32 seatCount, uint32 runnerUpCount, uint32 maxCandidateCount);
    error InvalidCandidateBondRequirement(uint256 candidateBondRequirement, uint256 minimumCandidateStake);
    error InvalidCycleDuration(uint64 cycleDuration, uint64 minimumNominationDuration, uint64 minimumVotingDuration);
    error InvalidDuration(uint64 duration);
    error InvalidPolicy(address policyAddress);
    error InvalidScheduleLeadTime(uint64 maxScheduleLeadTime, uint64 minimumNominationDuration);

    uint256 internal constant NEGATIVE_ALLOCATION_DIVISOR = 3;

    ICandidateEligibilityPolicy private immutable _candidateEligibilityPolicy;
    IVotingPowerPolicy private immutable _votingPowerPolicy;

    uint32 private immutable _seatCount;
    uint32 private immutable _runnerUpCount;
    uint32 private immutable _maxCandidateCount;
    uint256 private immutable _candidateBondRequirement;
    uint64 private immutable _minimumNominationDuration;
    uint64 private immutable _minimumVotingDuration;
    uint64 private immutable _maxScheduleLeadTime;
    uint64 private immutable _cycleDuration;

    /// @param candidateEligibilityPolicyAddress The candidate eligibility policy address.
    /// @param votingPowerPolicyAddress The voting power policy address.
    /// @param seatCount_ The number of Congress seats awarded per cycle.
    /// @param runnerUpCount_ The number of runner-up slots retained for vacancy filling.
    /// @param maxCandidateCount_ The maximum number of active candidates permitted in a cycle.
    /// @param candidateBondRequirement_ The minimum active stake required to stand as a bonded candidate.
    /// @param minimumNominationDuration_ The minimum nomination duration enforced for a cycle.
    /// @param minimumVotingDuration_ The minimum voting duration enforced for a cycle.
    /// @param maxScheduleLeadTime_ The maximum permitted lead time between scheduling and voting start.
    /// @param cycleDuration_ The total recurring duration between consecutive election end timestamps.
    constructor(
        address candidateEligibilityPolicyAddress,
        address votingPowerPolicyAddress,
        uint32 seatCount_,
        uint32 runnerUpCount_,
        uint32 maxCandidateCount_,
        uint256 candidateBondRequirement_,
        uint64 minimumNominationDuration_,
        uint64 minimumVotingDuration_,
        uint64 maxScheduleLeadTime_,
        uint64 cycleDuration_
    ) {
        if (candidateEligibilityPolicyAddress == address(0) || candidateEligibilityPolicyAddress.code.length == 0) {
            revert InvalidPolicy(candidateEligibilityPolicyAddress);
        }
        if (votingPowerPolicyAddress == address(0) || votingPowerPolicyAddress.code.length == 0) {
            revert InvalidPolicy(votingPowerPolicyAddress);
        }
        if (
            seatCount_ == 0 || runnerUpCount_ == 0 || maxCandidateCount_ < uint256(seatCount_) + uint256(runnerUpCount_)
        ) {
            revert InvalidCandidateCount(seatCount_, runnerUpCount_, maxCandidateCount_);
        }
        if (
            candidateBondRequirement_
                < ICandidateEligibilityPolicy(candidateEligibilityPolicyAddress).minimumCandidateStake()
        ) {
            revert InvalidCandidateBondRequirement(
                candidateBondRequirement_,
                ICandidateEligibilityPolicy(candidateEligibilityPolicyAddress).minimumCandidateStake()
            );
        }
        if (minimumNominationDuration_ == 0) {
            revert InvalidDuration(minimumNominationDuration_);
        }
        if (minimumVotingDuration_ == 0) {
            revert InvalidDuration(minimumVotingDuration_);
        }
        if (maxScheduleLeadTime_ == 0 || maxScheduleLeadTime_ < minimumNominationDuration_) {
            revert InvalidScheduleLeadTime(maxScheduleLeadTime_, minimumNominationDuration_);
        }
        if (cycleDuration_ < minimumNominationDuration_ + minimumVotingDuration_) {
            revert InvalidCycleDuration(cycleDuration_, minimumNominationDuration_, minimumVotingDuration_);
        }

        _candidateEligibilityPolicy = ICandidateEligibilityPolicy(candidateEligibilityPolicyAddress);
        _votingPowerPolicy = IVotingPowerPolicy(votingPowerPolicyAddress);
        _seatCount = seatCount_;
        _runnerUpCount = runnerUpCount_;
        _maxCandidateCount = maxCandidateCount_;
        _candidateBondRequirement = candidateBondRequirement_;
        _minimumNominationDuration = minimumNominationDuration_;
        _minimumVotingDuration = minimumVotingDuration_;
        _maxScheduleLeadTime = maxScheduleLeadTime_;
        _cycleDuration = cycleDuration_;
    }

    /// @inheritdoc ICongressElectionPolicy
    function candidateEligibilityPolicy() external view returns (address policyAddress) {
        return address(_candidateEligibilityPolicy);
    }

    /// @inheritdoc ICongressElectionPolicy
    function votingPowerPolicy() external view returns (address policyAddress) {
        return address(_votingPowerPolicy);
    }

    /// @inheritdoc ICongressElectionPolicy
    function seatCount() external view returns (uint32 seats) {
        return _seatCount;
    }

    /// @inheritdoc ICongressElectionPolicy
    function runnerUpCount() external view returns (uint32 seats) {
        return _runnerUpCount;
    }

    /// @inheritdoc ICongressElectionPolicy
    function maxCandidateCount() external view returns (uint32 count) {
        return _maxCandidateCount;
    }

    /// @inheritdoc ICongressElectionPolicy
    function candidateBondRequirement() external view returns (uint256 amount) {
        return _candidateBondRequirement;
    }

    /// @inheritdoc ICongressElectionPolicy
    function minimumNominationDuration() external view returns (uint64 duration) {
        return _minimumNominationDuration;
    }

    /// @inheritdoc ICongressElectionPolicy
    function minimumVotingDuration() external view returns (uint64 duration) {
        return _minimumVotingDuration;
    }

    /// @inheritdoc ICongressElectionPolicy
    function maxScheduleLeadTime() external view returns (uint64 duration) {
        return _maxScheduleLeadTime;
    }

    /// @inheritdoc ICongressElectionPolicy
    function cycleDuration() external view returns (uint64 duration) {
        return _cycleDuration;
    }

    /// @inheritdoc ICongressElectionPolicy
    function maxPositiveCandidates() external view returns (uint32 count) {
        return _seatCount;
    }

    /// @inheritdoc ICongressElectionPolicy
    function maxNegativeAllocation(address wallet) external view returns (uint256 amount) {
        return _votingPowerPolicy.votingPower(wallet) / NEGATIVE_ALLOCATION_DIVISOR;
    }

    /// @inheritdoc ICongressElectionPolicy
    function isEligibleCandidate(address wallet) external view returns (bool eligible) {
        if (!_candidateEligibilityPolicy.isEligibleCandidate(wallet)) {
            return false;
        }

        bytes32 personId =
            IIdentityRegistry(_candidateEligibilityPolicy.identityRegistry()).resolveWalletToPersonId(wallet);
        if (personId == bytes32(0)) {
            return false;
        }

        return IStakeRegistry(_candidateEligibilityPolicy.stakeRegistry()).activeStakeOf(personId)
            >= _candidateBondRequirement;
    }

    /// @inheritdoc ICongressElectionPolicy
    function isEligibleVoter(address wallet) external view returns (bool eligible) {
        return _votingPowerPolicy.votingPower(wallet) != 0;
    }

    /// @inheritdoc ICongressElectionPolicy
    function votingWeight(address wallet) external view returns (uint256 weight) {
        return _votingPowerPolicy.votingPower(wallet);
    }
}
