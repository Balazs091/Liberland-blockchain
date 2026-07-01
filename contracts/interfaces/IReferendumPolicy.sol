// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ReferendumTypes} from "../types/ReferendumTypes.sol";

/// @title IReferendumPolicy
/// @notice Policy interface for referendum creation rules, fees, quorum, and pass conditions.
interface IReferendumPolicy {
    /// @notice Returns the configured citizen eligibility policy address.
    /// @return policyAddress The citizen eligibility policy address.
    function citizenEligibilityPolicy() external view returns (address policyAddress);

    /// @notice Returns the configured voting power policy address.
    /// @return policyAddress The voting power policy address.
    function votingPowerPolicy() external view returns (address policyAddress);

    /// @notice Returns the configured temporary Congress proposal authority address.
    /// @return authority The proposal authority address.
    function congressProposalAuthority() external view returns (address authority);

    /// @notice Returns the minimum active stake required for a citizen-origin referendum proposal.
    /// @return amount The bonded stake requirement.
    function citizenProposalBondRequirement() external view returns (uint256 amount);

    /// @notice Returns the minimum referendum voting duration enforced by policy.
    /// @return duration The minimum allowed voting duration.
    function minimumVotingDuration() external view returns (uint64 duration);

    /// @notice Returns the shorter minimum voting duration allowed for Congress-origin emergency measures.
    /// @return duration The minimum emergency voting duration.
    function emergencyVotingDuration() external view returns (uint64 duration);

    /// @notice Returns the standard post-vote adoption review delay.
    /// @return duration The standard adoption delay.
    function standardAdoptionDelay() external view returns (uint64 duration);

    /// @notice Returns the maximum post-vote adoption review delay a proposal may request.
    /// @return duration The maximum adoption delay.
    function maximumAdoptionDelay() external view returns (uint64 duration);

    /// @notice Returns the configured proposal fee for a proposal origin.
    /// @param proposalOrigin The proposal origin to query.
    /// @return feeAmount The configured proposal fee amount.
    function proposalFee(ReferendumTypes.ProposalOrigin proposalOrigin) external view returns (uint256 feeAmount);

    /// @notice Returns whether the proposer may create a referendum for the given class and origin.
    /// @param referendumClass The referendum class to create.
    /// @param proposalOrigin The proposal origin to validate.
    /// @param proposer The proposing caller address.
    /// @return allowed Whether the proposal path is currently valid.
    function canCreateReferendum(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        address proposer
    ) external view returns (bool allowed);

    /// @notice Evaluates the referendum outcome from final tallies using the configured pass rules.
    /// @param referendumClass The referendum class being finalized.
    /// @param proposalOrigin The proposal origin used to create the referendum.
    /// @param forVotes The total voting power recorded in favor.
    /// @param againstVotes The total voting power recorded against.
    /// @param forVoterCount The number of voters currently recorded in favor.
    /// @param againstVoterCount The number of voters currently recorded against.
    /// @param electorateHeadcountSnapshot The eligible electorate headcount stored when the referendum was created.
    /// @param electorateVotingPowerSnapshot The eligible electorate voting power stored when the referendum was created.
    /// @param requiresSupermajority Whether the referendum must clear the constitutional double-threshold pass rule.
    /// @return outcome The evaluated turnout, quorum, and pass outcome.
    function evaluateOutcome(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 forVoterCount,
        uint256 againstVoterCount,
        uint256 electorateHeadcountSnapshot,
        uint256 electorateVotingPowerSnapshot,
        bool requiresSupermajority
    ) external view returns (ReferendumTypes.PolicyOutcome memory outcome);
}
