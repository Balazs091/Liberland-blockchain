// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title ICitizenEligibilityPolicy
/// @notice Policy interface for citizen political-rights eligibility.
interface ICitizenEligibilityPolicy {
    /// @notice Returns the configured identity registry address.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured stake registry address.
    /// @return registryAddress The stake registry address.
    function stakeRegistry() external view returns (address registryAddress);

    /// @notice Returns the minimum active political stake required for good standing.
    /// @return minimumStake The minimum stake amount.
    function minimumCitizenStake() external view returns (uint256 minimumStake);

    /// @notice Returns true when a person belongs to the constitutional civic roll.
    /// @dev Temporary post-unstake welfare suspends voting but does not remove citizenship from this roll.
    /// @param personId The canonical person identifier to evaluate.
    /// @return eligible Whether the person belongs to the civic roll.
    function isCitizenOnCivicRoll(bytes32 personId) external view returns (bool eligible);

    /// @notice Returns true when a wallet satisfies the v1 citizen-in-good-standing rule set.
    /// @param wallet The wallet to evaluate.
    /// @return eligible Whether the wallet is a citizen in good standing.
    function isCitizenInGoodStanding(address wallet) external view returns (bool eligible);
}
