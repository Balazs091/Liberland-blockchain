// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title LendingTypes
/// @notice Shared structs for stake-backed USDC lending.
library LendingTypes {
    struct RatePreview {
        uint256 utilizationRay;
        uint256 borrowRatePerSecondRay;
        uint256 supplyRatePerSecondRay;
    }
}
