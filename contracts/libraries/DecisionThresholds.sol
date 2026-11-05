// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

/// @title DecisionThresholds
/// @notice Overflow-safe arithmetic for specified vote denominators, without choosing legal quorum rules.
/// @dev Callers must establish eligible voters and the correct denominator, including abstention/recusal rules.
library DecisionThresholds {
    /// @notice Support cannot exceed the denominator to which it belongs.
    error InvalidTally(uint256 support, uint256 total);

    /// @notice Tests whether support is strictly greater than half of a supplied nonzero denominator.
    /// @param support Valid supporting votes or weight.
    /// @param total The independently established denominator; zero never passes.
    /// @return passed Whether the strict-majority arithmetic is satisfied.
    function hasStrictMajority(uint256 support, uint256 total) internal pure returns (bool passed) {
        if (support > total) revert InvalidTally(support, total);
        return total != 0 && support > total / 2;
    }

    /// @notice Tests whether support is at least two thirds of a supplied nonzero denominator.
    /// @param support Valid supporting votes or weight.
    /// @param total The independently established denominator; zero never passes.
    /// @return passed Whether the two-thirds arithmetic is satisfied, rounding the required support up.
    function hasTwoThirds(uint256 support, uint256 total) internal pure returns (bool passed) {
        if (support > total) revert InvalidTally(support, total);
        // ceil(2 * total / 3) == total - floor(total / 3), without an overflowing multiplication.
        return total != 0 && support >= total - total / 3;
    }
}
