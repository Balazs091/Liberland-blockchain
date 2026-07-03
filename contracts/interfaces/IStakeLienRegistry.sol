// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IKernelModule} from "./IKernelModule.sol";

/// @title IStakeLienRegistry
/// @notice Stable fact registry for lending liens against active political stake.
interface IStakeLienRegistry is IKernelModule {
    error InsufficientStakeLien(bytes32 personId, uint256 currentLien, uint256 requestedAmount);
    error InvalidLienAmount(uint256 amount);
    error InvalidPersonId(bytes32 personId);
    error UnauthorizedStakeLienRegistryCaller(address caller);

    event StakeLienIncreased(
        bytes32 indexed personId, uint256 amount, uint256 newLienedStake, uint64 updatedAt, address indexed updatedBy
    );

    event StakeLienDecreased(
        bytes32 indexed personId, uint256 amount, uint256 newLienedStake, uint64 updatedAt, address indexed updatedBy
    );

    /// @notice Returns the minimum active stake that cannot be pledged for lending.
    /// @return amount The retained active-stake floor.
    function minimumRetainedStake() external view returns (uint256 amount);

    /// @notice Returns the active stake amount currently locked by lending liens.
    /// @param personId The canonical person identifier.
    /// @return amount The liened active stake.
    function lienedStakeOf(bytes32 personId) external view returns (uint256 amount);

    /// @notice Increases the lending lien for a person identifier.
    /// @param personId The canonical person identifier.
    /// @param amount The amount of active stake to lock.
    function increaseLien(bytes32 personId, uint256 amount) external;

    /// @notice Decreases the lending lien for a person identifier.
    /// @param personId The canonical person identifier.
    /// @param amount The amount of active stake to unlock.
    function decreaseLien(bytes32 personId, uint256 amount) external;
}
