// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IElectorateRegistry} from "../interfaces/IElectorateRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {IPublicVetoApp} from "../interfaces/IPublicVetoApp.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {VetoTypes} from "../types/VetoTypes.sol";

/// @title PublicVetoApp
/// @notice User-facing application for person-counted public veto support and bounded legislation repeal.
contract PublicVetoApp is IPublicVetoApp {
    IConstitutionKernel private immutable _kernel;
    IIdentityRegistry private immutable _identityRegistry;
    ILegislationRegistry private immutable _legislationRegistry;
    uint256 private immutable _repealThreshold;

    mapping(bytes32 measureId => VetoTypes.PublicVetoRecord publicVetoRecord) private _publicVetoRecords;
    mapping(bytes32 measureId => mapping(bytes32 personId => VetoTypes.PublicVetoReceipt receipt)) private
        _publicVetoReceipts;
    // A threshold-reaching cast repeals atomically, so a pending measure's active set never exceeds the threshold.
    mapping(bytes32 measureId => bytes32[] personIds) private _activePublicVetoSupporters;

    /// @param legislationRegistryAddress The legislation registry address.
    /// @param citizenEligibilityPolicyAddress The citizen eligibility policy address.
    /// @param repealThreshold_ The immutable headcount threshold required to trigger repeal.
    constructor(address legislationRegistryAddress, address citizenEligibilityPolicyAddress, uint256 repealThreshold_) {
        if (legislationRegistryAddress == address(0) || legislationRegistryAddress.code.length == 0) {
            revert InvalidRegistry(legislationRegistryAddress);
        }
        if (citizenEligibilityPolicyAddress == address(0) || citizenEligibilityPolicyAddress.code.length == 0) {
            revert InvalidPolicy(citizenEligibilityPolicyAddress);
        }
        if (repealThreshold_ == 0) {
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
        return keccak256(abi.encode(block.chainid, address(this), measureId));
    }

    /// @inheritdoc IPublicVetoApp
    function getPublicVetoRecord(bytes32 measureId) external view returns (VetoTypes.PublicVetoRecord memory record) {
        record = _publicVetoRecords[measureId];
        if (!record.repealed) {
            record.supportCount = _currentPublicVetoSupportCount(measureId);
        }
    }

    /// @inheritdoc IPublicVetoApp
    function hasActivePublicVeto(bytes32 measureId, bytes32 personId) external view returns (bool active) {
        if (!_publicVetoReceipts[measureId][personId].active) {
            return false;
        }

        return
            _publicVetoRecords[measureId].repealed || _isCurrentlyEligiblePerson(_citizenEligibilityPolicy(), personId);
    }

    /// @inheritdoc IPublicVetoApp
    function remainingRepealSupport(bytes32 measureId) external view returns (uint256 remaining) {
        VetoTypes.PublicVetoRecord storage publicVetoRecord = _publicVetoRecords[measureId];
        if (publicVetoRecord.repealed) {
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
    function castPublicVeto(bytes32 measureId) external {
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

        if (!publicVetoRecord.repealed && publicVetoRecord.supportCount >= _repealThreshold) {
            publicVetoRecord.repealed = true;
            publicVetoRecord.repealedAt = currentTimestamp;

            emit PublicVetoThresholdReached(
                measureId, vetoId, publicVetoRecord.supportCount, msg.sender, currentTimestamp
            );
            _legislationRegistry.recordRepeal(measureId, LegislationTypes.RepealOrigin.PublicVeto, vetoId);
        }
    }

    /// @inheritdoc IPublicVetoApp
    function removePublicVeto(bytes32 measureId) external {
        bytes32 personId = _resolveActivePersonId(msg.sender);
        VetoTypes.PublicVetoReceipt storage receipt = _publicVetoReceipts[measureId][personId];
        if (!receipt.active) {
            revert PublicVetoNotFound(measureId, personId);
        }

        VetoTypes.PublicVetoRecord storage publicVetoRecord = _publicVetoRecords[measureId];
        if (publicVetoRecord.repealed) {
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
