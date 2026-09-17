// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IElectorateRegistry} from "../interfaces/IElectorateRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {IPublicVetoApp} from "../interfaces/IPublicVetoApp.sol";
import {IReferendumApp} from "../interfaces/IReferendumApp.sol";
import {IReferendumRegistry} from "../interfaces/IReferendumRegistry.sol";
import {IActionTimelock} from "../interfaces/IActionTimelock.sol";
import {ReferendumTypes} from "../types/ReferendumTypes.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {VetoTypes} from "../types/VetoTypes.sol";

/// @title PublicVetoApp
/// @notice Person-counted, two-citizen petitions that initiate a Law-tier repeal referendum, not immediate repeal.
contract PublicVetoApp is IPublicVetoApp, ReentrancyGuard {
    IConstitutionKernel private immutable _kernel;
    IIdentityRegistry private immutable _identityRegistry;
    ILegislationRegistry private immutable _legislationRegistry;
    uint256 private immutable _repealThreshold;

    mapping(bytes32 measureId => VetoTypes.PublicVetoRecord publicVetoRecord) private _publicVetoRecords;
    mapping(bytes32 measureId => mapping(bytes32 personId => VetoTypes.PublicVetoReceipt receipt)) private
        _publicVetoReceipts;
    // A threshold-reaching cast submits one referendum, so the petition set never exceeds two people.
    mapping(bytes32 measureId => bytes32[] personIds) private _activePublicVetoSupporters;
    mapping(bytes32 measureId => uint256 nonce) private _petitionNonces;

    /// @param legislationRegistryAddress The legislation registry address.
    /// @param citizenEligibilityPolicyAddress The citizen eligibility policy address.
    /// @param repealThreshold_ The immutable two-person threshold required to initiate a repeal referendum.
    constructor(address legislationRegistryAddress, address citizenEligibilityPolicyAddress, uint256 repealThreshold_) {
        if (legislationRegistryAddress == address(0) || legislationRegistryAddress.code.length == 0) {
            revert InvalidRegistry(legislationRegistryAddress);
        }
        if (citizenEligibilityPolicyAddress == address(0) || citizenEligibilityPolicyAddress.code.length == 0) {
            revert InvalidPolicy(citizenEligibilityPolicyAddress);
        }
        if (repealThreshold_ != 2) {
            revert InvalidRepealThreshold(repealThreshold_);
        }

        address identityRegistryAddress = ICitizenEligibilityPolicy(citizenEligibilityPolicyAddress).identityRegistry();
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidRegistry(identityRegistryAddress);
        }

        _kernel = IConstitutionKernel(ILegislationRegistry(legislationRegistryAddress).kernel());
        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _legislationRegistry = ILegislationRegistry(legislationRegistryAddress);
        _repealThreshold = repealThreshold_;
    }

    /// @inheritdoc IPublicVetoApp
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc IPublicVetoApp
    function legislationRegistry() external view returns (address registryAddress) {
        return address(_legislationRegistry);
    }

    /// @inheritdoc IPublicVetoApp
    function citizenEligibilityPolicy() external view returns (address policyAddress) {
        return address(_citizenEligibilityPolicy());
    }

    /// @inheritdoc IPublicVetoApp
    function repealThreshold() external view returns (uint256 threshold) {
        return _repealThreshold;
    }

    /// @inheritdoc IPublicVetoApp
    function eligibleCitizenCount() external view returns (uint256 count) {
        return _eligibleCitizenCount();
    }

    /// @inheritdoc IPublicVetoApp
    function previewVetoId(bytes32 measureId) public view returns (bytes32 vetoId) {
        return keccak256(abi.encode(block.chainid, address(this), measureId, _petitionNonces[measureId]));
    }

    /// @inheritdoc IPublicVetoApp
    function getPublicVetoRecord(bytes32 measureId) external view returns (VetoTypes.PublicVetoRecord memory record) {
        record = _publicVetoRecords[measureId];
        LegislationTypes.LegislationRecord memory measure = _legislationRegistry.getLegislationRecord(measureId);
        record.repealed = measure.repealed;
        record.repealedAt = measure.repealedAt;
        if (record.referendumId == bytes32(0)) {
            record.supportCount = _currentPublicVetoSupportCount(measureId);
        }
    }

    /// @inheritdoc IPublicVetoApp
    function hasActivePublicVeto(bytes32 measureId, bytes32 personId) external view returns (bool active) {
        if (!_publicVetoReceipts[measureId][personId].active) {
            return false;
        }

        return _publicVetoRecords[measureId].referendumId != bytes32(0)
            || _isCurrentlyEligiblePerson(_citizenEligibilityPolicy(), personId);
    }

    /// @inheritdoc IPublicVetoApp
    function remainingRepealSupport(bytes32 measureId) external view returns (uint256 remaining) {
        VetoTypes.PublicVetoRecord storage publicVetoRecord = _publicVetoRecords[measureId];
        if (publicVetoRecord.referendumId != bytes32(0)) {
            return 0;
        }

        uint256 supportCount = _currentPublicVetoSupportCount(measureId);
        if (supportCount >= _repealThreshold) {
            return 0;
        }

        return _repealThreshold - supportCount;
    }

    /// @inheritdoc IPublicVetoApp
    function currentPublicVetoSupportCount(bytes32 measureId) external view returns (uint256 count) {
        return _currentPublicVetoSupportCount(measureId);
    }

    /// @inheritdoc IPublicVetoApp
    function castPublicVeto(bytes32 measureId) external nonReentrant {
        ICitizenEligibilityPolicy eligibilityPolicy = _citizenEligibilityPolicy();
        if (!eligibilityPolicy.isCitizenInGoodStanding(msg.sender)) {
            revert NotEligiblePublicVetoer(msg.sender);
        }

        bytes32 personId = _resolveActivePersonId(msg.sender);
        LegislationTypes.LegislationRecord memory legislationRecord =
            _legislationRegistry.getLegislationRecord(measureId);
        _requireVetoEligible(legislationRecord, measureId);

        bytes32 vetoId = previewVetoId(measureId);
        VetoTypes.PublicVetoRecord storage publicVetoRecord = _publicVetoRecords[measureId];
        if (publicVetoRecord.referendumId != bytes32(0)) {
            revert PetitionAlreadySubmitted(measureId, publicVetoRecord.referendumId);
        }
        uint64 currentTimestamp = uint64(block.timestamp);
        _pruneIneligibleSupport(measureId, publicVetoRecord, eligibilityPolicy, currentTimestamp);

        VetoTypes.PublicVetoReceipt storage receipt = _publicVetoReceipts[measureId][personId];
        if (receipt.active) {
            revert PublicVetoAlreadyCast(measureId, personId);
        }

        if (publicVetoRecord.vetoId == bytes32(0)) {
            publicVetoRecord.vetoId = vetoId;
            publicVetoRecord.measureId = measureId;
            publicVetoRecord.createdAt = currentTimestamp;
        }

        receipt.personId = personId;
        receipt.active = true;
        receipt.updatedAt = currentTimestamp;
        _activePublicVetoSupporters[measureId].push(personId);
        publicVetoRecord.supportCount = _activePublicVetoSupporters[measureId].length;

        emit PublicVetoCast(measureId, vetoId, personId, msg.sender, publicVetoRecord.supportCount, currentTimestamp);

        if (publicVetoRecord.supportCount >= _repealThreshold) {
            emit PublicVetoThresholdReached(
                measureId, vetoId, publicVetoRecord.supportCount, msg.sender, currentTimestamp
            );
            bytes32 referendumId = IReferendumApp(_kernel.getModule(KernelModuleIds.REFERENDUM_APP))
                .createPublicRepealReferendum(measureId, vetoId);
            publicVetoRecord.referendumId = referendumId;
            emit PublicRepealReferendumCreated(measureId, vetoId, referendumId);
        }
    }

    /// @inheritdoc IPublicVetoApp
    function removePublicVeto(bytes32 measureId) external nonReentrant {
        bytes32 personId = _resolveActivePersonId(msg.sender);
        VetoTypes.PublicVetoReceipt storage receipt = _publicVetoReceipts[measureId][personId];
        if (!receipt.active) {
            revert PublicVetoNotFound(measureId, personId);
        }

        VetoTypes.PublicVetoRecord storage publicVetoRecord = _publicVetoRecords[measureId];
        if (publicVetoRecord.referendumId != bytes32(0)) {
            revert MeasureNotVetoEligible(measureId);
        }

        receipt.active = false;
        receipt.updatedAt = uint64(block.timestamp);
        _removeActiveSupporter(measureId, personId);
        publicVetoRecord.supportCount = _activePublicVetoSupporters[measureId].length;

        emit PublicVetoRemoved(
            measureId, publicVetoRecord.vetoId, personId, msg.sender, publicVetoRecord.supportCount, receipt.updatedAt
        );
    }

    /// @inheritdoc IPublicVetoApp
    function resetPublicPetition(bytes32 measureId) external nonReentrant {
        _requireVetoEligible(_legislationRegistry.getLegislationRecord(measureId), measureId);
        bytes32 referendumId = _publicVetoRecords[measureId].referendumId;
        if (referendumId == bytes32(0)) revert PetitionStillLive(referendumId);
        ReferendumTypes.ReferendumRecord memory vote =
            IReferendumRegistry(_kernel.getModule(KernelModuleIds.REFERENDUM_REGISTRY)).getReferendum(referendumId);
        bool terminal = vote.status == ReferendumTypes.ReferendumStatus.Defeated
            || vote.status == ReferendumTypes.ReferendumStatus.Canceled;
        if (vote.status == ReferendumTypes.ReferendumStatus.Succeeded && vote.enactmentActionId != bytes32(0)) {
            GovernanceTypes.ActionRecord memory action =
                IActionTimelock(_kernel.getModule(KernelModuleIds.ACTION_TIMELOCK)).getAction(vote.enactmentActionId);
            terminal = action.actionId != bytes32(0)
                && (action.state == GovernanceTypes.ActionState.Canceled
                    || action.state == GovernanceTypes.ActionState.Expired
                    || (action.state == GovernanceTypes.ActionState.Queued && block.timestamp > action.expiresAt));
        }
        if (!terminal) revert PetitionStillLive(referendumId);
        bytes32[] storage supporters = _activePublicVetoSupporters[measureId];
        // Exactly two maximum: a new round never inherits the previous petition's signatures.
        for (uint256 i; i < supporters.length; ++i) {
            delete _publicVetoReceipts[measureId][supporters[i]];
        }
        delete _activePublicVetoSupporters[measureId];
        delete _publicVetoRecords[measureId];
        uint256 nonce = ++_petitionNonces[measureId];
        emit PublicPetitionReset(measureId, referendumId, nonce);
    }

    function _resolveActivePersonId(address wallet) private view returns (bytes32 personId) {
        IdentityTypes.WalletLink memory walletLink = _identityRegistry.getWalletLink(wallet);
        if (walletLink.personId == bytes32(0) || walletLink.status != IdentityTypes.WalletLinkStatus.Active) {
            revert UnknownPersonReference(wallet);
        }

        return walletLink.personId;
    }

    function _requireVetoEligible(LegislationTypes.LegislationRecord memory legislationRecord, bytes32 measureId)
        private
        pure
    {
        if (legislationRecord.measureId == bytes32(0) || !legislationRecord.active || legislationRecord.repealed) {
            revert MeasureNotVetoEligible(measureId);
        }

        // Public veto remains a law-level repeal path, not a constitutional/treaty or sub-legal tool.
        if (!LegislationTypes.isLawTier(legislationRecord.tier)) {
            revert MeasureNotVetoEligible(measureId);
        }
    }

    function _eligibleCitizenCount() private view returns (uint256 count) {
        (count,) = IElectorateRegistry(_kernel.getModule(KernelModuleIds.ELECTORATE_REGISTRY)).snapshot();
    }

    function _currentPublicVetoSupportCount(bytes32 measureId) private view returns (uint256 count) {
        if (_publicVetoRecords[measureId].referendumId != bytes32(0)) {
            return _publicVetoRecords[measureId].supportCount;
        }
        ICitizenEligibilityPolicy eligibilityPolicy = _citizenEligibilityPolicy();
        bytes32[] storage supporters = _activePublicVetoSupporters[measureId];
        uint256 supporterCount = supporters.length;

        for (uint256 index = 0; index < supporterCount; ++index) {
            if (_isCurrentlyEligiblePerson(eligibilityPolicy, supporters[index])) {
                count += 1;
            }
        }
    }

    function _pruneIneligibleSupport(
        bytes32 measureId,
        VetoTypes.PublicVetoRecord storage publicVetoRecord,
        ICitizenEligibilityPolicy eligibilityPolicy,
        uint64 currentTimestamp
    ) private {
        bytes32[] storage supporters = _activePublicVetoSupporters[measureId];
        uint256 index;

        while (index < supporters.length) {
            bytes32 personId = supporters[index];
            if (_isCurrentlyEligiblePerson(eligibilityPolicy, personId)) {
                index += 1;
                continue;
            }

            VetoTypes.PublicVetoReceipt storage receipt = _publicVetoReceipts[measureId][personId];
            receipt.active = false;
            receipt.updatedAt = currentTimestamp;

            supporters[index] = supporters[supporters.length - 1];
            supporters.pop();
            publicVetoRecord.supportCount = supporters.length;

            emit PublicVetoEligibilityExpired(
                measureId, publicVetoRecord.vetoId, personId, publicVetoRecord.supportCount, currentTimestamp
            );
        }
    }

    function _removeActiveSupporter(bytes32 measureId, bytes32 personId) private {
        bytes32[] storage supporters = _activePublicVetoSupporters[measureId];
        uint256 supporterCount = supporters.length;

        for (uint256 index = 0; index < supporterCount; ++index) {
            if (supporters[index] != personId) {
                continue;
            }

            supporters[index] = supporters[supporterCount - 1];
            supporters.pop();
            return;
        }

        revert PublicVetoNotFound(measureId, personId);
    }

    function _isCurrentlyEligiblePerson(ICitizenEligibilityPolicy eligibilityPolicy, bytes32 personId)
        private
        view
        returns (bool eligible)
    {
        address activeWallet = _identityRegistry.activeWalletOf(personId);
        return activeWallet != address(0) && eligibilityPolicy.isCitizenInGoodStanding(activeWallet);
    }

    function _citizenEligibilityPolicy() private view returns (ICitizenEligibilityPolicy policy) {
        return ICitizenEligibilityPolicy(_kernel.getModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY));
    }
}
