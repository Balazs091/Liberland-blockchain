// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IUnstakingPolicy
/// @notice Policy interface for unstake cooldown mechanics and political-rights effects.
interface IUnstakingPolicy {
    /// @notice Returns the configured stake registry address.
    /// @return registryAddress The stake registry address.
    function stakeRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured unstake cooldown duration.
    /// @return durationSeconds The cooldown duration in seconds.
    function cooldownDuration() external view returns (uint64 durationSeconds);

    /// @notice Returns the cooldown end timestamp for a requested start timestamp.
    /// @param startTimestamp The cooldown start timestamp.
    /// @return cooldownEnd The derived cooldown end timestamp.
    function previewCooldownEnd(uint64 startTimestamp) external view returns (uint64 cooldownEnd);

    /// @notice Returns true when the requested unstake is valid under the current policy.
    /// @param personId The canonical person identifier.
    /// @param amount The requested unstake amount.
    /// @return allowed Whether the request is valid.
    function canStartUnstake(bytes32 personId, uint256 amount) external view returns (bool allowed);

    /// @notice Returns true when political rights are blocked by an active unstaking cooldown.
    /// @param personId The canonical person identifier.
    /// @return blocked Whether political rights are blocked.
    function isPoliticalRightsBlocked(bytes32 personId) external view returns (bool blocked);

    /// @notice Returns the currently claimable unstake amount for a person identifier.
    /// @param personId The canonical person identifier.
    /// @return amount The claimable amount.
    function claimableAmount(bytes32 personId) external view returns (uint256 amount);
}
