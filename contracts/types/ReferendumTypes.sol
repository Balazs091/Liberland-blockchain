// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {LegislationTypes} from "./LegislationTypes.sol";

/// @title ReferendumTypes
/// @notice Shared enums and structs for referendum proposal, voting, and finalization state.
library ReferendumTypes {
    enum ReferendumClass {
        Undefined,
        Legislation,
        ConstitutionalAmendment,
        CongressElectionPolicy
    }

    enum ProposalOrigin {
        Undefined,
        Citizen,
        Congress
    }

    enum VoteOption {
        Undefined,
        Against,
        For
    }

    enum ReferendumStatus {
        Undefined,
        Active,
        Succeeded,
        Defeated,
        Canceled
    }

    struct LegislationProposal {
        bytes32 proposalMetadataHash;
        bytes32 proposedMeasureId;
        bytes32 amendsMeasureId;
        bytes32 legislationTextHash;
        LegislationTypes.LegislationTier legislationTier;
        uint64 startTime;
        uint64 endTime;
    }

    struct CongressElectionPolicyProposal {
        bytes32 proposalMetadataHash;
        bytes32 proposalId;
        address newPolicy;
        uint64 startTime;
        uint64 endTime;
    }

    struct ReferendumRecordInput {
        ReferendumClass referendumClass;
        ProposalOrigin proposalOrigin;
        bytes32 proposalMetadataHash;
        bytes32 proposedMeasureId;
        bytes32 amendsMeasureId;
        bytes32 legislationTextHash;
        LegislationTypes.LegislationTier legislationTier;
        bytes32 targetModule;
        address proposedModuleAddress;
        bytes32 proposerReference;
        uint64 startTime;
        uint64 endTime;
    }

    struct ReferendumRecord {
        bytes32 referendumId;
        ReferendumClass referendumClass;
        ProposalOrigin proposalOrigin;
        bytes32 proposalMetadataHash;
        bytes32 proposedMeasureId;
        bytes32 amendsMeasureId;
        bytes32 legislationTextHash;
        LegislationTypes.LegislationTier legislationTier;
        bytes32 targetModule;
        address proposedModuleAddress;
        bytes32 proposerReference;
        uint64 startTime;
        uint64 endTime;
        ReferendumStatus status;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 forVoterCount;
        uint256 againstVoterCount;
        uint256 voterCount;
        uint64 finalizedAt;
        bytes32 enactedMeasureId;
        bytes32 enactmentActionId;
    }

    struct VoteReceipt {
        VoteOption option;
        uint256 weight;
        uint64 votedAt;
    }

    struct ReferendumResult {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 forVoterCount;
        uint256 againstVoterCount;
        uint256 turnout;
        uint256 quorumRequired;
        uint256 headcountQuorumRequired;
        uint256 electorateVotingPower;
        bool quorumMet;
        bool passed;
        uint64 finalizedAt;
        bytes32 enactmentActionId;
    }

    struct ReferendumResultInput {
        uint256 turnout;
        uint256 quorumRequired;
        uint256 headcountQuorumRequired;
        uint256 electorateVotingPower;
        bool quorumMet;
        bool passed;
        bytes32 enactedMeasureId;
        bytes32 enactmentActionId;
    }

    struct PolicyOutcome {
        uint256 turnout;
        uint256 quorumRequired;
        uint256 headcountQuorumRequired;
        uint256 electorateVotingPower;
        bool quorumMet;
        bool passed;
    }
}
