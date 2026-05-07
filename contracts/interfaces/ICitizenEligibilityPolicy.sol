// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

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

    /// @notice Returns true when a wallet satisfies the v1 citizen-in-good-standing rule set.
    /// @param wallet The wallet to evaluate.
    /// @return eligible Whether the wallet is a citizen in good standing.
    function isCitizenInGoodStanding(address wallet) external view returns (bool eligible);
}
