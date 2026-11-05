// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {MembershipTypes} from "../types/MembershipTypes.sol";

/// @title ISepoliaGovernedMembershipController
/// @notice Sepolia-only synthetic effect driver controlled by current Congress members, not a permanent operator.
/// @dev This is not a production legal decision issuer. Registry and governance facts remain canonical.
interface ISepoliaGovernedMembershipController {
    error WrongChain(uint256 actualChainId);
    error InvalidDependency(address dependency);
    error DependencyMismatch(address expected, address actual);
    error NotCurrentCongressMember(address caller);
    error NotSyntheticPerson(bytes32 personId);

    event SyntheticEffectExecuted(
        bytes32 indexed receiptId, bytes32 indexed personId, bytes32 indexed orderId, bytes32 operation, uint256 nonce
    );

    /// @notice Returns the canonical kernel selected at construction.
    function kernel() external view returns (address);
    /// @notice Returns the stable identity registry used by this test profile.
    function identityRegistry() external view returns (address);
    /// @notice Returns the stable membership ledger; replacing the controller never copies or clears this ledger.
    function membershipRegistry() external view returns (address);
    /// @notice Returns the next synthetic receipt nonce for this issuer domain.
    function nextReceiptNonce() external view returns (uint256);
    /// @notice Returns whether this current Congress member can submit synthetic effects on this network.
    function canSubmit(address account) external view returns (bool);
    /// @notice Records a synthetic restriction for one of the four fixed staged people.
    function recordRestriction(MembershipTypes.OrderInput calldata effect) external returns (bytes32 receiptId);
    /// @notice Stays exactly the named order at its expected current revision.
    function stayRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId);
    /// @notice Resumes one unexpired order without extending its original end.
    function resumeRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId);
    /// @notice Permanently revokes exactly the named synthetic order.
    function revokeRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
        external
        returns (bytes32 receiptId);
}
