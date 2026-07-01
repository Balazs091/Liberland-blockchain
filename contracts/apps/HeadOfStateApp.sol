// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IHeadOfStateApp} from "../interfaces/IHeadOfStateApp.sol";
import {IPresidentRegistry} from "../interfaces/IPresidentRegistry.sol";
import {ISenateSeatRegistry} from "../interfaces/ISenateSeatRegistry.sol";
import {SenateTypes} from "../types/SenateTypes.sol";

/// @title HeadOfStateApp
/// @notice Standing authority for the Senate-elected Head of State (Constitution Art VI §2). Registered as the
///         kernel PRESIDENT_REGISTRY_AUTHORITY, it is the sole live writer of the President registry after genesis,
///         fixing the post-genesis freeze that left PRESIDENT_REGISTRY_AUTHORITY unregistered.
///
///         Election model (seat-based majority, mirroring the Senate's occupied-seat counting): each occupied seat
///         casts one ballot for a sitting Senator; a ballot is bound to the seat's occupancy nonce so a
///         transferred or vacated seat's stale ballot no longer counts, and to an election cycle nonce so ballots
///         from a prior election never carry into the next. A permissionless finalizer installs a candidate whose
///         valid ballots are a strict majority of the occupied seats (`votes * 2 > occupiedSeatCount`).
///
///         The President's only power here is appointing two Vice Presidents from among the Senators; there is no
///         residual appointment power. On resignation the first-sworn Vice President assumes the presidency for the
///         remainder of the term, otherwise the office is left vacant for a fresh election.
contract HeadOfStateApp is IHeadOfStateApp {
    /// @dev Fixed five-year term (5 * 365 days) that ends by passage of time.
    uint64 internal constant PRESIDENT_TERM = 1825 days;

    IPresidentRegistry private immutable _presidentRegistry;
    ISenateSeatRegistry private immutable _senateSeatRegistry;
    address private immutable _kernel;

    struct SeatBallot {
        address candidate;
        uint64 seatOccupancyNonce;
        uint64 electionCycle;
        uint64 castAt;
    }

    mapping(uint32 seatIndex => SeatBallot ballot) private _seatBallots;
    uint64 private _electionCycle;

    /// @param presidentRegistryAddress The President registry mutated as the standing authority.
    /// @param senateSeatRegistryAddress The Senate seat registry used to resolve seat holders and occupancy.
    constructor(address presidentRegistryAddress, address senateSeatRegistryAddress) {
        if (presidentRegistryAddress == address(0) || presidentRegistryAddress.code.length == 0) {
            revert InvalidPresidentRegistry(presidentRegistryAddress);
        }
        if (senateSeatRegistryAddress == address(0) || senateSeatRegistryAddress.code.length == 0) {
            revert InvalidSenateSeatRegistry(senateSeatRegistryAddress);
        }

        address presidentKernel = IPresidentRegistry(presidentRegistryAddress).kernel();
        address seatKernel = ISenateSeatRegistry(senateSeatRegistryAddress).kernel();
        if (presidentKernel != seatKernel) {
            revert KernelMismatch(presidentKernel, seatKernel);
        }
        if (presidentKernel == address(0) || presidentKernel.code.length == 0) {
            revert KernelMismatch(presidentKernel, seatKernel);
        }

        _presidentRegistry = IPresidentRegistry(presidentRegistryAddress);
        _senateSeatRegistry = ISenateSeatRegistry(senateSeatRegistryAddress);
        _kernel = presidentKernel;
        _electionCycle = 1;
    }

    /// @inheritdoc IHeadOfStateApp
    function presidentRegistry() external view returns (address registryAddress) {
        return address(_presidentRegistry);
    }

    /// @inheritdoc IHeadOfStateApp
    function senateSeatRegistry() external view returns (address registryAddress) {
        return address(_senateSeatRegistry);
    }

    /// @inheritdoc IHeadOfStateApp
    function kernel() external view returns (address kernelAddress) {
        return _kernel;
    }

    /// @inheritdoc IHeadOfStateApp
    function presidentTerm() external pure returns (uint64 termSeconds) {
        return PRESIDENT_TERM;
    }

    /// @inheritdoc IHeadOfStateApp
    function currentElectionCycle() external view returns (uint64 cycle) {
        return _electionCycle;
    }

    /// @inheritdoc IHeadOfStateApp
    function getSeatVote(uint32 seatIndex)
        external
        view
        returns (address candidate, uint64 seatOccupancyNonce, uint64 electionCycle)
    {
        SeatBallot memory ballot = _seatBallots[seatIndex];
        return (ballot.candidate, ballot.seatOccupancyNonce, ballot.electionCycle);
    }

    /// @inheritdoc IHeadOfStateApp
    function voteCountFor(address candidate) external view returns (uint256 voteCount) {
        return _voteCountFor(candidate);
    }

    /// @inheritdoc IHeadOfStateApp
    function canElectPresident(address candidate) external view returns (bool electable) {
        if (_presidentRegistry.isPresidentInTerm()) {
            return false;
        }
        if (!_senateSeatRegistry.isActiveSeatHolder(candidate)) {
            return false;
        }

        return _voteCountFor(candidate) * 2 > _senateSeatRegistry.occupiedSeatCount();
    }

    /// @inheritdoc IHeadOfStateApp
    function voteForPresident(uint32 seatIndex, address candidate) external {
        _requireSeatHolder(seatIndex, msg.sender);
        if (!_senateSeatRegistry.isActiveSeatHolder(candidate)) {
            revert CandidateNotSeatHolder(candidate);
        }

        uint64 occupancyNonce = _senateSeatRegistry.getSeatRecord(seatIndex).occupancyNonce;
        uint64 cycle = _electionCycle;
        uint64 currentTimestamp = uint64(block.timestamp);

        _seatBallots[seatIndex] = SeatBallot({
            candidate: candidate, seatOccupancyNonce: occupancyNonce, electionCycle: cycle, castAt: currentTimestamp
        });

        emit PresidentVoteCast(seatIndex, msg.sender, candidate, occupancyNonce, cycle, currentTimestamp);
    }

    /// @inheritdoc IHeadOfStateApp
    function electPresident(address candidate) external {
        address sittingPresident = _presidentRegistry.currentPresident();
        if (_presidentRegistry.isPresidentInTerm()) {
            revert PresidentAlreadyInTerm(sittingPresident);
        }
        if (!_senateSeatRegistry.isActiveSeatHolder(candidate)) {
            revert CandidateNotSeatHolder(candidate);
        }

        uint256 voteCount = _voteCountFor(candidate);
        uint256 occupiedSeats = _senateSeatRegistry.occupiedSeatCount();
        if (voteCount * 2 <= occupiedSeats) {
            revert ElectionMajorityNotReached(candidate, voteCount, occupiedSeats);
        }

        bytes32 candidatePersonId = _resolveSeatHolderPersonId(candidate);
        uint64 termStart = uint64(block.timestamp);
        uint64 termEnd = termStart + PRESIDENT_TERM;
        bytes32 mandateHash = _electionMandateHash(candidate, termStart);

        // Advance the cycle so every ballot from this election is voided for the next one.
        _electionCycle += 1;

        _presidentRegistry.setPresident(candidate, candidatePersonId, mandateHash, termStart, termEnd);

        emit PresidentElected(
            candidate, candidatePersonId, voteCount, occupiedSeats, termStart, termEnd, uint64(block.timestamp)
        );
    }

    /// @inheritdoc IHeadOfStateApp
    function appointVicePresident(uint8 slot, address vp, bytes32 vpPersonId) external {
        _requireSittingPresident(msg.sender);
        if (slot >= 2) {
            revert InvalidVicePresidentSlot(slot);
        }
        if (!_senateSeatRegistry.isActiveSeatHolder(vp)) {
            revert VicePresidentNotSeatHolder(vp);
        }
        if (vp == msg.sender) {
            revert InvalidVicePresidentCandidate(vp);
        }

        uint8 otherSlot = slot == 0 ? 1 : 0;
        if (vp == _presidentRegistry.vicePresident(otherSlot)) {
            revert InvalidVicePresidentCandidate(vp);
        }

        bytes32 resolvedPersonId = _resolveSeatHolderPersonId(vp);
        if (vpPersonId != resolvedPersonId) {
            revert VicePresidentPersonIdMismatch(vp, vpPersonId, resolvedPersonId);
        }

        _presidentRegistry.setVicePresident(slot, vp, vpPersonId);

        emit VicePresidentAppointed(slot, vp, vpPersonId, msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc IHeadOfStateApp
    function resignPresident() external {
        if (msg.sender != _presidentRegistry.currentPresident() || msg.sender == address(0)) {
            revert NotPresident(msg.sender);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        emit PresidentResigned(msg.sender, currentTimestamp);

        address firstVicePresident = _presidentRegistry.vicePresident(0);
        if (firstVicePresident != address(0)) {
            // Succession (Art VI §2.5): the first-sworn Vice President assumes the presidency for the remainder of
            // the current term (same termEnd). setPresident clears both Vice President slots, so the successor may
            // re-appoint fresh Vice Presidents.
            bytes32 successorPersonId = _presidentRegistry.vicePresidentPersonId(0);
            uint64 remainingTermStart = _presidentRegistry.termStart();
            uint64 remainingTermEnd = _presidentRegistry.termEnd();
            bytes32 mandateHash = _successionMandateHash(firstVicePresident, remainingTermEnd);

            _presidentRegistry.setPresident(
                firstVicePresident, successorPersonId, mandateHash, remainingTermStart, remainingTermEnd
            );

            emit PresidentSucceeded(
                msg.sender, firstVicePresident, successorPersonId, remainingTermEnd, currentTimestamp
            );
            return;
        }

        // No first-sworn Vice President: leave the office vacant so a fresh election can run.
        _presidentRegistry.vacatePresident();

        emit PresidencyVacated(msg.sender, currentTimestamp);
    }

    function _voteCountFor(address candidate) private view returns (uint256 voteCount) {
        if (candidate == address(0)) {
            return 0;
        }

        uint64 cycle = _electionCycle;
        uint32 totalSeats = _senateSeatRegistry.totalSeats();
        for (uint32 seatIndex = 0; seatIndex < totalSeats; ++seatIndex) {
            SeatBallot memory ballot = _seatBallots[seatIndex];
            if (ballot.candidate != candidate || ballot.electionCycle != cycle) {
                continue;
            }

            SenateTypes.SenateSeatRecord memory seatRecord = _senateSeatRegistry.getSeatRecord(seatIndex);
            if (
                !seatRecord.vacant && seatRecord.holder != address(0)
                    && seatRecord.occupancyNonce == ballot.seatOccupancyNonce
            ) {
                voteCount += 1;
            }
        }
    }

    function _resolveSeatHolderPersonId(address holder) private view returns (bytes32 personId) {
        uint32 totalSeats = _senateSeatRegistry.totalSeats();
        for (uint32 seatIndex = 0; seatIndex < totalSeats; ++seatIndex) {
            SenateTypes.SenateSeatRecord memory seatRecord = _senateSeatRegistry.getSeatRecord(seatIndex);
            if (!seatRecord.vacant && seatRecord.holder == holder) {
                return seatRecord.holderPersonId;
            }
        }

        return bytes32(0);
    }

    function _requireSeatHolder(uint32 seatIndex, address caller) private view {
        SenateTypes.SenateSeatRecord memory seatRecord = _senateSeatRegistry.getSeatRecord(seatIndex);
        if (seatRecord.vacant || seatRecord.holder != caller) {
            revert NotSeatHolder(seatIndex, caller);
        }
    }

    function _requireSittingPresident(address caller) private view {
        if (
            caller == address(0) || caller != _presidentRegistry.currentPresident()
                || !_presidentRegistry.isPresidentInTerm()
        ) {
            revert NotPresident(caller);
        }
    }

    function _electionMandateHash(address candidate, uint64 termStart) private view returns (bytes32 mandateHash) {
        return keccak256(abi.encode(block.chainid, address(this), "head-of-state-election", candidate, termStart));
    }

    function _successionMandateHash(address successor, uint64 termEnd) private view returns (bytes32 mandateHash) {
        return keccak256(abi.encode(block.chainid, address(this), "head-of-state-succession", successor, termEnd));
    }
}
