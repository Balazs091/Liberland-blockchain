// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IMembershipRegistry} from "../interfaces/IMembershipRegistry.sol";
import {ISepoliaGovernedMembershipController} from "../interfaces/ISepoliaGovernedMembershipController.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {MembershipTypes} from "../types/MembershipTypes.sol";

/// @title SepoliaGovernedMembershipController
/// @notice Typed synthetic effect driver whose submitters follow the current elected Congress.
/// @dev No seeding, operator, arbitrary execution or custody. Ordinary governed IDENTITY_WRITER replacement
///      selects a successor with the same ledger, so active orders and source revisions survive replacement.
contract SepoliaGovernedMembershipController is ISepoliaGovernedMembershipController {
    uint256 private constant _CHAIN_ID = 11_155_111;
    bytes32 private constant _DOMAIN = keccak256("SEPOLIA_GOVERNED_SYNTHETIC_MEMBERSHIP_V1");
    IConstitutionKernel private immutable _kernel;
    IIdentityRegistry private immutable _identity;
    IMembershipRegistry private immutable _membership;
    uint256 private _nextReceiptNonce;

    /// @param identityAddress Stable, synthetic identity ledger from the governed Sepolia profile.
    /// @param membershipAddress Stable restriction ledger from that same kernel and identity bundle.
    constructor(address identityAddress, address membershipAddress) {
        if (block.chainid != _CHAIN_ID) revert WrongChain(block.chainid);
        if (identityAddress.code.length == 0) revert InvalidDependency(identityAddress);
        if (membershipAddress.code.length == 0) revert InvalidDependency(membershipAddress);
        _identity = IIdentityRegistry(identityAddress);
        _membership = IMembershipRegistry(membershipAddress);
        address kernelAddress = _identity.kernel();
        if (kernelAddress.code.length == 0) revert InvalidDependency(kernelAddress);
        if (_membership.kernel() != kernelAddress) revert DependencyMismatch(kernelAddress, _membership.kernel());
        if (_membership.identityRegistry() != identityAddress) {
            revert DependencyMismatch(identityAddress, _membership.identityRegistry());
        }
        _kernel = IConstitutionKernel(kernelAddress);
    }

    /// @inheritdoc ISepoliaGovernedMembershipController
    function kernel() external view returns (address) {
        return address(_kernel);
    }

    /// @inheritdoc ISepoliaGovernedMembershipController
    function identityRegistry() external view returns (address) {
        return address(_identity);
    }

    /// @inheritdoc ISepoliaGovernedMembershipController
    function membershipRegistry() external view returns (address) {
        return address(_membership);
    }

    /// @inheritdoc ISepoliaGovernedMembershipController
    function nextReceiptNonce() external view returns (uint256) {
        return _nextReceiptNonce;
    }

    /// @inheritdoc ISepoliaGovernedMembershipController
    function canSubmit(address account) public view returns (bool) {
        if (block.chainid != _CHAIN_ID || !_identity.hasActiveWalletLink(account)) return false;
        if (!_current(KernelModuleIds.IDENTITY_WRITER, address(this))) return false;
        if (!_current(KernelModuleIds.IDENTITY_REGISTRY, address(_identity))) return false;
        if (!_current(KernelModuleIds.MEMBERSHIP_REGISTRY, address(_membership))) return false;
        try _kernel.getModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY) returns (address congress) {
            try ICongressCandidateRegistry(congress).kernel() returns (address congressKernel) {
                if (congressKernel != address(_kernel)) return false;
            } catch {
                return false;
            }
            try ICongressCandidateRegistry(congress).isActiveCongressMember(account) returns (bool active) {
                return active;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    /// @inheritdoc ISepoliaGovernedMembershipController
    function recordRestriction(MembershipTypes.OrderInput calldata effect) external returns (bytes32 receiptId) {
        _requireSubject(effect.personId);
        uint256 nonce;
        (receiptId, nonce) = _reference(keccak256("recordRestriction"), keccak256(abi.encode(effect)));
        _membership.recordOrder(effect, receiptId);
        emit SyntheticEffectExecuted(receiptId, effect.personId, effect.orderId, keccak256("recordRestriction"), nonce);
    }

    /// @inheritdoc ISepoliaGovernedMembershipController
    function stayRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId)
    {
        _requireSubject(personId);
        uint256 nonce;
        (receiptId, nonce) =
            _reference(keccak256("stayRestriction"), keccak256(abi.encode(personId, orderId, expectedRevision)));
        _membership.stayOrder(personId, orderId, expectedRevision, receiptId);
        emit SyntheticEffectExecuted(receiptId, personId, orderId, keccak256("stayRestriction"), nonce);
    }

    /// @inheritdoc ISepoliaGovernedMembershipController
    function resumeRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId)
    {
        _requireSubject(personId);
        uint256 nonce;
        (receiptId, nonce) =
            _reference(keccak256("resumeRestriction"), keccak256(abi.encode(personId, orderId, expectedRevision)));
        _membership.resumeOrder(personId, orderId, expectedRevision, receiptId);
        emit SyntheticEffectExecuted(receiptId, personId, orderId, keccak256("resumeRestriction"), nonce);
    }

    /// @inheritdoc ISepoliaGovernedMembershipController
    function revokeRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId)
    {
        _requireSubject(personId);
        uint256 nonce;
        (receiptId, nonce) =
            _reference(keccak256("revokeRestriction"), keccak256(abi.encode(personId, orderId, expectedRevision)));
        _membership.revokeOrder(personId, orderId, expectedRevision, receiptId);
        emit SyntheticEffectExecuted(receiptId, personId, orderId, keccak256("revokeRestriction"), nonce);
    }

    function _requireSubject(bytes32 personId) private view {
        if (block.chainid != _CHAIN_ID) revert WrongChain(block.chainid);
        if (!canSubmit(msg.sender)) revert NotCurrentCongressMember(msg.sender);
        if (uint256(personId) < 1 || uint256(personId) > 4 || !_identity.identityExists(personId)) {
            revert NotSyntheticPerson(personId);
        }
    }

    function _reference(bytes32 operation, bytes32 effectHash) private returns (bytes32 receiptId, uint256 nonce) {
        nonce = _nextReceiptNonce++;
        receiptId = keccak256(abi.encode(_DOMAIN, block.chainid, address(this), nonce, operation, effectHash));
    }

    function _current(bytes32 moduleId, address expected) private view returns (bool) {
        try _kernel.getModule(moduleId) returns (address current) {
            return current == expected;
        } catch {
            return false;
        }
    }
}
