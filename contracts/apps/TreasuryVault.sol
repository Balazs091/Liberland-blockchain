// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ITreasuryVault} from "../interfaces/ITreasuryVault.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title TreasuryVault
/// @notice Minimal native-asset treasury vault executed only through the governance timelock.
contract TreasuryVault is ITreasuryVault {
    IConstitutionKernel private immutable _kernel;

    mapping(bytes32 requestId => bool executed) private _executedRequests;

    constructor(address kernelAddress) {
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) {
            revert IConstitutionKernel.InvalidModuleAddress(bytes32(0), kernelAddress);
        }

        _kernel = IConstitutionKernel(kernelAddress);
    }

    receive() external payable {}

    /// @inheritdoc ITreasuryVault
    function kernel() external view returns (address kernelAddress) {
        return address(_kernel);
    }

    /// @inheritdoc ITreasuryVault
    function isDisbursementExecuted(bytes32 requestId) external view returns (bool executed) {
        return _executedRequests[requestId];
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
        (bool success,) = payload.recipient.call{value: payload.amount}("");
        if (!success) {
            revert InsufficientTreasuryBalance(address(this).balance, payload.amount);
        }

        emit TreasuryDisbursementExecuted(
            payload.requestId,
            payload.budgetId,
            payload.recipient,
            payload.amount,
            payload.noteHash,
            uint64(block.timestamp),
            msg.sender
        );
    }
}
