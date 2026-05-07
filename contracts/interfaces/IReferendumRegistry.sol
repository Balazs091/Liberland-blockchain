// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ReferendumTypes} from "../types/ReferendumTypes.sol";

/// @title IReferendumRegistry
/// @notice Stable fact registry for referendum proposals, vote receipts, and result snapshots.
interface IReferendumRegistry {
    error DuplicateVote(bytes32 referendumId, address voter);
    error InvalidEnactedMeasureId(bytes32 referendumId, bytes32 measureId);
    error InvalidLegislationTier(uint8 legislationTier);
    error InvalidProposalMetadataHash(bytes32 metadataHash);
    error InvalidProposalOrigin(ReferendumTypes.ProposalOrigin proposalOrigin);
    error InvalidProposedModule(bytes32 targetModule, address proposedModuleAddress);
    error InvalidProposedMeasureId(bytes32 measureId);
    error InvalidProposerReference(bytes32 proposerReference);
    error InvalidReferendumClass(ReferendumTypes.ReferendumClass referendumClass);
    error InvalidReferendumId(bytes32 referendumId);
    error InvalidResultSnapshot(bytes32 referendumId, uint256 turnout, uint256 expectedTurnout);
    error InvalidTextHash(bytes32 textHash);
    error InvalidVoteOption(ReferendumTypes.VoteOption option);
    error InvalidVoteWeightUpdate(address voter, uint256 providedWeight, uint256 expectedWeight);
    error InvalidVotingWeight(address voter, uint256 weight);
    error InvalidVotingWindow(uint64 startTime, uint64 endTime);
    error ReferendumAlreadyExists(bytes32 referendumId);
    error ReferendumAlreadyFinalized(bytes32 referendumId, ReferendumTypes.ReferendumStatus status);
    error ReferendumNotFound(bytes32 referendumId);
    error ReferendumNotReady(bytes32 referendumId, uint64 endTime, uint64 currentTime);
    error UnauthorizedReferendumRegistryCaller(address caller);
    error UnexpectedEnactedMeasureId(bytes32 referendumId, bytes32 measureId);
    error VotingClosed(bytes32 referendumId, uint64 startTime, uint64 endTime, uint64 currentTime);

    event ReferendumCreated(
        bytes32 indexed referendumId,
        ReferendumTypes.ReferendumClass indexed referendumClass,
        ReferendumTypes.ProposalOrigin indexed proposalOrigin,
        bytes32 proposedMeasureId,
        bytes32 targetModule,
        address proposedModuleAddress,
        bytes32 proposerReference,
        bytes32 proposalMetadataHash,
        bytes32 legislationTextHash,
        uint64 startTime,
        uint64 endTime,
        address createdBy
    );

    event ReferendumVoteRecorded(
        bytes32 indexed referendumId,
        address indexed voter,
        ReferendumTypes.VoteOption option,
        uint256 weight,
        uint256 newForVotes,
        uint256 newAgainstVotes,
        uint256 newVoterCount,
        uint64 votedAt,
        address indexed recordedBy
    );

    event ReferendumFinalized(
        bytes32 indexed referendumId,
        ReferendumTypes.ReferendumStatus status,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 turnout,
        uint256 quorumRequired,
        bool quorumMet,
        bool passed,
        bytes32 enactedMeasureId,
        bytes32 enactmentActionId,
        uint64 finalizedAt,
        address indexed finalizedBy
    );

    /// @notice Returns the kernel used for narrow write authorization.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress);

    /// @notice Returns the stored referendum record for a referendum identifier.
    /// @param referendumId The referendum identifier to query.
    /// @return record The stored referendum record, or an empty record if unset.
    function getReferendum(bytes32 referendumId) external view returns (ReferendumTypes.ReferendumRecord memory record);

    /// @notice Returns the stored vote receipt for a voter on a referendum.
    /// @param referendumId The referendum identifier to query.
    /// @param voter The voter address to query.
    /// @return receipt The stored vote receipt, or an empty receipt if none exists.
    function getVoteReceipt(bytes32 referendumId, address voter)
        external
        view
        returns (ReferendumTypes.VoteReceipt memory receipt);

    /// @notice Returns the finalized result snapshot for a referendum.
    /// @param referendumId The referendum identifier to query.
    /// @return result The finalized result snapshot, or an empty result if unset.
    function getReferendumResult(bytes32 referendumId)
        external
        view
        returns (ReferendumTypes.ReferendumResult memory result);

    /// @notice Returns true when a referendum record exists.
    /// @param referendumId The referendum identifier to query.
    /// @return exists Whether the referendum exists.
    function referendumExists(bytes32 referendumId) external view returns (bool exists);

    /// @notice Returns true when a voter has already cast a vote on the referendum.
    /// @param referendumId The referendum identifier to query.
    /// @param voter The voter to query.
    /// @return voted Whether the voter already has a stored vote receipt.
    function hasVoted(bytes32 referendumId, address voter) external view returns (bool voted);

    /// @notice Stores a newly created referendum record.
    /// @param referendumId The referendum identifier to create.
    /// @param referendumInput The referendum metadata and scheduling fields to store.
    function createReferendum(bytes32 referendumId, ReferendumTypes.ReferendumRecordInput calldata referendumInput)
        external;

    /// @notice Stores a vote receipt and updates tallies for an active referendum.
    /// @param referendumId The referendum identifier to vote on.
    /// @param voter The voting wallet.
    /// @param option The vote option to record.
    /// @param weight The voting weight to attribute to the vote.
    function recordVote(bytes32 referendumId, address voter, ReferendumTypes.VoteOption option, uint256 weight) external;

    /// @notice Stores the final result snapshot for a referendum and marks it as finalized.
    /// @param referendumId The referendum identifier to finalize.
    /// @param resultInput The policy-evaluated result snapshot to store.
    function finalizeReferendum(bytes32 referendumId, ReferendumTypes.ReferendumResultInput calldata resultInput)
        external;
}
