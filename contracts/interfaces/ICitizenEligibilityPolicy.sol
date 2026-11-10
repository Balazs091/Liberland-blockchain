// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

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

    /// @notice Returns the membership ledger used by this policy, or zero for the legacy rule set.
    function membershipRegistry() external view returns (address registryAddress);

    /// @notice Returns whether active unstaking welfare also excludes constitutional headcount.
    function excludesWelfareFromCivicRoll() external view returns (bool excluded);

    /// @notice Returns whether the configured production legal writer and membership ledger remain canonical.
    function electorateConfigurationValid() external view returns (bool valid);

    /// @notice Returns true when a person belongs to the constitutional civic roll.
    /// @dev The legacy policy includes temporary welfare; the explicit justice policy excludes it using expiry
    ///      certification. Temporary disciplinary Political orders affect live voting, not this denominator.
    /// @param personId The canonical person identifier to evaluate.
    /// @return eligible Whether the person belongs to the civic roll.
    function isCitizenOnCivicRoll(bytes32 personId) external view returns (bool eligible);

    /// @notice Returns true when a wallet satisfies the v1 citizen-in-good-standing rule set.
    /// @param wallet The wallet to evaluate.
    /// @return eligible Whether the wallet is a citizen in good standing.
    function isCitizenInGoodStanding(address wallet) external view returns (bool eligible);

    /// @notice Returns the separate credit-origin eligibility without importing political restrictions.
    function isEligibleForCredit(address wallet) external view returns (bool eligible);

    /// @notice Returns political standing plus any explicit appointment-eligibility restriction.
    function isEligibleForAppointment(address wallet) external view returns (bool eligible);
}
