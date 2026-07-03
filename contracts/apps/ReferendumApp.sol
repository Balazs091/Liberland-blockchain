// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGovernanceRouter} from "../interfaces/IGovernanceRouter.sol";
import {ICongressElectionPolicy} from "../interfaces/ICongressElectionPolicy.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IBudgetEnvelopeRegistry} from "../interfaces/IBudgetEnvelopeRegistry.sol";
import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {IReferendumApp} from "../interfaces/IReferendumApp.sol";
import {IReferendumPolicy} from "../interfaces/IReferendumPolicy.sol";
import {IReferendumRegistry} from "../interfaces/IReferendumRegistry.sol";
import {ISenateApp} from "../interfaces/ISenateApp.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {IVotingPowerPolicy} from "../interfaces/IVotingPowerPolicy.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {ReferendumTypes} from "../types/ReferendumTypes.sol";
import {SenateTypes} from "../types/SenateTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title ReferendumApp
/// @notice User-facing application for bounded referendum proposal, voting, veto, and finalization flows.
contract ReferendumApp is IReferendumApp {
    using SafeERC20 for IERC20;

    error InvalidPolicy(address policyAddress);
    error InvalidRegistry(address registryAddress);

    IIdentityRegistry private immutable _identityRegistry;
    ILegislationRegistry private immutable _legislationRegistry;
    IReferendumPolicy private immutable _referendumPolicy;
    IReferendumRegistry private immutable _referendumRegistry;
    IGovernanceRouter private immutable _governanceRouter;
    IVotingPowerPolicy private immutable _votingPowerPolicy;

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
        _referendumPolicy = IReferendumPolicy(referendumPolicyAddress);
        _governanceRouter = IGovernanceRouter(governanceRouterAddress);
        _votingPowerPolicy = IVotingPowerPolicy(votingPowerPolicyAddress);
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
        return address(_referendumPolicy);
    }

    /// @inheritdoc IReferendumApp
    function governanceRouter() external view returns (address routerAddress) {
        return address(_governanceRouter);
    }

    /// @inheritdoc IReferendumApp
    function votingPowerPolicy() external view returns (address policyAddress) {
        return address(_votingPowerPolicy);
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
        ReferendumTypes.VoteReceipt memory existingReceipt = _referendumRegistry.getVoteReceipt(referendumId, personId);
        uint256 weight = existingReceipt.option == ReferendumTypes.VoteOption.Undefined
            ? _votingPowerPolicy.votingPower(msg.sender)
            : existingReceipt.weight;
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
        _requireNoPendingSenateVeto(referendumId);

        ReferendumTypes.PolicyOutcome memory outcome = _referendumPolicy.evaluateOutcome(
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
        if (!_referendumPolicy.canCreateReferendum(referendumClass, proposalOrigin, msg.sender)) {
            revert InvalidProposerOrigin(msg.sender, proposalOrigin);
        }

        _collectProposalFee(_referendumPolicy.proposalFee(proposalOrigin));
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
            ? _referendumPolicy.emergencyVotingDuration()
            : _referendumPolicy.minimumVotingDuration();
        if (startTime < block.timestamp || endTime <= startTime || endTime - startTime < minimumDuration) {
            revert InvalidVotingWindow(startTime, endTime, minimumDuration);
        }
        if (adoptionDelay > _referendumPolicy.maximumAdoptionDelay()) {
            revert InvalidAdoptionDelay(adoptionDelay, _referendumPolicy.maximumAdoptionDelay());
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
                && adoptionDelay != _referendumPolicy.standardAdoptionDelay()
        ) {
            revert InvalidAdoptionDelay(adoptionDelay, _referendumPolicy.standardAdoptionDelay());
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
        // to gate. Amending them therefore requires a fresh deployment and state migration rather than an in-band
        // vote. Rule-defining registries/authorities/policies stay live-repointable but only clear the constitutional
        // supermajority (see `_requiresGovernanceSupermajority`); ordinary app pointers use the standard quorum.
        if (
            proposal.targetModule == bytes32(0) || proposal.newModuleAddress == address(0)
                || proposal.newModuleAddress.code.length == 0 || _isCoreModule(proposal.targetModule)
                || _isSpecializedModuleGovernanceTarget(proposal.targetModule)
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
        IERC20(_referendumPolicy.proposalFeeAsset()).safeTransferFrom(msg.sender, treasuryVault, requiredFee);
    }

    /// @dev O(n) over the whole identity set, so constitutional-tier referendum-creation gas is bounded by the
    ///      electorate size (a full incremental aggregate is out of scope). Each identity is priced by a single
    ///      `getCitizenshipSummary` read (no `metadataURI` string copy) plus one reused `activeStakeOf` read.
    function _constitutionalElectorateSnapshot()
        private
        view
        returns (uint256 citizenCount, uint256 electorateVotingPower)
    {
        ICitizenEligibilityPolicy citizenEligibilityPolicy =
            ICitizenEligibilityPolicy(_referendumPolicy.citizenEligibilityPolicy());
        IStakeRegistry stakeRegistry = IStakeRegistry(citizenEligibilityPolicy.stakeRegistry());
        uint256 minimumCitizenStake = citizenEligibilityPolicy.minimumCitizenStake();
        uint256 identityCount = _identityRegistry.totalIdentityCount();

        for (uint256 index = 0; index < identityCount; ++index) {
            bytes32 personId = _identityRegistry.identityIdAt(index);
            uint256 activeStake = stakeRegistry.activeStakeOf(personId);
            if (!_isEligibleCitizenPerson(stakeRegistry, minimumCitizenStake, personId, activeStake)) {
                continue;
            }

            citizenCount += 1;
            electorateVotingPower += activeStake;
        }
    }

    function _isEligibleCitizenPerson(
        IStakeRegistry stakeRegistry,
        uint256 minimumCitizenStake,
        bytes32 personId,
        uint256 activeStake
    ) private view returns (bool eligible) {
        if (_identityRegistry.activeWalletCountOf(personId) == 0) {
            return false;
        }

        (
            IdentityTypes.VerificationStatus verificationStatus,
            IdentityTypes.CitizenshipStatus citizenshipStatus,
            IdentityTypes.AgeClass ageClass,
            bool finalSuspension
        ) = _identityRegistry.getCitizenshipSummary(personId);
        // A non-existent identity reports an Undefined citizenship status, which fails the Citizen check below,
        // so an explicit existence guard is unnecessary and the result matches the prior full-record path.
        if (verificationStatus != IdentityTypes.VerificationStatus.Verified) {
            return false;
        }
        if (citizenshipStatus != IdentityTypes.CitizenshipStatus.Citizen) {
            return false;
        }
        if (ageClass != IdentityTypes.AgeClass.Adult || finalSuspension) {
            return false;
        }
        if (activeStake < minimumCitizenStake) {
            return false;
        }

        return !stakeRegistry.isInWelfare(personId);
    }

    function _storeLegislationReferendumProposal(
        bytes32 referendumId,
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.LegislationProposal calldata proposal,
        bytes32 proposerReference
    ) private {
        uint256 electorateHeadcountSnapshot = 0;
        uint256 electorateVotingPowerSnapshot = 0;
        if (referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment) {
            (electorateHeadcountSnapshot, electorateVotingPowerSnapshot) = _constitutionalElectorateSnapshot();
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
            electorateHeadcountSnapshot: electorateHeadcountSnapshot,
            electorateVotingPowerSnapshot: electorateVotingPowerSnapshot,
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
        ReferendumTypes.ReferendumRecordInput memory
            referendumInput =
            ReferendumTypes.ReferendumRecordInput({
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
        ReferendumTypes.ReferendumRecordInput memory referendumInput =
            ReferendumTypes.ReferendumRecordInput({
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
        uint256 electorateHeadcountSnapshot = 0;
        uint256 electorateVotingPowerSnapshot = 0;
        if (requiresSupermajority) {
            (electorateHeadcountSnapshot, electorateVotingPowerSnapshot) = _constitutionalElectorateSnapshot();
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
            electorateHeadcountSnapshot: electorateHeadcountSnapshot,
            electorateVotingPowerSnapshot: electorateVotingPowerSnapshot,
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
        view
        returns (bytes32 policyReference)
    {
        return keccak256(
            abi.encode(
                address(_referendumPolicy),
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
        if (
            proposal.budgetId == bytes32(0) || proposal.budgetLawTextHash == bytes32(0)
                || proposal.budget.officeId == bytes32(0)
                || proposal.budget.disbursementType == TreasuryTypes.DisbursementType.Undefined
                || proposal.budget.asset == address(0) || proposal.budget.asset.code.length == 0
                || proposal.budget.allocatedAmount == 0 || proposal.budget.endsAt <= proposal.budget.startsAt
                || IBudgetEnvelopeRegistry(
                        IConstitutionKernel(_governanceRouter.kernel())
                            .getModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY)
                    ).budgetExists(proposal.budgetId)
        ) {
            revert InvalidBudgetProposal(proposal.budgetId);
        }
    }

    function _requireNoPendingSenateVeto(bytes32 referendumId) private view {
        address senateAppAddress = address(0);
        try IConstitutionKernel(_governanceRouter.kernel()).getModule(KernelModuleIds.SENATE_APP) returns (
            address moduleAddress
        ) {
            senateAppAddress = moduleAddress;
        } catch {
            return;
        }

        SenateTypes.ReferendumVetoRecord memory vetoRecord =
            ISenateApp(senateAppAddress).getReferendumVetoRecord(referendumId);
        if (
            vetoRecord.exists && !vetoRecord.finalized && vetoRecord.deadline != 0
                && block.timestamp >= vetoRecord.deadline
        ) {
            revert SenateVetoPending(referendumId, vetoRecord.deadline);
        }
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

    function _isSpecializedModuleGovernanceTarget(bytes32 moduleId) private pure returns (bool specializedTarget) {
        return moduleId == KernelModuleIds.CONGRESS_ELECTION_POLICY;
    }

    /// @notice Returns whether repointing a module must clear the constitutional-amendment double-threshold
    ///         (>=50% of the electorate by headcount AND >=65% of cast voting power) instead of the ordinary
    ///         module-governance quorum.
    /// @dev Rule-defining modules are the authorities (`authority.*`), policies (`policy.*`), and registries
    ///      (`registry.*`) enumerated below. Operational app pointers (`app.*`) and the value-holding treasury
    ///      vault stay at the ordinary threshold and return false. Core `governance-router`/`action-timelock`
    ///      are blocked upstream in `_validateModuleGovernanceProposal` and never reach here;
    ///      `CONGRESS_ELECTION_POLICY` is routed through its own specialized class and is likewise omitted.
    ///      ANY NEW rule-defining module id MUST be added to this list so its repoint keeps the supermajority.
    /// @param moduleId The target module identifier being repointed or registered.
    /// @return requiresSupermajority Whether the repoint must clear the constitutional double-threshold.
    function _requiresGovernanceSupermajority(bytes32 moduleId) private pure returns (bool requiresSupermajority) {
        return
        // Rule-defining and value-custody registries (`registry.*`), including the treasury vault: repointing
        // it would strand treasury funds and break disbursements, so it warrants broad consensus.
        moduleId == KernelModuleIds.TREASURY_VAULT || moduleId == KernelModuleIds.IDENTITY_REGISTRY
            || moduleId == KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY
            || moduleId == KernelModuleIds.LEGISLATION_REGISTRY || moduleId == KernelModuleIds.REFERENDUM_REGISTRY
            || moduleId == KernelModuleIds.SENATE_SEAT_REGISTRY || moduleId == KernelModuleIds.STAKE_REGISTRY
            || moduleId == KernelModuleIds.STAKE_LIEN_REGISTRY || moduleId == KernelModuleIds.LAND_REGISTRY
            || moduleId == KernelModuleIds.COMPANY_REGISTRY || moduleId == KernelModuleIds.BUDGET_ENVELOPE_REGISTRY
            || moduleId == KernelModuleIds.OFFICE_REGISTRY || moduleId == KernelModuleIds.PRESIDENT_REGISTRY
            || moduleId == KernelModuleIds.EXECUTIVE_REGISTRY
            // Rule-defining authorities (`authority.*`).
            || moduleId == KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY
            || moduleId == KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.COMPANY_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.INITIAL_SETUP_AUTHORITY
            || moduleId == KernelModuleIds.LAND_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.LEGISLATION_REPEAL_AUTHORITY
            || moduleId == KernelModuleIds.OFFICE_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.PRESIDENT_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.EXECUTIVE_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY
            || moduleId == KernelModuleIds.STAKE_DEPOSIT_AUTHORITY
            || moduleId == KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY
            || moduleId == KernelModuleIds.STAKE_REGISTRY_AUTHORITY
            // Rule-defining policies (`policy.*`); CONGRESS_ELECTION_POLICY uses its specialized class.
            || moduleId == KernelModuleIds.CANDIDATE_ELIGIBILITY_POLICY
            || moduleId == KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY
            || moduleId == KernelModuleIds.OFFICE_PERMISSION_POLICY || moduleId == KernelModuleIds.REFERENDUM_POLICY
            || moduleId == KernelModuleIds.SENATE_POWERS_POLICY || moduleId == KernelModuleIds.TREASURY_SPENDING_POLICY
            || moduleId == KernelModuleIds.VOTING_POWER_POLICY || moduleId == KernelModuleIds.UNSTAKING_POLICY
            || moduleId == KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY
            || moduleId == KernelModuleIds.USDC_INTEREST_RATE_POLICY;
    }

    function _addressToReference(address account) private pure returns (bytes32 accountReference) {
        return bytes32(uint256(uint160(account)));
    }
}
