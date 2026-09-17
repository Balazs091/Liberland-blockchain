// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title LLMTokenConstants
/// @notice Protocol-wide denomination and hard-cap constants for Liberland Merit.
library LLMTokenConstants {
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant MAX_SUPPLY = 70_000_000 * 1e18;
}
