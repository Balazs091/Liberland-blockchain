// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IReferendumProposalValidator} from "../interfaces/IReferendumProposalValidator.sol";
import {IReferendumApp} from "../interfaces/IReferendumApp.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IGovernanceRouter} from "../interfaces/IGovernanceRouter.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {ICongressElectionPolicy} from "../interfaces/ICongressElectionPolicy.sol";
import {ITreasurySpendingPolicy} from "../interfaces/ITreasurySpendingPolicy.sol";
import {IBudgetEnvelopeRegistry} from "../interfaces/IBudgetEnvelopeRegistry.sol";
import {IActionTimelock} from "../interfaces/IActionTimelock.sol";
import {IModuleUpgradePlanRegistry} from "../interfaces/IModuleUpgradePlanRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {ModuleUpgradePlanHash} from "../libraries/ModuleUpgradePlanHash.sol";
import {ModuleUpgradeRules} from "../libraries/ModuleUpgradeRules.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {ReferendumTypes} from "../types/ReferendumTypes.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title ReferendumProposalValidator
/// @notice Fixed read-only proposal validation; it has no authority and accepts no executable calldata.
/// @dev Each voting app creates its own immutable helper. No registry pointer or administrator can replace it.
contract ReferendumProposalValidator is IReferendumProposalValidator {
    ILegislationRegistry private immutable _legislationRegistry;
    IGovernanceRouter private immutable _governanceRouter;

    /// @param legislationRegistryAddress Stable legislation facts read by the parent app.
    /// @param governanceRouterAddress Parent app's core router, used to resolve the canonical kernel/policies.
    constructor(address legislationRegistryAddress, address governanceRouterAddress) {
        _legislationRegistry = ILegislationRegistry(legislationRegistryAddress);
        _governanceRouter = IGovernanceRouter(governanceRouterAddress);
    }

    /// @inheritdoc IReferendumProposalValidator
    function validateBundle(ReferendumTypes.ModuleGovernanceProposal calldata proposal) external view {
        IConstitutionKernel kernel = IConstitutionKernel(_governanceRouter.kernel());
        address registry = proposal.newModuleAddress;
        if (
            proposal.proposalId == bytes32(0)
                || registry != kernel.getModule(KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY)
                || registry.code.length == 0 || proposal.targetModule != KernelModuleIds.ACTION_TIMELOCK
                || proposal.registerNewModule || IModuleUpgradePlanRegistry(registry).kernel() != address(kernel)
        ) {
            revert IReferendumApp.InvalidModuleGovernanceProposal(
                proposal.targetModule, registry, proposal.registerNewModule
            );
        }
        (GovernanceTypes.ModuleUpdate[] memory updates, bytes32 evidenceHash) =
            IModuleUpgradePlanRegistry(registry).getPlan(proposal.proposalId);
        if (
            evidenceHash == bytes32(0)
                || ModuleUpgradePlanHash.hash(block.chainid, address(kernel), registry, evidenceHash, updates)
                    != proposal.proposalId
        ) {
            revert IReferendumApp.InvalidModuleGovernanceProposal(proposal.targetModule, registry, false);
        }
        ModuleUpgradeRules.validateCount(updates.length);
        bytes32 previous;
        for (uint256 i; i < updates.length; ++i) {
            GovernanceTypes.ModuleUpdate memory item = updates[i];
            ModuleUpgradeRules.validateEntry(
                item, previous, kernel.moduleClass(item.moduleId), kernel.getModule(item.moduleId), false
            );
            previous = item.moduleId;
        }
    }

    /// @inheritdoc IReferendumProposalValidator
    function validateLegislation(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.LegislationProposal calldata proposal
    ) external view {
        if (
            referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment
                && !LegislationTypes.isConstitutionalTier(proposal.legislationTier)
        ) {
            revert IReferendumApp.InvalidLegislationTier(uint8(proposal.legislationTier));
        }
        if (
            referendumClass == ReferendumTypes.ReferendumClass.Legislation
                && !LegislationTypes.isLawTier(proposal.legislationTier)
        ) {
            revert IReferendumApp.InvalidLegislationTier(uint8(proposal.legislationTier));
        }
        if (proposal.amendsMeasureId != bytes32(0)) {
            if (!_legislationRegistry.legislationExists(proposal.amendsMeasureId)) {
                revert IReferendumApp.UnknownAmendmentTarget(proposal.amendsMeasureId);
            }
            // An ordinary Law vote cannot bypass the constitutional route by labelling its new text Law
            // while declaring an amendment of an existing constitutional/treaty measure.
            LegislationTypes.LegislationTier targetTier =
            _legislationRegistry.getLegislationRecord(proposal.amendsMeasureId).tier;
            if (
                LegislationTypes.isConstitutionalTier(targetTier)
                    && !LegislationTypes.isConstitutionalTier(proposal.legislationTier)
            ) {
                revert IReferendumApp.InvalidLegislationTier(uint8(targetTier));
            }
        }
        if (_legislationRegistry.legislationExists(proposal.proposedMeasureId)) {
            revert IReferendumApp.MeasureAlreadyEnacted(proposal.proposedMeasureId);
        }
    }

    /// @inheritdoc IReferendumProposalValidator
    function validateModule(ReferendumTypes.ModuleGovernanceProposal calldata proposal) external view {
        // Core execution modules (governance-router, action-timelock) are intentionally NOT repointable through a
        // referendum at any threshold: they are the trust root that enforces the timelock and origin routing, so
        // live-swapping either one would let a single passing proposal bypass every downstream safeguard it is meant
        // to gate. Authorities (including router-origin and constitutional-review modules), policies, state-bearing
        // modules, and unclassified extension IDs require the constitutional supermajority; bounded application
        // pointers without protocol-wide routing or review powers use the ordinary threshold. The kernel cannot verify
        // state continuity, so state-bearing replacements additionally require an audited migration plan.
        if (
            proposal.targetModule == bytes32(0) || proposal.newModuleAddress == address(0)
                || proposal.newModuleAddress.code.length == 0 || _isCoreModule(proposal.targetModule)
        ) {
            revert IReferendumApp.InvalidModuleGovernanceProposal(
                proposal.targetModule, proposal.newModuleAddress, proposal.registerNewModule
            );
        }

        bool moduleActive = _isActiveModule(proposal.targetModule);
        if (proposal.registerNewModule == moduleActive) {
            revert IReferendumApp.InvalidModuleGovernanceProposal(
                proposal.targetModule, proposal.newModuleAddress, proposal.registerNewModule
            );
        }
    }

    /// @inheritdoc IReferendumProposalValidator
    function validateBudget(ReferendumTypes.BudgetApprovalProposal calldata proposal) external view {
        IConstitutionKernel kernel = IConstitutionKernel(_governanceRouter.kernel());
        uint256 approvalDelay = IActionTimelock(_governanceRouter.timelock())
            .minimumDelay(GovernanceTypes.ActionType.TreasuryBudgetApproval);
        if (proposal.adoptionDelay > approvalDelay) approvalDelay = proposal.adoptionDelay;
        // Finalization cannot happen before voting ends, and the immutable queue/adoption delay still follows.
        // Reject a budget that would already be expired at its earliest possible approval. Use widened arithmetic.
        uint256 earliestApproval = uint256(proposal.endTime) + approvalDelay;
        if (
            proposal.budgetId == bytes32(0) || proposal.budgetLawTextHash == bytes32(0)
                || proposal.budget.officeId == bytes32(0)
                || proposal.budget.disbursementType == TreasuryTypes.DisbursementType.Undefined
                || proposal.budget.asset == address(0) || proposal.budget.asset.code.length == 0
                || proposal.budget.allocatedAmount == 0 || proposal.budget.endsAt <= proposal.budget.startsAt
                || uint256(proposal.budget.endsAt) < earliestApproval
                || IBudgetEnvelopeRegistry(kernel.getModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY))
                    .budgetExists(proposal.budgetId)
                // Fail fast: an asset the spending policy does not allow would produce an approved-but-unspendable
                // budget (payouts require ITreasurySpendingPolicy.isAssetAllowed). Best-effort at creation time.
                || !ITreasurySpendingPolicy(kernel.getModule(KernelModuleIds.TREASURY_SPENDING_POLICY))
                    .isAssetAllowed(proposal.budget.asset)
        ) {
            revert IReferendumApp.InvalidBudgetProposal(proposal.budgetId);
        }
    }

    /// @inheritdoc IReferendumProposalValidator
    function validateElectionPolicy(address newPolicyAddress) external view {
        if (newPolicyAddress == address(0) || newPolicyAddress.code.length == 0) {
            revert IReferendumApp.InvalidProposedCongressElectionPolicy(newPolicyAddress);
        }

        address currentPolicyAddress =
            IConstitutionKernel(_governanceRouter.kernel()).getModule(KernelModuleIds.CONGRESS_ELECTION_POLICY);
        ICongressElectionPolicy currentPolicy = ICongressElectionPolicy(currentPolicyAddress);
        ICongressElectionPolicy newPolicy = ICongressElectionPolicy(newPolicyAddress);

        bool sameNonTimingRules = newPolicy.candidateEligibilityPolicy() == currentPolicy.candidateEligibilityPolicy()
            && newPolicy.votingPowerPolicy() == currentPolicy.votingPowerPolicy()
            && newPolicy.seatCount() == currentPolicy.seatCount()
            && newPolicy.runnerUpCount() == currentPolicy.runnerUpCount()
            && newPolicy.maxCandidateCount() == currentPolicy.maxCandidateCount()
            && newPolicy.candidateBondRequirement() == currentPolicy.candidateBondRequirement();
        if (!sameNonTimingRules) {
            revert IReferendumApp.InvalidProposedCongressElectionPolicy(newPolicyAddress);
        }
    }

    function _isActiveModule(bytes32 moduleId) private view returns (bool active) {
        try IConstitutionKernel(_governanceRouter.kernel()).getModuleRecord(moduleId) returns (
            GovernanceTypes.ModuleRecord memory moduleRecord
        ) {
            return
                moduleRecord.status == GovernanceTypes.ModuleStatus.Active && moduleRecord.moduleAddress != address(0);
        } catch {
            return false;
        }
    }

    function _isCoreModule(bytes32 moduleId) private pure returns (bool coreModule) {
        return moduleId == KernelModuleIds.GOVERNANCE_ROUTER || moduleId == KernelModuleIds.ACTION_TIMELOCK;
    }
}
