// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SenateTypes} from "../types/SenateTypes.sol";

/// @title ISenateApp
/// @notice User-facing interface for Senate seat succession and bounded negative-control action cancellation.
interface ISenateApp {
    error ActionCancellationAlreadyExecuted(bytes32 actionId);
    error ActionCancellationNotAllowed(bytes32 actionId);
    error ActionSupportAlreadyActive(bytes32 actionId, uint32 seatIndex);
    error ActionSupportNotActive(bytes32 actionId, uint32 seatIndex);
    error InvalidPolicy(address policyAddress);
    error InvalidRegistry(address registryAddress);
    error InvalidRouter(address routerAddress);
    error InvalidTimelock(address timelockAddress);
    error NotNominatedSuccessor(uint32 seatIndex, address claimant);
    error NotSeatHolder(uint32 seatIndex, address caller);
    error SeatNotVacant(uint32 seatIndex);
    error UnauthorizedBootstrapCaller(address caller);
    error UnknownPersonReference(address wallet);

    event SenateActionCancellationOpened(
        bytes32 indexed actionId, uint32 indexed openedBySeat, address indexed openedBy, uint64 openedAt
    );

    event SenateActionSupportRecorded(
        bytes32 indexed actionId,
        uint32 indexed seatIndex,
        address indexed seatHolder,
        uint256 supportCount,
        uint64 recordedAt
    );

    event SenateActionSupportRemoved(
        bytes32 indexed actionId,
        uint32 indexed seatIndex,
        address indexed seatHolder,
        uint256 supportCount,
        uint64 removedAt
    );

    event SenateActionCanceled(
        bytes32 indexed actionId, uint256 indexed supportCount, address indexed canceledBy, uint64 canceledAt
    );

    /// @notice Returns the configured identity registry address used for holder and successor person resolution.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured Senate seat registry address.
    /// @return registryAddress The Senate seat registry address.
    function senateSeatRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured Senate powers policy address.
    /// @return policyAddress The Senate powers policy address.
    function senatePowersPolicy() external view returns (address policyAddress);

    /// @notice Returns the configured governance router address.
    /// @return routerAddress The governance router address.
    function governanceRouter() external view returns (address routerAddress);

    /// @notice Returns the configured action timelock address.
    /// @return timelockAddress The action timelock address.
    function actionTimelock() external view returns (address timelockAddress);

    /// @notice Returns the stored action-cancellation process record for a queued action.
    /// @param actionId The queued action identifier.
    /// @return record The stored Senate cancellation process record.
    function getActionCancellationRecord(bytes32 actionId)
        external
        view
        returns (SenateTypes.ActionCancellationRecord memory record);

    /// @notice Returns the current support receipt for a seat on an action cancellation process.
    /// @param actionId The queued action identifier.
    /// @param seatIndex The fixed seat index to inspect.
    /// @return support The seat's current support receipt.
    function getActionCancellationSupport(bytes32 actionId, uint32 seatIndex)
        external
        view
        returns (SenateTypes.ActionCancellationSupport memory support);

    /// @notice Returns the current number of valid seat supports for an action cancellation process.
    /// @param actionId The queued action identifier.
    /// @return count The current number of valid supporting seats.
    function actionCancellationSupportCount(bytes32 actionId) external view returns (uint256 count);

    /// @notice Assigns a Senate seat during bootstrap through the shared kernel bootstrap authority.
    /// @param seatIndex The seat index to assign.
    /// @param holder The holder wallet to assign.
    function bootstrapAssignSeat(uint32 seatIndex, address holder) external;

    /// @notice Vacates the caller's occupied Senate seat.
    /// @param seatIndex The seat index held by the caller.
    function vacateMySeat(uint32 seatIndex) external;

    /// @notice Transfers the caller's occupied seat directly to another eligible wallet.
    /// @param seatIndex The seat index held by the caller.
    /// @param recipient The new seat holder wallet.
    function transferMySeat(uint32 seatIndex, address recipient) external;

    /// @notice Stores or replaces the nominated successor for the caller's occupied seat.
    /// @param seatIndex The seat index held by the caller.
    /// @param nominee The nominated successor wallet.
    function nominateSuccessor(uint32 seatIndex, address nominee) external;

    /// @notice Clears the nominated successor for the caller's occupied seat.
    /// @param seatIndex The seat index held by the caller.
    function clearSuccessor(uint32 seatIndex) external;

    /// @notice Claims a vacant Senate seat when the caller is the nominated successor person.
    /// @param seatIndex The vacant seat index to claim.
    function claimSeatBySuccession(uint32 seatIndex) external;

    /// @notice Records equal-weight seat support to cancel a queued governance action.
    /// @param actionId The queued action identifier to cancel.
    /// @param seatIndex The caller-controlled seat index contributing support.
    function supportActionCancellation(bytes32 actionId, uint32 seatIndex) external;

    /// @notice Removes equal-weight seat support from an action cancellation process.
    /// @param actionId The queued action identifier to update.
    /// @param seatIndex The caller-controlled seat index to remove.
    function removeActionCancellationSupport(bytes32 actionId, uint32 seatIndex) external;
}
