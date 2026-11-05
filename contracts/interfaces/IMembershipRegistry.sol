// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IKernelModule} from "./IKernelModule.sol";
import {MembershipTypes} from "../types/MembershipTypes.sol";

/// @title IMembershipRegistry
/// @notice Person-bound independent restriction facts, written solely by the kernel's typed IdentityWriter.
/// @dev This foundation does not activate membership, change citizenship, authenticate legal receipts, or certify
///      electorate snapshots. The writer must authenticate the exact legal effect and consume its receipt.
interface IMembershipRegistry is IKernelModule {
    error InvalidIdentityRegistry(address identityRegistry);
    error IdentityRegistryKernelMismatch(address expectedKernel, address actualKernel);
    error UnauthorizedMembershipRegistryCaller(address caller);
    error UnknownPerson(bytes32 personId);
    error InvalidOrderId();
    error InvalidReceiptId();
    error InvalidRestrictedMask(uint16 mask);
    error InvalidOrderInterval(uint64 effectiveAt, uint64 expiresAt, bool indefinite);
    error OrderAlreadyRecorded(bytes32 personId, bytes32 orderId);
    error OrderNotRecorded(bytes32 personId, bytes32 orderId);
    error OrderRevisionMismatch(uint256 expectedRevision, uint256 actualRevision);
    error InvalidOrderTransition(MembershipTypes.OrderStatus currentStatus);
    error OrderExpired(uint64 expiresAt);

    event RestrictionRecorded(
        bytes32 indexed personId,
        bytes32 indexed orderId,
        bytes32 indexed sourceReceiptId,
        uint16 restrictedMask,
        uint64 effectiveAt,
        uint64 expiresAt,
        bool indefinite
    );
    event RestrictionStatusChanged(
        bytes32 indexed personId,
        bytes32 indexed orderId,
        bytes32 indexed receiptId,
        MembershipTypes.OrderStatus status,
        uint256 orderRevision
    );
    event MembershipSourceRevisionAdvanced(
        bytes32 indexed personId, uint256 personRevision, uint256 totalMutationCount
    );

    /// @notice Returns the immutable identity registry that defines known person identifiers.
    function identityRegistry() external view returns (address identityRegistryAddress);

    /// @notice Returns an order's immutable scope/provenance and current procedural state; unset means absent.
    function orderOf(bytes32 personId, bytes32 orderId)
        external
        view
        returns (MembershipTypes.RestrictionOrder memory order);

    /// @notice Returns fixed-size current restriction summaries without requiring expiry cleanup.
    /// @dev Unknown people return no restriction facts, which must never be interpreted as eligibility.
    function rightsNow(bytes32 personId) external view returns (MembershipTypes.RightsSummary memory summary);

    /// @notice Returns whether a specified right is currently restricted by any unstayed, unrevoked order.
    /// @dev Does not answer whether the person has that right under citizenship/membership/office policy.
    function isRestrictedNow(bytes32 personId, MembershipTypes.Right right) external view returns (bool restricted);

    /// @notice Returns the number of recorded restriction mutations for one person.
    /// @dev The passage of time alone does not increment this revision.
    function membershipRevisionOf(bytes32 personId) external view returns (uint256 revision);

    /// @notice Returns the aggregate number of recorded restriction mutations.
    /// @dev This counter alone cannot certify time-dependent eligibility; finite expiries require separate
    ///      certification/scheduling in a future electorate integration.
    function electorateMutationCount() external view returns (uint256 count);

    /// @notice Records one already-effective, not-yet-expired order with immutable scope and provenance.
    /// @dev Only IdentityWriter. Future starts and reused IDs are rejected. The receipt must be consumed by the
    ///      authenticating issuer/writer in the same transaction; a nonzero ID alone is not legal authority.
    function recordOrder(MembershipTypes.OrderInput calldata effect, bytes32 sourceReceiptId) external;

    /// @notice Stays exactly one unstayed order without changing its scope, duration or original provenance.
    /// @dev Only IdentityWriter. expectedRevision binds relief to this order, not unrelated person activity.
    function stayOrder(bytes32 personId, bytes32 orderId, uint256 expectedRevision, bytes32 receiptId) external;

    /// @notice Lifts the stay on exactly one unexpired order; its original exclusive end remains unchanged.
    /// @dev Only IdentityWriter. Does not restart an expired clock or erase any other order.
    function resumeOrder(bytes32 personId, bytes32 orderId, uint256 expectedRevision, bytes32 receiptId) external;

    /// @notice Permanently revokes exactly one existing order, including a stayed or expired order.
    /// @dev Only IdentityWriter. Revoked IDs remain recorded and cannot be reused.
    function revokeOrder(bytes32 personId, bytes32 orderId, uint256 expectedRevision, bytes32 receiptId) external;
}
