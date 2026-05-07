// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ReferendumTypes} from "../types/ReferendumTypes.sol";

/// @title IReferendumApp
/// @notice User-facing interface for legislation referendum proposal, voting, and finalization flows.
interface IReferendumApp {
    error InvalidLegislationTier(uint8 legislationTier);
    error InvalidProposalFee(uint256 requiredFee);
    error InvalidProposedCongressElectionPolicy(address policyAddress);
    error InvalidProposerOrigin(address proposer, ReferendumTypes.ProposalOrigin proposalOrigin);
    error InvalidProposerReference(address proposer);
    error InvalidVoteOption(ReferendumTypes.VoteOption option);
    error InvalidVotingWindow(uint64 startTime, uint64 endTime, uint64 minimumDuration);
    error MeasureAlreadyEnacted(bytes32 measureId);
    error NoVotingPower(address voter);
    error ReferendumNotEnded(bytes32 referendumId, uint64 endTime, uint64 currentTime);
    error UnknownAmendmentTarget(bytes32 measureId);

    /// @notice Returns the configured identity registry address.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured legislation registry address.
    /// @return registryAddress The legislation registry address.
    function legislationRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured referendum registry address.
    /// @return registryAddress The referendum registry address.
    function referendumRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured referendum policy address.
    /// @return policyAddress The referendum policy address.
    function referendumPolicy() external view returns (address policyAddress);

    /// @notice Returns the configured governance router address used for queued enactment.
    /// @return routerAddress The governance router address.
    function governanceRouter() external view returns (address routerAddress);

    /// @notice Returns the configured voting power policy address.
    /// @return policyAddress The voting power policy address.
    function votingPowerPolicy() external view returns (address policyAddress);

    /// @notice Returns the deterministic referendum identifier for a proposal payload and proposer reference.
    /// @param referendumClass The referendum class used for creation.
    /// @param proposalOrigin The proposal origin used for creation.
    /// @param proposal The legislation proposal payload.
    /// @param proposerReference The proposer reference that will be stored in the registry.
    /// @return referendumId The deterministic referendum identifier.
    function previewReferendumId(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.LegislationProposal calldata proposal,
        bytes32 proposerReference
    ) external pure returns (bytes32 referendumId);

    /// @notice Returns the deterministic referendum identifier for a proposal payload and proposer reference.
    /// @param proposalOrigin The proposal origin used for creation.
    /// @param proposal The legislation proposal payload.
    /// @param proposerReference The proposer reference that will be stored in the registry.
    /// @return referendumId The deterministic referendum identifier.
    function previewReferendumId(
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.LegislationProposal calldata proposal,
        bytes32 proposerReference
    ) external pure returns (bytes32 referendumId);

    /// @notice Returns the deterministic referendum identifier for a Congress election policy proposal.
    /// @param proposalOrigin The proposal origin used for creation.
    /// @param proposal The Congress election policy proposal payload.
    /// @param proposerReference The proposer reference that will be stored in the registry.
    /// @return referendumId The deterministic referendum identifier.
    function previewCongressElectionPolicyReferendumId(
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.CongressElectionPolicyProposal calldata proposal,
        bytes32 proposerReference
    ) external pure returns (bytes32 referendumId);

    /// @notice Creates a citizen-origin referendum for legislation enactment.
    /// @param proposal The legislation proposal payload to register.
    /// @return referendumId The created referendum identifier.
    function createCitizenLegislationReferendum(ReferendumTypes.LegislationProposal calldata proposal)
        external
        returns (bytes32 referendumId);

    /// @notice Creates a Congress-origin referendum for legislation enactment.
    /// @param proposal The legislation proposal payload to register.
    /// @return referendumId The created referendum identifier.
    function createCongressLegislationReferendum(ReferendumTypes.LegislationProposal calldata proposal)
        external
        returns (bytes32 referendumId);

    /// @notice Creates a Congress-origin constitutional-amendment referendum.
    /// @param proposal The constitutional amendment proposal payload to register.
    /// @return referendumId The created referendum identifier.
    function createCongressConstitutionalAmendmentReferendum(ReferendumTypes.LegislationProposal calldata proposal)
        external
        returns (bytes32 referendumId);

    /// @notice Creates a citizen-origin referendum to replace the Congress election policy module.
    /// @param proposal The Congress election policy proposal payload.
    /// @return referendumId The created referendum identifier.
    function createCitizenCongressElectionPolicyReferendum(
        ReferendumTypes.CongressElectionPolicyProposal calldata proposal
    ) external returns (bytes32 referendumId);

    /// @notice Creates a Congress-origin referendum to replace the Congress election policy module.
    /// @param proposal The Congress election policy proposal payload.
    /// @return referendumId The created referendum identifier.
    function createCongressElectionPolicyReferendum(ReferendumTypes.CongressElectionPolicyProposal calldata proposal)
        external
        returns (bytes32 referendumId);

    /// @notice Records a vote on an active referendum using the caller's current voting power.
    /// @param referendumId The referendum identifier to vote on.
    /// @param option The vote option to record.
    function castVote(bytes32 referendumId, ReferendumTypes.VoteOption option) external;

    /// @notice Finalizes an ended referendum and records legislation on success.
    /// @param referendumId The referendum identifier to finalize.
    function finalizeReferendum(bytes32 referendumId) external;
}
