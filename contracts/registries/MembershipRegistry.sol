// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {KernelModule} from "../base/KernelModule.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IElectorateRegistry} from "../interfaces/IElectorateRegistry.sol";
import {IMembershipRegistry} from "../interfaces/IMembershipRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {TimedRestrictionSet} from "../libraries/TimedRestrictionSet.sol";
import {MembershipTypes} from "../types/MembershipTypes.sol";

/// @title MembershipRegistry
/// @notice Stable person-bound membership removal and independently stayed, revoked and expiring restriction orders.
/// @dev Membership effects do not change citizenship or authorize financial consequences.
///      IdentityWriter alone records authenticated legal effects; bootstrap and offices have no bypass.
///      Public order/subject facts need the approved disclosure policy before deployment.
contract MembershipRegistry is IMembershipRegistry, KernelModule {
    using TimedRestrictionSet for TimedRestrictionSet.Set;

    IIdentityRegistry private immutable _identityRegistry;
    mapping(bytes32 personId => mapping(bytes32 orderId => MembershipTypes.RestrictionOrder order)) private _orders;
    mapping(bytes32 personId => mapping(uint8 right => TimedRestrictionSet.Set orders)) private _rightOrders;
    mapping(bytes32 personId => uint256 revision) private _personRevisions;
    uint256 private _mutationCount;
    mapping(bytes32 personId => bool removed) private _membershipRemoved;

    uint256 private constant _ELECTORATE_SYNC_GAS_LIMIT = 500_000;
    uint256 private constant _ELECTORATE_SYNC_GAS_RESERVE = 50_000;

    /// @param kernelAddress Canonical kernel whose IDENTITY_WRITER is the sole write authority.
    /// @param identityRegistryAddress Stable identity registry bound to the same kernel.
    constructor(address kernelAddress, address identityRegistryAddress) KernelModule(kernelAddress) {
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidIdentityRegistry(identityRegistryAddress);
        }
        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        address identityKernel = _identityRegistry.kernel();
        if (identityKernel != kernelAddress) {
            revert IdentityRegistryKernelMismatch(kernelAddress, identityKernel);
        }
    }

    /// @inheritdoc IMembershipRegistry
    function identityRegistry() external view returns (address identityRegistryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc IMembershipRegistry
    function membershipRemoved(bytes32 personId) external view returns (bool removed) {
        return _membershipRemoved[personId];
    }

    /// @inheritdoc IMembershipRegistry
    function setMembershipRemoved(bytes32 personId, bool removed, uint256 expectedRevision, bytes32 receiptId)
        external
    {
        _requireWriter();
        if (!_identityRegistry.identityExists(personId)) revert UnknownPerson(personId);
        _requireReceipt(receiptId);
        uint256 revision = _personRevisions[personId];
        if (revision != expectedRevision) revert MembershipRevisionMismatch(expectedRevision, revision);
        if (_membershipRemoved[personId] == removed) revert MembershipRemovalUnchanged(personId, removed);
        _membershipRemoved[personId] = removed;
        _advanceRevision(personId);
        emit MembershipRemovalUpdated(personId, removed, receiptId, _personRevisions[personId]);
    }

    /// @inheritdoc IMembershipRegistry
    function orderOf(bytes32 personId, bytes32 orderId)
        external
        view
        returns (MembershipTypes.RestrictionOrder memory order)
    {
        return _orders[personId][orderId];
    }

    /// @inheritdoc IMembershipRegistry
    function rightsNow(bytes32 personId) external view returns (MembershipTypes.RightsSummary memory summary) {
        summary.personRevision = _personRevisions[personId];
        for (uint8 right; right < 5; ++right) {
            (bool exists, TimedRestrictionSet.Entry memory entry) = _rightOrders[personId][right].latest();
            if (!exists || (!entry.indefinite && block.timestamp >= entry.expiresAt)) continue;
            uint16 bit = uint16(1) << right;
            summary.restrictedMask |= bit;
            if (entry.indefinite) summary.indefiniteMask |= bit;
            else summary.restrictedUntil[right] = entry.expiresAt;
        }
    }

    /// @inheritdoc IMembershipRegistry
    function isRestrictedNow(bytes32 personId, MembershipTypes.Right right) external view returns (bool restricted) {
        return _rightOrders[personId][uint8(right)].isRestrictedAt(block.timestamp);
    }

    /// @inheritdoc IMembershipRegistry
    function membershipRevisionOf(bytes32 personId) external view returns (uint256 revision) {
        return _personRevisions[personId];
    }

    /// @inheritdoc IMembershipRegistry
    function electorateMutationCount() external view returns (uint256 count) {
        return _mutationCount;
    }

    /// @inheritdoc IMembershipRegistry
    function recordOrder(MembershipTypes.OrderInput calldata effect, bytes32 sourceReceiptId) external {
        _requireWriter();
        if (!_identityRegistry.identityExists(effect.personId)) revert UnknownPerson(effect.personId);
        if (effect.orderId == bytes32(0)) revert InvalidOrderId();
        _requireReceipt(sourceReceiptId);
        if (effect.restrictedMask == 0 || (effect.restrictedMask & ~MembershipTypes.SUPPORTED_RIGHTS_MASK) != 0) {
            revert InvalidRestrictedMask(effect.restrictedMask);
        }
        if (
            effect.effectiveAt == 0 || effect.effectiveAt > block.timestamp
                || (effect.indefinite ? effect.expiresAt != 0 : effect.expiresAt <= block.timestamp)
        ) revert InvalidOrderInterval(effect.effectiveAt, effect.expiresAt, effect.indefinite);

        MembershipTypes.RestrictionOrder storage order = _orders[effect.personId][effect.orderId];
        if (order.status != MembershipTypes.OrderStatus.Unset) {
            revert OrderAlreadyRecorded(effect.personId, effect.orderId);
        }
        order.sourceReceiptId = sourceReceiptId;
        order.revision = 1;
        order.restrictedMask = effect.restrictedMask;
        order.effectiveAt = effect.effectiveAt;
        order.expiresAt = effect.expiresAt;
        order.indefinite = effect.indefinite;
        order.status = MembershipTypes.OrderStatus.Unstayed;
        _indexOrder(effect.personId, effect.orderId, order, true);
        _advanceRevision(effect.personId);

        emit RestrictionRecorded(
            effect.personId,
            effect.orderId,
            sourceReceiptId,
            effect.restrictedMask,
            effect.effectiveAt,
            effect.expiresAt,
            effect.indefinite
        );
    }

    /// @inheritdoc IMembershipRegistry
    function stayOrder(bytes32 personId, bytes32 orderId, uint256 expectedRevision, bytes32 receiptId) external {
        _requireWriter();
        _requireReceipt(receiptId);
        MembershipTypes.RestrictionOrder storage order = _checkedOrder(personId, orderId, expectedRevision);
        if (order.status != MembershipTypes.OrderStatus.Unstayed) revert InvalidOrderTransition(order.status);
        _indexOrder(personId, orderId, order, false);
        _setStatus(personId, orderId, order, MembershipTypes.OrderStatus.Stayed, receiptId);
    }

    /// @inheritdoc IMembershipRegistry
    function resumeOrder(bytes32 personId, bytes32 orderId, uint256 expectedRevision, bytes32 receiptId) external {
        _requireWriter();
        _requireReceipt(receiptId);
        MembershipTypes.RestrictionOrder storage order = _checkedOrder(personId, orderId, expectedRevision);
        if (order.status != MembershipTypes.OrderStatus.Stayed) revert InvalidOrderTransition(order.status);
        if (!order.indefinite && block.timestamp >= order.expiresAt) revert OrderExpired(order.expiresAt);
        _indexOrder(personId, orderId, order, true);
        _setStatus(personId, orderId, order, MembershipTypes.OrderStatus.Unstayed, receiptId);
    }

    /// @inheritdoc IMembershipRegistry
    function revokeOrder(bytes32 personId, bytes32 orderId, uint256 expectedRevision, bytes32 receiptId) external {
        _requireWriter();
        _requireReceipt(receiptId);
        MembershipTypes.RestrictionOrder storage order = _checkedOrder(personId, orderId, expectedRevision);
        if (order.status == MembershipTypes.OrderStatus.Revoked) revert InvalidOrderTransition(order.status);
        if (order.status == MembershipTypes.OrderStatus.Unstayed) _indexOrder(personId, orderId, order, false);
        _setStatus(personId, orderId, order, MembershipTypes.OrderStatus.Revoked, receiptId);
    }

    function _requireWriter() private view {
        if (!_isModuleCaller(KernelModuleIds.IDENTITY_WRITER, msg.sender)) {
            revert UnauthorizedMembershipRegistryCaller(msg.sender);
        }
    }

    function _requireReceipt(bytes32 receiptId) private pure {
        if (receiptId == bytes32(0)) revert InvalidReceiptId();
    }

    function _checkedOrder(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        private
        view
        returns (MembershipTypes.RestrictionOrder storage order)
    {
        order = _orders[personId][orderId];
        if (order.status == MembershipTypes.OrderStatus.Unset) revert OrderNotRecorded(personId, orderId);
        if (expectedRevision != order.revision) revert OrderRevisionMismatch(expectedRevision, order.revision);
    }

    function _indexOrder(bytes32 personId, bytes32 orderId, MembershipTypes.RestrictionOrder storage order, bool add)
        private
    {
        for (uint8 right; right < 5; ++right) {
            if ((order.restrictedMask & (uint16(1) << right)) == 0) continue;
            if (add) _rightOrders[personId][right].add(orderId, order.expiresAt, order.indefinite);
            else _rightOrders[personId][right].remove(orderId);
        }
    }

    function _setStatus(
        bytes32 personId,
        bytes32 orderId,
        MembershipTypes.RestrictionOrder storage order,
        MembershipTypes.OrderStatus status,
        bytes32 receiptId
    ) private {
        order.status = status;
        ++order.revision;
        _advanceRevision(personId);
        emit RestrictionStatusChanged(personId, orderId, receiptId, status, order.revision);
    }

    function _advanceRevision(bytes32 personId) private {
        ++_personRevisions[personId];
        ++_mutationCount;
        emit MembershipSourceRevisionAdvanced(personId, _personRevisions[personId], _mutationCount);
        address electorate;
        try _kernel.getModule(KernelModuleIds.ELECTORATE_REGISTRY) returns (address registered) {
            electorate = registered;
        } catch {
            return;
        }
        uint256 requiredGas = _ELECTORATE_SYNC_GAS_LIMIT + _ELECTORATE_SYNC_GAS_RESERVE;
        if (gasleft() < requiredGas) revert InsufficientElectorateSyncGas(gasleft(), requiredGas);
        // Offer the entire callback budget. A genuine failure remains visible through source revision mismatch.
        (bool synchronized,) =
            electorate.call{gas: _ELECTORATE_SYNC_GAS_LIMIT}(abi.encodeCall(IElectorateRegistry.syncPerson, (personId)));
        if (!synchronized) emit ElectorateSynchronizationDeferred(personId, electorate);
    }
}
