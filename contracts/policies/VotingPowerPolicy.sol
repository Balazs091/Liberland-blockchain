// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IElectorateRegistry} from "../interfaces/IElectorateRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IVotingPowerPolicy} from "../interfaces/IVotingPowerPolicy.sol";

/// @title VotingPowerPolicy
/// @notice Computes governance voting power from active political stake for eligible wallets.
contract VotingPowerPolicy is IVotingPowerPolicy {
    error InvalidPolicy(address policyAddress);
    error InvalidRegistry(address registryAddress);

    ICitizenEligibilityPolicy private immutable _citizenEligibilityPolicy;
    IElectorateRegistry private immutable _electorateRegistry;
    IIdentityRegistry private immutable _identityRegistry;
    IStakeRegistry private immutable _stakeRegistry;

    /// @param identityRegistryAddress The identity registry address.
    /// @param stakeRegistryAddress The stake registry address.
    /// @param citizenEligibilityPolicyAddress The citizen eligibility policy address.
    /// @param electorateRegistryAddress The electorate registry pinned for historical voting eligibility.
    constructor(
        address identityRegistryAddress,
        address stakeRegistryAddress,
        address citizenEligibilityPolicyAddress,
        address electorateRegistryAddress
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
        if (electorateRegistryAddress == address(0) || electorateRegistryAddress.code.length == 0) {
            revert InvalidRegistry(electorateRegistryAddress);
        }
        if (
            IElectorateRegistry(electorateRegistryAddress).identityRegistry() != identityRegistryAddress
                || IElectorateRegistry(electorateRegistryAddress).stakeRegistry() != stakeRegistryAddress
        ) {
            revert InvalidRegistry(electorateRegistryAddress);
        }

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _citizenEligibilityPolicy = ICitizenEligibilityPolicy(citizenEligibilityPolicyAddress);
        _electorateRegistry = IElectorateRegistry(electorateRegistryAddress);
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
    function electorateRegistry() external view returns (address registryAddress) {
        return address(_electorateRegistry);
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

    /// @inheritdoc IVotingPowerPolicy
    function votingPowerAt(address wallet, uint48 blockNumber) external view returns (uint256 power) {
        if (!_citizenEligibilityPolicy.isCitizenInGoodStanding(wallet)) {
            return 0;
        }

        bytes32 personId = _identityRegistry.resolveWalletToPersonId(wallet);
        if (personId == bytes32(0)) {
            return 0;
        }

        if (!_electorateRegistry.wasEligibleAt(personId, blockNumber)) {
            return 0;
        }

        return _stakeRegistry.activeStakeAt(personId, blockNumber);
    }
}
