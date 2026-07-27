// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title IUnstakingPolicy
/// @notice Policy interface for the discrete 30-day unstaking model and welfare effect.
interface IUnstakingPolicy {
    /// @notice Returns the configured stake registry address.
    /// @return registryAddress The stake registry address.
    function stakeRegistry() external view returns (address registryAddress);

    /// @notice Returns the welfare period applied after each discrete unstake.
    /// @return durationSeconds The welfare period in seconds.
    function welfarePeriod() external view returns (uint64 durationSeconds);

    /// @notice Returns the annualized unstake rate cap expressed in basis points.
    /// @return rateBps The annual unstake rate in basis points.
    function annualUnstakeRateBps() external view returns (uint16 rateBps);

    /// @notice Returns the stake portion releasable by a single discrete unstake.
    /// @dev Equals activeStake * annualUnstakeRateBps * welfarePeriod / (10_000 * YEAR).
    /// @param activeStake The current active political stake.
    /// @return portion The releasable portion for one unstake call.
    function unstakePortion(uint256 activeStake) external view returns (uint256 portion);

    /// @notice Returns the welfare end timestamp for an unstake starting at a timestamp.
    /// @param startTimestamp The unstake start timestamp.
    /// @return welfareUntil The derived welfare end timestamp.
    function previewWelfareUntil(uint64 startTimestamp) external view returns (uint64 welfareUntil);

    /// @notice Returns true when the person is currently inside a welfare period.
    /// @param personId The canonical person identifier.
    /// @return inWelfare Whether the person is in welfare.
    function isInWelfare(bytes32 personId) external view returns (bool inWelfare);

    /// @notice Returns true when the person may execute a discrete unstake right now.
    /// @param personId The canonical person identifier.
    /// @return allowed Whether an unstake would release a non-zero amount.
    function canUnstake(bytes32 personId) external view returns (bool allowed);
}
