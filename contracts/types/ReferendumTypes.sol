// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {LegislationTypes} from "./LegislationTypes.sol";
import {TreasuryTypes} from "./TreasuryTypes.sol";

/// @title ReferendumTypes
/// @notice Shared enums and structs for referendum proposal, voting, and finalization state.
library ReferendumTypes {
    enum ReferendumClass {
        Undefined,
        Legislation,
        ConstitutionalAmendment,
        CongressElectionPolicy,
        BudgetApproval,
        ModuleGovernance
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
        uint64 adoptionDelay;
        bool emergency;
    }

    struct CongressElectionPolicyProposal {
        bytes32 proposalMetadataHash;
        bytes32 proposalId;
        address newPolicy;
        uint64 startTime;
        uint64 endTime;
        uint64 adoptionDelay;
    }

    struct BudgetApprovalProposal {
        bytes32 proposalMetadataHash;
        bytes32 budgetId;
        bytes32 budgetLawTextHash;
        BudgetApprovalDetails budget;
        uint64 startTime;
        uint64 endTime;
        uint64 adoptionDelay;
        bool emergency;
    }

    struct ModuleGovernanceProposal {
        bytes32 proposalMetadataHash;
        bytes32 proposalId;
        bytes32 targetModule;
        address newModuleAddress;
        bool registerNewModule;
        uint64 startTime;
        uint64 endTime;
        uint64 adoptionDelay;
    }

    struct BudgetApprovalDetails {
        bytes32 officeId;
        TreasuryTypes.DisbursementType disbursementType;
        address asset;
        uint256 allocatedAmount;
        uint64 startsAt;
        uint64 endsAt;
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
        bool registerNewModule;
        bytes32 proposerReference;
        uint64 startTime;
        uint64 endTime;
        uint64 adoptionDelay;
        uint48 votingPowerSnapshotBlock;
        address referendumPolicy;
        address votingPowerPolicy;
        uint256 electorateHeadcountSnapshot;
        uint256 electorateVotingPowerSnapshot;
        bool requiresSupermajority;
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
        bool registerNewModule;
        bytes32 proposerReference;
        uint64 startTime;
        uint64 endTime;
        uint48 votingPowerSnapshotBlock;
        address referendumPolicy;
        address votingPowerPolicy;
        uint256 electorateHeadcountSnapshot;
        uint256 electorateVotingPowerSnapshot;
        bool requiresSupermajority;
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
