// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IVotingPowerPolicy} from "../interfaces/IVotingPowerPolicy.sol";

/// @title VotingPowerPolicy
/// @notice Computes governance voting power from active political stake for eligible wallets.
contract VotingPowerPolicy is IVotingPowerPolicy {
    error InvalidPolicy(address policyAddress);
    error InvalidRegistry(address registryAddress);

    ICitizenEligibilityPolicy private immutable _citizenEligibilityPolicy;
    IIdentityRegistry private immutable _identityRegistry;
    IStakeRegistry private immutable _stakeRegistry;

    /// @param identityRegistryAddress The identity registry address.
    /// @param stakeRegistryAddress The stake registry address.
    /// @param citizenEligibilityPolicyAddress The citizen eligibility policy address.
    constructor(
        address identityRegistryAddress,
        address stakeRegistryAddress,
        address citizenEligibilityPolicyAddress
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

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _citizenEligibilityPolicy = ICitizenEligibilityPolicy(citizenEligibilityPolicyAddress);
    }

    /// @inheritdoc IVotingPowerPolicy
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc IVotingPowerPolicy
    function stakeRegistry() external view returns (address registryAddress) {
        return address(_stakeRegistry);
    }

    /// @inheritdoc IVotingPowerPolicy
    function citizenEligibilityPolicy() external view returns (address policyAddress) {
        return address(_citizenEligibilityPolicy);
    }

    /// @inheritdoc IVotingPowerPolicy
    function votingPower(address wallet) external view returns (uint256 power) {
        if (!_citizenEligibilityPolicy.isCitizenInGoodStanding(wallet)) {
            return 0;
        }

        bytes32 personId = _identityRegistry.resolveWalletToPersonId(wallet);
        if (personId == bytes32(0)) {
            return 0;
        }

        return _stakeRegistry.activeStakeOf(personId);
    }
}
