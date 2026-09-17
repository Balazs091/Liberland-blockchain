// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IConstitutionalReview} from "../interfaces/IConstitutionalReview.sol";
import {ISenateApp} from "../interfaces/ISenateApp.sol";
import {SenateTypes} from "../types/SenateTypes.sol";

/// @title BoundedGovernanceHook
/// @notice Reads optional negative-power hooks without trusting their gas use or ABI return data.
/// @dev Hooks receive at most 100,000 gas. Failure or a noncanonical response disables that optional read;
///      callers must supply enough gas to offer the whole budget, so underfunding cannot bypass an active hook.
library BoundedGovernanceHook {
    error InsufficientHookGas(uint256 available, uint256 required);

    uint256 internal constant HOOK_GAS_LIMIT = 100_000;
    // Cover EIP-150's 1/64 reserve, cold STATICCALL cost, and the instructions between the check and call.
    uint256 internal constant MINIMUM_CALLER_GAS = HOOK_GAS_LIMIT + HOOK_GAS_LIMIT / 63 + 10_000;

    /// @notice Reads a canonical action-cancellation record or returns an empty record for a failed hook.
    function actionCancellation(address senate, bytes32 actionId)
        internal
        view
        returns (SenateTypes.ActionCancellationRecord memory record)
    {
        (bool valid, bytes memory response) =
            _read(senate, abi.encodeCall(ISenateApp.getActionCancellationRecord, (actionId)), 10);
        if (!valid || !_fits(response, 1, 32) || !_fits(response, 2, 32)) return record;
        for (uint256 index = 3; index <= 6; ++index) {
            if (!_fits(response, index, 64)) return record;
        }
        if (!_boolean(response, 7) || !_boolean(response, 8) || !_boolean(response, 9)) return record;
        return abi.decode(response, (SenateTypes.ActionCancellationRecord));
    }

    /// @notice Reads a canonical referendum-veto record or returns an empty record for a failed hook.
    function referendumVeto(address senate, bytes32 referendumId)
        internal
        view
        returns (SenateTypes.ReferendumVetoRecord memory record)
    {
        (bool valid, bytes memory response) =
            _read(senate, abi.encodeCall(ISenateApp.getReferendumVetoRecord, (referendumId)), 10);
        if (!valid || !_fits(response, 5, 32) || !_fits(response, 6, 32)) return record;
        for (uint256 index = 1; index <= 4; ++index) {
            if (!_fits(response, index, 64)) return record;
        }
        if (!_boolean(response, 7) || !_boolean(response, 8) || !_boolean(response, 9)) return record;
        return abi.decode(response, (SenateTypes.ReferendumVetoRecord));
    }

    /// @notice Reads a canonical disbursement suspension or returns an empty record for a failed hook.
    function disbursementSuspension(address senate, bytes32 actionId)
        internal
        view
        returns (SenateTypes.DisbursementSuspension memory record)
    {
        (bool valid, bytes memory response) =
            _read(senate, abi.encodeCall(ISenateApp.getDisbursementSuspension, (actionId)), 4);
        if (!valid || !_boolean(response, 0) || !_fits(response, 1, 64) || !_fits(response, 2, 32)) return record;
        return abi.decode(response, (SenateTypes.DisbursementSuspension));
    }

    /// @notice Reads a canonical review decision or returns false for a failed hook.
    function executionPaused(address review, bytes32 actionId) internal view returns (bool paused) {
        (bool valid, bytes memory response) =
            _read(review, abi.encodeCall(IConstitutionalReview.isActionExecutionPaused, (actionId)), 1);
        return valid && _boolean(response, 0) && _word(response, 0) == 1;
    }

    function _read(address target, bytes memory callData, uint256 responseWords)
        private
        view
        returns (bool valid, bytes memory response)
    {
        response = new bytes(responseWords * 32);
        uint256 available = gasleft();
        if (available < MINIMUM_CALLER_GAS) revert InsufficientHookGas(available, MINIMUM_CALLER_GAS);
        // Copy at most the fixed expected output size. Never allocate or copy an untrusted RETURNDATASIZE.
        assembly ("memory-safe") {
            valid := staticcall(
                HOOK_GAS_LIMIT,
                target,
                add(callData, 32),
                mload(callData),
                add(response, 32),
                mload(response)
            )
            valid := and(valid, eq(returndatasize(), mload(response)))
        }
    }

    function _fits(bytes memory response, uint256 index, uint256 bits) private pure returns (bool canonical) {
        return _word(response, index) >> bits == 0;
    }

    function _boolean(bytes memory response, uint256 index) private pure returns (bool canonical) {
        return _word(response, index) <= 1;
    }

    function _word(bytes memory response, uint256 index) private pure returns (uint256 value) {
        assembly ("memory-safe") {
            value := mload(add(add(response, 32), mul(index, 32)))
        }
    }
}
