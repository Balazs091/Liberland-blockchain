// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {KernelModule} from "../base/KernelModule.sol";
import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IStakeLienRegistry} from "../interfaces/IStakeLienRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title StakeLienRegistry
/// @notice Stable fact registry for lending liens against active political stake.
contract StakeLienRegistry is IStakeLienRegistry, KernelModule {
    mapping(bytes32 personId => uint256 lienedStake) private _liens;
    mapping(bytes32 personId => uint256 retainedStakeFloor) private _retainedStakeFloors;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IStakeLienRegistry
    /// @dev Sourced live from the governed citizenship policy for positions that do not yet have a lien.
    function minimumRetainedStake() external view returns (uint256 amount) {
        return _currentMinimumRetainedStake();
    }

    /// @inheritdoc IStakeLienRegistry
    function retainedStakeFloorOf(bytes32 personId) external view returns (uint256 amount) {
        if (_liens[personId] == 0) {
            return _currentMinimumRetainedStake();
        }

        return _retainedStakeFloors[personId];
    }

    /// @inheritdoc IStakeLienRegistry
    function lienedStakeOf(bytes32 personId) external view returns (uint256 amount) {
        return _liens[personId];
    }

    /// @inheritdoc IStakeLienRegistry
    function increaseLien(bytes32 personId, uint256 amount) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidPersonId(personId);
        _requireValidAmount(amount);

        uint256 currentLienedStake = _liens[personId];
        uint256 newLienedStake = currentLienedStake + amount;
        uint64 updatedAt = uint64(block.timestamp);
        if (currentLienedStake == 0) {
            uint256 retainedStakeFloor = _currentMinimumRetainedStake();
            _retainedStakeFloors[personId] = retainedStakeFloor;
            emit RetainedStakeFloorUpdated(personId, 0, retainedStakeFloor, updatedAt);
        }
        _liens[personId] = newLienedStake;

        emit StakeLienIncreased(personId, amount, newLienedStake, updatedAt, msg.sender);
    }

    /// @inheritdoc IStakeLienRegistry
    function decreaseLien(bytes32 personId, uint256 amount) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidPersonId(personId);
        _requireValidAmount(amount);

        uint256 currentLien = _liens[personId];
        if (currentLien < amount) {
            revert InsufficientStakeLien(personId, currentLien, amount);
        }

        uint256 newLienedStake = currentLien - amount;
        uint64 updatedAt = uint64(block.timestamp);
        _liens[personId] = newLienedStake;
        if (newLienedStake == 0) {
            uint256 previousRetainedFloor = _retainedStakeFloors[personId];
            delete _retainedStakeFloors[personId];
            emit RetainedStakeFloorUpdated(personId, previousRetainedFloor, 0, updatedAt);
        }

        emit StakeLienDecreased(personId, amount, newLienedStake, updatedAt, msg.sender);
    }

    function _currentMinimumRetainedStake() private view returns (uint256 amount) {
        return
            ICitizenEligibilityPolicy(_kernel.getModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY))
                .minimumCitizenStake();
    }

    function _requireRegistryAuthority(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY)) {
            revert UnauthorizedStakeLienRegistryCaller(caller);
        }
    }

    function _requireValidPersonId(bytes32 personId) private pure {
        if (personId == bytes32(0)) {
            revert InvalidPersonId(personId);
        }
    }

    function _requireValidAmount(uint256 amount) private pure {
        if (amount == 0) {
            revert InvalidLienAmount(amount);
        }
    }
}
