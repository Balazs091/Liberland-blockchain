// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IStakeLienRegistry} from "../interfaces/IStakeLienRegistry.sol";
import {IElectorateRegistry} from "../interfaces/IElectorateRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IUnstakingPolicy} from "../interfaces/IUnstakingPolicy.sol";
import {KernelModule} from "../base/KernelModule.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {StakeTypes} from "../types/StakeTypes.sol";

/// @title StakeRegistry
/// @notice Stable fact registry for political stake, discrete unstaking, welfare, and slash accounting.
contract StakeRegistry is IStakeRegistry, KernelModule {
    using Checkpoints for Checkpoints.Trace208;

    uint256 private constant _ELECTORATE_SYNC_GAS_LIMIT = 500_000;
    uint256 private constant _ELECTORATE_SYNC_GAS_RESERVE = 50_000;

    mapping(bytes32 personId => StakeTypes.StakeRecord stakeRecord) private _stakeRecords;
    mapping(bytes32 personId => Checkpoints.Trace208 checkpoints) private _activeStakeCheckpoints;
    mapping(bytes32 personId => uint256 revision) private _electorateRevisions;
    uint256 private _totalActiveStake;
    uint256 private _electorateMutationCount;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IStakeRegistry
    function getStakeRecord(bytes32 personId) external view returns (StakeTypes.StakeRecord memory record) {
        return _stakeRecords[personId];
    }

    /// @inheritdoc IStakeRegistry
    function activeStakeOf(bytes32 personId) external view returns (uint256 amount) {
        return _stakeRecords[personId].activeStake;
    }

    /// @inheritdoc IStakeRegistry
    function activeStakeAt(bytes32 personId, uint48 blockNumber) external view returns (uint256 amount) {
        return _activeStakeCheckpoints[personId].upperLookupRecent(blockNumber);
    }

    /// @inheritdoc IStakeRegistry
    function totalActiveStake() external view returns (uint256 amount) {
        return _totalActiveStake;
    }

    /// @inheritdoc IStakeRegistry
    function electorateRevisionOf(bytes32 personId) external view returns (uint256 revision) {
        return _electorateRevisions[personId];
    }

    /// @inheritdoc IStakeRegistry
    function electorateMutationCount() external view returns (uint256 count) {
        return _electorateMutationCount;
    }

    /// @inheritdoc IStakeRegistry
    function protectedStakeFloorOf(bytes32 personId) external view returns (uint256 amount) {
        return _stakeRecords[personId].protectedStakeFloor;
    }

    /// @inheritdoc IStakeRegistry
    function requiredActiveStakeFloorOf(bytes32 personId) external view returns (uint256 amount) {
        StakeTypes.StakeRecord storage stakeRecord = _stakeRecords[personId];
        return _requiredActiveStakeFloor(personId, stakeRecord.protectedStakeFloor);
    }

    /// @inheritdoc IStakeRegistry
    function isInWelfare(bytes32 personId) public view returns (bool inWelfare) {
        uint64 welfareUntil = _stakeRecords[personId].welfareUntil;
        return welfareUntil != 0 && block.timestamp < welfareUntil;
    }

    /// @inheritdoc IStakeRegistry
    function welfareUntilOf(bytes32 personId) external view returns (uint64 welfareUntil) {
        return _stakeRecords[personId].welfareUntil;
    }

    /// @inheritdoc IStakeRegistry
    function increaseStake(bytes32 personId, uint256 amount) external {
        _requireStakeIncreaseAuthority(msg.sender);
        _requireValidPersonId(personId);
        _requireValidStakeAmount(amount);

        StakeTypes.StakeRecord storage stakeRecord = _touchStakeRecord(personId);
        uint64 updatedAt = uint64(block.timestamp);

        stakeRecord.activeStake += amount;
        _totalActiveStake += amount;
        stakeRecord.updatedAt = updatedAt;
        _writeActiveStakeCheckpoint(personId, stakeRecord.activeStake);

        emit StakeIncreased(personId, amount, stakeRecord.activeStake, updatedAt, msg.sender);
        _advanceElectorateSource(personId);
    }

    /// @inheritdoc IStakeRegistry
    function setProtectedStakeFloor(bytes32 personId, uint256 newProtectedFloor) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidPersonId(personId);

        StakeTypes.StakeRecord storage stakeRecord = _touchStakeRecord(personId);
        uint256 previousProtectedFloor = stakeRecord.protectedStakeFloor;
        uint256 requiredStakeFloor = _requiredActiveStakeFloor(personId, newProtectedFloor);
        if (requiredStakeFloor > stakeRecord.activeStake) {
            revert ProtectedStakeFloorBreached(personId, stakeRecord.activeStake, requiredStakeFloor);
        }
        uint64 updatedAt = uint64(block.timestamp);

        stakeRecord.protectedStakeFloor = newProtectedFloor;
        stakeRecord.updatedAt = updatedAt;

        emit ProtectedStakeFloorUpdated(personId, previousProtectedFloor, newProtectedFloor, updatedAt, msg.sender);
    }

    /// @inheritdoc IStakeRegistry
    function unstake(bytes32 personId) external returns (uint256 releasedAmount, uint64 welfareUntil) {
        _requireStakingVault(msg.sender);
        _requireValidPersonId(personId);

        if (isInWelfare(personId)) {
            revert InWelfarePeriod(personId, _stakeRecords[personId].welfareUntil);
        }

        IUnstakingPolicy unstakingPolicy = IUnstakingPolicy(_kernel.getModule(KernelModuleIds.UNSTAKING_POLICY));

        StakeTypes.StakeRecord storage stakeRecord = _touchStakeRecord(personId);
        uint256 activeStake = stakeRecord.activeStake;
        uint256 portion = unstakingPolicy.unstakePortion(activeStake);
        uint256 requiredStakeFloor = _requiredActiveStakeFloor(personId, stakeRecord.protectedStakeFloor);
        uint256 surplus = activeStake > requiredStakeFloor ? activeStake - requiredStakeFloor : 0;
        releasedAmount = portion < surplus ? portion : surplus;

        if (releasedAmount == 0) {
            revert NothingToUnstake(personId);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        welfareUntil = currentTimestamp + unstakingPolicy.welfarePeriod();

        stakeRecord.activeStake = activeStake - releasedAmount;
        _totalActiveStake -= releasedAmount;
        stakeRecord.totalUnstaked += releasedAmount;
        stakeRecord.welfareUntil = welfareUntil;
        stakeRecord.lastUnstakeAt = currentTimestamp;
        stakeRecord.updatedAt = currentTimestamp;
        _writeActiveStakeCheckpoint(personId, stakeRecord.activeStake);

        emit UnstakeExecuted(
            personId, releasedAmount, stakeRecord.activeStake, welfareUntil, currentTimestamp, msg.sender
        );
        _advanceElectorateSource(personId);
    }

    /// @inheritdoc IStakeRegistry
    function slashStake(bytes32 personId, uint256 amount) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidPersonId(personId);
        _requireValidStakeAmount(amount);

        StakeTypes.StakeRecord storage stakeRecord = _stakeRecords[personId];

        if (stakeRecord.activeStake < amount) {
            revert InsufficientSlashableStake(personId, stakeRecord.activeStake, amount);
        }

        uint256 remainingStake = stakeRecord.activeStake - amount;
        uint256 requiredStakeFloor = _requiredActiveStakeFloor(personId, stakeRecord.protectedStakeFloor);
        if (remainingStake < requiredStakeFloor) {
            revert ProtectedStakeFloorBreached(personId, remainingStake, requiredStakeFloor);
        }

        uint64 updatedAt = uint64(block.timestamp);

        stakeRecord.activeStake = remainingStake;
        _totalActiveStake -= amount;
        stakeRecord.totalSlashed += amount;
        stakeRecord.updatedAt = updatedAt;
        _writeActiveStakeCheckpoint(personId, stakeRecord.activeStake);

        emit StakeSlashed(personId, amount, stakeRecord.activeStake, stakeRecord.totalSlashed, updatedAt, msg.sender);
        _advanceElectorateSource(personId);
    }

    /// @inheritdoc IStakeRegistry
    function recoverStake(bytes32 personId, uint256 amount) external {
        _requireStakingVault(msg.sender);
        _requireValidPersonId(personId);
        _requireValidStakeAmount(amount);

        StakeTypes.StakeRecord storage stakeRecord = _touchStakeRecord(personId);
        uint64 updatedAt = uint64(block.timestamp);

        stakeRecord.activeStake += amount;
        _totalActiveStake += amount;
        stakeRecord.totalRecovered += amount;
        stakeRecord.updatedAt = updatedAt;
        _writeActiveStakeCheckpoint(personId, stakeRecord.activeStake);

        emit StakeRecovered(
            personId, amount, stakeRecord.activeStake, stakeRecord.totalRecovered, updatedAt, msg.sender
        );
        _advanceElectorateSource(personId);
    }

    /// @inheritdoc IStakeRegistry
    function transferActiveStake(bytes32 fromPersonId, bytes32 toPersonId, uint256 amount) external {
        _requireStakeTransferAuthority(msg.sender);
        _requireValidPersonId(fromPersonId);
        _requireValidPersonId(toPersonId);
        _requireValidStakeAmount(amount);

        if (fromPersonId == toPersonId) {
            revert InvalidStakeTransfer(fromPersonId, toPersonId);
        }

        StakeTypes.StakeRecord storage fromRecord = _stakeRecords[fromPersonId];
        if (fromRecord.activeStake < amount) {
            revert InsufficientActiveStake(fromPersonId, fromRecord.activeStake, amount);
        }

        uint256 fromActiveStake = fromRecord.activeStake - amount;
        uint256 requiredStakeFloor = _requiredActiveStakeFloor(fromPersonId, fromRecord.protectedStakeFloor);
        if (fromActiveStake < requiredStakeFloor) {
            revert ProtectedStakeFloorBreached(fromPersonId, fromActiveStake, requiredStakeFloor);
        }

        StakeTypes.StakeRecord storage toRecord = _touchStakeRecord(toPersonId);
        uint64 updatedAt = uint64(block.timestamp);

        fromRecord.activeStake = fromActiveStake;
        fromRecord.updatedAt = updatedAt;
        toRecord.activeStake += amount;
        toRecord.updatedAt = updatedAt;
        _writeActiveStakeCheckpoint(fromPersonId, fromRecord.activeStake);
        _writeActiveStakeCheckpoint(toPersonId, toRecord.activeStake);

        emit ActiveStakeTransferred(
            fromPersonId, toPersonId, amount, fromRecord.activeStake, toRecord.activeStake, updatedAt, msg.sender
        );
        _advanceElectorateSource(fromPersonId);
        _advanceElectorateSource(toPersonId);
    }

    function _touchStakeRecord(bytes32 personId) private returns (StakeTypes.StakeRecord storage stakeRecord) {
        stakeRecord = _stakeRecords[personId];
        if (stakeRecord.personId == bytes32(0)) {
            stakeRecord.personId = personId;
        }
    }

    function _advanceElectorateSource(bytes32 personId) private {
        uint256 personRevision = ++_electorateRevisions[personId];
        uint256 mutationCount = ++_electorateMutationCount;
        emit ElectorateSourceRevisionAdvanced(personId, personRevision, mutationCount);

        address electorateRegistryAddress = address(0);
        try _kernel.getModule(KernelModuleIds.ELECTORATE_REGISTRY) returns (address moduleAddress) {
            electorateRegistryAddress = moduleAddress;
        } catch {
            return;
        }

        uint256 availableGas = gasleft();
        if (availableGas <= _ELECTORATE_SYNC_GAS_RESERVE) {
            emit ElectorateSynchronizationDeferred(personId, electorateRegistryAddress);
            return;
        }
        uint256 forwardedGas = availableGas - _ELECTORATE_SYNC_GAS_RESERVE;
        if (forwardedGas > _ELECTORATE_SYNC_GAS_LIMIT) {
            forwardedGas = _ELECTORATE_SYNC_GAS_LIMIT;
        }

        (bool synchronized,) = electorateRegistryAddress.call{gas: forwardedGas}(
            abi.encodeCall(IElectorateRegistry.syncPerson, (personId))
        );
        if (!synchronized) {
            emit ElectorateSynchronizationDeferred(personId, electorateRegistryAddress);
        }
    }

    function _writeActiveStakeCheckpoint(bytes32 personId, uint256 activeStake) private {
        _activeStakeCheckpoints[personId].push(SafeCast.toUint48(block.number), SafeCast.toUint208(activeStake));
    }

    function _requireRegistryAuthority(address caller) private view {
        if (_isModuleCaller(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, caller)) {
            return;
        }
        if (_isActiveSetupAuthority(caller)) {
            return;
        }

        revert UnauthorizedStakeRegistryCaller(caller);
    }

    function _requireStakeIncreaseAuthority(address caller) private view {
        if (_isModuleCaller(KernelModuleIds.LLM_STAKING_VAULT, caller)) {
            return;
        }

        revert UnauthorizedStakeRegistryCaller(caller);
    }

    function _requireStakingVault(address caller) private view {
        if (!_isModuleCaller(KernelModuleIds.LLM_STAKING_VAULT, caller)) {
            revert UnauthorizedStakeRegistryCaller(caller);
        }
    }

    function _requireStakeTransferAuthority(address caller) private view {
        if (_isModuleCaller(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, caller)) {
            return;
        }

        if (_isModuleCaller(KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY, caller)) {
            return;
        }

        revert UnauthorizedStakeRegistryCaller(caller);
    }

    function _requiredActiveStakeFloor(bytes32 personId, uint256 protectedStakeFloor)
        private
        view
        returns (uint256 requiredStakeFloor)
    {
        requiredStakeFloor = protectedStakeFloor;

        address stakeLienRegistryAddress = address(0);
        try _kernel.getModule(KernelModuleIds.STAKE_LIEN_REGISTRY) returns (address moduleAddress) {
            stakeLienRegistryAddress = moduleAddress;
        } catch {
            // Lending is optional before the lien registry is registered.
            return requiredStakeFloor;
        }

        IStakeLienRegistry stakeLienRegistry = IStakeLienRegistry(stakeLienRegistryAddress);
        uint256 lienedStake = 0;
        uint256 retainedStakeFloor = 0;
        try stakeLienRegistry.lienedStakeOf(personId) returns (uint256 amount) {
            lienedStake = amount;
        } catch {
            revert StakeLienRegistryUnavailable(personId);
        }
        try stakeLienRegistry.retainedStakeFloorOf(personId) returns (uint256 amount) {
            retainedStakeFloor = amount;
        } catch {
            revert StakeLienRegistryUnavailable(personId);
        }

        // The minimum retained stake only binds active borrowers. A person without a lien can
        // fully exit down to their own protected floor.
        if (lienedStake > 0 && retainedStakeFloor > requiredStakeFloor) {
            requiredStakeFloor = retainedStakeFloor;
        }
        requiredStakeFloor += lienedStake;
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
