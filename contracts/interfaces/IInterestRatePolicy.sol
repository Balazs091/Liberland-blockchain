// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title IInterestRatePolicy
/// @notice Policy interface for utilization-based lending rates.
interface IInterestRatePolicy {
    /// @notice Returns the fixed-point scale used for rates and utilization.
    /// @return rayValue The 1e27 scale.
    function ray() external pure returns (uint256 rayValue);

    /// @notice Returns the borrow rate per second for a utilization value.
    /// @param utilizationRay Utilization scaled by 1e27.
    /// @return rateRay The borrow rate per second scaled by 1e27.
    function borrowRatePerSecond(uint256 utilizationRay) external view returns (uint256 rateRay);

    /// @notice Returns the supply rate per second after reserve factor.
    /// @param utilizationRay Utilization scaled by 1e27.
    /// @param reserveFactorBps Protocol reserve factor in basis points.
    /// @return rateRay The supply rate per second scaled by 1e27.
    function supplyRatePerSecond(uint256 utilizationRay, uint16 reserveFactorBps)
        external
        view
        returns (uint256 rateRay);
}
