// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {LandTypes} from "../types/LandTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title ILandRegistryApp
/// @notice User-facing cadastral workflow interface with explicit preparation and finalization powers.
interface ILandRegistryApp {
    error InvalidLandPartyPolicy(address policyAddress);
    error InvalidLandRegistry(address registryAddress);
    error InvalidLandRegistryOffice(bytes32 officeId);
    error InvalidOfficePermissionPolicy(address policyAddress);
    error InvalidOfficeRegistry(address registryAddress);
    error InvalidParty(LandTypes.PartyRef party);
    error InvalidPartySigner(bytes32 partyKey, address signer);
    error InvalidSignature(bytes32 partyKey, address signer);
    error TitleNotExpiredLease(bytes32 titleId);
    error InvalidTransferDeadline(uint64 deadline, uint64 currentTime);
    error InvalidTransferNonce(bytes32 titleId, uint256 providedNonce, uint256 expectedNonce);
    error UnauthorizedLandRegistryOfficeAction(
        address caller, bytes32 officeId, OfficeTypes.OfficeActionClass actionClass
    );

    /// @notice Returns the stable land registry written by this app.
    function landRegistry() external view returns (address registryAddress);

    /// @notice Returns the office registry used for registrar/clerk authorization.
    function officeRegistry() external view returns (address registryAddress);

    /// @notice Returns the live office-permission policy.
    function officePermissionPolicy() external view returns (address policyAddress);

    /// @notice Returns the live land-party policy.
    function landPartyPolicy() external view returns (address policyAddress);

    /// @notice Returns the Land Registry Office identifier.
    function landOfficeId() external view returns (bytes32 officeId);

    /// @notice Returns the next title-scoped transfer authorization nonce.
    function titleTransferNonce(bytes32 titleId) external view returns (uint256 nonce);

    /// @notice Returns the EIP-712 digest that the current seller and prospective buyer must both sign.
    function hashTitleTransferAuthorization(LandTypes.TitleTransferRequest calldata request)
        external
        view
        returns (bytes32 digest);

    /// @notice Submits a new parcel draft through an authorized clerk or registrar.
    function submitParcelDraft(bytes32 parcelId, LandTypes.ParcelInput calldata input, bytes32 transactionId) external;

    /// @notice Replaces an existing parcel draft at its expected revision.
    function updateParcelDraft(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.ParcelInput calldata input,
        bytes32 transactionId
    ) external;
    /// @notice Finalizes a draft as an active cadastral parcel.
    function activateParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.RecordAnchor calldata finalAnchor,
        bytes32 transactionId
    ) external;
    /// @notice Records a new content-addressed revision of an active parcel.
    function reviseParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.ParcelInput calldata input,
        bytes32 transactionId
    ) external;
    /// @notice Retires an untitled, unlocked parcel.
    function retireParcel(
        bytes32 parcelId,
        uint64 expectedRevision,
        LandTypes.RecordAnchor calldata retirementAnchor,
        bytes32 transactionId
    ) external;
    /// @notice Registers the initial active title for an active untitled parcel.
    function registerTitle(bytes32 titleId, LandTypes.TitleInput calldata input, bytes32 transactionId) external;

    /// @notice Finalizes a title transfer authorized by the current seller and eligible buyer.
    function transferTitle(
        LandTypes.TitleTransferRequest calldata request,
        address sellerSigner,
        bytes calldata sellerSignature,
        address buyerSigner,
        bytes calldata buyerSignature
    ) external;
    /// @notice Closes a leasehold title only after its recorded expiry.
    function closeExpiredLease(
        bytes32 parcelId,
        bytes32 titleId,
        bytes32 expectedVersionHash,
        LandTypes.RecordAnchor calldata closingAnchor,
        bytes32 transactionId
    ) external;
    /// @notice Atomically retires one parcel/title and creates bounded child parcels/titles.
    function subdivideParcel(
        bytes32 parentParcelId,
        uint64 expectedParentRevision,
        LandTypes.SubdivisionChild[] calldata children,
        bytes32 transactionId
    ) external;
    /// @notice Atomically retires compatible source parcels/titles and creates one replacement.
    function mergeParcels(
        bytes32[] calldata sourceParcelIds,
        uint64[] calldata expectedRevisions,
        LandTypes.MergeResult calldata result,
        bytes32 transactionId
    ) external;
    /// @notice Atomically revises the cadastral data for exactly two parcels.
    function adjustBoundary(
        LandTypes.ParcelRevisionInput calldata first,
        LandTypes.ParcelRevisionInput calldata second,
        bytes32 transactionId
    ) external;

    /// @notice Files a dispute for a claimant represented by the caller.
    function fileDispute(
        bytes32 disputeId,
        bytes32 parcelId,
        LandTypes.PartyRef calldata claimant,
        bytes32 evidenceHash,
        bytes32 transactionId
    ) external;
    /// @notice Accepts a filed dispute and activates the parcel lock.
    function acceptDispute(bytes32 disputeId, bytes32 evidenceHash, bytes32 transactionId) external;

    /// @notice Resolves or dismisses a filed/accepted dispute.
    function resolveDispute(bytes32 disputeId, bytes32 resolutionHash, bool claimAccepted, bytes32 transactionId)
        external;

    /// @notice Registers an active encumbrance against an active title.
    function registerEncumbrance(
        bytes32 encumbranceId,
        LandTypes.EncumbranceInput calldata input,
        bytes32 transactionId
    ) external;
    /// @notice Releases an active encumbrance with an anchored release record.
    function releaseEncumbrance(
        bytes32 encumbranceId,
        LandTypes.RecordAnchor calldata releaseAnchor,
        bytes32 transactionId
    ) external;
}
