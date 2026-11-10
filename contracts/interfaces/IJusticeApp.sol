// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IKernelModule} from "./IKernelModule.sol";
import {JusticeTypes} from "../types/JusticeTypes.sol";

/// @notice Verifies private proceedings' signed final decisions and applies their fixed effects.
interface IJusticeApp is IKernelModule {
    error InvalidCharter();
    error InvalidRoster(JusticeTypes.Body body, bytes32 personId);
    error InactiveJustice();
    error InvalidDecision();
    error InvalidEffect();
    error InvalidApproval(bytes32 personId);
    error InsufficientApproval(JusticeTypes.Body body, uint256 required);
    error NoticePending(uint256 earliest);
    error ProtectedOffice(bytes32 personId);

    event JusticeMemberAppointed(JusticeTypes.Body indexed body, bytes32 indexed personId);
    event JusticeDecisionExecuted(
        bytes32 indexed decisionId,
        bytes32 indexed personId,
        JusticeTypes.Action indexed action,
        bytes32 reasonHash,
        bytes32 recordHash,
        string publicReasonURI
    );

    /// @notice Returns the pinned identity writer.
    function identityWriter() external view returns (address);

    /// @notice Reports whether all execution dependencies are canonical.
    function isCurrent() external view returns (bool);

    /// @notice Returns the public charter bounds, including its source document hash.
    function charter() external view returns (JusticeTypes.Charter memory);

    /// @notice Returns the configured size and membership of a body.
    function bodyMembership(JusticeTypes.Body body, bytes32 personId) external view returns (uint256 size, bool member);

    /// @notice Returns the relevant current revision to bind in a decision.
    function decisionStateRevision(JusticeTypes.Action action, bytes32 personId) external view returns (uint256);

    /// @notice Returns the EIP-712 digest to sign for the exact decision.
    function decisionDigest(JusticeTypes.Decision calldata decision) external view returns (bytes32);

    /// @notice Returns the separate consent digest that the destination wallet signs.
    function destinationConsentDigest(JusticeTypes.Decision calldata decision) external view returns (bytes32);

    /// @notice Executes admission, annulment, an exact reversal, adulthood recognition or wallet recovery.
    function executeIdentity(
        JusticeTypes.Decision calldata decision,
        JusticeTypes.IdentityEffect calldata effect,
        JusticeTypes.Approvals calldata approvals
    ) external;

    /// @notice Executes one membership restriction, removal, restoration or order relief.
    function executeMembership(
        JusticeTypes.Decision calldata decision,
        JusticeTypes.MembershipEffect calldata effect,
        JusticeTypes.Approvals calldata approvals
    ) external;

    /// @notice Executes one award from opted-in escrow or restoration backed by allocated funds.
    function executeFinancial(
        JusticeTypes.Decision calldata decision,
        JusticeTypes.FinancialEffect calldata effect,
        JusticeTypes.Approvals calldata approvals
    ) external;
}
