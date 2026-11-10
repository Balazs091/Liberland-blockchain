// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Heap} from "@openzeppelin/contracts/utils/structs/Heap.sol";

import {KernelModule} from "../base/KernelModule.sol";
import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IElectorateRegistry} from "../interfaces/IElectorateRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IMembershipRegistry} from "../interfaces/IMembershipRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title ElectorateRegistry
/// @notice Maintains checkpointed electorate totals, with bounded welfare-expiry synchronization when opted in.
contract ElectorateRegistry is IElectorateRegistry, KernelModule {
    using Checkpoints for Checkpoints.Trace208;
    using Heap for Heap.Uint256Heap;

    struct PersonCheckpoint {
        uint64 epoch;
        bool eligible;
        uint256 votingPower;
        uint256 identityRevision;
        uint256 stakeRevision;
        uint256 membershipRevision;
        uint64 welfareUntil;
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
    IMembershipRegistry private _membershipRegistry;
    bool private _excludeWelfare;
    uint256 private _synchronizedMembershipMutations;
    Heap.Uint256Heap private _welfareExpiries;
    uint192 private _expiryNonce;
    mapping(uint192 entryId => bytes32 personId) private _expiryPersons;

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
        (address membership, bool excludeWelfare, bool valid) = _policyConfiguration();
        return valid && membership == address(_membershipRegistry) && excludeWelfare == _excludeWelfare && !_expiryDue()
            && _synchronizedMembershipMutations == _membershipMutationCount()
            && _synchronizedIdentities == _identityRegistry.totalIdentityCount()
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
        uint256 membershipMutations = _membershipMutationCount();
        if (_synchronizedMembershipMutations != membershipMutations) {
            revert ElectorateMembershipIncomplete(_synchronizedMembershipMutations, membershipMutations);
        }
        if (_expiryDue()) revert ElectorateWelfareExpiryPending(nextWelfareExpiry());
        if (!isReady()) revert ElectoratePolicyConfigurationInvalid();
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
    function nextWelfareExpiry() public view returns (uint64 expiresAt) {
        return _welfareExpiries.length() == 0 ? 0 : uint64(_welfareExpiries.peek() >> 192);
    }

    /// @inheritdoc IElectorateRegistry
    function syncExpired(uint256 maxCount) external returns (uint256 processed) {
        if (maxCount == 0 || maxCount > 32) revert InvalidExpiryBatchSize(maxCount);
        _ensurePolicyConfiguration();
        // Time has no source callback. Re-certify from this block after the last elapsed entry is consumed.
        if (_expiryDue()) _invalidateCurrentBoundary();
        while (processed < maxCount && _expiryDue()) {
            uint192 entryId = uint192(_welfareExpiries.pop());
            bytes32 personId = _expiryPersons[entryId];
            delete _expiryPersons[entryId];
            _syncPerson(personId);
            ++processed;
        }
    }

    /// @inheritdoc IElectorateRegistry
    function rebuild(uint256 startIndex, uint256 maxCount) external returns (uint256 nextIndex) {
        uint256 identityCount = _identityRegistry.totalIdentityCount();
        if (startIndex >= identityCount || maxCount == 0) {
            return startIndex;
        }
        // Bound before addition: checked arithmetic makes a post-addition overflow test unreachable.
        uint256 remaining = identityCount - startIndex;
        uint256 endIndex = startIndex + (maxCount < remaining ? maxCount : remaining);
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
        (address membership, bool excludeWelfare,) = _policyConfiguration();
        _startEpoch(membership, excludeWelfare);
    }

    function _startEpoch(address membership, bool excludeWelfare) private {
        _epoch += 1;
        _membershipRegistry = IMembershipRegistry(membership);
        _excludeWelfare = excludeWelfare;
        _synchronizedIdentities = 0;
        _synchronizedIdentityMutations = 0;
        _synchronizedStakeMutations = 0;
        _synchronizedMembershipMutations = 0;
        // Heap.clear is O(1). Entry IDs never repeat; old epoch mappings are unreachable.
        _welfareExpiries.clear();
        _citizenCount = 0;
        _votingPower = 0;
        _currentEpochReady = false;
        _currentEpochReadyAt = 0;
        _writeAggregateCheckpoints();
        emit ElectorateRebuildStarted(_epoch, uint64(block.timestamp));
    }

    function _syncPerson(bytes32 personId) private {
        _ensurePolicyConfiguration();
        if (personId == bytes32(0) || !_identityRegistry.identityExists(personId)) {
            revert UnknownElectoratePerson(personId);
        }
        _checkSynchronizationBoundary();
        _updatePersonCheckpoint(personId);
    }

    function _checkSynchronizationBoundary() private {
        uint256 identityMutationCount = _identityRegistry.electorateMutationCount();
        uint256 stakeMutationCount = _stakeRegistry.electorateMutationCount();
        uint256 membershipMutationCount = _membershipMutationCount();
        bool timelySourceCallback =
            (msg.sender == address(_identityRegistry)
                    && identityMutationCount == _synchronizedIdentityMutations + 1
                    && stakeMutationCount == _synchronizedStakeMutations
                    && membershipMutationCount == _synchronizedMembershipMutations)
                || (msg.sender == address(_stakeRegistry)
                    && stakeMutationCount == _synchronizedStakeMutations + 1
                    && identityMutationCount == _synchronizedIdentityMutations
                    && membershipMutationCount == _synchronizedMembershipMutations)
                || (msg.sender == address(_membershipRegistry)
                    && membershipMutationCount == _synchronizedMembershipMutations + 1
                    && identityMutationCount == _synchronizedIdentityMutations
                    && stakeMutationCount == _synchronizedStakeMutations);
        // A normal source callback can safely leave the last-completed-block boundary unchanged: that block predates
        // the current mutation. A permissionless or multi-revision catch-up advances the boundary so no process can
        // select a block from an interval whose missing synchronization could not be checkpointed retroactively.
        if (
            _expiryDue()
                || (!timelySourceCallback
                    && (identityMutationCount != _synchronizedIdentityMutations
                        || stakeMutationCount != _synchronizedStakeMutations
                        || membershipMutationCount != _synchronizedMembershipMutations))
        ) {
            _invalidateCurrentBoundary();
        }
    }

    function _updatePersonCheckpoint(bytes32 personId) private {
        uint256 identityRevision = _identityRegistry.electorateRevisionOf(personId);
        uint256 stakeRevision = _stakeRegistry.electorateRevisionOf(personId);
        uint256 membershipRevision =
            address(_membershipRegistry) == address(0) ? 0 : _membershipRegistry.membershipRevisionOf(personId);
        PersonCheckpoint storage checkpoint = _checkpoints[personId];
        if (checkpoint.epoch == _epoch) {
            if (checkpoint.eligible) {
                _citizenCount -= 1;
                _votingPower -= checkpoint.votingPower;
            }
            _synchronizedIdentityMutations += identityRevision - checkpoint.identityRevision;
            _synchronizedStakeMutations += stakeRevision - checkpoint.stakeRevision;
            _synchronizedMembershipMutations += membershipRevision - checkpoint.membershipRevision;
        } else {
            checkpoint.epoch = _epoch;
            _synchronizedIdentities += 1;
            _synchronizedIdentityMutations += identityRevision;
            _synchronizedStakeMutations += stakeRevision;
            _synchronizedMembershipMutations += membershipRevision;
            checkpoint.welfareUntil = 0;
        }

        (bool eligible, uint256 votingPower) = _currentCivicRollStatus(personId);
        checkpoint.eligible = eligible;
        checkpoint.votingPower = votingPower;
        checkpoint.identityRevision = identityRevision;
        checkpoint.stakeRevision = stakeRevision;
        checkpoint.membershipRevision = membershipRevision;
        uint64 welfareUntil = _excludeWelfare ? _stakeRegistry.welfareUntilOf(personId) : 0;
        if (welfareUntil > block.timestamp && welfareUntil != checkpoint.welfareUntil) {
            uint192 entryId = ++_expiryNonce;
            _expiryPersons[entryId] = personId;
            _welfareExpiries.insert((uint256(welfareUntil) << 192) | entryId);
        }
        checkpoint.welfareUntil = welfareUntil;
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

    function _invalidateCurrentBoundary() private {
        _currentEpochReady = false;
        _currentEpochReadyAt = 0;
    }

    function _expiryDue() private view returns (bool) {
        return _excludeWelfare && _welfareExpiries.length() != 0 && nextWelfareExpiry() <= block.timestamp;
    }

    function _membershipMutationCount() private view returns (uint256) {
        return address(_membershipRegistry) == address(0) ? 0 : _membershipRegistry.electorateMutationCount();
    }

    function _ensurePolicyConfiguration() private {
        (address membership, bool excludeWelfare, bool valid) = _policyConfiguration();
        if (!valid) revert ElectoratePolicyConfigurationInvalid();
        if (membership != address(_membershipRegistry) || excludeWelfare != _excludeWelfare) {
            _startEpoch(membership, excludeWelfare);
        }
    }

    function _policyConfiguration() private view returns (address membership, bool excludeWelfare, bool valid) {
        valid = true;
        ICitizenEligibilityPolicy policy;
        try _kernel.getModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY) returns (address registered) {
            policy = ICitizenEligibilityPolicy(registered);
        } catch {
            return (address(0), false, true);
        }
        // Older policies have no membership/time-dependent civic roll and retain their existing semantics.
        try policy.membershipRegistry() returns (address registry) {
            membership = registry;
        } catch {}
        try policy.excludesWelfareFromCivicRoll() returns (bool excluded) {
            excludeWelfare = excluded;
        } catch {}
        try policy.electorateConfigurationValid() returns (bool configured) {
            valid = configured;
        } catch {}
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
