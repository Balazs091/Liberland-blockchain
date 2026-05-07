// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IUnstakingPolicy} from "../interfaces/IUnstakingPolicy.sol";
import {StakeTypes} from "../types/StakeTypes.sol";

/// @title UnstakingPolicy
/// @notice Evaluates unstake cooldown rules and the resulting political-rights effect.
contract UnstakingPolicy is IUnstakingPolicy {
    error InvalidCooldownDuration(uint64 cooldownDurationSeconds);
    error InvalidRegistry(address registryAddress);

    uint64 private immutable _cooldownDuration;
    IStakeRegistry private immutable _stakeRegistry;

    /// @param stakeRegistryAddress The stake registry address.
    /// @param cooldownDurationSeconds The cooldown duration applied to new unstake requests.
    constructor(address stakeRegistryAddress, uint64 cooldownDurationSeconds) {
        if (stakeRegistryAddress == address(0) || stakeRegistryAddress.code.length == 0) {
            revert InvalidRegistry(stakeRegistryAddress);
        }
        if (cooldownDurationSeconds == 0) {
            revert InvalidCooldownDuration(cooldownDurationSeconds);
        }

        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _cooldownDuration = cooldownDurationSeconds;
    }

    /// @inheritdoc IUnstakingPolicy
    function stakeRegistry() external view returns (address registryAddress) {
        return address(_stakeRegistry);
    }

    /// @inheritdoc IUnstakingPolicy
    function cooldownDuration() external view returns (uint64 durationSeconds) {
        return _cooldownDuration;
    }

    /// @inheritdoc IUnstakingPolicy
    function previewCooldownEnd(uint64 startTimestamp) external view returns (uint64 cooldownEnd) {
        return startTimestamp + _cooldownDuration;
    }

    /// @inheritdoc IUnstakingPolicy
    function canStartUnstake(bytes32 personId, uint256 amount) external view returns (bool allowed) {
        if (personId == bytes32(0) || amount == 0) {
            return false;
        }

        StakeTypes.StakeRecord memory stakeRecord = _stakeRegistry.getStakeRecord(personId);
        if (stakeRecord.pendingUnstake != 0) {
            return false;
        }
        if (stakeRecord.activeStake < amount) {
            return false;
        }

        return stakeRecord.activeStake - amount >= stakeRecord.protectedStakeFloor;
    }

    /// @inheritdoc IUnstakingPolicy
    function isPoliticalRightsBlocked(bytes32 personId) external view returns (bool blocked) {
        return _stakeRegistry.hasActiveUnstakeCooldown(personId);
    }

    /// @inheritdoc IUnstakingPolicy
    function claimableAmount(bytes32 personId) external view returns (uint256 amount) {
        return _stakeRegistry.claimableUnstake(personId);
    }
}
