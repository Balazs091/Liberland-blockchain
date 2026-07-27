// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {LandTypes} from "../types/LandTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title ILandRegistryApp
/// @notice User-facing workflow interface for land registry office actions and public dispute notices.
interface ILandRegistryApp {
    error InvalidLandRegistry(address registryAddress);
    error InvalidLandRegistryOffice(bytes32 officeId);
    error InvalidOfficePermissionPolicy(address policyAddress);
    error InvalidOfficeRegistry(address registryAddress);
    error UnauthorizedLandRegistryOfficeAction(
        address caller, bytes32 officeId, OfficeTypes.OfficeActionClass actionClass
    );

    function landRegistry() external view returns (address registryAddress);
    function officeRegistry() external view returns (address registryAddress);
    function officePermissionPolicy() external view returns (address policyAddress);
    function landOfficeId() external view returns (bytes32 officeId);
    function submitParcelDraft(bytes32 parcelId, LandTypes.ParcelInput calldata input) external;
    function updateParcel(bytes32 parcelId, LandTypes.ParcelInput calldata input) external;
    function activateParcel(bytes32 parcelId, bytes32 documentHash) external;
    function retireParcel(bytes32 parcelId, bytes32 documentHash) external;
    function registerTitle(bytes32 titleId, LandTypes.TitleInput calldata input) external;
    function transferTitle(bytes32 titleId, address newHolder, bytes32 documentHash) external;
    function fileDispute(bytes32 disputeId, bytes32 parcelId, bytes32 evidenceHash) external;
    function acceptDispute(bytes32 disputeId, bytes32 evidenceHash) external;
    function resolveDispute(bytes32 disputeId, bytes32 resolutionHash, bool claimAccepted) external;
    function registerEncumbrance(bytes32 encumbranceId, bytes32 titleId, bytes32 documentHash) external;
    function releaseEncumbrance(bytes32 encumbranceId, bytes32 documentHash) external;
}
