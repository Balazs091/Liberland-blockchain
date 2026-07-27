// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ISenateSeatRegistry} from "../interfaces/ISenateSeatRegistry.sol";
import {KernelModule} from "../base/KernelModule.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {SenateTypes} from "../types/SenateTypes.sol";

/// @title SenateSeatRegistry
/// @notice Stable fact registry for the fixed 100-seat v1 Senate and nominated successor metadata.
contract SenateSeatRegistry is ISenateSeatRegistry, KernelModule {
    uint32 internal constant TOTAL_SEATS = 100;

    mapping(uint32 seatIndex => SenateTypes.SenateSeatRecord seatRecord) private _seatRecords;
    mapping(address wallet => uint256 count) private _activeSeatCounts;
    mapping(address wallet => bytes32 personId) private _activeSeatHolderPersonIds;
    mapping(bytes32 personId => uint256 count) private _activeSeatCountsByPerson;

    uint32 private _occupiedSeatCount;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc ISenateSeatRegistry
    function totalSeats() external pure returns (uint32 count) {
        return TOTAL_SEATS;
    }

    /// @inheritdoc ISenateSeatRegistry
    function occupiedSeatCount() external view returns (uint32 count) {
        return _occupiedSeatCount;
    }

    /// @inheritdoc ISenateSeatRegistry
    function activeSeatCount(address wallet) external view returns (uint256 count) {
        return _activeSeatCounts[wallet];
    }

    /// @inheritdoc ISenateSeatRegistry
    function isActiveSeatHolder(address wallet) external view returns (bool active) {
        return _activeSeatCounts[wallet] != 0;
    }

    /// @inheritdoc ISenateSeatRegistry
    function isActiveSeatHolderPerson(bytes32 personId) external view returns (bool active) {
        return _activeSeatCountsByPerson[personId] != 0;
    }

    /// @inheritdoc ISenateSeatRegistry
    function activeSeatHolderPersonId(address wallet) external view returns (bytes32 personId) {
        return _activeSeatHolderPersonIds[wallet];
    }

    /// @inheritdoc ISenateSeatRegistry
    function getSeatRecord(uint32 seatIndex) external view returns (SenateTypes.SenateSeatRecord memory seatRecord) {
        _requireValidSeatIndex(seatIndex);

        seatRecord = _seatRecords[seatIndex];
        seatRecord.seatIndex = seatIndex;
        if (seatRecord.holder == address(0) && seatRecord.transferCount == 0) {
            seatRecord.vacant = true;
        }
    }

    /// @inheritdoc ISenateSeatRegistry
    function assignSeat(uint32 seatIndex, address holder, bytes32 holderPersonId, bool filledBySuccession) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidSeatIndex(seatIndex);

        if (holder == address(0)) {
            revert InvalidSeatHolder(holder);
        }
        if (holderPersonId == bytes32(0)) {
            revert InvalidPersonId(holderPersonId);
        }

        SenateTypes.SenateSeatRecord storage seatRecord = _seatRecords[seatIndex];
        if (seatRecord.holder != address(0) && !seatRecord.vacant) {
            revert SeatAlreadyOccupied(seatIndex, seatRecord.holder);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        uint64 occupancyNonce = seatRecord.occupancyNonce + 1;

        seatRecord.seatIndex = seatIndex;
        seatRecord.holder = holder;
        seatRecord.holderPersonId = holderPersonId;
        seatRecord.nominatedSuccessor = address(0);
        seatRecord.nominatedSuccessorPersonId = bytes32(0);
        seatRecord.transferCount += 1;
        seatRecord.occupancyNonce = occupancyNonce;
        seatRecord.assignedAt = currentTimestamp;
        seatRecord.vacatedAt = 0;
        seatRecord.successorNominatedAt = 0;
        seatRecord.vacant = false;

        _requireConsistentHolderPerson(holder, holderPersonId);
        _activeSeatCounts[holder] += 1;
        _activeSeatHolderPersonIds[holder] = holderPersonId;
        _activeSeatCountsByPerson[holderPersonId] += 1;
        _occupiedSeatCount += 1;

        emit SenateSeatAssigned(
            seatIndex,
            holder,
            holderPersonId,
            filledBySuccession,
            seatRecord.transferCount,
            occupancyNonce,
            currentTimestamp,
            msg.sender
        );
    }

    /// @inheritdoc ISenateSeatRegistry
    function vacateSeat(uint32 seatIndex) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidSeatIndex(seatIndex);

        SenateTypes.SenateSeatRecord storage seatRecord = _seatRecords[seatIndex];
        if (seatRecord.holder == address(0) || seatRecord.vacant) {
            revert SeatAlreadyVacant(seatIndex);
        }

        address previousHolder = seatRecord.holder;
        bytes32 previousHolderPersonId = seatRecord.holderPersonId;
        uint64 currentTimestamp = uint64(block.timestamp);
        uint64 occupancyNonce = seatRecord.occupancyNonce + 1;

        _activeSeatCounts[previousHolder] -= 1;
        if (_activeSeatCounts[previousHolder] == 0) {
            delete _activeSeatHolderPersonIds[previousHolder];
        }
        _activeSeatCountsByPerson[previousHolderPersonId] -= 1;
        _occupiedSeatCount -= 1;

        seatRecord.holder = address(0);
        seatRecord.holderPersonId = bytes32(0);
        seatRecord.occupancyNonce = occupancyNonce;
        seatRecord.vacatedAt = currentTimestamp;
        seatRecord.vacant = true;

        emit SenateSeatVacated(
            seatIndex, previousHolder, previousHolderPersonId, occupancyNonce, currentTimestamp, msg.sender
        );
    }

    /// @inheritdoc ISenateSeatRegistry
    function transferSeat(uint32 seatIndex, address newHolder, bytes32 newHolderPersonId) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidSeatIndex(seatIndex);

        if (newHolder == address(0)) {
            revert InvalidSeatHolder(newHolder);
        }
        if (newHolderPersonId == bytes32(0)) {
            revert InvalidPersonId(newHolderPersonId);
        }

        SenateTypes.SenateSeatRecord storage seatRecord = _seatRecords[seatIndex];
        if (seatRecord.holder == address(0) || seatRecord.vacant) {
            revert SeatAlreadyVacant(seatIndex);
        }
        if (seatRecord.holder == newHolder) {
            revert InvalidSeatHolder(newHolder);
        }

        address previousHolder = seatRecord.holder;
        bytes32 previousHolderPersonId = seatRecord.holderPersonId;
        _requireConsistentHolderPerson(newHolder, newHolderPersonId);
        _activeSeatCounts[previousHolder] -= 1;
        if (_activeSeatCounts[previousHolder] == 0) {
            delete _activeSeatHolderPersonIds[previousHolder];
        }
        _activeSeatCounts[newHolder] += 1;
        _activeSeatHolderPersonIds[newHolder] = newHolderPersonId;
        _activeSeatCountsByPerson[previousHolderPersonId] -= 1;
        _activeSeatCountsByPerson[newHolderPersonId] += 1;

        uint64 currentTimestamp = uint64(block.timestamp);
        uint64 occupancyNonce = seatRecord.occupancyNonce + 1;
        seatRecord.holder = newHolder;
        seatRecord.holderPersonId = newHolderPersonId;
        seatRecord.nominatedSuccessor = address(0);
        seatRecord.nominatedSuccessorPersonId = bytes32(0);
        seatRecord.transferCount += 1;
        seatRecord.occupancyNonce = occupancyNonce;
        seatRecord.assignedAt = currentTimestamp;
        seatRecord.vacatedAt = 0;
        seatRecord.successorNominatedAt = 0;
        seatRecord.vacant = false;

        emit SenateSeatTransferred(
            seatIndex,
            previousHolder,
            newHolder,
            newHolderPersonId,
            seatRecord.transferCount,
            occupancyNonce,
            currentTimestamp,
            msg.sender
        );
    }

    /// @inheritdoc ISenateSeatRegistry
    function nominateSuccessor(uint32 seatIndex, address nominee, bytes32 nomineePersonId) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidSeatIndex(seatIndex);

        if (nominee == address(0)) {
            revert InvalidSuccessor(nominee);
        }
        if (nomineePersonId == bytes32(0)) {
            revert InvalidPersonId(nomineePersonId);
        }

        SenateTypes.SenateSeatRecord storage seatRecord = _seatRecords[seatIndex];
        if (seatRecord.holder == address(0) || seatRecord.vacant) {
            revert SeatAlreadyVacant(seatIndex);
        }
        if (seatRecord.holder == nominee) {
            revert InvalidSuccessor(nominee);
        }

        uint64 nominatedAt = uint64(block.timestamp);
        seatRecord.nominatedSuccessor = nominee;
        seatRecord.nominatedSuccessorPersonId = nomineePersonId;
        seatRecord.successorNominatedAt = nominatedAt;

        emit SenateSuccessorNominated(seatIndex, seatRecord.holder, nominee, nomineePersonId, nominatedAt, msg.sender);
    }

    /// @inheritdoc ISenateSeatRegistry
    function clearSuccessor(uint32 seatIndex) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidSeatIndex(seatIndex);

        SenateTypes.SenateSeatRecord storage seatRecord = _seatRecords[seatIndex];
        address previousNominee = seatRecord.nominatedSuccessor;
        uint64 clearedAt = uint64(block.timestamp);

        seatRecord.nominatedSuccessor = address(0);
        seatRecord.nominatedSuccessorPersonId = bytes32(0);
        seatRecord.successorNominatedAt = 0;

        emit SenateSuccessorCleared(seatIndex, previousNominee, clearedAt, msg.sender);
    }

    function _requireRegistryAuthority(address caller) private view {
        if (caller == _kernel.getModule(KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY)) {
            return;
        }
        if (_isActiveSetupAuthority(caller)) {
            return;
        }

        revert UnauthorizedSenateSeatRegistryCaller(caller);
    }

    function _requireConsistentHolderPerson(address holder, bytes32 suppliedPersonId) private view {
        bytes32 currentPersonId = _activeSeatHolderPersonIds[holder];
        if (_activeSeatCounts[holder] != 0 && currentPersonId != suppliedPersonId) {
            revert SeatHolderPersonMismatch(holder, currentPersonId, suppliedPersonId);
        }
    }

    function _requireValidSeatIndex(uint32 seatIndex) private pure {
        if (seatIndex >= TOTAL_SEATS) {
            revert InvalidSeatIndex(seatIndex);
        }
    }
}
