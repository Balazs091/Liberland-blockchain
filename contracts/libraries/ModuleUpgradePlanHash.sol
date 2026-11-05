// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title ModuleUpgradePlanHash
/// @notice Unambiguous full-content plan commitments, bound to chain, kernel and immutable plan registry.
library ModuleUpgradePlanHash {
    bytes32 internal constant DOMAIN = keccak256("Liberland.ModuleUpgradePlan.v1");

    function hash(
        uint256 chainId,
        address kernel,
        address registry,
        bytes32 evidenceHash,
        GovernanceTypes.ModuleUpdate[] memory updates
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN, chainId, kernel, registry, evidenceHash, updates));
    }
}
