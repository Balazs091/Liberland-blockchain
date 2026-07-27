// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IUnstakingPolicy} from "../interfaces/IUnstakingPolicy.sol";

/// @title UnstakingPolicy
/// @notice Parameterizes the discrete 30-day unstake portion and welfare period.
contract UnstakingPolicy is IUnstakingPolicy {
    error InvalidRegistry(address registryAddress);
    error InvalidUnstakeRate(uint16 annualUnstakeRateBps);
    error InvalidWelfarePeriod(uint64 welfarePeriodSeconds);

    uint64 public constant YEAR = 365 days;
    uint16 private constant BPS_DENOMINATOR = 10_000;

    IStakeRegistry private immutable _stakeRegistry;
    uint64 private immutable _welfarePeriod;
    uint16 private immutable _annualUnstakeRateBps;

    /// @param stakeRegistryAddress The stake registry address.
    /// @param welfarePeriodSeconds The welfare period applied after each unstake.
    /// @param annualUnstakeRateBps_ The annual unstake rate cap in basis points (max 10_000).
    constructor(address stakeRegistryAddress, uint64 welfarePeriodSeconds, uint16 annualUnstakeRateBps_) {
        if (stakeRegistryAddress == address(0) || stakeRegistryAddress.code.length == 0) {
            revert InvalidRegistry(stakeRegistryAddress);
        }
        if (welfarePeriodSeconds == 0) {
            revert InvalidWelfarePeriod(welfarePeriodSeconds);
        }
        if (annualUnstakeRateBps_ == 0 || annualUnstakeRateBps_ > BPS_DENOMINATOR) {
            revert InvalidUnstakeRate(annualUnstakeRateBps_);
        }

        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _welfarePeriod = welfarePeriodSeconds;
        _annualUnstakeRateBps = annualUnstakeRateBps_;
    }

    /// @inheritdoc IUnstakingPolicy
    function stakeRegistry() external view returns (address registryAddress) {
        return address(_stakeRegistry);
    }

    /// @inheritdoc IUnstakingPolicy
    function welfarePeriod() external view returns (uint64 durationSeconds) {
        return _welfarePeriod;
    }

    /// @inheritdoc IUnstakingPolicy
    function annualUnstakeRateBps() external view returns (uint16 rateBps) {
        return _annualUnstakeRateBps;
    }

    /// @inheritdoc IUnstakingPolicy
    function unstakePortion(uint256 activeStake) public view returns (uint256 portion) {
        return activeStake * _annualUnstakeRateBps * _welfarePeriod / (uint256(BPS_DENOMINATOR) * YEAR);
    }

    /// @inheritdoc IUnstakingPolicy
    function previewWelfareUntil(uint64 startTimestamp) external view returns (uint64 welfareUntil) {
        return startTimestamp + _welfarePeriod;
    }

    /// @inheritdoc IUnstakingPolicy
    function isInWelfare(bytes32 personId) external view returns (bool inWelfare) {
        return _stakeRegistry.isInWelfare(personId);
    }

    /// @inheritdoc IUnstakingPolicy
    function canUnstake(bytes32 personId) external view returns (bool allowed) {
        if (personId == bytes32(0)) {
            return false;
        }
        if (_stakeRegistry.isInWelfare(personId)) {
            return false;
        }

        uint256 activeStake = _stakeRegistry.activeStakeOf(personId);
        uint256 requiredFloor = _stakeRegistry.requiredActiveStakeFloorOf(personId);

        return activeStake > requiredFloor && unstakePortion(activeStake) > 0;
    }
}
