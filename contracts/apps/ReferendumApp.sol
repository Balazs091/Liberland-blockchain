// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGovernanceRouter} from "../interfaces/IGovernanceRouter.sol";
import {ICongressElectionPolicy} from "../interfaces/ICongressElectionPolicy.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ITreasurySpendingPolicy} from "../interfaces/ITreasurySpendingPolicy.sol";
import {IBudgetEnvelopeRegistry} from "../interfaces/IBudgetEnvelopeRegistry.sol";
import {IElectorateRegistry} from "../interfaces/IElectorateRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {IReferendumApp} from "../interfaces/IReferendumApp.sol";
import {IReferendumPolicy} from "../interfaces/IReferendumPolicy.sol";
import {IReferendumRegistry} from "../interfaces/IReferendumRegistry.sol";
import {ISenateApp} from "../interfaces/ISenateApp.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {IVotingPowerPolicy} from "../interfaces/IVotingPowerPolicy.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {ReferendumTypes} from "../types/ReferendumTypes.sol";
import {SenateTypes} from "../types/SenateTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title ReferendumApp
/// @notice User-facing application for bounded referendum proposal, voting, veto, and finalization flows.
contract ReferendumApp is IReferendumApp {
    using SafeERC20 for IERC20;

    error InvalidPolicy(address policyAddress);
    error InvalidRegistry(address registryAddress);

    IIdentityRegistry private immutable _identityRegistry;
    ILegislationRegistry private immutable _legislationRegistry;
    IReferendumRegistry private immutable _referendumRegistry;
    IGovernanceRouter private immutable _governanceRouter;

    /// @param identityRegistryAddress The identity registry used to resolve citizen proposer references.
    /// @param legislationRegistryAddress The legislation registry used for successful enactment records.
    /// @param referendumRegistryAddress The referendum registry used for proposal and vote storage.
    /// @param referendumPolicyAddress The referendum policy used for proposal and pass-rule checks.
    /// @param governanceRouterAddress The governance router used to queue enactment actions.
    /// @param votingPowerPolicyAddress The voting power policy used to weight votes.
    constructor(
        address identityRegistryAddress,
        address legislationRegistryAddress,
        address referendumRegistryAddress,
        address referendumPolicyAddress,
        address governanceRouterAddress,
        address votingPowerPolicyAddress
    ) {
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidRegistry(identityRegistryAddress);
        }
        if (legislationRegistryAddress == address(0) || legislationRegistryAddress.code.length == 0) {
            revert InvalidRegistry(legislationRegistryAddress);
        }
        if (referendumRegistryAddress == address(0) || referendumRegistryAddress.code.length == 0) {
            revert InvalidRegistry(referendumRegistryAddress);
        }
        if (referendumPolicyAddress == address(0) || referendumPolicyAddress.code.length == 0) {
            revert InvalidPolicy(referendumPolicyAddress);
        }
        if (governanceRouterAddress == address(0) || governanceRouterAddress.code.length == 0) {
            revert InvalidPolicy(governanceRouterAddress);
        }
        if (votingPowerPolicyAddress == address(0) || votingPowerPolicyAddress.code.length == 0) {
            revert InvalidPolicy(votingPowerPolicyAddress);
        }

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _legislationRegistry = ILegislationRegistry(legislationRegistryAddress);
        _referendumRegistry = IReferendumRegistry(referendumRegistryAddress);
        _governanceRouter = IGovernanceRouter(governanceRouterAddress);
    }

    /// @inheritdoc IReferendumApp
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc IReferendumApp
    function legislationRegistry() external view returns (address registryAddress) {
        return address(_legislationRegistry);
    }

    /// @inheritdoc IReferendumApp
    function referendumRegistry() external view returns (address registryAddress) {
        return address(_referendumRegistry);
    }

    /// @inheritdoc IReferendumApp
    function referendumPolicy() external view returns (address policyAddress) {
        return address(_currentReferendumPolicy());
    }

    /// @inheritdoc IReferendumApp
    function governanceRouter() external view returns (address routerAddress) {
        return address(_governanceRouter);
    }

    /// @inheritdoc IReferendumApp
    function votingPowerPolicy() external view returns (address policyAddress) {
        return address(_currentVotingPowerPolicy());
    }

    /// @inheritdoc IReferendumApp
    function previewReferendumId(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.LegislationProposal calldata proposal,
        bytes32 proposerReference
    ) external pure returns (bytes32 referendumId) {
        return _previewReferendumId(referendumClass, proposalOrigin, proposal, proposerReference);
    }

    /// @inheritdoc IReferendumApp
    function previewReferendumId(
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.LegislationProposal calldata proposal,
        bytes32 proposerReference
    ) external pure returns (bytes32 referendumId) {
        return _previewReferendumId(
            ReferendumTypes.ReferendumClass.Legislation, proposalOrigin, proposal, proposerReference
        );
    }

    /// @inheritdoc IReferendumApp
    function previewCongressElectionPolicyReferendumId(
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.CongressElectionPolicyProposal calldata proposal,
        bytes32 proposerReference
    ) external pure returns (bytes32 referendumId) {
        return _previewCongressElectionPolicyReferendumId(proposalOrigin, proposal, proposerReference);
    }

    /// @inheritdoc IReferendumApp
    function previewBudgetApprovalReferendumId(
        ReferendumTypes.BudgetApprovalProposal calldata proposal,
        bytes32 proposerReference
    ) external pure returns (bytes32 referendumId) {
        return _previewBudgetApprovalReferendumId(proposal, proposerReference);
    }

    /// @inheritdoc IReferendumApp
    function previewModuleGovernanceReferendumId(
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.ModuleGovernanceProposal calldata proposal,
        bytes32 proposerReference
    ) external pure returns (bytes32 referendumId) {
        return _previewModuleGovernanceReferendumId(proposalOrigin, proposal, proposerReference);
    }

    /// @inheritdoc IReferendumApp
    function createCitizenLegislationReferendum(ReferendumTypes.LegislationProposal calldata proposal)
        external
        returns (bytes32 referendumId)
    {
        return _createReferendum(
            ReferendumTypes.ReferendumClass.Legislation, proposal, ReferendumTypes.ProposalOrigin.Citizen
        );
    }

    /// @inheritdoc IReferendumApp
    function createCongressLegislationReferendum(ReferendumTypes.LegislationProposal calldata proposal)
        external
        returns (bytes32 referendumId)
    {
        return _createReferendum(
            ReferendumTypes.ReferendumClass.Legislation, proposal, ReferendumTypes.ProposalOrigin.Congress
        );
    }

    /// @inheritdoc IReferendumApp
    function createCongressConstitutionalAmendmentReferendum(ReferendumTypes.LegislationProposal calldata proposal)
        external
        returns (bytes32 referendumId)
    {
        return _createReferendum(
            ReferendumTypes.ReferendumClass.ConstitutionalAmendment, proposal, ReferendumTypes.ProposalOrigin.Congress
        );
    }

    /// @inheritdoc IReferendumApp
    function createCitizenCongressElectionPolicyReferendum(
        ReferendumTypes.CongressElectionPolicyProposal calldata proposal
    ) external returns (bytes32 referendumId) {
        return _createCongressElectionPolicyReferendum(proposal, ReferendumTypes.ProposalOrigin.Citizen);
    }

    /// @inheritdoc IReferendumApp
    function createCongressElectionPolicyReferendum(ReferendumTypes.CongressElectionPolicyProposal calldata proposal)
        external
        returns (bytes32 referendumId)
    {
        return _createCongressElectionPolicyReferendum(proposal, ReferendumTypes.ProposalOrigin.Congress);
    }

    /// @inheritdoc IReferendumApp
    function createCongressBudgetApprovalReferendum(ReferendumTypes.BudgetApprovalProposal calldata proposal)
        external
        returns (bytes32 referendumId)
    {
        ReferendumTypes.ReferendumClass referendumClass = ReferendumTypes.ReferendumClass.BudgetApproval;
        ReferendumTypes.ProposalOrigin proposalOrigin = ReferendumTypes.ProposalOrigin.Congress;
        _authorizeProposalAndCollectFee(referendumClass, proposalOrigin);

        _validateReferendumSchedule(
            referendumClass,
            proposal.startTime,
            proposal.endTime,
            proposal.adoptionDelay,
            proposal.emergency,
            proposalOrigin
        );
        _validateBudgetProposal(proposal);

        bytes32 proposerReference = _resolveProposerReference(proposalOrigin);
        referendumId = _previewBudgetApprovalReferendumId(proposal, proposerReference);
        _storeBudgetApprovalReferendumProposal(referendumId, proposal, proposerReference);
    }

    /// @inheritdoc IReferendumApp
    function createCitizenModuleGovernanceReferendum(ReferendumTypes.ModuleGovernanceProposal calldata proposal)
        external
        returns (bytes32 referendumId)
    {
        return _createModuleGovernanceReferendum(proposal, ReferendumTypes.ProposalOrigin.Citizen);
    }

    /// @inheritdoc IReferendumApp
    function createCongressModuleGovernanceReferendum(ReferendumTypes.ModuleGovernanceProposal calldata proposal)
        external
        returns (bytes32 referendumId)
    {
        return _createModuleGovernanceReferendum(proposal, ReferendumTypes.ProposalOrigin.Congress);
    }

    /// @inheritdoc IReferendumApp
    function castVote(bytes32 referendumId, ReferendumTypes.VoteOption option) external {
        if (option != ReferendumTypes.VoteOption.Against && option != ReferendumTypes.VoteOption.For) {
            revert InvalidVoteOption(option);
        }

        ReferendumTypes.ReferendumRecord memory referendumRecord = _referendumRegistry.getReferendum(referendumId);
        if (referendumRecord.referendumId == bytes32(0)) {
            revert IReferendumRegistry.ReferendumNotFound(referendumId);
        }

        // Receipts are person-keyed so a citizen cannot vote twice by rotating their active wallet mid-referendum.
        bytes32 personId = _identityRegistry.resolveWalletToPersonId(msg.sender);
        uint256 weight = IVotingPowerPolicy(referendumRecord.votingPowerPolicy)
            .votingPowerAt(msg.sender, referendumRecord.votingPowerSnapshotBlock);
        if (weight == 0) {
            revert NoVotingPower(msg.sender);
        }

        _referendumRegistry.recordVote(referendumId, personId, msg.sender, option, weight);
    }

    /// @inheritdoc IReferendumApp
    function finalizeReferendum(bytes32 referendumId) external {
        ReferendumTypes.ReferendumRecord memory referendumRecord = _referendumRegistry.getReferendum(referendumId);
        if (referendumRecord.referendumId == bytes32(0)) {
            revert IReferendumRegistry.ReferendumNotFound(referendumId);
        }
        if (block.timestamp < referendumRecord.endTime) {
            revert ReferendumNotEnded(referendumId, referendumRecord.endTime, uint64(block.timestamp));
        }
        _requireNoPendingSenateVeto(referendumId, referendumRecord);

        ReferendumTypes.PolicyOutcome memory outcome = IReferendumPolicy(referendumRecord.referendumPolicy)
            .evaluateOutcome(
                referendumRecord.referendumClass,
                referendumRecord.proposalOrigin,
                referendumRecord.forVotes,
                referendumRecord.againstVotes,
                referendumRecord.forVoterCount,
                referendumRecord.againstVoterCount,
                referendumRecord.electorateHeadcountSnapshot,
                referendumRecord.electorateVotingPowerSnapshot,
                referendumRecord.requiresSupermajority
            );

        bytes32 enactedMeasureId = bytes32(0);
        bytes32 enactmentActionId = bytes32(0);
        if (outcome.passed) {
            enactedMeasureId = referendumRecord.proposedMeasureId;
            if (referendumRecord.referendumClass == ReferendumTypes.ReferendumClass.CongressElectionPolicy) {
                enactmentActionId = _queueCongressElectionPolicyUpdate(referendumId, referendumRecord);
            } else if (referendumRecord.referendumClass == ReferendumTypes.ReferendumClass.ModuleGovernance) {
                enactmentActionId = _queueModuleGovernance(referendumId, referendumRecord);
            } else if (referendumRecord.referendumClass == ReferendumTypes.ReferendumClass.BudgetApproval) {
                enactmentActionId = _queueBudgetApproval(referendumId, referendumRecord);
            } else {
                enactmentActionId = _queueLegislationEnactment(referendumId, referendumRecord, enactedMeasureId);
            }
        }

        _storeReferendumResult(referendumId, outcome, enactedMeasureId, enactmentActionId);
    }

    /// @inheritdoc IReferendumApp
    function cancelReferendumBySenate(bytes32 referendumId) external {
        if (msg.sender != IConstitutionKernel(_governanceRouter.kernel()).getModule(KernelModuleIds.SENATE_APP)) {
            revert InvalidReferendumCancellation(referendumId);
        }

        ReferendumTypes.ReferendumRecord memory referendumRecord = _referendumRegistry.getReferendum(referendumId);
        if (
            referendumRecord.referendumId == bytes32(0)
                || referendumRecord.status != ReferendumTypes.ReferendumStatus.Active
                || block.timestamp < referendumRecord.startTime
                || referendumRecord.referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment
                || _isSenateSelfReplacement(referendumRecord)
        ) {
            revert InvalidReferendumCancellation(referendumId);
        }

        _referendumRegistry.cancelReferendum(referendumId);
    }

    /// @dev Shared creation prologue for every referendum class: enforces the policy's proposer-origin gate and
    ///      collects the proposal fee before any class-specific validation, keeping that authorization step in one
    ///      place across the create paths.
    function _authorizeProposalAndCollectFee(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin
    ) private {
        IReferendumPolicy referendumPolicy_ = _currentReferendumPolicy();
        if (!referendumPolicy_.canCreateReferendum(referendumClass, proposalOrigin, msg.sender)) {
            revert InvalidProposerOrigin(msg.sender, proposalOrigin);
        }

        _collectProposalFee(referendumPolicy_.proposalFee(proposalOrigin));
    }

    function _createReferendum(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.LegislationProposal calldata proposal,
        ReferendumTypes.ProposalOrigin proposalOrigin
    ) private returns (bytes32 referendumId) {
        _authorizeProposalAndCollectFee(referendumClass, proposalOrigin);

        _validateReferendumSchedule(
            referendumClass,
            proposal.startTime,
            proposal.endTime,
            proposal.adoptionDelay,
            proposal.emergency,
            proposalOrigin
        );
        _validateProposalTargets(referendumClass, proposal);

        bytes32 proposerReference = _resolveProposerReference(proposalOrigin);
        referendumId = _previewReferendumId(referendumClass, proposalOrigin, proposal, proposerReference);
        _storeLegislationReferendumProposal(referendumId, referendumClass, proposalOrigin, proposal, proposerReference);
    }

    function _createCongressElectionPolicyReferendum(
        ReferendumTypes.CongressElectionPolicyProposal calldata proposal,
        ReferendumTypes.ProposalOrigin proposalOrigin
    ) private returns (bytes32 referendumId) {
        ReferendumTypes.ReferendumClass referendumClass = ReferendumTypes.ReferendumClass.CongressElectionPolicy;
        _authorizeProposalAndCollectFee(referendumClass, proposalOrigin);

        _validateReferendumSchedule(
            ReferendumTypes.ReferendumClass.CongressElectionPolicy,
            proposal.startTime,
            proposal.endTime,
            proposal.adoptionDelay,
            false,
            proposalOrigin
        );
        _validateProposedCongressElectionPolicy(proposal.newPolicy);

        bytes32 proposerReference = _resolveProposerReference(proposalOrigin);
        referendumId = _previewCongressElectionPolicyReferendumId(proposalOrigin, proposal, proposerReference);
        _storeCongressElectionPolicyReferendumProposal(referendumId, proposalOrigin, proposal, proposerReference);
    }

    function _createModuleGovernanceReferendum(
        ReferendumTypes.ModuleGovernanceProposal calldata proposal,
        ReferendumTypes.ProposalOrigin proposalOrigin
    ) private returns (bytes32 referendumId) {
        ReferendumTypes.ReferendumClass referendumClass = ReferendumTypes.ReferendumClass.ModuleGovernance;
        _authorizeProposalAndCollectFee(referendumClass, proposalOrigin);

        _validateReferendumSchedule(
            referendumClass, proposal.startTime, proposal.endTime, proposal.adoptionDelay, false, proposalOrigin
        );
        _validateModuleGovernanceProposal(proposal);

        bytes32 proposerReference = _resolveProposerReference(proposalOrigin);
        referendumId = _previewModuleGovernanceReferendumId(proposalOrigin, proposal, proposerReference);
        _storeModuleGovernanceReferendumProposal(referendumId, proposalOrigin, proposal, proposerReference);
    }

    function _validateReferendumSchedule(
        ReferendumTypes.ReferendumClass referendumClass,
        uint64 startTime,
        uint64 endTime,
        uint64 adoptionDelay,
        bool emergency,
        ReferendumTypes.ProposalOrigin proposalOrigin
    ) private view {
        uint64 minimumDuration = emergency
            ? _currentReferendumPolicy().emergencyVotingDuration()
            : _currentReferendumPolicy().minimumVotingDuration();
        if (startTime < block.timestamp || endTime <= startTime || endTime - startTime < minimumDuration) {
            revert InvalidVotingWindow(startTime, endTime, minimumDuration);
        }
        if (adoptionDelay > _currentReferendumPolicy().maximumAdoptionDelay()) {
            revert InvalidAdoptionDelay(adoptionDelay, _currentReferendumPolicy().maximumAdoptionDelay());
        }
        if (emergency) {
            if (referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment) {
                revert InvalidEmergencyReferendumClass(referendumClass);
            }
            if (proposalOrigin != ReferendumTypes.ProposalOrigin.Congress || adoptionDelay != 0) {
                revert InvalidEmergencyReferendum(proposalOrigin, adoptionDelay);
            }

            return;
        }
        if (
            proposalOrigin == ReferendumTypes.ProposalOrigin.Citizen
                && adoptionDelay != _currentReferendumPolicy().standardAdoptionDelay()
        ) {
            revert InvalidAdoptionDelay(adoptionDelay, _currentReferendumPolicy().standardAdoptionDelay());
        }
    }

    function _validateProposalTargets(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.LegislationProposal calldata proposal
    ) private view {
        if (
            referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment
                && !LegislationTypes.isConstitutionalTier(proposal.legislationTier)
        ) {
            revert InvalidLegislationTier(uint8(proposal.legislationTier));
        }
        if (
            referendumClass == ReferendumTypes.ReferendumClass.Legislation
                && !LegislationTypes.isLawTier(proposal.legislationTier)
        ) {
            revert InvalidLegislationTier(uint8(proposal.legislationTier));
        }
        if (proposal.amendsMeasureId != bytes32(0) && !_legislationRegistry.legislationExists(proposal.amendsMeasureId))
        {
            revert UnknownAmendmentTarget(proposal.amendsMeasureId);
        }
        if (_legislationRegistry.legislationExists(proposal.proposedMeasureId)) {
            revert MeasureAlreadyEnacted(proposal.proposedMeasureId);
        }
    }

    function _validateModuleGovernanceProposal(ReferendumTypes.ModuleGovernanceProposal calldata proposal)
        private
        view
    {
        // Core execution modules (governance-router, action-timelock) are intentionally NOT repointable through a
        // referendum at any threshold: they are the trust root that enforces the timelock and origin routing, so
        // live-swapping either one would let a single passing proposal bypass every downstream safeguard it is meant
        // to gate. Authorities, policies, state-bearing modules, and unclassified extension IDs require the
        // constitutional supermajority; known application pointers use the ordinary threshold. The kernel cannot
        // verify state continuity, so state-bearing replacements additionally require an audited migration plan.
        if (
            proposal.targetModule == bytes32(0) || proposal.newModuleAddress == address(0)
                || proposal.newModuleAddress.code.length == 0 || _isCoreModule(proposal.targetModule)
        ) {
            revert InvalidModuleGovernanceProposal(
                proposal.targetModule, proposal.newModuleAddress, proposal.registerNewModule
            );
        }

        bool moduleActive = _isActiveModule(proposal.targetModule);
        if (proposal.registerNewModule == moduleActive) {
            revert InvalidModuleGovernanceProposal(
                proposal.targetModule, proposal.newModuleAddress, proposal.registerNewModule
            );
        }
    }

    /// @dev Proposal fees are ERC20 (the policy's fee asset, LLM by convention) pulled straight into the treasury
    ///      vault, so the proposer must approve this app for the fee before creating a referendum.
    function _collectProposalFee(uint256 requiredFee) private {
        if (requiredFee == 0) {
            return;
        }

        address treasuryVault =
            IConstitutionKernel(_governanceRouter.kernel()).getModule(KernelModuleIds.TREASURY_VAULT);
        IERC20(_currentReferendumPolicy().proposalFeeAsset()).safeTransferFrom(msg.sender, treasuryVault, requiredFee);
    }

    /// @dev O(1): registry mutation hooks maintain historical civic-roll checkpoints. A citizen-policy replacement
    ///      starts a bounded permissionless rebuild; a new process must use a completed block in the current epoch.
    function _electorateSnapshotAt(uint48 snapshotBlock)
        private
        view
        returns (uint256 citizenCount, uint256 electorateVotingPower)
    {
        IElectorateRegistry electorateRegistry = IElectorateRegistry(
            IConstitutionKernel(_governanceRouter.kernel()).getModule(KernelModuleIds.ELECTORATE_REGISTRY)
        );
        IVotingPowerPolicy votingPolicy = _currentVotingPowerPolicy();
        address policyElectorateRegistry = votingPolicy.electorateRegistry();
        if (policyElectorateRegistry != address(electorateRegistry)) {
            revert VotingPowerElectorateMismatch(
                address(votingPolicy), policyElectorateRegistry, address(electorateRegistry)
            );
        }
        return electorateRegistry.snapshotAtCurrentEpoch(snapshotBlock);
    }

    function _storeLegislationReferendumProposal(
        bytes32 referendumId,
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.LegislationProposal calldata proposal,
        bytes32 proposerReference
    ) private {
        uint48 votingPowerSnapshotBlock = _lastCompletedBlock();
        (uint256 snapshotHeadcount, uint256 snapshotVotingPower) = _electorateSnapshotAt(votingPowerSnapshotBlock);
        if (referendumClass != ReferendumTypes.ReferendumClass.ConstitutionalAmendment) {
            snapshotHeadcount = 0;
            snapshotVotingPower = 0;
        }

        ReferendumTypes.ReferendumRecordInput memory referendumInput = ReferendumTypes.ReferendumRecordInput({
            referendumClass: referendumClass,
            proposalOrigin: proposalOrigin,
            proposalMetadataHash: proposal.proposalMetadataHash,
            proposedMeasureId: proposal.proposedMeasureId,
            amendsMeasureId: proposal.amendsMeasureId,
            legislationTextHash: proposal.legislationTextHash,
            legislationTier: proposal.legislationTier,
            targetModule: bytes32(0),
            proposedModuleAddress: address(0),
            registerNewModule: false,
            proposerReference: proposerReference,
            startTime: proposal.startTime,
            endTime: proposal.endTime,
            adoptionDelay: proposal.adoptionDelay,
            votingPowerSnapshotBlock: votingPowerSnapshotBlock,
            referendumPolicy: address(_currentReferendumPolicy()),
            votingPowerPolicy: address(_currentVotingPowerPolicy()),
            electorateHeadcountSnapshot: snapshotHeadcount,
            electorateVotingPowerSnapshot: snapshotVotingPower,
            requiresSupermajority: false
        });

        _referendumRegistry.createReferendum(referendumId, referendumInput);
    }

    function _storeCongressElectionPolicyReferendumProposal(
        bytes32 referendumId,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.CongressElectionPolicyProposal calldata proposal,
        bytes32 proposerReference
    ) private {
        uint48 votingPowerSnapshotBlock = _lastCompletedBlock();
        _electorateSnapshotAt(votingPowerSnapshotBlock);
        ReferendumTypes.ReferendumRecordInput memory referendumInput = ReferendumTypes.ReferendumRecordInput({
            referendumClass: ReferendumTypes.ReferendumClass.CongressElectionPolicy,
            proposalOrigin: proposalOrigin,
            proposalMetadataHash: proposal.proposalMetadataHash,
            proposedMeasureId: proposal.proposalId,
            amendsMeasureId: bytes32(0),
            legislationTextHash: bytes32(0),
            legislationTier: LegislationTypes.LegislationTier.Undefined,
            targetModule: KernelModuleIds.CONGRESS_ELECTION_POLICY,
            proposedModuleAddress: proposal.newPolicy,
            registerNewModule: false,
            proposerReference: proposerReference,
            startTime: proposal.startTime,
            endTime: proposal.endTime,
            adoptionDelay: proposal.adoptionDelay,
            votingPowerSnapshotBlock: votingPowerSnapshotBlock,
            referendumPolicy: address(_currentReferendumPolicy()),
            votingPowerPolicy: address(_currentVotingPowerPolicy()),
            electorateHeadcountSnapshot: 0,
            electorateVotingPowerSnapshot: 0,
            requiresSupermajority: false
        });

        _referendumRegistry.createReferendum(referendumId, referendumInput);
    }

    function _storeBudgetApprovalReferendumProposal(
        bytes32 referendumId,
        ReferendumTypes.BudgetApprovalProposal calldata proposal,
        bytes32 proposerReference
    ) private {
        uint48 votingPowerSnapshotBlock = _lastCompletedBlock();
        _electorateSnapshotAt(votingPowerSnapshotBlock);
        ReferendumTypes.ReferendumRecordInput memory referendumInput = ReferendumTypes.ReferendumRecordInput({
            referendumClass: ReferendumTypes.ReferendumClass.BudgetApproval,
            proposalOrigin: ReferendumTypes.ProposalOrigin.Congress,
            proposalMetadataHash: proposal.proposalMetadataHash,
            proposedMeasureId: proposal.budgetId,
            amendsMeasureId: bytes32(0),
            legislationTextHash: proposal.budgetLawTextHash,
            legislationTier: LegislationTypes.LegislationTier.Law,
            targetModule: KernelModuleIds.BUDGET_ENVELOPE_REGISTRY,
            proposedModuleAddress: address(0),
            registerNewModule: false,
            proposerReference: proposerReference,
            startTime: proposal.startTime,
            endTime: proposal.endTime,
            adoptionDelay: proposal.adoptionDelay,
            votingPowerSnapshotBlock: votingPowerSnapshotBlock,
            referendumPolicy: address(_currentReferendumPolicy()),
            votingPowerPolicy: address(_currentVotingPowerPolicy()),
            electorateHeadcountSnapshot: 0,
            electorateVotingPowerSnapshot: 0,
            requiresSupermajority: false
        });

        _referendumRegistry.createBudgetApprovalReferendum(referendumId, referendumInput, proposal.budget);
    }

    function _storeModuleGovernanceReferendumProposal(
        bytes32 referendumId,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.ModuleGovernanceProposal calldata proposal,
        bytes32 proposerReference
    ) private {
        // Repointing a rule-defining module (authority/policy/registry) must clear the constitutional
        // double-threshold, so it takes the same electorate snapshot amendments take at creation.
        bool requiresSupermajority = _requiresGovernanceSupermajority(proposal.targetModule);
        uint48 votingPowerSnapshotBlock = _lastCompletedBlock();
        (uint256 snapshotHeadcount, uint256 snapshotVotingPower) = _electorateSnapshotAt(votingPowerSnapshotBlock);
        if (!requiresSupermajority) {
            snapshotHeadcount = 0;
            snapshotVotingPower = 0;
        }

        ReferendumTypes.ReferendumRecordInput memory referendumInput = ReferendumTypes.ReferendumRecordInput({
            referendumClass: ReferendumTypes.ReferendumClass.ModuleGovernance,
            proposalOrigin: proposalOrigin,
            proposalMetadataHash: proposal.proposalMetadataHash,
            proposedMeasureId: proposal.proposalId,
            amendsMeasureId: bytes32(0),
            legislationTextHash: bytes32(0),
            legislationTier: LegislationTypes.LegislationTier.Undefined,
            targetModule: proposal.targetModule,
            proposedModuleAddress: proposal.newModuleAddress,
            registerNewModule: proposal.registerNewModule,
            proposerReference: proposerReference,
            startTime: proposal.startTime,
            endTime: proposal.endTime,
            adoptionDelay: proposal.adoptionDelay,
            votingPowerSnapshotBlock: votingPowerSnapshotBlock,
            referendumPolicy: address(_currentReferendumPolicy()),
            votingPowerPolicy: address(_currentVotingPowerPolicy()),
            electorateHeadcountSnapshot: snapshotHeadcount,
            electorateVotingPowerSnapshot: snapshotVotingPower,
            requiresSupermajority: requiresSupermajority
        });

        _referendumRegistry.createReferendum(referendumId, referendumInput);
    }

    function _resolveProposerReference(ReferendumTypes.ProposalOrigin proposalOrigin)
        private
        view
        returns (bytes32 proposerReference)
    {
        if (proposalOrigin == ReferendumTypes.ProposalOrigin.Citizen) {
            proposerReference = _identityRegistry.resolveWalletToPersonId(msg.sender);
            if (proposerReference == bytes32(0)) {
                revert InvalidProposerReference(msg.sender);
            }

            return proposerReference;
        }

        return _addressToReference(msg.sender);
    }

    function _previewReferendumId(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.LegislationProposal calldata proposal,
        bytes32 proposerReference
    ) private pure returns (bytes32 referendumId) {
        return keccak256(
            abi.encode(
                referendumClass,
                proposalOrigin,
                proposal.proposalMetadataHash,
                proposal.proposedMeasureId,
                proposal.amendsMeasureId,
                proposal.legislationTextHash,
                proposal.legislationTier,
                proposerReference,
                proposal.startTime,
                proposal.endTime,
                proposal.adoptionDelay,
                proposal.emergency
            )
        );
    }

    function _previewCongressElectionPolicyReferendumId(
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.CongressElectionPolicyProposal calldata proposal,
        bytes32 proposerReference
    ) private pure returns (bytes32 referendumId) {
        return keccak256(
            abi.encode(
                ReferendumTypes.ReferendumClass.CongressElectionPolicy,
                proposalOrigin,
                proposal.proposalMetadataHash,
                proposal.proposalId,
                KernelModuleIds.CONGRESS_ELECTION_POLICY,
                proposal.newPolicy,
                proposerReference,
                proposal.startTime,
                proposal.endTime,
                proposal.adoptionDelay
            )
        );
    }

    function _previewBudgetApprovalReferendumId(
        ReferendumTypes.BudgetApprovalProposal calldata proposal,
        bytes32 proposerReference
    ) private pure returns (bytes32 referendumId) {
        return keccak256(
            abi.encode(
                ReferendumTypes.ReferendumClass.BudgetApproval,
                ReferendumTypes.ProposalOrigin.Congress,
                proposal,
                proposerReference,
                "budget-approval-v1"
            )
        );
    }

    function _previewModuleGovernanceReferendumId(
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.ModuleGovernanceProposal calldata proposal,
        bytes32 proposerReference
    ) private pure returns (bytes32 referendumId) {
        return keccak256(
            abi.encode(
                ReferendumTypes.ReferendumClass.ModuleGovernance,
                proposalOrigin,
                proposal.proposalMetadataHash,
                proposal.proposalId,
                proposal.targetModule,
                proposal.newModuleAddress,
                proposal.registerNewModule,
                proposerReference,
                proposal.startTime,
                proposal.endTime,
                proposal.adoptionDelay
            )
        );
    }

    function _queueLegislationEnactment(
        bytes32 referendumId,
        ReferendumTypes.ReferendumRecord memory referendumRecord,
        bytes32 enactedMeasureId
    ) private returns (bytes32 actionId) {
        GovernanceTypes.LegislationEnactmentPayload memory payload =
            GovernanceTypes.LegislationEnactmentPayload({
                measureId: enactedMeasureId,
                tier: referendumRecord.legislationTier,
                textHash: referendumRecord.legislationTextHash,
                proposerReference: referendumRecord.proposerReference,
                enactedByReferendumId: referendumId,
                amendsMeasureId: referendumRecord.amendsMeasureId
            });

        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.LegislationEnactment,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: referendumId,
            policyReference: _policyReference(referendumRecord),
            targetModule: KernelModuleIds.LEGISLATION_REGISTRY,
            payload: abi.encode(payload),
            requestedExecutionTime: _requestedExecutionTime(referendumId, referendumRecord),
            expiresAt: 0
        });

        actionId = _governanceRouter.routeAction(request);
    }

    function _queueCongressElectionPolicyUpdate(
        bytes32 referendumId,
        ReferendumTypes.ReferendumRecord memory referendumRecord
    ) private returns (bytes32 actionId) {
        GovernanceTypes.ModuleUpdatePayload memory payload =
            GovernanceTypes.ModuleUpdatePayload({newModuleAddress: referendumRecord.proposedModuleAddress});

        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.ModulePointerUpdate,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: referendumId,
            policyReference: _policyReference(referendumRecord),
            targetModule: referendumRecord.targetModule,
            payload: abi.encode(payload),
            requestedExecutionTime: _requestedExecutionTime(referendumId, referendumRecord),
            expiresAt: 0
        });

        actionId = _governanceRouter.routeAction(request);
    }

    function _queueModuleGovernance(bytes32 referendumId, ReferendumTypes.ReferendumRecord memory referendumRecord)
        private
        returns (bytes32 actionId)
    {
        GovernanceTypes.ModuleUpdatePayload memory payload =
            GovernanceTypes.ModuleUpdatePayload({newModuleAddress: referendumRecord.proposedModuleAddress});

        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: referendumRecord.registerNewModule
                ? GovernanceTypes.ActionType.ModuleRegistration
                : GovernanceTypes.ActionType.ModulePointerUpdate,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: referendumId,
            policyReference: _policyReference(referendumRecord),
            targetModule: referendumRecord.targetModule,
            payload: abi.encode(payload),
            requestedExecutionTime: _requestedExecutionTime(referendumId, referendumRecord),
            expiresAt: 0
        });

        actionId = _governanceRouter.routeAction(request);
    }

    function _queueBudgetApproval(bytes32 referendumId, ReferendumTypes.ReferendumRecord memory referendumRecord)
        private
        returns (bytes32 actionId)
    {
        GovernanceTypes.TreasuryBudgetApprovalPayload memory payload =
            _budgetApprovalPayload(referendumId, referendumRecord);

        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.TreasuryBudgetApproval,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: referendumId,
            policyReference: _policyReference(referendumRecord),
            targetModule: KernelModuleIds.BUDGET_ENVELOPE_REGISTRY,
            payload: abi.encode(payload),
            requestedExecutionTime: _requestedExecutionTime(referendumId, referendumRecord),
            expiresAt: 0
        });

        actionId = _governanceRouter.routeAction(request);
    }

    function _budgetApprovalPayload(bytes32 referendumId, ReferendumTypes.ReferendumRecord memory referendumRecord)
        private
        view
        returns (GovernanceTypes.TreasuryBudgetApprovalPayload memory payload)
    {
        ReferendumTypes.BudgetApprovalDetails memory budgetDetails =
            _referendumRegistry.getBudgetApprovalDetails(referendumId);

        return GovernanceTypes.TreasuryBudgetApprovalPayload({
            budgetId: referendumRecord.proposedMeasureId,
            officeId: budgetDetails.officeId,
            disbursementType: budgetDetails.disbursementType,
            asset: budgetDetails.asset,
            allocatedAmount: budgetDetails.allocatedAmount,
            startsAt: budgetDetails.startsAt,
            endsAt: budgetDetails.endsAt,
            policyReference: _policyReference(referendumRecord)
        });
    }

    function _storeReferendumResult(
        bytes32 referendumId,
        ReferendumTypes.PolicyOutcome memory outcome,
        bytes32 enactedMeasureId,
        bytes32 enactmentActionId
    ) private {
        ReferendumTypes.ReferendumResultInput memory resultInput =
            ReferendumTypes.ReferendumResultInput({
                turnout: outcome.turnout,
                quorumRequired: outcome.quorumRequired,
                headcountQuorumRequired: outcome.headcountQuorumRequired,
                electorateVotingPower: outcome.electorateVotingPower,
                quorumMet: outcome.quorumMet,
                passed: outcome.passed,
                enactedMeasureId: enactedMeasureId,
                enactmentActionId: enactmentActionId
            });

        _referendumRegistry.finalizeReferendum(referendumId, resultInput);
    }

    function _policyReference(ReferendumTypes.ReferendumRecord memory referendumRecord)
        private
        pure
        returns (bytes32 policyReference)
    {
        return keccak256(
            abi.encode(
                referendumRecord.referendumPolicy,
                referendumRecord.votingPowerPolicy,
                referendumRecord.votingPowerSnapshotBlock,
                referendumRecord.referendumClass,
                referendumRecord.proposalOrigin,
                referendumRecord.legislationTier,
                referendumRecord.targetModule,
                referendumRecord.proposedModuleAddress,
                referendumRecord.registerNewModule
            )
        );
    }

    function _requestedExecutionTime(bytes32 referendumId, ReferendumTypes.ReferendumRecord memory referendumRecord)
        private
        view
        returns (uint64 executionTime)
    {
        return referendumRecord.endTime + _referendumRegistry.adoptionDelayOf(referendumId);
    }

    function _validateBudgetProposal(ReferendumTypes.BudgetApprovalProposal calldata proposal) private view {
        IConstitutionKernel kernel = IConstitutionKernel(_governanceRouter.kernel());
        if (
            proposal.budgetId == bytes32(0) || proposal.budgetLawTextHash == bytes32(0)
                || proposal.budget.officeId == bytes32(0)
                || proposal.budget.disbursementType == TreasuryTypes.DisbursementType.Undefined
                || proposal.budget.asset == address(0) || proposal.budget.asset.code.length == 0
                || proposal.budget.allocatedAmount == 0 || proposal.budget.endsAt <= proposal.budget.startsAt
                || IBudgetEnvelopeRegistry(kernel.getModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY))
                    .budgetExists(proposal.budgetId)
                // Fail fast: an asset the spending policy does not allow would produce an approved-but-unspendable
                // budget (payouts require ITreasurySpendingPolicy.isAssetAllowed). Best-effort at creation time.
                || !ITreasurySpendingPolicy(kernel.getModule(KernelModuleIds.TREASURY_SPENDING_POLICY))
                    .isAssetAllowed(proposal.budget.asset)
        ) {
            revert InvalidBudgetProposal(proposal.budgetId);
        }
    }

    function _requireNoPendingSenateVeto(bytes32 referendumId, ReferendumTypes.ReferendumRecord memory referendumRecord)
        private
        view
    {
        // The Senate's negative power cannot make its own application pointer irrevocable. This check precedes the
        // optional Senate hook so even an incompatible or malicious incumbent cannot fabricate a pending veto.
        if (_isSenateSelfReplacement(referendumRecord)) {
            return;
        }

        address senateAppAddress = address(0);
        try IConstitutionKernel(_governanceRouter.kernel()).getModule(KernelModuleIds.SENATE_APP) returns (
            address moduleAddress
        ) {
            senateAppAddress = moduleAddress;
        } catch {
            return;
        }

        // This is an optional negative-power hook. A future audited Senate implementation may intentionally use a
        // different interface; that must disable the hook, not brick referendum finalization and therefore module
        // governance itself.
        try ISenateApp(senateAppAddress).getReferendumVetoRecord(referendumId) returns (
            SenateTypes.ReferendumVetoRecord memory vetoRecord
        ) {
            if (
                vetoRecord.exists && !vetoRecord.finalized && vetoRecord.deadline != 0
                    && block.timestamp >= vetoRecord.deadline
            ) {
                revert SenateVetoPending(referendumId, vetoRecord.deadline);
            }
        } catch {}
    }

    function _isSenateSelfReplacement(ReferendumTypes.ReferendumRecord memory referendumRecord)
        private
        pure
        returns (bool selfReplacement)
    {
        return referendumRecord.referendumClass == ReferendumTypes.ReferendumClass.ModuleGovernance
            && referendumRecord.targetModule == KernelModuleIds.SENATE_APP;
    }

    function _validateProposedCongressElectionPolicy(address newPolicyAddress) private view {
        if (newPolicyAddress == address(0) || newPolicyAddress.code.length == 0) {
            revert InvalidProposedCongressElectionPolicy(newPolicyAddress);
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
            revert InvalidProposedCongressElectionPolicy(newPolicyAddress);
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

    function _currentReferendumPolicy() private view returns (IReferendumPolicy policy) {
        return
            IReferendumPolicy(
                IConstitutionKernel(_governanceRouter.kernel()).getModule(KernelModuleIds.REFERENDUM_POLICY)
            );
    }

    function _currentVotingPowerPolicy() private view returns (IVotingPowerPolicy policy) {
        return IVotingPowerPolicy(
            IConstitutionKernel(_governanceRouter.kernel()).getModule(KernelModuleIds.VOTING_POWER_POLICY)
        );
    }

    /// @dev Using the last completed block makes the snapshot immune to later transactions in the creation block.
    function _lastCompletedBlock() private view returns (uint48 snapshotBlock) {
        return block.number == 0 ? 0 : SafeCast.toUint48(block.number - 1);
    }

    /// @notice Returns whether repointing a module must clear the constitutional-amendment double-threshold
    ///         (>=50% of the electorate by headcount AND >=65% of cast voting power) instead of the ordinary
    ///         module-governance quorum.
    /// @dev Policy, authority, state-bearing, and unclassified modules use the constitutional threshold. Known
    ///      operational application pointers use the ordinary threshold. Core `governance-router` and
    ///      `action-timelock` are blocked upstream in `_validateModuleGovernanceProposal` and never reach here. The dedicated
    ///      Congress-election-policy referendum remains a lower-friction timing-only path; a full breaking policy
    ///      replacement uses this constitutional module-governance path.
    /// @param moduleId The target module identifier being repointed or registered.
    /// @return requiresSupermajority Whether the repoint must clear the constitutional double-threshold.
    function _requiresGovernanceSupermajority(bytes32 moduleId) private view returns (bool requiresSupermajority) {
        if (!_isActiveModule(moduleId)) {
            return true;
        }
        GovernanceTypes.ModuleClass moduleClass = IConstitutionKernel(_governanceRouter.kernel()).moduleClass(moduleId);
        return moduleClass != GovernanceTypes.ModuleClass.Application;
    }

    function _addressToReference(address account) private pure returns (bytes32 accountReference) {
        return bytes32(uint256(uint160(account)));
    }
}
