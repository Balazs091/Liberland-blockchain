// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IKernelModule} from "./IKernelModule.sol";
import {LandTypes} from "../types/LandTypes.sol";

/// @title ILandRegistry
/// @notice Stable fact registry interface for parcels, titles, disputes, and encumbrances.
interface ILandRegistry is IKernelModule {
    error DisputeAlreadyRegistered(bytes32 disputeId);
    error DisputeNotFound(bytes32 disputeId);
    error EncumbranceAlreadyRegistered(bytes32 encumbranceId);
    error EncumbranceNotFound(bytes32 encumbranceId);
    error InvalidDisputePayload(bytes32 disputeId);
    error InvalidDisputeStatus(LandTypes.DisputeStatus status);
    error InvalidEncumbrancePayload(bytes32 encumbranceId);
    error InvalidParcelPayload(bytes32 parcelId);
    error InvalidParcelStatus(LandTypes.ParcelStatus status);
    error InvalidTitlePayload(bytes32 titleId);
    error ParcelAlreadyRegistered(bytes32 parcelId);
    error ParcelAlreadyTitled(bytes32 parcelId, bytes32 activeTitleId);
    error ParcelNotFound(bytes32 parcelId);
    error ParcelTransferLocked(bytes32 parcelId);
    error TitleAlreadyRegistered(bytes32 titleId);
    error TitleNotFound(bytes32 titleId);
    error UnauthorizedLandRegistryCaller(address caller);

    event ParcelRegistered(
        bytes32 indexed parcelId, bytes32 indexed parcelNumberHash, uint64 registeredAt, address indexed recordedBy
    );
    event ParcelUpdated(
        bytes32 indexed parcelId, LandTypes.ParcelStatus indexed status, uint64 updatedAt, address indexed recordedBy
    );
    event TitleRegistered(
        bytes32 indexed titleId, bytes32 indexed parcelId, address indexed holder, uint64 registeredAt
    );
    event TitleTransferred(
        bytes32 indexed titleId, address indexed previousHolder, address indexed newHolder, uint64 transferredAt
    );
    event TitleClosed(bytes32 indexed titleId, bytes32 indexed parcelId, uint64 closedAt, address indexed recordedBy);
    event DisputeFiled(bytes32 indexed disputeId, bytes32 indexed parcelId, address indexed claimant, uint64 filedAt);
    event DisputeStatusUpdated(
        bytes32 indexed disputeId, LandTypes.DisputeStatus indexed status, uint64 updatedAt, address indexed recordedBy
    );
    event EncumbranceRegistered(
        bytes32 indexed encumbranceId, bytes32 indexed parcelId, bytes32 indexed titleId, uint64 registeredAt
    );
    event EncumbranceReleased(
        bytes32 indexed encumbranceId, bytes32 indexed parcelId, uint64 releasedAt, address indexed recordedBy
    );

    function getParcel(bytes32 parcelId) external view returns (LandTypes.ParcelRecord memory record);
    function getTitle(bytes32 titleId) external view returns (LandTypes.TitleRecord memory record);
    function getDispute(bytes32 disputeId) external view returns (LandTypes.DisputeRecord memory record);
    function getEncumbrance(bytes32 encumbranceId) external view returns (LandTypes.EncumbranceRecord memory record);
    function parcelExists(bytes32 parcelId) external view returns (bool exists);
    function titleExists(bytes32 titleId) external view returns (bool exists);
    function activeTitleOfParcel(bytes32 parcelId) external view returns (bytes32 titleId);
    function activeDisputeCountOf(bytes32 parcelId) external view returns (uint256 count);
    function activeEncumbranceCountOf(bytes32 parcelId) external view returns (uint256 count);
    function totalParcelCount() external view returns (uint256 count);
    function parcelIdAt(uint256 index) external view returns (bytes32 parcelId);
    function createParcel(bytes32 parcelId, LandTypes.ParcelInput calldata input) external;
    function updateParcel(bytes32 parcelId, LandTypes.ParcelInput calldata input) external;
    function activateParcel(bytes32 parcelId, bytes32 documentHash) external;
    function retireParcel(bytes32 parcelId, bytes32 documentHash) external;
    function registerTitle(bytes32 titleId, LandTypes.TitleInput calldata input) external;
    function transferTitle(bytes32 titleId, address newHolder, bytes32 documentHash) external;
    function closeTitle(bytes32 parcelId, bytes32 titleId, bytes32 documentHash) external;
    function fileDispute(bytes32 disputeId, bytes32 parcelId, address claimant, bytes32 evidenceHash) external;
    function acceptDispute(bytes32 disputeId, bytes32 evidenceHash) external;
    function resolveDispute(bytes32 disputeId, bytes32 resolutionHash, bool claimAccepted) external;
    function registerEncumbrance(bytes32 encumbranceId, bytes32 titleId, bytes32 documentHash) external;
    function releaseEncumbrance(bytes32 encumbranceId, bytes32 documentHash) external;
}
