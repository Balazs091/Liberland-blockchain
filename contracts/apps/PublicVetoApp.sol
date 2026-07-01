// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {IPublicVetoApp} from "../interfaces/IPublicVetoApp.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {VetoTypes} from "../types/VetoTypes.sol";

/// @title PublicVetoApp
/// @notice User-facing application for person-counted public veto support and bounded legislation repeal.
contract PublicVetoApp is IPublicVetoApp {
    ICitizenEligibilityPolicy private immutable _citizenEligibilityPolicy;
    IIdentityRegistry private immutable _identityRegistry;
    ILegislationRegistry private immutable _legislationRegistry;
    uint256 private immutable _repealThreshold;

    mapping(bytes32 measureId => VetoTypes.PublicVetoRecord publicVetoRecord) private _publicVetoRecords;
    mapping(bytes32 measureId => mapping(bytes32 personId => VetoTypes.PublicVetoReceipt receipt)) private
        _publicVetoReceipts;
    mapping(bytes32 measureId => bytes32[] personIds) private _publicVetoSupporters;

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

        _citizenEligibilityPolicy = ICitizenEligibilityPolicy(citizenEligibilityPolicyAddress);
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
        return address(_citizenEligibilityPolicy);
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
        return _publicVetoRecords[measureId];
    }

    /// @inheritdoc IPublicVetoApp
    function hasActivePublicVeto(bytes32 measureId, bytes32 personId) external view returns (bool active) {
        return _publicVetoReceipts[measureId][personId].active && _isCurrentlyEligiblePerson(personId);
    }

    /// @inheritdoc IPublicVetoApp
    function remainingRepealSupport(bytes32 measureId) external view returns (uint256 remaining) {
        uint256 supportCount = _validPublicVetoSupportCount(measureId);
        if (supportCount >= _repealThreshold) {
            return 0;
        }

        return _repealThreshold - supportCount;
    }

    /// @inheritdoc IPublicVetoApp
    function currentPublicVetoSupportCount(bytes32 measureId) external view returns (uint256 count) {
        return _validPublicVetoSupportCount(measureId);
    }

    /// @inheritdoc IPublicVetoApp
    function castPublicVeto(bytes32 measureId) external {
        if (!_citizenEligibilityPolicy.isCitizenInGoodStanding(msg.sender)) {
            revert NotEligiblePublicVetoer(msg.sender);
        }

        bytes32 personId = _resolveActivePersonId(msg.sender);
        LegislationTypes.LegislationRecord memory legislationRecord =
            _legislationRegistry.getLegislationRecord(measureId);
        _requireVetoEligible(legislationRecord, measureId);

        VetoTypes.PublicVetoReceipt storage receipt = _publicVetoReceipts[measureId][personId];
        if (receipt.active) {
            revert PublicVetoAlreadyCast(measureId, personId);
        }

        bytes32 vetoId = previewVetoId(measureId);
        VetoTypes.PublicVetoRecord storage publicVetoRecord = _publicVetoRecords[measureId];
        uint64 currentTimestamp = uint64(block.timestamp);
        if (publicVetoRecord.vetoId == bytes32(0)) {
            publicVetoRecord.vetoId = vetoId;
            publicVetoRecord.measureId = measureId;
            publicVetoRecord.createdAt = currentTimestamp;
        }

        if (receipt.personId == bytes32(0)) {
            _publicVetoSupporters[measureId].push(personId);
        }

        receipt.personId = personId;
        receipt.active = true;
        receipt.updatedAt = currentTimestamp;
        uint256 supportCount = publicVetoRecord.supportCount + 1;
        if (supportCount >= _repealThreshold) {
            supportCount = _validPublicVetoSupportCount(measureId);
        }
        publicVetoRecord.supportCount = supportCount;

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
        publicVetoRecord.supportCount = _validPublicVetoSupportCount(measureId);

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
        uint256 identityCount = _identityRegistry.totalIdentityCount();
        IStakeRegistry stakeRegistry = IStakeRegistry(_citizenEligibilityPolicy.stakeRegistry());
        uint256 minimumCitizenStake = _citizenEligibilityPolicy.minimumCitizenStake();

        for (uint256 index = 0; index < identityCount; ++index) {
            bytes32 personId = _identityRegistry.identityIdAt(index);
            if (_isEligibleCitizenPerson(stakeRegistry, minimumCitizenStake, personId)) {
                count += 1;
            }
        }
    }

    function _validPublicVetoSupportCount(bytes32 measureId) private view returns (uint256 count) {
        bytes32[] storage supporters = _publicVetoSupporters[measureId];
        uint256 supporterCount = supporters.length;
        // Hoist the two eligibility-policy reads out of the loop (they are the same for every supporter).
        IStakeRegistry stakeRegistry = IStakeRegistry(_citizenEligibilityPolicy.stakeRegistry());
        uint256 minimumCitizenStake = _citizenEligibilityPolicy.minimumCitizenStake();
        for (uint256 index = 0; index < supporterCount; ++index) {
            bytes32 personId = supporters[index];
            if (
                _publicVetoReceipts[measureId][personId].active
                    && _isEligibleCitizenPerson(stakeRegistry, minimumCitizenStake, personId)
            ) {
                count += 1;
            }
        }
    }

    function _isCurrentlyEligiblePerson(bytes32 personId) private view returns (bool eligible) {
        IStakeRegistry stakeRegistry = IStakeRegistry(_citizenEligibilityPolicy.stakeRegistry());
        return _isEligibleCitizenPerson(stakeRegistry, _citizenEligibilityPolicy.minimumCitizenStake(), personId);
    }

    function _isEligibleCitizenPerson(IStakeRegistry stakeRegistry, uint256 minimumCitizenStake, bytes32 personId)
        private
        view
        returns (bool eligible)
    {
        IdentityTypes.IdentityRecord memory record = _identityRegistry.getIdentityRecord(personId);
        if (record.personId == bytes32(0)) {
            return false;
        }
        if (_identityRegistry.activeWalletCountOf(personId) == 0) {
            return false;
        }
        if (record.verificationStatus != IdentityTypes.VerificationStatus.Verified) {
            return false;
        }
        if (record.citizenshipStatus != IdentityTypes.CitizenshipStatus.Citizen) {
            return false;
        }
        if (record.ageClass != IdentityTypes.AgeClass.Adult || record.finalSuspension) {
            return false;
        }
        if (stakeRegistry.activeStakeOf(personId) < minimumCitizenStake) {
            return false;
        }

        return !stakeRegistry.isInWelfare(personId);
    }
}
