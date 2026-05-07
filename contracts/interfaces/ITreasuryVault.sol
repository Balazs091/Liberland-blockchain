// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title ITreasuryVault
/// @notice Minimal interface for bounded timelock-executed treasury disbursements.
interface ITreasuryVault {
    error InsufficientTreasuryBalance(uint256 available, uint256 requiredAmount);
    error InvalidDisbursementAsset(address asset);
    error InvalidDisbursementRecipient(address recipient);
    error InvalidDisbursementRequest(bytes32 requestId);
    error UnauthorizedTreasuryCaller(address caller);

    event TreasuryDisbursementExecuted(
        bytes32 indexed requestId,
        bytes32 indexed budgetId,
        address indexed recipient,
        uint256 amount,
        bytes32 noteHash,
        uint64 executedAt,
        address executedBy
    );

    function kernel() external view returns (address kernelAddress);
    function isDisbursementExecuted(bytes32 requestId) external view returns (bool executed);
    function executeDisbursement(GovernanceTypes.TreasuryDisbursementPayload calldata payload) external;
}
