// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {MembershipTypes} from "../types/MembershipTypes.sol";

/// @title ISepoliaMembershipController
/// @notice Explicitly synthetic Sepolia-only controller for exercising restriction storage.
/// @dev This is not an IdentityWriter implementation or a legal decision/receipt issuer for production.
interface ISepoliaMembershipController {
    error WrongChain(uint256 chainId);
    error InvalidOperator(address operator);
    error InvalidIdentityRegistry(address identityRegistry);
    error InvalidMembershipRegistry(address membershipRegistry);
    error InvalidKernel(address kernel);
    error DependencyKernelMismatch(address expectedKernel, address actualKernel);
    error MembershipIdentityMismatch(address expectedIdentity, address actualIdentity);
    error NotFixtureOperator(address caller);
    error FixtureAlreadySeeded();
    error FixtureBootstrapInactive(address bootstrapAuthority);
    error FixtureAuthorityMismatch(address currentAuthority);
    error FixtureAlreadyExists(bytes32 personId);
    error NotSyntheticPerson(bytes32 personId);
    error FixturesNotSeeded();

    event SyntheticFixturesSeeded(bytes32 indexed fixtureVersion, uint256 count);
    event SyntheticEffectExecuted(
        bytes32 indexed receiptId, bytes32 indexed personId, bytes32 indexed orderId, bytes32 operation, uint256 nonce
    );

    /// @notice Returns the immutable test operator, which has no production authority.
    function operator() external view returns (address);

    /// @notice Returns the immutable kernel shared by the fixture registries.
    function kernel() external view returns (address);

    /// @notice Returns the identity registry containing the fixed synthetic people.
    function identityRegistry() external view returns (address);

    /// @notice Returns the independent restriction registry exercised by this controller.
    function membershipRegistry() external view returns (address);

    /// @notice Returns whether the fixed three-person fixture has been seeded successfully.
    function fixturesSeeded() external view returns (bool);

    /// @notice Returns the next synthetic receipt nonce; failed writes do not advance it.
    function nextReceiptNonce() external view returns (uint256);

    /// @notice Seeds exactly the fixed synthetic records once, while the operator still owns kernel bootstrap.
    /// @dev Cannot edit arbitrary identities or reseed after bootstrap retirement.
    function seedSyntheticIdentities() external;

    /// @notice Records a synthetic restriction on a fixed fixture person and returns its generated reference.
    /// @dev Operator-only; the reference is not a legal approval, signed certificate or production receipt.
    function recordRestriction(MembershipTypes.OrderInput calldata effect) external returns (bytes32 receiptId);

    /// @notice Stays exactly one fixture order at its expected revision.
    function stayRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId);

    /// @notice Resumes exactly one unexpired fixture order without extending its original period.
    function resumeRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId);

    /// @notice Permanently revokes exactly one fixture order at its expected revision.
    function revokeRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId);
}
