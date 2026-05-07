// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IGovernanceRouter} from "../interfaces/IGovernanceRouter.sol";
import {ICongressElectionPolicy} from "../interfaces/ICongressElectionPolicy.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {IReferendumApp} from "../interfaces/IReferendumApp.sol";
import {IReferendumPolicy} from "../interfaces/IReferendumPolicy.sol";
import {IReferendumRegistry} from "../interfaces/IReferendumRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {IVotingPowerPolicy} from "../interfaces/IVotingPowerPolicy.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {ReferendumTypes} from "../types/ReferendumTypes.sol";

/// @title ReferendumApp
/// @notice User-facing application for legislation referendum proposal, voting, and finalization.
contract ReferendumApp is IReferendumApp {
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
    function castVote(bytes32 referendumId, ReferendumTypes.VoteOption option) external {
        if (option != ReferendumTypes.VoteOption.Against && option != ReferendumTypes.VoteOption.For) {
            revert InvalidVoteOption(option);
        }

        ReferendumTypes.ReferendumRecord memory referendumRecord = _referendumRegistry.getReferendum(referendumId);
        if (referendumRecord.referendumId == bytes32(0)) {
            revert IReferendumRegistry.ReferendumNotFound(referendumId);
        }

        ReferendumTypes.VoteReceipt memory existingReceipt =
            _referendumRegistry.getVoteReceipt(referendumId, msg.sender);
        uint256 weight = existingReceipt.option == ReferendumTypes.VoteOption.Undefined
            ? _votingPowerPolicy.votingPower(msg.sender)
            : existingReceipt.weight;
        if (weight == 0) {
            revert NoVotingPower(msg.sender);
        }

        _referendumRegistry.recordVote(referendumId, msg.sender, option, weight);
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

        ReferendumTypes.PolicyOutcome memory outcome = _referendumPolicy.evaluateOutcome(
            referendumRecord.referendumClass,
            referendumRecord.proposalOrigin,
            referendumRecord.forVotes,
            referendumRecord.againstVotes,
            referendumRecord.forVoterCount,
            referendumRecord.againstVoterCount
        );

        bytes32 enactedMeasureId;
        bytes32 enactmentActionId;
        if (outcome.passed) {
            enactedMeasureId = referendumRecord.proposedMeasureId;
            if (referendumRecord.referendumClass == ReferendumTypes.ReferendumClass.CongressElectionPolicy) {
                enactmentActionId = _queueCongressElectionPolicyUpdate(referendumId, referendumRecord);
            } else {
                enactmentActionId = _queueLegislationEnactment(referendumId, referendumRecord, enactedMeasureId);
            }
        }

        _storeReferendumResult(referendumId, outcome, enactedMeasureId, enactmentActionId);
    }

    function _createReferendum(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.LegislationProposal calldata proposal,
        ReferendumTypes.ProposalOrigin proposalOrigin
    ) private returns (bytes32 referendumId) {
        if (!_referendumPolicy.canCreateReferendum(referendumClass, proposalOrigin, msg.sender)) {
            revert InvalidProposerOrigin(msg.sender, proposalOrigin);
        }

        uint256 requiredFee = _referendumPolicy.proposalFee(proposalOrigin);
        if (requiredFee != 0) {
            revert InvalidProposalFee(requiredFee);
        }

        _validateVotingWindow(proposal.startTime, proposal.endTime);
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
        if (!_referendumPolicy.canCreateReferendum(referendumClass, proposalOrigin, msg.sender)) {
            revert InvalidProposerOrigin(msg.sender, proposalOrigin);
        }

        uint256 requiredFee = _referendumPolicy.proposalFee(proposalOrigin);
        if (requiredFee != 0) {
            revert InvalidProposalFee(requiredFee);
        }

        _validateVotingWindow(proposal.startTime, proposal.endTime);
        _validateProposedCongressElectionPolicy(proposal.newPolicy);

        bytes32 proposerReference = _resolveProposerReference(proposalOrigin);
        referendumId = _previewCongressElectionPolicyReferendumId(proposalOrigin, proposal, proposerReference);
        _storeCongressElectionPolicyReferendumProposal(referendumId, proposalOrigin, proposal, proposerReference);
    }

    function _validateVotingWindow(uint64 startTime, uint64 endTime) private view {
        uint64 minimumDuration = _referendumPolicy.minimumVotingDuration();
        if (startTime < block.timestamp || endTime <= startTime || endTime - startTime < minimumDuration) {
            revert InvalidVotingWindow(startTime, endTime, minimumDuration);
        }
    }

    function _validateProposalTargets(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.LegislationProposal calldata proposal
    ) private view {
        if (
            referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment
                && proposal.legislationTier != LegislationTypes.LegislationTier.ConstitutionalLaw
        ) {
            revert InvalidLegislationTier(uint8(proposal.legislationTier));
        }
        if (
            referendumClass == ReferendumTypes.ReferendumClass.Legislation
                && proposal.legislationTier == LegislationTypes.LegislationTier.ConstitutionalLaw
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

    function _storeLegislationReferendumProposal(
        bytes32 referendumId,
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        ReferendumTypes.LegislationProposal calldata proposal,
        bytes32 proposerReference
    ) private {
        ReferendumTypes.ReferendumRecordInput memory
            referendumInput =
            ReferendumTypes.ReferendumRecordInput({
                referendumClass: referendumClass,
                proposalOrigin: proposalOrigin,
                proposalMetadataHash: proposal.proposalMetadataHash,
                proposedMeasureId: proposal.proposedMeasureId,
                amendsMeasureId: proposal.amendsMeasureId,
                legislationTextHash: proposal.legislationTextHash,
                legislationTier: proposal.legislationTier,
                targetModule: bytes32(0),
                proposedModuleAddress: address(0),
                proposerReference: proposerReference,
                startTime: proposal.startTime,
                endTime: proposal.endTime
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
                proposerReference: proposerReference,
                startTime: proposal.startTime,
                endTime: proposal.endTime
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
                proposal.endTime
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
                proposal.endTime
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
            requestedExecutionTime: 0,
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
            requestedExecutionTime: 0,
            expiresAt: 0
        });

        actionId = _governanceRouter.routeAction(request);
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
                referendumRecord.proposedModuleAddress
            )
        );
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

    function _addressToReference(address account) private pure returns (bytes32 accountReference) {
        return bytes32(uint256(uint160(account)));
    }
}
