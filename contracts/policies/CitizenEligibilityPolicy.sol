// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";

/// @title CitizenEligibilityPolicy
/// @notice Evaluates whether a wallet is a citizen in good standing for v1 political rights.
contract CitizenEligibilityPolicy is ICitizenEligibilityPolicy {
    error InvalidMinimumCitizenStake(uint256 minimumStake);
    error InvalidRegistry(address registryAddress);

    IIdentityRegistry private immutable _identityRegistry;
    IStakeRegistry private immutable _stakeRegistry;
    uint256 private immutable _minimumCitizenStake;

    /// @param identityRegistryAddress The identity registry address.
    /// @param stakeRegistryAddress The stake registry address.
    /// @param minimumCitizenStake_ The minimum active stake required for good standing.
    constructor(address identityRegistryAddress, address stakeRegistryAddress, uint256 minimumCitizenStake_) {
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidRegistry(identityRegistryAddress);
        }
        if (stakeRegistryAddress == address(0) || stakeRegistryAddress.code.length == 0) {
            revert InvalidRegistry(stakeRegistryAddress);
        }
        if (minimumCitizenStake_ == 0) {
            revert InvalidMinimumCitizenStake(minimumCitizenStake_);
        }

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _minimumCitizenStake = minimumCitizenStake_;
    }

    /// @inheritdoc ICitizenEligibilityPolicy
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc ICitizenEligibilityPolicy
    function stakeRegistry() external view returns (address registryAddress) {
        return address(_stakeRegistry);
    }

    /// @inheritdoc ICitizenEligibilityPolicy
    function minimumCitizenStake() external view returns (uint256 minimumStake) {
        return _minimumCitizenStake;
    }

    /// @inheritdoc ICitizenEligibilityPolicy
    function isCitizenOnCivicRoll(bytes32 personId) public view returns (bool eligible) {
        if (personId == bytes32(0) || _identityRegistry.activeWalletCountOf(personId) == 0) {
            return false;
        }

        IdentityTypes.IdentityRecord memory record = _identityRegistry.getIdentityRecord(personId);
        return record.personId != bytes32(0) && record.verificationStatus == IdentityTypes.VerificationStatus.Verified
            && record.citizenshipStatus == IdentityTypes.CitizenshipStatus.Citizen
            && record.ageClass == IdentityTypes.AgeClass.Adult && !record.finalSuspension
            && _stakeRegistry.activeStakeOf(personId) >= _minimumCitizenStake;
    }

    /// @inheritdoc ICitizenEligibilityPolicy
    function isCitizenInGoodStanding(address wallet) external view returns (bool eligible) {
        if (wallet == address(0)) {
            return false;
        }

        IdentityTypes.WalletLink memory walletLink = _identityRegistry.getWalletLink(wallet);
        if (walletLink.personId == bytes32(0) || walletLink.status != IdentityTypes.WalletLinkStatus.Active) {
            return false;
        }

        if (!isCitizenOnCivicRoll(walletLink.personId)) {
            return false;
        }

        return !_stakeRegistry.isInWelfare(walletLink.personId);
    }
}
