// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IKernelModule} from "./IKernelModule.sol";
import {StakeTypes} from "../types/StakeTypes.sol";

/// @title IStakeRegistry
/// @notice Stable fact registry for political stake, discrete unstaking, welfare, and slash accounting.
interface IStakeRegistry is IKernelModule {
    error InsufficientActiveStake(bytes32 personId, uint256 availableStake, uint256 requiredStake);
    error InsufficientSlashableStake(bytes32 personId, uint256 slashableStake, uint256 requestedSlash);
    error InWelfarePeriod(bytes32 personId, uint64 welfareUntil);
    error InvalidPersonId(bytes32 personId);
    error InvalidStakeAmount(uint256 amount);
    error InvalidStakeTransfer(bytes32 fromPersonId, bytes32 toPersonId);
    error NothingToUnstake(bytes32 personId);
    error ProtectedStakeFloorBreached(bytes32 personId, uint256 remainingStake, uint256 protectedFloor);
    error StakeLienRegistryUnavailable(bytes32 personId);
    error UnauthorizedStakeRegistryCaller(address caller);

    event StakeIncreased(
        bytes32 indexed personId, uint256 amount, uint256 newActiveStake, uint64 updatedAt, address indexed updatedBy
    );

    event ProtectedStakeFloorUpdated(
        bytes32 indexed personId,
        uint256 previousProtectedFloor,
        uint256 newProtectedFloor,
        uint64 updatedAt,
        address indexed updatedBy
    );

    event UnstakeExecuted(
        bytes32 indexed personId,
        uint256 releasedAmount,
        uint256 remainingActiveStake,
        uint64 welfareUntil,
        uint64 timestamp,
        address indexed caller
    );

    event StakeSlashed(
        bytes32 indexed personId,
        uint256 amount,
        uint256 newActiveStake,
        uint256 totalSlashed,
        uint64 updatedAt,
        address indexed updatedBy
    );

    event StakeRecovered(
        bytes32 indexed personId,
        uint256 amount,
        uint256 newActiveStake,
        uint256 totalRecovered,
        uint64 updatedAt,
        address indexed updatedBy
    );

    event ActiveStakeTransferred(
        bytes32 indexed fromPersonId,
        bytes32 indexed toPersonId,
        uint256 amount,
        uint256 fromActiveStake,
        uint256 toActiveStake,
        uint64 updatedAt,
        address indexed updatedBy
    );

    event ElectorateSourceRevisionAdvanced(
        bytes32 indexed personId, uint256 personRevision, uint256 totalMutationCount
    );
    event ElectorateSynchronizationDeferred(bytes32 indexed personId, address indexed electorateRegistry);

    /// @notice Returns the full stake record for a person identifier.
    /// @param personId The canonical person identifier.
    /// @return record The stored stake record, or an empty record if unset.
    function getStakeRecord(bytes32 personId) external view returns (StakeTypes.StakeRecord memory record);

    /// @notice Returns the active political stake for a person identifier.
    /// @param personId The canonical person identifier.
    /// @return amount The active political stake.
    function activeStakeOf(bytes32 personId) external view returns (uint256 amount);

    /// @notice Returns active political stake at or before a historical block.
    /// @param personId The canonical person identifier.
    /// @param blockNumber The block-number checkpoint to query.
    /// @return amount The active stake recorded at that checkpoint.
    function activeStakeAt(bytes32 personId, uint48 blockNumber) external view returns (uint256 amount);

    /// @notice Returns total active political stake across all person identifiers.
    /// @return amount The aggregate active stake tracked by this registry.
    function totalActiveStake() external view returns (uint256 amount);

    /// @notice Returns the electorate-relevant stake revision for one person.
    /// @param personId The canonical person identifier.
    /// @return revision The number of active-stake mutations recorded for the person.
    function electorateRevisionOf(bytes32 personId) external view returns (uint256 revision);

    /// @notice Returns the aggregate number of electorate-relevant stake mutations.
    /// @return count The source mutation count mirrored by a ready electorate registry.
    function electorateMutationCount() external view returns (uint256 count);

    /// @notice Returns the configured protected political floor for a person identifier.
    /// @param personId The canonical person identifier.
    /// @return amount The protected floor amount.
    function protectedStakeFloorOf(bytes32 personId) external view returns (uint256 amount);

    /// @notice Returns the active stake that must remain after any unstake or lending transfer.
    /// @param personId The canonical person identifier.
    /// @return amount The required active-stake floor, including lending liens when configured.
    function requiredActiveStakeFloorOf(bytes32 personId) external view returns (uint256 amount);

    /// @notice Returns true when a person identifier is currently inside a welfare period.
    /// @param personId The canonical person identifier.
    /// @return inWelfare Whether the person is in welfare.
    function isInWelfare(bytes32 personId) external view returns (bool inWelfare);

    /// @notice Returns the timestamp until which a person identifier remains in welfare.
    /// @param personId The canonical person identifier.
    /// @return welfareUntil The welfare end timestamp, or zero if not in welfare.
    function welfareUntilOf(bytes32 personId) external view returns (uint64 welfareUntil);

    /// @notice Increases the active political stake for a person identifier.
    /// @param personId The canonical person identifier.
    /// @param amount The amount to add.
    function increaseStake(bytes32 personId, uint256 amount) external;

    /// @notice Updates the protected political floor for a person identifier.
    /// @param personId The canonical person identifier.
    /// @param newProtectedFloor The new protected floor amount.
    function setProtectedStakeFloor(bytes32 personId, uint256 newProtectedFloor) external;

    /// @notice Releases the discrete unstake portion and starts a welfare period.
    /// @dev Immediate: the caller transfers the released amount to the user in the same transaction.
    /// @param personId The canonical person identifier.
    /// @return releasedAmount The active stake released to the caller for payout.
    /// @return welfareUntil The timestamp until which the person is in welfare.
    function unstake(bytes32 personId) external returns (uint256 releasedAmount, uint64 welfareUntil);

    /// @notice Records a slash against active political stake above the person's required active-stake floor.
    /// @param personId The canonical person identifier.
    /// @param amount The amount to slash.
    function slashStake(bytes32 personId, uint256 amount) external;

    /// @notice Records stake recovery back into active political stake.
    /// @param personId The canonical person identifier.
    /// @param amount The amount to recover.
    function recoverStake(bytes32 personId, uint256 amount) external;

    /// @notice Transfers active political stake between person identifiers through an authorized liquidation path.
    /// @param fromPersonId The person identifier losing active stake.
    /// @param toPersonId The person identifier receiving active stake.
    /// @param amount The active stake amount to transfer.
    function transferActiveStake(bytes32 fromPersonId, bytes32 toPersonId, uint256 amount) external;
}
