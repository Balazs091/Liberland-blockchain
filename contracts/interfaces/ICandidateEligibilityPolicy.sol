// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title ICandidateEligibilityPolicy
/// @notice Policy interface for determining whether a wallet may stand for Congress.
interface ICandidateEligibilityPolicy {
    /// @notice Returns the configured identity registry address.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured stake registry address.
    /// @return registryAddress The stake registry address.
    function stakeRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured citizen eligibility policy address.
    /// @return policyAddress The citizen eligibility policy address.
    function citizenEligibilityPolicy() external view returns (address policyAddress);

    /// @notice Returns the minimum active stake required to stand as a Congress candidate.
    /// @return minimumStake The minimum candidate stake.
    function minimumCandidateStake() external view returns (uint256 minimumStake);

    /// @notice Returns true when a wallet may stand as a Congress candidate under the current v1 rules.
    /// @param wallet The wallet to evaluate.
    /// @return eligible Whether the wallet may stand for Congress.
    function isEligibleCandidate(address wallet) external view returns (bool eligible);
}
