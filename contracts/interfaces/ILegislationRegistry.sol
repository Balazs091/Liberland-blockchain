// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IKernelModule} from "./IKernelModule.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";

/// @title ILegislationRegistry
/// @notice Stable fact registry for enacted legislation text and enactment metadata.
interface ILegislationRegistry is IKernelModule {
    error InvalidEnactingReferendum(bytes32 referendumId);
    error InvalidLegislationTier(LegislationTypes.LegislationTier tier);
    error InvalidMeasureId(bytes32 measureId);
    error InvalidProposerReference(bytes32 proposerReference);
    error InvalidRepealOrigin(LegislationTypes.RepealOrigin repealOrigin);
    error InvalidRepealReference(bytes32 repealReference);
    error InvalidTextHash(bytes32 textHash);
    error LegislationAlreadyExists(bytes32 measureId);
    error LegislationAlreadyRepealed(bytes32 measureId);
    error LegislationNotFound(bytes32 measureId);
    error RepealTierNotPermitted(LegislationTypes.RepealOrigin repealOrigin, LegislationTypes.LegislationTier tier);
    error UnauthorizedLegislationRegistryCaller(address caller);
    error UnauthorizedLegislationRepealCaller(address caller);
    error UnknownAmendmentTarget(bytes32 measureId);

    event LegislationEnacted(
        bytes32 indexed measureId,
        bytes32 indexed enactedByReferendumId,
        bytes32 indexed proposerReference,
        LegislationTypes.LegislationTier tier,
        bytes32 textHash,
        bytes32 amendsMeasureId,
        uint64 enactedAt,
        address enactedBy
    );

    event LegislationRepealed(
        bytes32 indexed measureId,
        bytes32 indexed repealReference,
        LegislationTypes.RepealOrigin indexed repealOrigin,
        uint64 repealedAt,
        address repealedBy
    );

    /// @notice Returns the stored legislation record for a measure identifier.
    /// @param measureId The canonical measure identifier.
    /// @return record The stored legislation record, or an empty record if unset.
    function getLegislationRecord(bytes32 measureId)
        external
        view
        returns (LegislationTypes.LegislationRecord memory record);

    /// @notice Returns true when a legislation record exists for a measure identifier.
    /// @param measureId The canonical measure identifier.
    /// @return exists Whether the record exists.
    function legislationExists(bytes32 measureId) external view returns (bool exists);

    /// @notice Records an enacted legislation measure and its linked referendum metadata.
    /// @param measureId The canonical measure identifier to store.
    /// @param recordInput The enactment metadata and text references to store.
    function recordEnactment(bytes32 measureId, LegislationTypes.LegislationRecordInput calldata recordInput) external;

    /// @notice Records a legislation repeal through an authorized bounded repeal pathway.
    /// @param measureId The canonical measure identifier to repeal.
    /// @param repealOrigin The bounded governance origin that triggered repeal.
    /// @param repealReference The deterministic repeal process reference.
    function recordRepeal(bytes32 measureId, LegislationTypes.RepealOrigin repealOrigin, bytes32 repealReference)
        external;
}
