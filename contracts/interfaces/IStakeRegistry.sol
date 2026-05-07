// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {StakeTypes} from "../types/StakeTypes.sol";

/// @title IStakeRegistry
/// @notice Stable fact registry for political stake, cooldowns, and slash accounting.
interface IStakeRegistry {
    error CooldownNotComplete(bytes32 personId, uint64 cooldownEnd);
    error InsufficientActiveStake(bytes32 personId, uint256 availableStake, uint256 requiredStake);
    error InsufficientSlashableStake(bytes32 personId, uint256 slashableStake, uint256 requestedSlash);
    error InvalidCooldownEnd(uint64 cooldownEnd, uint64 currentTimestamp);
    error InvalidPersonId(bytes32 personId);
    error InvalidStakeAmount(uint256 amount);
    error NoPendingUnstake(bytes32 personId);
    error PendingUnstakeExists(bytes32 personId);
    error ProtectedStakeFloorBreached(bytes32 personId, uint256 remainingStake, uint256 protectedFloor);
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

    event UnstakeRequested(
        bytes32 indexed personId,
        uint256 amount,
        uint256 newActiveStake,
        uint256 pendingUnstake,
        uint64 cooldownStart,
        uint64 cooldownEnd,
        address indexed updatedBy
    );

    event UnstakeClaimed(bytes32 indexed personId, uint256 claimedAmount, uint64 claimedAt, address indexed updatedBy);

    event StakeSlashed(
        bytes32 indexed personId,
        uint256 amount,
        uint256 newActiveStake,
        uint256 newPendingUnstake,
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

    /// @notice Returns the kernel used for narrow write authorization.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress);

    /// @notice Returns the full stake record for a person identifier.
    /// @param personId The canonical person identifier.
    /// @return record The stored stake record, or an empty record if unset.
    function getStakeRecord(bytes32 personId) external view returns (StakeTypes.StakeRecord memory record);

    /// @notice Returns the active political stake for a person identifier.
    /// @param personId The canonical person identifier.
    /// @return amount The active political stake.
    function activeStakeOf(bytes32 personId) external view returns (uint256 amount);

    /// @notice Returns the currently pending unstake amount for a person identifier.
    /// @param personId The canonical person identifier.
    /// @return amount The pending unstake amount.
    function pendingUnstakeOf(bytes32 personId) external view returns (uint256 amount);

    /// @notice Returns the configured protected political floor for a person identifier.
    /// @param personId The canonical person identifier.
    /// @return amount The protected floor amount.
    function protectedStakeFloorOf(bytes32 personId) external view returns (uint256 amount);

    /// @notice Returns true when a person identifier has any pending unstake amount.
    /// @param personId The canonical person identifier.
    /// @return pending Whether a pending unstake exists.
    function hasPendingUnstake(bytes32 personId) external view returns (bool pending);

    /// @notice Returns true when a person identifier is still inside an active unstaking cooldown.
    /// @param personId The canonical person identifier.
    /// @return active Whether a cooldown is active.
    function hasActiveUnstakeCooldown(bytes32 personId) external view returns (bool active);

    /// @notice Returns the amount claimable from a completed unstake cooldown.
    /// @param personId The canonical person identifier.
    /// @return amount The claimable unstake amount.
    function claimableUnstake(bytes32 personId) external view returns (uint256 amount);

    /// @notice Increases the active political stake for a person identifier.
    /// @param personId The canonical person identifier.
    /// @param amount The amount to add.
    function increaseStake(bytes32 personId, uint256 amount) external;

    /// @notice Updates the protected political floor for a person identifier.
    /// @param personId The canonical person identifier.
    /// @param newProtectedFloor The new protected floor amount.
    function setProtectedStakeFloor(bytes32 personId, uint256 newProtectedFloor) external;

    /// @notice Starts a single outstanding unstake cooldown for a person identifier.
    /// @param personId The canonical person identifier.
    /// @param amount The amount to move into pending unstake.
    /// @param cooldownEnd The timestamp at which the unstake becomes claimable.
    function requestUnstake(bytes32 personId, uint256 amount, uint64 cooldownEnd) external;

    /// @notice Claims the currently pending unstake amount after the cooldown completes.
    /// @param personId The canonical person identifier.
    /// @return claimedAmount The amount that was claimed.
    function claimUnstake(bytes32 personId) external returns (uint256 claimedAmount);

    /// @notice Records a slash against slashable stake for a person identifier.
    /// @param personId The canonical person identifier.
    /// @param amount The amount to slash.
    function slashStake(bytes32 personId, uint256 amount) external;

    /// @notice Records stake recovery back into active political stake.
    /// @param personId The canonical person identifier.
    /// @param amount The amount to recover.
    function recoverStake(bytes32 personId, uint256 amount) external;
}
