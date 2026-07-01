// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IKernelModule} from "./IKernelModule.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title ITreasuryVault
/// @notice Minimal interface for bounded timelock-executed treasury disbursements.
interface ITreasuryVault is IKernelModule {
    error InsufficientTreasuryBalance(uint256 available, uint256 requiredAmount);
    error InvalidDisbursementAsset(address asset);
    error InvalidDisbursementRecipient(address recipient);
    error InvalidDisbursementRequest(bytes32 requestId);
    error InvalidTreasuryDeposit(uint256 amount);
    error UnauthorizedTreasuryCaller(address caller);

    event TreasuryNativeDepositReceived(
        address indexed sender, uint256 amount, bytes32 indexed depositReference, uint64 receivedAt
    );

    event TreasuryDisbursementExecuted(
        bytes32 indexed requestId,
        bytes32 indexed budgetId,
        address indexed recipient,
        uint256 amount,
        bytes32 noteHash,
        uint64 executedAt,
        address executedBy
    );

    function isDisbursementExecuted(bytes32 requestId) external view returns (bool executed);

    /// @notice Receives native-asset deposits into the treasury through an explicit accounting entrypoint.
    /// @param depositReference Caller-supplied reference for off-chain deposit classification.
    function receiveNativeDeposit(bytes32 depositReference) external payable;

    function executeDisbursement(GovernanceTypes.TreasuryDisbursementPayload calldata payload) external;
}
