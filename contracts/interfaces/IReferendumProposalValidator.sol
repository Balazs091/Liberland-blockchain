// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {ReferendumTypes} from "../types/ReferendumTypes.sol";

/// @notice Stateless validation separated from the voting app to keep its runtime below the EVM size limit.
/// @dev This interface grants no proposal, voting, registry-write or execution authority.
interface IReferendumProposalValidator {
    function validateLegislation(
        ReferendumTypes.ReferendumClass kind,
        ReferendumTypes.LegislationProposal calldata proposal
    ) external view;
    function validateModule(ReferendumTypes.ModuleGovernanceProposal calldata proposal) external view;
    function validateBundle(ReferendumTypes.ModuleGovernanceProposal calldata proposal) external view;
    function validateBudget(ReferendumTypes.BudgetApprovalProposal calldata proposal) external view;
    function validateElectionPolicy(address newPolicyAddress) external view;
}
