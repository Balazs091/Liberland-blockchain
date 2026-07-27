// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IKernelModule} from "./IKernelModule.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title ITreasuryVault
/// @notice Minimal interface for bounded timelock-executed ERC20 treasury disbursements.
interface ITreasuryVault is IKernelModule {
    error InsufficientTreasuryBalance(address asset, uint256 available, uint256 requiredAmount);
    error InvalidDisbursementAsset(address asset);
    error InvalidDisbursementRecipient(address recipient);
    error InvalidDisbursementRequest(bytes32 requestId);
    error InvalidTreasuryDeposit(uint256 amount);
    error InvalidTreasuryDepositAsset(address asset);
    error UnexpectedDisbursementAmount(uint256 expectedAmount, uint256 receivedAmount);
    error UnauthorizedTreasuryCaller(address caller);

    event TreasuryTokenDepositReceived(
        address indexed sender,
        address indexed asset,
        uint256 amount,
        bytes32 indexed depositReference,
        uint64 receivedAt
    );

    event TreasuryDisbursementExecuted(
        bytes32 indexed requestId,
        bytes32 indexed budgetId,
        address indexed recipient,
        address asset,
        uint256 amount,
        bytes32 noteHash,
        uint64 executedAt,
        address executedBy
    );

    function isDisbursementExecuted(bytes32 requestId) external view returns (bool executed);

    /// @notice Returns the vault's current balance of an ERC20 asset.
    /// @param asset The ERC20 token address.
    /// @return amount The vault balance in the asset's smallest units.
    function treasuryBalanceOf(address asset) external view returns (uint256 amount);

    /// @notice Receives ERC20 deposits into the treasury through an explicit accounting entrypoint.
    /// @dev Requires prior ERC20 approval for the vault. Direct ERC20 transfers also fund the treasury; this
    ///      entrypoint exists so deposits can carry an off-chain classification reference.
    /// @param asset The ERC20 token address.
    /// @param amount The deposit amount in the asset's smallest units.
    /// @param depositReference Caller-supplied reference for off-chain deposit classification.
    function receiveTokenDeposit(address asset, uint256 amount, bytes32 depositReference) external;

    /// @notice Executes an exact, active budget commitment through the canonical timelock.
    /// @param payload The disbursement terms, which must match the stable budget registry commitment.
    function executeDisbursement(GovernanceTypes.TreasuryDisbursementPayload calldata payload) external;
}
