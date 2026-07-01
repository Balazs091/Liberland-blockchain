// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title LendingTypes
/// @notice Shared structs for the stake-backed USDC lending milestone.
library LendingTypes {
    struct RatePreview {
        uint256 utilizationRay;
        uint256 borrowRatePerSecondRay;
        uint256 supplyRatePerSecondRay;
    }
}
