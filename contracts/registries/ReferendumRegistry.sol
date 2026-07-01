// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IReferendumRegistry} from "../interfaces/IReferendumRegistry.sol";
import {KernelModule} from "../base/KernelModule.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {ReferendumTypes} from "../types/ReferendumTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title ReferendumRegistry
/// @notice Stable fact registry for referendum proposals, mutable vote receipts, and result snapshots.
contract ReferendumRegistry is IReferendumRegistry, KernelModule {
    mapping(bytes32 referendumId => ReferendumTypes.ReferendumRecord referendumRecord) private _referendumRecords;
    mapping(bytes32 referendumId => ReferendumTypes.ReferendumResult referendumResult) private _referendumResults;
    mapping(bytes32 referendumId => ReferendumTypes.BudgetApprovalDetails budgetDetails) private _budgetApprovalDetails;
    mapping(bytes32 referendumId => uint64 adoptionDelay) private _adoptionDelays;
    mapping(bytes32 referendumId => mapping(address voter => ReferendumTypes.VoteReceipt receipt)) private
        _voteReceipts;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IReferendumRegistry
    function getReferendum(bytes32 referendumId)
        external
        view
        returns (ReferendumTypes.ReferendumRecord memory record)
    {
        return _referendumRecords[referendumId];
    }

    /// @inheritdoc IReferendumRegistry
    function getVoteReceipt(bytes32 referendumId, address voter)
        external
        view
        returns (ReferendumTypes.VoteReceipt memory receipt)
    {
        return _voteReceipts[referendumId][voter];
    }

    /// @inheritdoc IReferendumRegistry
    function getReferendumResult(bytes32 referendumId)
        external
        view
        returns (ReferendumTypes.ReferendumResult memory result)
    {
        return _referendumResults[referendumId];
    }

    /// @inheritdoc IReferendumRegistry
    function adoptionDelayOf(bytes32 referendumId) external view returns (uint64 delaySeconds) {
        return _adoptionDelays[referendumId];
    }

    /// @inheritdoc IReferendumRegistry
    function getBudgetApprovalDetails(bytes32 referendumId)
        external
        view
        returns (ReferendumTypes.BudgetApprovalDetails memory details)
    {
        return _budgetApprovalDetails[referendumId];
    }

    /// @inheritdoc IReferendumRegistry
    function referendumExists(bytes32 referendumId) public view returns (bool exists) {
        return _referendumRecords[referendumId].referendumId != bytes32(0);
    }

    /// @inheritdoc IReferendumRegistry
    function hasVoted(bytes32 referendumId, address voter) external view returns (bool voted) {
        return _voteReceipts[referendumId][voter].option != ReferendumTypes.VoteOption.Undefined;
    }

    /// @inheritdoc IReferendumRegistry
    function createReferendum(bytes32 referendumId, ReferendumTypes.ReferendumRecordInput calldata referendumInput)
        external
    {
        _requireRegistryAuthority(msg.sender);
        if (referendumInput.referendumClass == ReferendumTypes.ReferendumClass.BudgetApproval) {
            revert InvalidBudgetPayload(referendumInput.proposedMeasureId);
        }
        _createReferendum(referendumId, referendumInput);
    }

    /// @inheritdoc IReferendumRegistry
    function createBudgetApprovalReferendum(
        bytes32 referendumId,
        ReferendumTypes.ReferendumRecordInput calldata referendumInput,
        ReferendumTypes.BudgetApprovalDetails calldata budgetDetails
    ) external {
        _requireRegistryAuthority(msg.sender);
        _validateBudgetApprovalDetails(referendumInput.proposedMeasureId, budgetDetails);
        _createReferendum(referendumId, referendumInput);
        _budgetApprovalDetails[referendumId] = budgetDetails;
    }

    function _createReferendum(bytes32 referendumId, ReferendumTypes.ReferendumRecordInput calldata referendumInput)
        private
    {
        if (referendumId == bytes32(0)) {
            revert InvalidReferendumId(referendumId);
        }
        if (referendumExists(referendumId)) {
            revert ReferendumAlreadyExists(referendumId);
        }
        if (
            referendumInput.referendumClass != ReferendumTypes.ReferendumClass.Legislation
                && referendumInput.referendumClass != ReferendumTypes.ReferendumClass.ConstitutionalAmendment
                && referendumInput.referendumClass != ReferendumTypes.ReferendumClass.CongressElectionPolicy
                && referendumInput.referendumClass != ReferendumTypes.ReferendumClass.BudgetApproval
                && referendumInput.referendumClass != ReferendumTypes.ReferendumClass.ModuleGovernance
        ) {
            revert InvalidReferendumClass(referendumInput.referendumClass);
        }
        if (
            referendumInput.proposalOrigin != ReferendumTypes.ProposalOrigin.Citizen
                && referendumInput.proposalOrigin != ReferendumTypes.ProposalOrigin.Congress
        ) {
            revert InvalidProposalOrigin(referendumInput.proposalOrigin);
        }
        if (
            referendumInput.referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment
                && referendumInput.proposalOrigin != ReferendumTypes.ProposalOrigin.Congress
        ) {
            revert InvalidProposalOrigin(referendumInput.proposalOrigin);
        }
        if (referendumInput.proposalMetadataHash == bytes32(0)) {
            revert InvalidProposalMetadataHash(referendumInput.proposalMetadataHash);
        }
        if (referendumInput.proposedMeasureId == bytes32(0)) {
            revert InvalidProposedMeasureId(referendumInput.proposedMeasureId);
        }
        if (referendumInput.proposerReference == bytes32(0)) {
            revert InvalidProposerReference(referendumInput.proposerReference);
        }
        if (referendumInput.referendumClass == ReferendumTypes.ReferendumClass.CongressElectionPolicy) {
            if (
                referendumInput.targetModule != KernelModuleIds.CONGRESS_ELECTION_POLICY
                    || referendumInput.proposedModuleAddress == address(0)
                    || referendumInput.proposedModuleAddress.code.length == 0
            ) {
                revert InvalidProposedModule(referendumInput.targetModule, referendumInput.proposedModuleAddress);
            }
        } else if (referendumInput.referendumClass == ReferendumTypes.ReferendumClass.ModuleGovernance) {
            _validateModuleGovernanceReferendum(referendumInput);
        } else if (referendumInput.referendumClass == ReferendumTypes.ReferendumClass.BudgetApproval) {
            _validateBudgetApprovalReferendum(referendumInput);
        } else {
            if (referendumInput.legislationTextHash == bytes32(0)) {
                revert InvalidTextHash(referendumInput.legislationTextHash);
            }
            if (referendumInput.legislationTier == LegislationTypes.LegislationTier.Undefined) {
                revert InvalidLegislationTier(uint8(referendumInput.legislationTier));
            }
            if (
                referendumInput.referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment
                    && !LegislationTypes.isConstitutionalTier(referendumInput.legislationTier)
            ) {
                revert InvalidLegislationTier(uint8(referendumInput.legislationTier));
            }
            if (
                referendumInput.referendumClass == ReferendumTypes.ReferendumClass.Legislation
                    && !LegislationTypes.isLawTier(referendumInput.legislationTier)
            ) {
                revert InvalidLegislationTier(uint8(referendumInput.legislationTier));
            }
            if (referendumInput.targetModule != bytes32(0) || referendumInput.proposedModuleAddress != address(0)) {
                revert InvalidProposedModule(referendumInput.targetModule, referendumInput.proposedModuleAddress);
            }
        }
        if (referendumInput.startTime >= referendumInput.endTime) {
            revert InvalidVotingWindow(referendumInput.startTime, referendumInput.endTime);
        }
        if (
            referendumInput.referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment
                || referendumInput.requiresSupermajority
        ) {
            if (referendumInput.electorateHeadcountSnapshot == 0 || referendumInput.electorateVotingPowerSnapshot == 0)
            {
                revert InvalidResultSnapshot(
                    referendumId,
                    referendumInput.electorateVotingPowerSnapshot,
                    referendumInput.electorateHeadcountSnapshot
                );
            }
        } else if (
            referendumInput.electorateHeadcountSnapshot != 0 || referendumInput.electorateVotingPowerSnapshot != 0
        ) {
            revert InvalidResultSnapshot(
                referendumId, referendumInput.electorateVotingPowerSnapshot, referendumInput.electorateHeadcountSnapshot
            );
        }

        _referendumRecords[referendumId] = ReferendumTypes.ReferendumRecord({
            referendumId: referendumId,
            referendumClass: referendumInput.referendumClass,
            proposalOrigin: referendumInput.proposalOrigin,
            proposalMetadataHash: referendumInput.proposalMetadataHash,
            proposedMeasureId: referendumInput.proposedMeasureId,
            amendsMeasureId: referendumInput.amendsMeasureId,
            legislationTextHash: referendumInput.legislationTextHash,
            legislationTier: referendumInput.legislationTier,
            targetModule: referendumInput.targetModule,
            proposedModuleAddress: referendumInput.proposedModuleAddress,
            registerNewModule: referendumInput.registerNewModule,
            proposerReference: referendumInput.proposerReference,
            startTime: referendumInput.startTime,
            endTime: referendumInput.endTime,
            electorateHeadcountSnapshot: referendumInput.electorateHeadcountSnapshot,
            electorateVotingPowerSnapshot: referendumInput.electorateVotingPowerSnapshot,
            requiresSupermajority: referendumInput.requiresSupermajority,
            status: ReferendumTypes.ReferendumStatus.Active,
            forVotes: 0,
            againstVotes: 0,
            forVoterCount: 0,
            againstVoterCount: 0,
            voterCount: 0,
            finalizedAt: 0,
            enactedMeasureId: bytes32(0),
            enactmentActionId: bytes32(0)
        });
        _adoptionDelays[referendumId] = referendumInput.adoptionDelay;

        emit ReferendumCreated(
            referendumId,
            referendumInput.referendumClass,
            referendumInput.proposalOrigin,
            referendumInput.proposedMeasureId,
            referendumInput.targetModule,
            referendumInput.proposedModuleAddress,
            referendumInput.proposerReference,
            referendumInput.proposalMetadataHash,
            referendumInput.legislationTextHash,
            referendumInput.startTime,
            referendumInput.endTime,
            referendumInput.adoptionDelay,
            referendumInput.electorateHeadcountSnapshot,
            referendumInput.electorateVotingPowerSnapshot,
            msg.sender
        );
    }

    /// @inheritdoc IReferendumRegistry
    function recordVote(bytes32 referendumId, address voter, ReferendumTypes.VoteOption option, uint256 weight)
        external
    {
        _requireRegistryAuthority(msg.sender);

        ReferendumTypes.ReferendumRecord storage referendumRecord = _getActiveReferendum(referendumId);

        if (option != ReferendumTypes.VoteOption.Against && option != ReferendumTypes.VoteOption.For) {
            revert InvalidVoteOption(option);
        }
        if (weight == 0) {
            revert InvalidVotingWeight(voter, weight);
        }
        if (block.timestamp < referendumRecord.startTime || block.timestamp >= referendumRecord.endTime) {
            revert VotingClosed(
                referendumId, referendumRecord.startTime, referendumRecord.endTime, uint64(block.timestamp)
            );
        }

        ReferendumTypes.VoteReceipt storage existingReceipt = _voteReceipts[referendumId][voter];
        uint64 votedAt = uint64(block.timestamp);

        if (existingReceipt.option == ReferendumTypes.VoteOption.Undefined) {
            _voteReceipts[referendumId][voter] =
                ReferendumTypes.VoteReceipt({option: option, weight: weight, votedAt: votedAt});
            _applyVoteOption(referendumRecord, option, weight, true);
            referendumRecord.voterCount += 1;
        } else {
            if (existingReceipt.weight != weight) {
                revert InvalidVoteWeightUpdate(voter, weight, existingReceipt.weight);
            }

            if (existingReceipt.option != option) {
                _applyVoteOption(referendumRecord, existingReceipt.option, existingReceipt.weight, false);
                _applyVoteOption(referendumRecord, option, weight, true);
            }

            existingReceipt.option = option;
            existingReceipt.votedAt = votedAt;
        }

        emit ReferendumVoteRecorded(
            referendumId,
            voter,
            option,
            weight,
            referendumRecord.forVotes,
            referendumRecord.againstVotes,
            referendumRecord.voterCount,
            votedAt,
            msg.sender
        );
    }

    /// @inheritdoc IReferendumRegistry
    function finalizeReferendum(bytes32 referendumId, ReferendumTypes.ReferendumResultInput calldata resultInput)
        external
    {
        _requireRegistryAuthority(msg.sender);

        ReferendumTypes.ReferendumRecord storage referendumRecord = _getActiveReferendum(referendumId);
        if (block.timestamp < referendumRecord.endTime) {
            revert ReferendumNotReady(referendumId, referendumRecord.endTime, uint64(block.timestamp));
        }

        uint256 expectedTurnout = referendumRecord.forVotes + referendumRecord.againstVotes;
        if (resultInput.turnout != expectedTurnout) {
            revert InvalidResultSnapshot(referendumId, resultInput.turnout, expectedTurnout);
        }
        if (referendumRecord.forVoterCount + referendumRecord.againstVoterCount != referendumRecord.voterCount) {
            revert InvalidResultSnapshot(
                referendumId,
                referendumRecord.forVoterCount + referendumRecord.againstVoterCount,
                referendumRecord.voterCount
            );
        }
        if (resultInput.passed) {
            if (!resultInput.quorumMet) {
                revert InvalidResultSnapshot(referendumId, resultInput.turnout, expectedTurnout);
            }
            if (resultInput.enactedMeasureId != referendumRecord.proposedMeasureId) {
                revert InvalidEnactedMeasureId(referendumId, resultInput.enactedMeasureId);
            }
            if (resultInput.enactmentActionId == bytes32(0)) {
                revert InvalidEnactedMeasureId(referendumId, resultInput.enactedMeasureId);
            }
        } else if (resultInput.enactedMeasureId != bytes32(0) || resultInput.enactmentActionId != bytes32(0)) {
            revert UnexpectedEnactedMeasureId(referendumId, resultInput.enactedMeasureId);
        }

        uint64 finalizedAt = uint64(block.timestamp);
        ReferendumTypes.ReferendumStatus status =
            resultInput.passed ? ReferendumTypes.ReferendumStatus.Succeeded : ReferendumTypes.ReferendumStatus.Defeated;

        _storeFinalizedResult(referendumId, referendumRecord, resultInput, status, finalizedAt);
    }

    /// @inheritdoc IReferendumRegistry
    function cancelReferendum(bytes32 referendumId) external {
        _requireRegistryAuthority(msg.sender);

        ReferendumTypes.ReferendumRecord storage referendumRecord = _getActiveReferendum(referendumId);
        referendumRecord.status = ReferendumTypes.ReferendumStatus.Canceled;

        emit ReferendumCanceled(referendumId, uint64(block.timestamp), msg.sender);
    }

    function _validateBudgetApprovalReferendum(ReferendumTypes.ReferendumRecordInput calldata referendumInput)
        private
        pure
    {
        if (
            referendumInput.targetModule != KernelModuleIds.BUDGET_ENVELOPE_REGISTRY
                || referendumInput.proposedModuleAddress != address(0)
        ) {
            revert InvalidProposedModule(referendumInput.targetModule, referendumInput.proposedModuleAddress);
        }
        if (referendumInput.legislationTextHash == bytes32(0)) {
            revert InvalidTextHash(referendumInput.legislationTextHash);
        }
        if (!LegislationTypes.isLawTier(referendumInput.legislationTier)) {
            revert InvalidLegislationTier(uint8(referendumInput.legislationTier));
        }
    }

    function _validateModuleGovernanceReferendum(ReferendumTypes.ReferendumRecordInput calldata referendumInput)
        private
        view
    {
        if (
            referendumInput.targetModule == bytes32(0) || referendumInput.proposedModuleAddress == address(0)
                || referendumInput.proposedModuleAddress.code.length == 0
                || referendumInput.legislationTextHash != bytes32(0)
                || referendumInput.legislationTier != LegislationTypes.LegislationTier.Undefined
                || referendumInput.targetModule == KernelModuleIds.CONGRESS_ELECTION_POLICY
        ) {
            revert InvalidProposedModule(referendumInput.targetModule, referendumInput.proposedModuleAddress);
        }

        bool moduleActive = _isActiveModule(referendumInput.targetModule);
        if (referendumInput.registerNewModule == moduleActive) {
            revert InvalidProposedModule(referendumInput.targetModule, referendumInput.proposedModuleAddress);
        }
    }

    function _validateBudgetApprovalDetails(
        bytes32 budgetId,
        ReferendumTypes.BudgetApprovalDetails calldata budgetDetails
    ) private pure {
        if (
            budgetDetails.officeId == bytes32(0)
                || budgetDetails.disbursementType == TreasuryTypes.DisbursementType.Undefined
                || budgetDetails.asset != address(0) || budgetDetails.allocatedAmount == 0
                || budgetDetails.endsAt <= budgetDetails.startsAt
        ) {
            revert InvalidBudgetPayload(budgetId);
        }
    }

    function _isActiveModule(bytes32 moduleId) private view returns (bool active) {
        try _kernel.getModuleRecord(moduleId) returns (GovernanceTypes.ModuleRecord memory moduleRecord) {
            return
                moduleRecord.status == GovernanceTypes.ModuleStatus.Active && moduleRecord.moduleAddress != address(0);
        } catch {
            return false;
        }
    }

    function _applyVoteOption(
        ReferendumTypes.ReferendumRecord storage referendumRecord,
        ReferendumTypes.VoteOption option,
        uint256 weight,
        bool adding
    ) private {
        if (option == ReferendumTypes.VoteOption.For) {
            if (adding) {
                referendumRecord.forVotes += weight;
                referendumRecord.forVoterCount += 1;
            } else {
                referendumRecord.forVotes -= weight;
                referendumRecord.forVoterCount -= 1;
            }

            return;
        }

        if (adding) {
            referendumRecord.againstVotes += weight;
            referendumRecord.againstVoterCount += 1;
        } else {
            referendumRecord.againstVotes -= weight;
            referendumRecord.againstVoterCount -= 1;
        }
    }

    function _storeFinalizedResult(
        bytes32 referendumId,
        ReferendumTypes.ReferendumRecord storage referendumRecord,
        ReferendumTypes.ReferendumResultInput calldata resultInput,
        ReferendumTypes.ReferendumStatus status,
        uint64 finalizedAt
    ) private {
        referendumRecord.status = status;
        referendumRecord.finalizedAt = finalizedAt;
        referendumRecord.enactedMeasureId = resultInput.enactedMeasureId;
        referendumRecord.enactmentActionId = resultInput.enactmentActionId;

        _referendumResults[referendumId] = ReferendumTypes.ReferendumResult({
            forVotes: referendumRecord.forVotes,
            againstVotes: referendumRecord.againstVotes,
            forVoterCount: referendumRecord.forVoterCount,
            againstVoterCount: referendumRecord.againstVoterCount,
            turnout: resultInput.turnout,
            quorumRequired: resultInput.quorumRequired,
            headcountQuorumRequired: resultInput.headcountQuorumRequired,
            electorateVotingPower: resultInput.electorateVotingPower,
            quorumMet: resultInput.quorumMet,
            passed: resultInput.passed,
            finalizedAt: finalizedAt,
            enactmentActionId: resultInput.enactmentActionId
        });

        emit ReferendumFinalized(
            referendumId,
            status,
            referendumRecord.forVotes,
            referendumRecord.againstVotes,
            resultInput.turnout,
            resultInput.quorumRequired,
            resultInput.quorumMet,
            resultInput.passed,
            resultInput.enactedMeasureId,
            resultInput.enactmentActionId,
            finalizedAt,
            msg.sender
        );
    }

    function _getActiveReferendum(bytes32 referendumId)
        private
        view
        returns (ReferendumTypes.ReferendumRecord storage referendumRecord)
    {
        referendumRecord = _referendumRecords[referendumId];
        if (referendumRecord.referendumId == bytes32(0)) {
            revert ReferendumNotFound(referendumId);
        }
        if (referendumRecord.status != ReferendumTypes.ReferendumStatus.Active) {
            revert ReferendumAlreadyFinalized(referendumId, referendumRecord.status);
        }
    }

    function _requireRegistryAuthority(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY)) {
            revert UnauthorizedReferendumRegistryCaller(caller);
        }
    }
}
