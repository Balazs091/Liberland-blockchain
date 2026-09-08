// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IKernelModule} from "./IKernelModule.sol";

/// @title IStakeLienRegistry
/// @notice Stable fact registry for lending liens against active political stake.
interface IStakeLienRegistry is IKernelModule {
    error InsufficientStakeLien(bytes32 personId, uint256 currentLien, uint256 requestedAmount);
    error InvalidLienAmount(uint256 amount);
    error InvalidPersonId(bytes32 personId);
    error UnauthorizedStakeLienRegistryCaller(address caller);
    error LoanBookConflict(bytes32 personId, address owner, address caller);
    error InvalidLiquidationSettlement(bytes32 personId);
    error LienExceedsActiveStake(bytes32 personId, uint256 requiredStake, uint256 activeStake);
    error RetiredLoanCollateralExceeded(
        bytes32 personId, uint256 priorLien, uint256 seizedStake, uint256 remainingLien
    );

    event StakeLienIncreased(
        bytes32 indexed personId, uint256 amount, uint256 newLienedStake, uint64 updatedAt, address indexed updatedBy
    );

    event StakeLienDecreased(
        bytes32 indexed personId, uint256 amount, uint256 newLienedStake, uint64 updatedAt, address indexed updatedBy
    );

    event RetainedStakeFloorUpdated(
        bytes32 indexed personId, uint256 previousRetainedFloor, uint256 newRetainedFloor, uint64 updatedAt
    );

    event LoanBookOpened(bytes32 indexed personId, address indexed pool);
    event LoanBookClosed(bytes32 indexed personId, address indexed pool);
    event LienLiquidationSettled(
        bytes32 indexed personId,
        bytes32 indexed recipientPersonId,
        address indexed pool,
        uint256 seizedStake,
        uint256 remainingLien,
        bool debtCleared
    );

    /// @notice Returns the current policy minimum that cannot be pledged by a new lending position.
    /// @return amount The current retained active-stake floor.
    function minimumRetainedStake() external view returns (uint256 amount);

    /// @notice Returns the loan's snapshotted floor, or the current policy minimum when no loan book owns it.
    /// @param personId The canonical person identifier.
    /// @return amount The retained floor governing this person's current or next lending position.
    function retainedStakeFloorOf(bytes32 personId) external view returns (uint256 amount);

    /// @notice Returns the active stake amount currently locked by lending liens.
    /// @param personId The canonical person identifier.
    /// @return amount The liened active stake.
    function lienedStakeOf(bytes32 personId) external view returns (uint256 amount);

    /// @notice Returns the sole pool owning the person's outstanding loan, including exhausted-collateral debt.
    /// @dev Ownership persists at zero lien until that pool explicitly closes the debt position.
    function loanBookOf(bytes32 personId) external view returns (address pool);

    /// @notice Opens or increases a lien only for the current jointly authorized pool, never another loan book.
    /// @param personId The canonical person identifier.
    /// @param amount The amount of active stake to lock.
    function increaseLien(bytes32 personId, uint256 amount) external;

    /// @notice Decreases the caller's own lien, including for a retired pool; does not close loan-book ownership.
    /// @param personId The canonical person identifier.
    /// @param amount The amount of active stake to unlock.
    function decreaseLien(bytes32 personId, uint256 amount) external;

    /// @notice Closes the caller's recorded loan book and releases its remaining lien and captured floor.
    /// @dev The owning pool calls only after full repayment or valid bad-debt absorption; retirement does not revoke it.
    function closeLoan(bytes32 personId) external;

    /// @notice Atomically reduces an owned lien and transfers the exact seized active stake to a liquidator.
    /// @dev Only the recorded pool may settle its borrower. A retired pool cannot seize plus retain more than its
    ///      prior numerical lien, so later stake is not newly pledged to historical code. The protected
    ///      and captured retained floors are checked even when final settlement clears ownership before transfer.
    function settleLiquidation(
        bytes32 personId,
        bytes32 recipientPersonId,
        uint256 seizedStake,
        uint256 remainingLien,
        bool debtCleared
    ) external;
}
