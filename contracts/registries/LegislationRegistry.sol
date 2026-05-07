// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";

/// @title LegislationRegistry
/// @notice Stable fact registry for enacted legislation text and enactment metadata.
contract LegislationRegistry is ILegislationRegistry {
    IConstitutionKernel private immutable _kernel;

    mapping(bytes32 measureId => LegislationTypes.LegislationRecord legislationRecord) private _legislationRecords;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) {
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) {
            revert IConstitutionKernel.InvalidModuleAddress(bytes32(0), kernelAddress);
        }

        _kernel = IConstitutionKernel(kernelAddress);
    }

    /// @inheritdoc ILegislationRegistry
    function kernel() external view returns (address kernelAddress) {
        return address(_kernel);
    }

    /// @inheritdoc ILegislationRegistry
    function getLegislationRecord(bytes32 measureId)
        external
        view
        returns (LegislationTypes.LegislationRecord memory record)
    {
        return _legislationRecords[measureId];
    }

    /// @inheritdoc ILegislationRegistry
    function legislationExists(bytes32 measureId) public view returns (bool exists) {
        return _legislationRecords[measureId].measureId != bytes32(0);
    }

    /// @inheritdoc ILegislationRegistry
    function recordEnactment(bytes32 measureId, LegislationTypes.LegislationRecordInput calldata recordInput) external {
        _requireRegistryAuthority(msg.sender);

        if (measureId == bytes32(0)) {
            revert InvalidMeasureId(measureId);
        }
        if (recordInput.tier == LegislationTypes.LegislationTier.Undefined) {
            revert InvalidLegislationTier(recordInput.tier);
        }
        if (recordInput.textHash == bytes32(0)) {
            revert InvalidTextHash(recordInput.textHash);
        }
        if (recordInput.proposerReference == bytes32(0)) {
            revert InvalidProposerReference(recordInput.proposerReference);
        }
        if (recordInput.enactedByReferendumId == bytes32(0)) {
            revert InvalidEnactingReferendum(recordInput.enactedByReferendumId);
        }
        if (legislationExists(measureId)) {
            revert LegislationAlreadyExists(measureId);
        }
        if (recordInput.amendsMeasureId != bytes32(0) && !legislationExists(recordInput.amendsMeasureId)) {
            revert UnknownAmendmentTarget(recordInput.amendsMeasureId);
        }

        uint64 enactedAt = uint64(block.timestamp);

        _legislationRecords[measureId] = LegislationTypes.LegislationRecord({
            measureId: measureId,
            tier: recordInput.tier,
            textHash: recordInput.textHash,
            proposerReference: recordInput.proposerReference,
            enactedByReferendumId: recordInput.enactedByReferendumId,
            amendsMeasureId: recordInput.amendsMeasureId,
            repealOrigin: LegislationTypes.RepealOrigin.Undefined,
            repealReference: bytes32(0),
            active: true,
            repealed: false,
            enactedAt: enactedAt,
            repealedAt: 0
        });

        emit LegislationEnacted(
            measureId,
            recordInput.enactedByReferendumId,
            recordInput.proposerReference,
            recordInput.tier,
            recordInput.textHash,
            recordInput.amendsMeasureId,
            enactedAt,
            msg.sender
        );
    }

    /// @inheritdoc ILegislationRegistry
    function recordRepeal(bytes32 measureId, LegislationTypes.RepealOrigin repealOrigin, bytes32 repealReference)
        external
    {
        _requireRepealAuthority(msg.sender);

        if (measureId == bytes32(0)) {
            revert InvalidMeasureId(measureId);
        }
        if (repealOrigin == LegislationTypes.RepealOrigin.Undefined) {
            revert InvalidRepealOrigin(repealOrigin);
        }
        if (repealReference == bytes32(0)) {
            revert InvalidRepealReference(repealReference);
        }

        LegislationTypes.LegislationRecord storage legislationRecord = _legislationRecords[measureId];
        if (legislationRecord.measureId == bytes32(0)) {
            revert LegislationNotFound(measureId);
        }
        if (legislationRecord.repealed || !legislationRecord.active) {
            revert LegislationAlreadyRepealed(measureId);
        }

        uint64 repealedAt = uint64(block.timestamp);
        legislationRecord.repealOrigin = repealOrigin;
        legislationRecord.repealReference = repealReference;
        legislationRecord.active = false;
        legislationRecord.repealed = true;
        legislationRecord.repealedAt = repealedAt;

        emit LegislationRepealed(measureId, repealReference, repealOrigin, repealedAt, msg.sender);
    }

    function _requireRegistryAuthority(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY)) {
            revert UnauthorizedLegislationRegistryCaller(caller);
        }
    }

    function _requireRepealAuthority(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.LEGISLATION_REPEAL_AUTHORITY)) {
            revert UnauthorizedLegislationRepealCaller(caller);
        }
    }
}
