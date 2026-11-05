// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

/// @title DeterminationHash
/// @notice Fixed context commitments for exact effects; a hash is neither approval nor execution authority.
/// @dev Unwired primitive. Issuers must compose the struct hash with their reviewed EIP-712 domain (chain ID,
///      verifying contract, name and version), authenticate decisions and validate each typed effect themselves.
library DeterminationHash {
    /// @dev No legal kind values or thresholds are assigned here. decisionType must identify a closed typed effect.
    struct Context {
        bytes32 matterId;
        bytes32 subjectCommitment;
        bytes32 rulesVersion;
        bytes32 decisionType;
        bytes32 effectHash;
        bytes32 expectedStateHash;
        address issuer;
        address writer;
        uint256 nonce;
        uint64 bodyEpoch;
        uint64 rosterRevision;
        uint32 revision;
        uint8 stage;
    }

    bytes32 internal constant CONTEXT_TYPEHASH = keccak256(
        "Determination(bytes32 matterId,bytes32 subjectCommitment,bytes32 rulesVersion,bytes32 decisionType,bytes32 effectHash,bytes32 expectedStateHash,address issuer,address writer,uint256 nonce,uint64 bodyEpoch,uint64 rosterRevision,uint32 revision,uint8 stage)"
    );

    /// @notice Hashes every context field using unambiguous static ABI encoding.
    /// @dev This is the EIP-712 struct hash only, not a domain-separated digest. For this all-static tuple,
    ///      abi.encode(CONTEXT_TYPEHASH, context) is identical to encoding the type hash then each field in order.
    ///      expectedStateHash must cover only the relevant state, so unrelated writes cannot stale an approval.
    ///      No field validation, signature verification, legal finding or permission is inferred from this hash.
    /// @param context The exact issuer/writer, case revision, effect and relevant-state commitment.
    /// @return structHash The commitment to the complete typed context.
    function hashStruct(Context memory context) internal pure returns (bytes32 structHash) {
        return keccak256(abi.encode(CONTEXT_TYPEHASH, context));
    }
}
