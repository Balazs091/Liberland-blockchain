// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {VetoTypes} from "../types/VetoTypes.sol";

/// @title IPublicVetoApp
/// @notice User-facing interface for headcount-based public veto and legislation repeal.
interface IPublicVetoApp {
    error InvalidPolicy(address policyAddress);
    error InvalidRegistry(address registryAddress);
    error InvalidRepealThreshold(uint256 threshold);
    error MeasureNotVetoEligible(bytes32 measureId);
    error NotEligiblePublicVetoer(address voter);
    error PublicVetoAlreadyCast(bytes32 measureId, bytes32 personId);
    error PublicVetoNotFound(bytes32 measureId, bytes32 personId);
    error UnknownPersonReference(address wallet);

    event PublicVetoCast(
        bytes32 indexed measureId,
        bytes32 indexed vetoId,
        bytes32 indexed personId,
        address voter,
        uint256 supportCount,
        uint64 castAt
    );

    event PublicVetoRemoved(
        bytes32 indexed measureId,
        bytes32 indexed vetoId,
        bytes32 indexed personId,
        address voter,
        uint256 supportCount,
        uint64 removedAt
    );

    event PublicVetoEligibilityExpired(
        bytes32 indexed measureId,
        bytes32 indexed vetoId,
        bytes32 indexed personId,
        uint256 supportCount,
        uint64 expiredAt
    );

    event PublicVetoThresholdReached(
        bytes32 indexed measureId,
        bytes32 indexed vetoId,
        uint256 supportCount,
        address indexed triggeredBy,
        uint64 repealedAt
    );

    /// @notice Returns the configured identity registry used for person-level headcount tracking.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured legislation registry address.
    /// @return registryAddress The legislation registry address.
    function legislationRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured citizen eligibility policy address.
    /// @return policyAddress The citizen eligibility policy address.
    function citizenEligibilityPolicy() external view returns (address policyAddress);

    /// @notice Returns the immutable headcount threshold required for repeal.
    /// @return threshold The repeal threshold.
    function repealThreshold() external view returns (uint256 threshold);

    /// @notice Returns the current number of unique citizens in good standing who may participate in public veto.
    /// @return count The number of eligible citizens.
    function eligibleCitizenCount() external view returns (uint256 count);

    /// @notice Returns the deterministic public veto identifier for a measure.
    /// @param measureId The legislation measure identifier.
    /// @return vetoId The deterministic public veto identifier.
    function previewVetoId(bytes32 measureId) external view returns (bytes32 vetoId);

    /// @notice Returns the stored public veto process record for a measure.
    /// @param measureId The legislation measure identifier.
    /// @return record The stored public veto process record.
    function getPublicVetoRecord(bytes32 measureId) external view returns (VetoTypes.PublicVetoRecord memory record);

    /// @notice Returns true when a person currently has an active public veto recorded for a measure.
    /// @param measureId The legislation measure identifier.
    /// @param personId The person identifier to inspect.
    /// @return active Whether the person currently has an active veto recorded.
    function hasActivePublicVeto(bytes32 measureId, bytes32 personId) external view returns (bool active);

    /// @notice Returns the remaining support needed to reach the repeal threshold for a measure.
    /// @param measureId The legislation measure identifier.
    /// @return remaining The number of additional supports required.
    function remainingRepealSupport(bytes32 measureId) external view returns (uint256 remaining);

    /// @notice Returns the currently eligible active support count for a measure.
    /// @param measureId The legislation measure identifier.
    /// @return count The active support count after excluding stale ineligible receipts.
    function currentPublicVetoSupportCount(bytes32 measureId) external view returns (uint256 count);

    /// @notice Casts a headcount-based public veto on an eligible legislation measure.
    /// @param measureId The legislation measure identifier.
    function castPublicVeto(bytes32 measureId) external;

    /// @notice Removes a previously cast public veto before repeal finalizes.
    /// @param measureId The legislation measure identifier.
    function removePublicVeto(bytes32 measureId) external;
}
