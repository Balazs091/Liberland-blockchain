// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

/// @title ReceiptConsumption
/// @notice Internal one-shot storage mechanics keyed by the complete domain-separated receipt digest.
/// @dev This library provides no approval or authority. Callers MUST authenticate the issuer/writer, verify
///      approved exact effects and check effect-specific effective/final/stay conditions before consuming.
///      Store this state in the issuing workflow; a new deployment does not inherit old consumption markers.
library ReceiptConsumption {
    /// @notice The zero value is not a receipt identifier.
    error InvalidReceiptDigest();
    /// @notice The complete receipt digest was already consumed in this state.
    error ReceiptAlreadyConsumed(bytes32 digest);

    struct State {
        mapping(bytes32 digest => bool consumed) consumed;
    }

    /// @notice Marks an authorised, executable receipt as consumed exactly once.
    /// @dev Apply the approved downstream effect in the same transaction so a failure also reverts this write.
    ///      Never pass a bare struct hash, local nonce or user-selected case ID instead of the full digest.
    /// @param self Canonical consumption state owned by the issuing workflow.
    /// @param digest The complete nonzero receipt digest, after caller-side authorisation and effect checks.
    function consume(State storage self, bytes32 digest) internal {
        if (digest == bytes32(0)) revert InvalidReceiptDigest();
        if (self.consumed[digest]) revert ReceiptAlreadyConsumed(digest);
        self.consumed[digest] = true;
    }

    /// @notice Reads whether a complete receipt digest has already been consumed in this state.
    /// @param self Canonical consumption state owned by the issuing workflow.
    /// @param digest The complete receipt digest to inspect.
    /// @return consumed Whether this state has recorded consumption.
    function isConsumed(State storage self, bytes32 digest) internal view returns (bool consumed) {
        return self.consumed[digest];
    }
}
