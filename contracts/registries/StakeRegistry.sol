// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {StakeTypes} from "../types/StakeTypes.sol";

/// @title StakeRegistry
/// @notice Stable fact registry for political stake, cooldowns, and slash accounting.
contract StakeRegistry is IStakeRegistry {
    IConstitutionKernel private immutable _kernel;

    mapping(bytes32 personId => StakeTypes.StakeRecord stakeRecord) private _stakeRecords;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) {
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) {
            revert IConstitutionKernel.InvalidModuleAddress(bytes32(0), kernelAddress);
        }

        _kernel = IConstitutionKernel(kernelAddress);
    }

    /// @inheritdoc IStakeRegistry
    function kernel() external view returns (address kernelAddress) {
        return address(_kernel);
    }

    /// @inheritdoc IStakeRegistry
    function getStakeRecord(bytes32 personId) external view returns (StakeTypes.StakeRecord memory record) {
        return _stakeRecords[personId];
    }

    /// @inheritdoc IStakeRegistry
    function activeStakeOf(bytes32 personId) external view returns (uint256 amount) {
        return _stakeRecords[personId].activeStake;
    }

    /// @inheritdoc IStakeRegistry
    function pendingUnstakeOf(bytes32 personId) external view returns (uint256 amount) {
        return _stakeRecords[personId].pendingUnstake;
    }

    /// @inheritdoc IStakeRegistry
    function protectedStakeFloorOf(bytes32 personId) external view returns (uint256 amount) {
        return _stakeRecords[personId].protectedStakeFloor;
    }

    /// @inheritdoc IStakeRegistry
    function hasPendingUnstake(bytes32 personId) external view returns (bool pending) {
        return _stakeRecords[personId].pendingUnstake != 0;
    }

    /// @inheritdoc IStakeRegistry
    function hasActiveUnstakeCooldown(bytes32 personId) public view returns (bool active) {
        StakeTypes.StakeRecord storage stakeRecord = _stakeRecords[personId];
        return
            stakeRecord.pendingUnstake != 0 && stakeRecord.cooldownEnd != 0 && block.timestamp < stakeRecord.cooldownEnd;
    }

    /// @inheritdoc IStakeRegistry
    function claimableUnstake(bytes32 personId) public view returns (uint256 amount) {
        StakeTypes.StakeRecord storage stakeRecord = _stakeRecords[personId];
        if (
            stakeRecord.pendingUnstake == 0 || stakeRecord.cooldownEnd == 0 || block.timestamp < stakeRecord.cooldownEnd
        ) {
            return 0;
        }

        return stakeRecord.pendingUnstake;
    }

    /// @inheritdoc IStakeRegistry
    function increaseStake(bytes32 personId, uint256 amount) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidPersonId(personId);
        _requireValidStakeAmount(amount);

        StakeTypes.StakeRecord storage stakeRecord = _touchStakeRecord(personId);
        uint64 updatedAt = uint64(block.timestamp);

        stakeRecord.activeStake += amount;
        stakeRecord.updatedAt = updatedAt;

        emit StakeIncreased(personId, amount, stakeRecord.activeStake, updatedAt, msg.sender);
    }

    /// @inheritdoc IStakeRegistry
    function setProtectedStakeFloor(bytes32 personId, uint256 newProtectedFloor) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidPersonId(personId);

        StakeTypes.StakeRecord storage stakeRecord = _touchStakeRecord(personId);
        uint256 previousProtectedFloor = stakeRecord.protectedStakeFloor;
        uint64 updatedAt = uint64(block.timestamp);

        stakeRecord.protectedStakeFloor = newProtectedFloor;
        stakeRecord.updatedAt = updatedAt;

        emit ProtectedStakeFloorUpdated(personId, previousProtectedFloor, newProtectedFloor, updatedAt, msg.sender);
    }

    /// @inheritdoc IStakeRegistry
    function requestUnstake(bytes32 personId, uint256 amount, uint64 cooldownEnd) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidPersonId(personId);
        _requireValidStakeAmount(amount);

        StakeTypes.StakeRecord storage stakeRecord = _touchStakeRecord(personId);
        uint64 currentTimestamp = uint64(block.timestamp);

        if (stakeRecord.pendingUnstake != 0) {
            revert PendingUnstakeExists(personId);
        }
        if (cooldownEnd <= currentTimestamp) {
            revert InvalidCooldownEnd(cooldownEnd, currentTimestamp);
        }
        if (stakeRecord.activeStake < amount) {
            revert InsufficientActiveStake(personId, stakeRecord.activeStake, amount);
        }

        uint256 remainingStake = stakeRecord.activeStake - amount;
        if (remainingStake < stakeRecord.protectedStakeFloor) {
            revert ProtectedStakeFloorBreached(personId, remainingStake, stakeRecord.protectedStakeFloor);
        }

        stakeRecord.activeStake = remainingStake;
        stakeRecord.pendingUnstake = amount;
        stakeRecord.cooldownStart = currentTimestamp;
        stakeRecord.cooldownEnd = cooldownEnd;
        stakeRecord.updatedAt = currentTimestamp;

        emit UnstakeRequested(
            personId, amount, remainingStake, stakeRecord.pendingUnstake, currentTimestamp, cooldownEnd, msg.sender
        );
    }

    /// @inheritdoc IStakeRegistry
    function claimUnstake(bytes32 personId) external returns (uint256 claimedAmount) {
        _requireRegistryAuthority(msg.sender);
        _requireValidPersonId(personId);

        StakeTypes.StakeRecord storage stakeRecord = _stakeRecords[personId];
        claimedAmount = stakeRecord.pendingUnstake;

        if (claimedAmount == 0) {
            revert NoPendingUnstake(personId);
        }
        if (block.timestamp < stakeRecord.cooldownEnd) {
            revert CooldownNotComplete(personId, stakeRecord.cooldownEnd);
        }

        uint64 claimedAt = uint64(block.timestamp);

        stakeRecord.pendingUnstake = 0;
        stakeRecord.cooldownStart = 0;
        stakeRecord.cooldownEnd = 0;
        stakeRecord.updatedAt = claimedAt;

        emit UnstakeClaimed(personId, claimedAmount, claimedAt, msg.sender);
    }

    /// @inheritdoc IStakeRegistry
    function slashStake(bytes32 personId, uint256 amount) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidPersonId(personId);
        _requireValidStakeAmount(amount);

        StakeTypes.StakeRecord storage stakeRecord = _stakeRecords[personId];
        uint256 slashableStake = stakeRecord.activeStake + stakeRecord.pendingUnstake;

        if (slashableStake < amount) {
            revert InsufficientSlashableStake(personId, slashableStake, amount);
        }

        uint256 pendingSlash = amount > stakeRecord.pendingUnstake ? stakeRecord.pendingUnstake : amount;
        uint256 activeSlash = amount - pendingSlash;
        uint64 updatedAt = uint64(block.timestamp);

        stakeRecord.pendingUnstake -= pendingSlash;
        stakeRecord.activeStake -= activeSlash;
        stakeRecord.totalSlashed += amount;
        stakeRecord.updatedAt = updatedAt;

        if (stakeRecord.pendingUnstake == 0) {
            stakeRecord.cooldownStart = 0;
            stakeRecord.cooldownEnd = 0;
        }

        emit StakeSlashed(
            personId,
            amount,
            stakeRecord.activeStake,
            stakeRecord.pendingUnstake,
            stakeRecord.totalSlashed,
            updatedAt,
            msg.sender
        );
    }

    /// @inheritdoc IStakeRegistry
    function recoverStake(bytes32 personId, uint256 amount) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidPersonId(personId);
        _requireValidStakeAmount(amount);

        StakeTypes.StakeRecord storage stakeRecord = _touchStakeRecord(personId);
        uint64 updatedAt = uint64(block.timestamp);

        stakeRecord.activeStake += amount;
        stakeRecord.totalRecovered += amount;
        stakeRecord.updatedAt = updatedAt;

        emit StakeRecovered(
            personId, amount, stakeRecord.activeStake, stakeRecord.totalRecovered, updatedAt, msg.sender
        );
    }

    function _touchStakeRecord(bytes32 personId) private returns (StakeTypes.StakeRecord storage stakeRecord) {
        stakeRecord = _stakeRecords[personId];
        if (stakeRecord.personId == bytes32(0)) {
            stakeRecord.personId = personId;
        }
    }

    function _requireRegistryAuthority(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY)) {
            revert UnauthorizedStakeRegistryCaller(caller);
        }
    }

    function _requireValidPersonId(bytes32 personId) private pure {
        if (personId == bytes32(0)) {
            revert InvalidPersonId(personId);
        }
    }

    function _requireValidStakeAmount(uint256 amount) private pure {
        if (amount == 0) {
            revert InvalidStakeAmount(amount);
        }
    }
}
