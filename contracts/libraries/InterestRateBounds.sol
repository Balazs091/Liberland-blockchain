// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title InterestRateBounds
/// @notice Shared numerical operating limits for nominal, per-second-compounded lending rates.
/// @dev At the ceiling, 50 years of uninterrupted accrual grows an initially RAY-scaled index by less than e^100.
///      This preserves the configured 113% maximum APR; it is not a perpetual arithmetic-liveness guarantee.
library InterestRateBounds {
    uint256 internal constant RAY = 1e27;
    uint256 internal constant MAX_ANNUAL_RATE_BPS = 20_000;
    uint256 internal constant MAX_RATE_PER_SECOND_RAY = MAX_ANNUAL_RATE_BPS * RAY / (10_000 * 365 days);
}
