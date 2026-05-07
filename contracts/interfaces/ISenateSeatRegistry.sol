// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SenateTypes} from "../types/SenateTypes.sol";

/// @title ISenateSeatRegistry
/// @notice Stable fact registry for the fixed v1 Senate seat set and succession metadata.
interface ISenateSeatRegistry {
    error InvalidPersonId(bytes32 personId);
    error InvalidSeatHolder(address holder);
    error InvalidSeatIndex(uint32 seatIndex);
    error InvalidSuccessor(address nominee);
    error SeatAlreadyOccupied(uint32 seatIndex, address currentHolder);
    error SeatAlreadyVacant(uint32 seatIndex);
    error UnauthorizedSenateSeatRegistryCaller(address caller);

    event SenateSeatAssigned(
        uint32 indexed seatIndex,
        address indexed holder,
        bytes32 indexed holderPersonId,
        bool filledBySuccession,
        uint32 transferCount,
        uint64 occupancyNonce,
        uint64 assignedAt,
        address assignedBy
    );

    event SenateSeatVacated(
        uint32 indexed seatIndex,
        address indexed previousHolder,
        bytes32 indexed previousHolderPersonId,
        uint64 occupancyNonce,
        uint64 vacatedAt,
        address vacatedBy
    );

    event SenateSuccessorNominated(
        uint32 indexed seatIndex,
        address indexed holder,
        address indexed nominee,
        bytes32 nomineePersonId,
        uint64 nominatedAt,
        address nominatedBy
    );

    event SenateSuccessorCleared(
        uint32 indexed seatIndex, address indexed previousNominee, uint64 clearedAt, address indexed clearedBy
    );

    event SenateSeatTransferred(
        uint32 indexed seatIndex,
        address indexed previousHolder,
        address indexed newHolder,
        bytes32 newHolderPersonId,
        uint32 transferCount,
        uint64 occupancyNonce,
        uint64 transferredAt,
        address transferredBy
    );

    /// @notice Returns the kernel used for narrow registry write authorization.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress);

    /// @notice Returns the fixed v1 Senate seat count.
    /// @return count The total number of Senate seats.
    function totalSeats() external pure returns (uint32 count);

    /// @notice Returns the current number of occupied Senate seats.
    /// @return count The number of occupied seats.
    function occupiedSeatCount() external view returns (uint32 count);

    /// @notice Returns the current number of active seats held by a wallet.
    /// @param wallet The wallet to inspect.
    /// @return count The number of occupied seats held by the wallet.
    function activeSeatCount(address wallet) external view returns (uint256 count);

    /// @notice Returns true when a wallet currently occupies at least one Senate seat.
    /// @param wallet The wallet to inspect.
    /// @return active Whether the wallet holds at least one active seat.
    function isActiveSeatHolder(address wallet) external view returns (bool active);

    /// @notice Returns the stored Senate seat record for a seat index.
    /// @param seatIndex The fixed seat index to inspect.
    /// @return seatRecord The stored seat record.
    function getSeatRecord(uint32 seatIndex) external view returns (SenateTypes.SenateSeatRecord memory seatRecord);

    /// @notice Assigns a vacant Senate seat to a holder through the authorized app.
    /// @param seatIndex The seat index to assign.
    /// @param holder The holder wallet address.
    /// @param holderPersonId The resolved holder person identifier.
    /// @param filledBySuccession Whether this assignment came from a nominated successor claim.
    function assignSeat(uint32 seatIndex, address holder, bytes32 holderPersonId, bool filledBySuccession) external;

    /// @notice Vacates an occupied Senate seat while preserving any nominated successor metadata.
    /// @param seatIndex The seat index to vacate.
    function vacateSeat(uint32 seatIndex) external;

    /// @notice Transfers an occupied Senate seat directly to another eligible holder.
    /// @param seatIndex The occupied seat index to transfer.
    /// @param newHolder The new holder wallet address.
    /// @param newHolderPersonId The resolved person identifier for the new holder.
    function transferSeat(uint32 seatIndex, address newHolder, bytes32 newHolderPersonId) external;

    /// @notice Stores or replaces the nominated successor for an occupied seat.
    /// @param seatIndex The seat index to update.
    /// @param nominee The nominated successor wallet.
    /// @param nomineePersonId The resolved nominee person identifier.
    function nominateSuccessor(uint32 seatIndex, address nominee, bytes32 nomineePersonId) external;

    /// @notice Clears the nominated successor for a seat.
    /// @param seatIndex The seat index to update.
    function clearSuccessor(uint32 seatIndex) external;
}
