// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IMembershipRegistry} from "../interfaces/IMembershipRegistry.sol";
import {ISepoliaMembershipController} from "../interfaces/ISepoliaMembershipController.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {MembershipTypes} from "../types/MembershipTypes.sol";
import {SepoliaFoundationFixtures} from "./SepoliaFoundationFixtures.sol";

/// @title SepoliaMembershipController
/// @notice Visible test-only authority for the three synthetic Sepolia fixture people.
/// @dev Not a legal workflow or production IdentityWriter. No arbitrary identity edits, execution or custody.
///      Fixture seeding becomes unavailable after kernel bootstrap retirement; restriction testing remains.
contract SepoliaMembershipController is ISepoliaMembershipController {
    bytes32 private constant _RECEIPT_DOMAIN = keccak256("SEPOLIA_SYNTHETIC_RESTRICTION_REFERENCE_V1");
    bytes32 private constant _RECORD = keccak256("recordRestriction");
    bytes32 private constant _STAY = keccak256("stayRestriction");
    bytes32 private constant _RESUME = keccak256("resumeRestriction");
    bytes32 private constant _REVOKE = keccak256("revokeRestriction");

    address private immutable _operator;
    IConstitutionKernel private immutable _kernel;
    IIdentityRegistry private immutable _identityRegistry;
    IMembershipRegistry private immutable _membershipRegistry;
    bool private _fixturesSeeded;
    uint256 private _nextReceiptNonce;

    /// @param operatorAddress Immutable operator of this isolated test deployment.
    /// @param identityRegistryAddress Stable synthetic identity registry.
    /// @param membershipRegistryAddress Restriction registry sharing that identity registry and kernel.
    constructor(address operatorAddress, address identityRegistryAddress, address membershipRegistryAddress) {
        _requireSepolia();
        if (operatorAddress == address(0)) revert InvalidOperator(operatorAddress);
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidIdentityRegistry(identityRegistryAddress);
        }
        if (membershipRegistryAddress == address(0) || membershipRegistryAddress.code.length == 0) {
            revert InvalidMembershipRegistry(membershipRegistryAddress);
        }
        _operator = operatorAddress;
        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _membershipRegistry = IMembershipRegistry(membershipRegistryAddress);
        address kernelAddress = _identityRegistry.kernel();
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) revert InvalidKernel(kernelAddress);
        address membershipKernel = _membershipRegistry.kernel();
        if (membershipKernel != kernelAddress) revert DependencyKernelMismatch(kernelAddress, membershipKernel);
        address membershipIdentity = _membershipRegistry.identityRegistry();
        if (membershipIdentity != identityRegistryAddress) {
            revert MembershipIdentityMismatch(identityRegistryAddress, membershipIdentity);
        }
        _kernel = IConstitutionKernel(kernelAddress);
    }

    /// @inheritdoc ISepoliaMembershipController
    function operator() external view returns (address) {
        return _operator;
    }

    /// @inheritdoc ISepoliaMembershipController
    function kernel() external view returns (address) {
        return address(_kernel);
    }

    /// @inheritdoc ISepoliaMembershipController
    function identityRegistry() external view returns (address) {
        return address(_identityRegistry);
    }

    /// @inheritdoc ISepoliaMembershipController
    function membershipRegistry() external view returns (address) {
        return address(_membershipRegistry);
    }

    /// @inheritdoc ISepoliaMembershipController
    function fixturesSeeded() external view returns (bool) {
        return _fixturesSeeded;
    }

    /// @inheritdoc ISepoliaMembershipController
    function nextReceiptNonce() external view returns (uint256) {
        return _nextReceiptNonce;
    }

    /// @inheritdoc ISepoliaMembershipController
    function seedSyntheticIdentities() external {
        _requireOperator();
        if (_fixturesSeeded) revert FixtureAlreadySeeded();
        address bootstrap = _kernel.bootstrapAuthority();
        if (bootstrap != _operator) revert FixtureBootstrapInactive(bootstrap);
        address authority = _kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY);
        if (authority != address(this)) revert FixtureAuthorityMismatch(authority);
        _fixturesSeeded = true;
        for (uint256 index; index < SepoliaFoundationFixtures.PERSON_COUNT; ++index) {
            bytes32 personId = SepoliaFoundationFixtures.personIdAt(index);
            if (_identityRegistry.identityExists(personId)) revert FixtureAlreadyExists(personId);
            _identityRegistry.setIdentityRecord(
                personId,
                IdentityTypes.IdentityRecordInput({
                    metadataHash: SepoliaFoundationFixtures.metadataHashAt(index),
                    metadataURI: "synthetic://sepolia-foundation-v1/NO_REAL_PERSON",
                    verificationStatus: IdentityTypes.VerificationStatus.Verified,
                    citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                    ageClass: IdentityTypes.AgeClass.Adult,
                    correctionFlag: false,
                    finalSuspension: false
                })
            );
            _identityRegistry.setWalletLink(
                personId, SepoliaFoundationFixtures.walletAt(index), IdentityTypes.WalletLinkStatus.Active
            );
        }
        emit SyntheticFixturesSeeded(SepoliaFoundationFixtures.FIXTURE_VERSION, SepoliaFoundationFixtures.PERSON_COUNT);
    }

    /// @inheritdoc ISepoliaMembershipController
    function recordRestriction(MembershipTypes.OrderInput calldata effect) external returns (bytes32 receiptId) {
        _requireSubject(effect.personId);
        uint256 nonce;
        (receiptId, nonce) = _newReference(_RECORD, keccak256(abi.encode(effect)));
        _membershipRegistry.recordOrder(effect, receiptId);
        emit SyntheticEffectExecuted(receiptId, effect.personId, effect.orderId, _RECORD, nonce);
    }

    /// @inheritdoc ISepoliaMembershipController
    function stayRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId)
    {
        _requireSubject(personId);
        uint256 nonce;
        (receiptId, nonce) = _newReference(_STAY, keccak256(abi.encode(personId, orderId, expectedRevision)));
        _membershipRegistry.stayOrder(personId, orderId, expectedRevision, receiptId);
        emit SyntheticEffectExecuted(receiptId, personId, orderId, _STAY, nonce);
    }

    /// @inheritdoc ISepoliaMembershipController
    function resumeRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId)
    {
        _requireSubject(personId);
        uint256 nonce;
        (receiptId, nonce) = _newReference(_RESUME, keccak256(abi.encode(personId, orderId, expectedRevision)));
        _membershipRegistry.resumeOrder(personId, orderId, expectedRevision, receiptId);
        emit SyntheticEffectExecuted(receiptId, personId, orderId, _RESUME, nonce);
    }

    /// @inheritdoc ISepoliaMembershipController
    function revokeRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId)
    {
        _requireSubject(personId);
        uint256 nonce;
        (receiptId, nonce) = _newReference(_REVOKE, keccak256(abi.encode(personId, orderId, expectedRevision)));
        _membershipRegistry.revokeOrder(personId, orderId, expectedRevision, receiptId);
        emit SyntheticEffectExecuted(receiptId, personId, orderId, _REVOKE, nonce);
    }

    function _requireOperator() private view {
        _requireSepolia();
        if (msg.sender != _operator) revert NotFixtureOperator(msg.sender);
    }

    function _requireSubject(bytes32 personId) private view {
        _requireOperator();
        if (!_fixturesSeeded) revert FixturesNotSeeded();
        if (!SepoliaFoundationFixtures.isSyntheticPerson(personId)) revert NotSyntheticPerson(personId);
    }

    function _requireSepolia() private view {
        if (block.chainid != SepoliaFoundationFixtures.CHAIN_ID) revert WrongChain(block.chainid);
    }

    function _newReference(bytes32 operation, bytes32 effectHash) private returns (bytes32 receiptId, uint256 nonce) {
        nonce = _nextReceiptNonce++;
        receiptId = keccak256(abi.encode(_RECEIPT_DOMAIN, block.chainid, address(this), nonce, operation, effectHash));
    }
}
