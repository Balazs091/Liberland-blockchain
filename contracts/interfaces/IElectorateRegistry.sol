// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IKernelModule} from "./IKernelModule.sol";

/// @title IElectorateRegistry
/// @notice Checkpointed aggregate of the constitutional civic roll and its active stake.
interface IElectorateRegistry is IKernelModule {
    error ElectorateCheckpointIncomplete(uint256 synchronizedIdentities, uint256 totalIdentities, uint64 epoch);
    error ElectorateCurrentEpochUnavailable(uint48 blockNumber, uint48 currentEpochReadyAt, uint64 epoch);
    error ElectorateSourceMutationsIncomplete(
        uint256 synchronizedIdentityMutations,
        uint256 identityMutations,
        uint256 synchronizedStakeMutations,
        uint256 stakeMutations,
        uint64 epoch
    );
    error ElectorateSnapshotUnavailable(uint48 blockNumber);
    error InvalidElectorateAddress(address account);
    error InvalidElectorateSnapshotBlock(uint48 blockNumber, uint256 currentBlock);
    error UnknownElectoratePerson(bytes32 personId);
    error UnauthorizedElectorateInvalidation(address caller);
    error ElectorateMembershipIncomplete(uint256 synchronizedMutations, uint256 sourceMutations);
    error ElectoratePolicyConfigurationInvalid();
    error ElectorateWelfareExpiryPending(uint64 expiresAt);
    error InvalidExpiryBatchSize(uint256 maxCount);

    event ElectoratePersonSynchronized(
        bytes32 indexed personId, bool eligible, uint256 votingPower, uint64 indexed epoch, uint64 timestamp
    );
    event ElectorateRebuildStarted(uint64 indexed epoch, uint64 timestamp);

    /// @notice Returns the current checkpoint epoch.
    function epoch() external view returns (uint64 currentEpoch);

    /// @notice Returns the immutable identity registry used as an electorate fact source.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the immutable stake registry used as an electorate fact source.
    function stakeRegistry() external view returns (address registryAddress);

    /// @notice Returns whether all identities, source revisions and elapsed welfare periods are synchronized.
    function isReady() external view returns (bool ready);

    /// @notice Returns a complete O(1) constitutional electorate snapshot or reverts while rebuilding.
    function snapshot() external view returns (uint256 citizenCount, uint256 votingPower);

    /// @notice Returns stored history for a block already certified when a process was created.
    /// @dev This is not a certificate for an arbitrary past block. Missed source callbacks and elapsed welfare
    ///      periods cannot retroactively mark an uncheckpointed interval. New processes must use
    ///      `snapshotAtCurrentEpoch`; existing processes retain the snapshot that passed that gate at creation.
    /// @param blockNumber The block-number checkpoint to query.
    /// @return citizenCount The eligible civic-roll headcount at the checkpoint.
    /// @return votingPower The eligible active stake at the checkpoint.
    function snapshotAt(uint48 blockNumber) external view returns (uint256 citizenCount, uint256 votingPower);

    /// @notice Returns a historical snapshot only when it belongs to the currently rebuilt policy epoch.
    /// @dev Intended for new process creation. Historical processes should use `snapshotAt` and `wasEligibleAt`.
    /// @param blockNumber The last completed block selected for the new process.
    /// @return citizenCount The eligible civic-roll headcount at the checkpoint.
    /// @return votingPower The eligible active stake at the checkpoint.
    function snapshotAtCurrentEpoch(uint48 blockNumber)
        external
        view
        returns (uint256 citizenCount, uint256 votingPower);

    /// @notice Returns stored person eligibility at a previously certified process snapshot.
    /// @dev Returns false for future blocks and blocks marked incomplete by this registry. New processes must first
    ///      pass `snapshotAtCurrentEpoch`, which checks live source revisions and unprocessed welfare expiry.
    ///      Arbitrary unpinned past blocks are diagnostic reads, not certified electorate membership.
    /// @param personId The canonical person identifier.
    /// @param blockNumber The block-number checkpoint to query.
    /// @return eligible Whether the person belonged to the snapshotted electorate.
    function wasEligibleAt(bytes32 personId, uint48 blockNumber) external view returns (bool eligible);

    /// @notice Re-evaluates one identity against the current civic-roll policy.
    function syncPerson(bytes32 personId) external;

    /// @notice Processes at most 32 elapsed welfare periods; anyone may keep the production roll current.
    /// @dev New processes remain blocked until all due entries are processed and a completed block is available.
    function syncExpired(uint256 maxCount) external returns (uint256 processed);

    /// @notice Returns the earliest scheduled welfare expiry, or zero when none remain.
    function nextWelfareExpiry() external view returns (uint64 expiresAt);

    /// @notice Synchronizes a bounded identity-index range for a policy-epoch rebuild.
    function rebuild(uint256 startIndex, uint256 maxCount) external returns (uint256 nextIndex);

    /// @notice Invalidates aggregates after the citizen-eligibility policy changes.
    function beginPolicyRebuild() external;
}
