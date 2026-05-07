// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IVotingPowerPolicy
/// @notice Policy interface for governance voting power derived from political stake.
interface IVotingPowerPolicy {
    /// @notice Returns the configured identity registry address.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured stake registry address.
    /// @return registryAddress The stake registry address.
    function stakeRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured citizen eligibility policy address.
    /// @return policyAddress The citizen eligibility policy address.
    function citizenEligibilityPolicy() external view returns (address policyAddress);

    /// @notice Returns the governance voting power for a wallet.
    /// @param wallet The wallet to evaluate.
    /// @return power The resolved voting power.
    function votingPower(address wallet) external view returns (uint256 power);
}
