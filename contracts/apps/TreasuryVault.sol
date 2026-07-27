// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {KernelModule} from "../base/KernelModule.sol";
import {IBudgetEnvelopeRegistry} from "../interfaces/IBudgetEnvelopeRegistry.sol";
import {ITreasuryVault} from "../interfaces/ITreasuryVault.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title TreasuryVault
/// @notice Minimal ERC20 treasury vault executed only through the governance timelock.
/// @dev System money is ERC20 (LLM and stablecoins); native ETH is gas-only and is deliberately not accepted, so
///      the vault has no payable path at all.
contract TreasuryVault is ITreasuryVault, KernelModule {
    using SafeERC20 for IERC20;

    mapping(bytes32 requestId => bool executed) private _executedRequests;

    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc ITreasuryVault
    function isDisbursementExecuted(bytes32 requestId) external view returns (bool executed) {
        return _executedRequests[requestId];
    }

    /// @inheritdoc ITreasuryVault
    function treasuryBalanceOf(address asset) external view returns (uint256 amount) {
        return IERC20(asset).balanceOf(address(this));
    }

    /// @inheritdoc ITreasuryVault
    function receiveTokenDeposit(address asset, uint256 amount, bytes32 depositReference) external {
        if (asset == address(0) || asset.code.length == 0) {
            revert InvalidTreasuryDepositAsset(asset);
        }
        if (amount == 0) {
            revert InvalidTreasuryDeposit(amount);
        }

        IERC20 token = IERC20(asset);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 receivedAmount = token.balanceOf(address(this)) - balanceBefore;
        if (receivedAmount == 0) {
            revert InvalidTreasuryDeposit(receivedAmount);
        }

        emit TreasuryTokenDepositReceived(msg.sender, asset, receivedAmount, depositReference, uint64(block.timestamp));
    }

    /// @inheritdoc ITreasuryVault
    function executeDisbursement(GovernanceTypes.TreasuryDisbursementPayload calldata payload) external {
        if (msg.sender != _kernel.getModule(KernelModuleIds.ACTION_TIMELOCK)) {
            revert UnauthorizedTreasuryCaller(msg.sender);
        }
        if (payload.requestId == bytes32(0)) {
            revert InvalidDisbursementRequest(payload.requestId);
        }
        if (payload.asset == address(0) || payload.asset.code.length == 0) {
            revert InvalidDisbursementAsset(payload.asset);
        }
        if (payload.recipient == address(0)) {
            revert InvalidDisbursementRecipient(payload.recipient);
        }
        if (_executedRequests[payload.requestId]) {
            revert InvalidDisbursementRequest(payload.requestId);
        }

        IBudgetEnvelopeRegistry budgetRegistry =
            IBudgetEnvelopeRegistry(_kernel.getModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY));
        (bytes32 committedBudgetId, uint256 committedAmount, bool activeCommitment) =
            budgetRegistry.getBudgetCommitment(payload.requestId);
        TreasuryTypes.BudgetEnvelope memory envelope = budgetRegistry.getBudgetEnvelope(payload.budgetId);
        if (
            !activeCommitment || committedBudgetId != payload.budgetId || committedAmount != payload.amount
                || envelope.asset != payload.asset
        ) {
            revert InvalidDisbursementRequest(payload.requestId);
        }

        IERC20 token = IERC20(payload.asset);
        uint256 balance = token.balanceOf(address(this));
        if (balance < payload.amount) {
            revert InsufficientTreasuryBalance(payload.asset, balance, payload.amount);
        }

        _executedRequests[payload.requestId] = true;
        emit TreasuryDisbursementExecuted(
            payload.requestId,
            payload.budgetId,
            payload.recipient,
            payload.asset,
            payload.amount,
            payload.noteHash,
            uint64(block.timestamp),
            msg.sender
        );

        uint256 recipientBalanceBefore = token.balanceOf(payload.recipient);
        token.safeTransfer(payload.recipient, payload.amount);
        uint256 receivedAmount = token.balanceOf(payload.recipient) - recipientBalanceBefore;
        if (receivedAmount != payload.amount) {
            revert UnexpectedDisbursementAmount(payload.amount, receivedAmount);
        }
    }
}
