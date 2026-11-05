// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

/// @title SepoliaFoundationFixtures
/// @notice Fixed public test records and balances, with no real identities or supplied private keys.
library SepoliaFoundationFixtures {
    error SyntheticIndexOutOfBounds(uint256 index);

    uint256 internal constant CHAIN_ID = 11_155_111;
    uint256 internal constant PERSON_COUNT = 3;
    uint256 internal constant GENESIS_SUPPLY = 1_000_000e18;
    uint256 internal constant BALANCE_PER_PERSON = 10_000e18;
    bytes32 internal constant FIXTURE_VERSION = keccak256("sepolia.foundation.fixtures.v1");

    /// @notice Returns a stable ID for one of the three synthetic records.
    function personIdAt(uint256 index) internal pure returns (bytes32) {
        _checkIndex(index);
        return keccak256(abi.encode(FIXTURE_VERSION, "synthetic-person", index));
    }

    /// @notice Returns a deterministic dummy wallet, not a provided or known signing key.
    /// @dev Dummy balances are for storage/display checks. The operator reserve can fund actual testers.
    function walletAt(uint256 index) internal pure returns (address) {
        _checkIndex(index);
        return address(uint160(uint256(keccak256(abi.encode(FIXTURE_VERSION, "synthetic-wallet", index)))));
    }

    /// @notice Returns the public metadata commitment for one fixed dummy record.
    function metadataHashAt(uint256 index) internal pure returns (bytes32) {
        _checkIndex(index);
        return keccak256(abi.encode(FIXTURE_VERSION, "NO_REAL_PERSON_SYNTHETIC_RECORD", index));
    }

    /// @notice Returns whether a subject is one of the fixed fixture people.
    function isSyntheticPerson(bytes32 personId) internal pure returns (bool) {
        for (uint256 index; index < PERSON_COUNT; ++index) {
            if (personIdAt(index) == personId) return true;
        }
        return false;
    }

    function _checkIndex(uint256 index) private pure {
        if (index >= PERSON_COUNT) revert SyntheticIndexOutOfBounds(index);
    }
}
