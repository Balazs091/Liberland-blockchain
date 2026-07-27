// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {KernelModule} from "../base/KernelModule.sol";
import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IElectorateRegistry} from "../interfaces/IElectorateRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title ElectorateRegistry
/// @notice Maintains bounded-cost electorate totals; temporary welfare affects voting, not civic-roll membership.
contract ElectorateRegistry is IElectorateRegistry, KernelModule {
    using Checkpoints for Checkpoints.Trace208;

    struct PersonCheckpoint {
        uint64 epoch;
        bool eligible;
        uint256 votingPower;
        uint256 identityRevision;
        uint256 stakeRevision;
    }

    IIdentityRegistry private immutable _identityRegistry;
    IStakeRegistry private immutable _stakeRegistry;

    mapping(bytes32 personId => PersonCheckpoint checkpoint) private _checkpoints;
    mapping(bytes32 personId => Checkpoints.Trace208 checkpoints) private _eligibilityCheckpoints;
    Checkpoints.Trace208 private _readinessCheckpoints;
    Checkpoints.Trace208 private _citizenCountCheckpoints;
    Checkpoints.Trace208 private _votingPowerCheckpoints;
    uint64 private _epoch = 1;
    uint256 private _synchronizedIdentities;
    uint256 private _synchronizedIdentityMutations;
    uint256 private _synchronizedStakeMutations;
    uint256 private _citizenCount;
    uint256 private _votingPower;
    uint48 private _currentEpochReadyAt;
    bool private _currentEpochReady;

    constructor(address kernelAddress, address identityRegistryAddress, address stakeRegistryAddress)
        KernelModule(kernelAddress)
    {
        _requireContract(identityRegistryAddress);
        _requireContract(stakeRegistryAddress);
        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _writeAggregateCheckpoints();
    }

    /// @inheritdoc IElectorateRegistry
    function epoch() external view returns (uint64 currentEpoch) {
        return _epoch;
    }

    /// @inheritdoc IElectorateRegistry
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc IElectorateRegistry
    function stakeRegistry() external view returns (address registryAddress) {
        return address(_stakeRegistry);
    }

    /// @inheritdoc IElectorateRegistry
    function isReady() public view returns (bool ready) {
        return _synchronizedIdentities == _identityRegistry.totalIdentityCount()
            && _synchronizedIdentityMutations == _identityRegistry.electorateMutationCount()
            && _synchronizedStakeMutations == _stakeRegistry.electorateMutationCount();
    }

    /// @inheritdoc IElectorateRegistry
    function snapshot() external view returns (uint256 citizenCount, uint256 votingPower) {
        uint256 identityCount = _identityRegistry.totalIdentityCount();
        if (_synchronizedIdentities != identityCount) {
            revert ElectorateCheckpointIncomplete(_synchronizedIdentities, identityCount, _epoch);
        }
        uint256 identityMutations = _identityRegistry.electorateMutationCount();
        uint256 stakeMutations = _stakeRegistry.electorateMutationCount();
        if (_synchronizedIdentityMutations != identityMutations || _synchronizedStakeMutations != stakeMutations) {
            revert ElectorateSourceMutationsIncomplete(
                _synchronizedIdentityMutations, identityMutations, _synchronizedStakeMutations, stakeMutations, _epoch
            );
        }
        return (_citizenCount, _votingPower);
    }

    /// @inheritdoc IElectorateRegistry
    function snapshotAt(uint48 blockNumber) external view returns (uint256 citizenCount, uint256 votingPower) {
        return _snapshotAt(blockNumber);
    }

    /// @inheritdoc IElectorateRegistry
    function snapshotAtCurrentEpoch(uint48 blockNumber)
        external
        view
        returns (uint256 citizenCount, uint256 votingPower)
    {
        if (blockNumber > block.number) {
            revert InvalidElectorateSnapshotBlock(blockNumber, block.number);
        }
        if (!_currentEpochReady || blockNumber < _currentEpochReadyAt || !isReady()) {
            revert ElectorateCurrentEpochUnavailable(blockNumber, _currentEpochReadyAt, _epoch);
        }
        return _snapshotAt(blockNumber);
    }

    function _snapshotAt(uint48 blockNumber) private view returns (uint256 citizenCount, uint256 votingPower) {
        if (blockNumber > block.number) {
            revert InvalidElectorateSnapshotBlock(blockNumber, block.number);
        }
        if (_readinessCheckpoints.upperLookupRecent(blockNumber) == 0) {
            revert ElectorateSnapshotUnavailable(blockNumber);
        }
        return (
            _citizenCountCheckpoints.upperLookupRecent(blockNumber),
            _votingPowerCheckpoints.upperLookupRecent(blockNumber)
        );
    }

    /// @inheritdoc IElectorateRegistry
    function wasEligibleAt(bytes32 personId, uint48 blockNumber) external view returns (bool eligible) {
        if (blockNumber > block.number || _readinessCheckpoints.upperLookupRecent(blockNumber) == 0) {
            return false;
        }
        return _eligibilityCheckpoints[personId].upperLookupRecent(blockNumber) == 1;
    }

    /// @inheritdoc IElectorateRegistry
    function syncPerson(bytes32 personId) external {
        _syncPerson(personId);
    }

    /// @inheritdoc IElectorateRegistry
    function rebuild(uint256 startIndex, uint256 maxCount) external returns (uint256 nextIndex) {
        uint256 identityCount = _identityRegistry.totalIdentityCount();
        if (startIndex >= identityCount || maxCount == 0) {
            return startIndex;
        }
        uint256 endIndex = startIndex + maxCount;
        if (endIndex < startIndex || endIndex > identityCount) {
            endIndex = identityCount;
        }
        for (uint256 index = startIndex; index < endIndex; ++index) {
            _syncPerson(_identityRegistry.identityIdAt(index));
        }
        return endIndex;
    }

    /// @inheritdoc IElectorateRegistry
    function beginPolicyRebuild() external {
        if (msg.sender != address(_kernel)) {
            revert UnauthorizedElectorateInvalidation(msg.sender);
        }
        _epoch += 1;
        _synchronizedIdentities = 0;
        _synchronizedIdentityMutations = 0;
        _synchronizedStakeMutations = 0;
        _citizenCount = 0;
        _votingPower = 0;
        _currentEpochReady = false;
        _currentEpochReadyAt = 0;
        _writeAggregateCheckpoints();
        emit ElectorateRebuildStarted(_epoch, uint64(block.timestamp));
    }

    function _syncPerson(bytes32 personId) private {
        if (personId == bytes32(0) || !_identityRegistry.identityExists(personId)) {
            revert UnknownElectoratePerson(personId);
        }
        uint256 identityMutationCount = _identityRegistry.electorateMutationCount();
        uint256 stakeMutationCount = _stakeRegistry.electorateMutationCount();
        bool timelySourceCallback =
            (msg.sender == address(_identityRegistry)
                    && identityMutationCount == _synchronizedIdentityMutations + 1
                    && stakeMutationCount == _synchronizedStakeMutations)
                || (msg.sender == address(_stakeRegistry)
                    && stakeMutationCount == _synchronizedStakeMutations + 1
                    && identityMutationCount == _synchronizedIdentityMutations);
        // A normal source callback can safely leave the last-completed-block boundary unchanged: that block predates
        // the current mutation. A permissionless or multi-revision catch-up advances the boundary so no process can
        // select a block from an interval whose missing synchronization could not be checkpointed retroactively.
        if (
            !timelySourceCallback
                && (identityMutationCount != _synchronizedIdentityMutations
                    || stakeMutationCount != _synchronizedStakeMutations)
        ) {
            _currentEpochReady = false;
            _currentEpochReadyAt = 0;
        }
        uint256 identityRevision = _identityRegistry.electorateRevisionOf(personId);
        uint256 stakeRevision = _stakeRegistry.electorateRevisionOf(personId);
        PersonCheckpoint storage checkpoint = _checkpoints[personId];
        if (checkpoint.epoch == _epoch) {
            if (checkpoint.eligible) {
                _citizenCount -= 1;
                _votingPower -= checkpoint.votingPower;
            }
            _synchronizedIdentityMutations += identityRevision - checkpoint.identityRevision;
            _synchronizedStakeMutations += stakeRevision - checkpoint.stakeRevision;
        } else {
            checkpoint.epoch = _epoch;
            _synchronizedIdentities += 1;
            _synchronizedIdentityMutations += identityRevision;
            _synchronizedStakeMutations += stakeRevision;
        }

        (bool eligible, uint256 votingPower) = _currentCivicRollStatus(personId);
        checkpoint.eligible = eligible;
        checkpoint.votingPower = votingPower;
        checkpoint.identityRevision = identityRevision;
        checkpoint.stakeRevision = stakeRevision;
        if (eligible) {
            _citizenCount += 1;
            _votingPower += votingPower;
        }
        uint208 historicalEligibility = eligible ? 1 : 0;
        if (_eligibilityCheckpoints[personId].latest() != historicalEligibility) {
            _eligibilityCheckpoints[personId].push(SafeCast.toUint48(block.number), historicalEligibility);
        }
        _writeAggregateCheckpoints();
        emit ElectoratePersonSynchronized(personId, eligible, votingPower, _epoch, uint64(block.timestamp));
    }

    function _writeAggregateCheckpoints() private {
        uint48 blockNumber = SafeCast.toUint48(block.number);
        uint208 ready = isReady() ? 1 : 0;
        if (_readinessCheckpoints.latest() != ready) {
            _readinessCheckpoints.push(blockNumber, ready);
        }
        if (ready == 0) {
            _currentEpochReady = false;
            _currentEpochReadyAt = 0;
            return;
        }

        if (!_currentEpochReady) {
            _currentEpochReady = true;
            _currentEpochReadyAt = blockNumber;
        }
        uint208 citizenCount = SafeCast.toUint208(_citizenCount);
        uint208 votingPower = SafeCast.toUint208(_votingPower);
        if (_citizenCountCheckpoints.latest() != citizenCount) {
            _citizenCountCheckpoints.push(blockNumber, citizenCount);
        }
        if (_votingPowerCheckpoints.latest() != votingPower) {
            _votingPowerCheckpoints.push(blockNumber, votingPower);
        }
    }

    function _currentCivicRollStatus(bytes32 personId) private view returns (bool eligible, uint256 votingPower) {
        ICitizenEligibilityPolicy citizenPolicy =
            ICitizenEligibilityPolicy(_kernel.getModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY));
        if (!citizenPolicy.isCitizenOnCivicRoll(personId)) {
            return (false, 0);
        }
        votingPower = _stakeRegistry.activeStakeOf(personId);
        return (true, votingPower);
    }

    function _requireContract(address account) private view {
        if (account == address(0) || account.code.length == 0) {
            revert InvalidElectorateAddress(account);
        }
    }
}
