// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ICandidateEligibilityPolicy} from "../interfaces/ICandidateEligibilityPolicy.sol";
import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";

/// @title CandidateEligibilityPolicy
/// @notice Evaluates whether a wallet may stand for Congress under the current v1 rules.
contract CandidateEligibilityPolicy is ICandidateEligibilityPolicy {
    error InvalidMinimumCandidateStake(uint256 minimumStake);
    error InvalidPolicy(address policyAddress);
    error InvalidRegistry(address registryAddress);

    ICitizenEligibilityPolicy private immutable _citizenEligibilityPolicy;
    IIdentityRegistry private immutable _identityRegistry;
    IStakeRegistry private immutable _stakeRegistry;
    uint256 private immutable _minimumCandidateStake;

    /// @param identityRegistryAddress The identity registry address.
    /// @param stakeRegistryAddress The stake registry address.
    /// @param citizenEligibilityPolicyAddress The citizen eligibility policy address.
    /// @param minimumCandidateStake_ The minimum active stake required to stand for Congress.
    constructor(
        address identityRegistryAddress,
        address stakeRegistryAddress,
        address citizenEligibilityPolicyAddress,
        uint256 minimumCandidateStake_
    ) {
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidRegistry(identityRegistryAddress);
        }
        if (stakeRegistryAddress == address(0) || stakeRegistryAddress.code.length == 0) {
            revert InvalidRegistry(stakeRegistryAddress);
        }
        if (citizenEligibilityPolicyAddress == address(0) || citizenEligibilityPolicyAddress.code.length == 0) {
            revert InvalidPolicy(citizenEligibilityPolicyAddress);
        }

        uint256 minimumCitizenStake = ICitizenEligibilityPolicy(citizenEligibilityPolicyAddress).minimumCitizenStake();
        if (minimumCandidateStake_ == 0 || minimumCandidateStake_ < minimumCitizenStake) {
            revert InvalidMinimumCandidateStake(minimumCandidateStake_);
        }

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _citizenEligibilityPolicy = ICitizenEligibilityPolicy(citizenEligibilityPolicyAddress);
        _minimumCandidateStake = minimumCandidateStake_;
    }

    /// @inheritdoc ICandidateEligibilityPolicy
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc ICandidateEligibilityPolicy
    function stakeRegistry() external view returns (address registryAddress) {
        return address(_stakeRegistry);
    }

    /// @inheritdoc ICandidateEligibilityPolicy
    function citizenEligibilityPolicy() external view returns (address policyAddress) {
        return address(_citizenEligibilityPolicy);
    }

    /// @inheritdoc ICandidateEligibilityPolicy
    function minimumCandidateStake() external view returns (uint256 minimumStake) {
        return _minimumCandidateStake;
    }

    /// @inheritdoc ICandidateEligibilityPolicy
    function isEligibleCandidate(address wallet) external view returns (bool eligible) {
        if (!_citizenEligibilityPolicy.isCitizenInGoodStanding(wallet)) {
            return false;
        }

        bytes32 personId = _identityRegistry.resolveWalletToPersonId(wallet);
        if (personId == bytes32(0)) {
            return false;
        }

        return _stakeRegistry.activeStakeOf(personId) >= _minimumCandidateStake;
    }
}
