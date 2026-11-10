// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IKernelModule} from "./IKernelModule.sol";
import {MembershipTypes} from "../types/MembershipTypes.sol";

/// @title IMembershipRegistry
/// @notice Person-bound independent restriction facts, written solely by the kernel's typed IdentityWriter.
/// @dev Removal is separate from citizenship. The writer authenticates the exact legal effect and consumes its
///      receipt. Temporary restriction expiry does not change the constitutional denominator.
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
    error MembershipRevisionMismatch(uint256 expectedRevision, uint256 actualRevision);
    error MembershipRemovalUnchanged(bytes32 personId, bool removed);
    error InsufficientElectorateSyncGas(uint256 available, uint256 required);

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
    event MembershipRemovalUpdated(
        bytes32 indexed personId, bool removed, bytes32 indexed receiptId, uint256 personRevision
    );
    event ElectorateSynchronizationDeferred(bytes32 indexed personId, address indexed electorateRegistry);

    /// @notice Returns the immutable identity registry that defines known person identifiers.
    function identityRegistry() external view returns (address identityRegistryAddress);

    /// @notice Returns a recorded full removal; false alone never proves membership or citizenship.
    function membershipRemoved(bytes32 personId) external view returns (bool removed);

    /// @notice Records or lifts full removal, bound to the current person revision and authenticated receipt.
    /// @dev Only the current IDENTITY_WRITER. Does not alter citizenship, custody or independent restrictions.
    function setMembershipRemoved(bytes32 personId, bool removed, uint256 expectedRevision, bytes32 receiptId) external;

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

    /// @notice Returns the number of recorded lifecycle and restriction mutations for one person.
    /// @dev The passage of time alone does not increment this revision.
    function membershipRevisionOf(bytes32 personId) external view returns (uint256 revision);

    /// @notice Returns the aggregate number of recorded lifecycle and restriction mutations.
    /// @dev Finite restrictions affect live privileges, not denominator membership. Time alone never increments it.
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
