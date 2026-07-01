// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {KernelModule} from "../base/KernelModule.sol";
import {ITreasuryVault} from "../interfaces/ITreasuryVault.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title TreasuryVault
/// @notice Minimal native-asset treasury vault executed only through the governance timelock.
contract TreasuryVault is ITreasuryVault, KernelModule {
    mapping(bytes32 requestId => bool executed) private _executedRequests;

    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    receive() external payable {}

    /// @inheritdoc ITreasuryVault
    function isDisbursementExecuted(bytes32 requestId) external view returns (bool executed) {
        return _executedRequests[requestId];
    }

    /// @inheritdoc ITreasuryVault
    function receiveNativeDeposit(bytes32 depositReference) external payable {
        if (msg.value == 0) {
            revert InvalidTreasuryDeposit(msg.value);
        }

        emit TreasuryNativeDepositReceived(msg.sender, msg.value, depositReference, uint64(block.timestamp));
    }

    /// @inheritdoc ITreasuryVault
    function executeDisbursement(GovernanceTypes.TreasuryDisbursementPayload calldata payload) external {
        if (msg.sender != _kernel.getModule(KernelModuleIds.ACTION_TIMELOCK)) {
            revert UnauthorizedTreasuryCaller(msg.sender);
        }
        if (payload.requestId == bytes32(0)) {
            revert InvalidDisbursementRequest(payload.requestId);
        }
        if (payload.asset != address(0)) {
            revert InvalidDisbursementAsset(payload.asset);
        }
        if (payload.recipient == address(0)) {
            revert InvalidDisbursementRecipient(payload.recipient);
        }
        if (_executedRequests[payload.requestId]) {
            revert InvalidDisbursementRequest(payload.requestId);
        }
        if (address(this).balance < payload.amount) {
            revert InsufficientTreasuryBalance(address(this).balance, payload.amount);
        }

        _executedRequests[payload.requestId] = true;
        emit TreasuryDisbursementExecuted(
            payload.requestId,
            payload.budgetId,
            payload.recipient,
            payload.amount,
            payload.noteHash,
            uint64(block.timestamp),
            msg.sender
        );

        (bool success,) = payload.recipient.call{value: payload.amount}("");
        if (!success) {
            revert InsufficientTreasuryBalance(address(this).balance, payload.amount);
        }
    }
}
