// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {KernelModule} from "../base/KernelModule.sol";
import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {ElectionTypes} from "../types/ElectionTypes.sol";

/// @title CongressCandidateRegistry
/// @notice Stable fact registry for Congress election cycles, candidate states, signed ballots, and active seat occupancy.
contract CongressCandidateRegistry is ICongressCandidateRegistry, KernelModule {
    struct BallotConfig {
        uint256 cycleId;
        address voter;
        uint256 ballotWeight;
        uint256 allocationCount;
        uint32 maxPositiveCandidates;
        uint256 maxNegativeAllocation;
        uint64 updatedAt;
    }

    struct BallotTotals {
        uint256 positiveAllocationTotal;
        uint256 negativeAllocationTotal;
        uint256 totalAllocation;
        uint32 positiveCandidateCount;
    }

    uint256 private _latestCycleId;

    mapping(uint256 cycleId => ElectionTypes.CongressCycleRecord cycleRecord) private _cycles;
    mapping(uint256 cycleId => address[] candidates) private _cycleCandidates;
    mapping(uint256 cycleId => address[] electedCandidates) private _electedCandidates;
    mapping(uint256 cycleId => address[] runnerUps) private _runnerUpCandidates;
    mapping(uint256 cycleId => mapping(address candidate => ElectionTypes.CongressCandidateRecord record)) private
        _candidateRecords;
    mapping(uint256 cycleId => mapping(address candidate => uint256 indexPlusOne)) private _candidateIndexPlusOne;
    mapping(uint256 cycleId => mapping(address voter => ElectionTypes.BallotReceipt receipt)) private _ballotReceipts;
    mapping(uint256 cycleId => mapping(address voter => ElectionTypes.BallotAllocation[] allocations)) private
        _ballotAllocations;
    mapping(address voter => ElectionTypes.BallotReceipt receipt) private _standingBallotReceipts;
    mapping(address voter => ElectionTypes.BallotAllocation[] allocations) private _standingBallotAllocations;
    mapping(address candidate => int256 voteTotal) private _standingVoteTotals;
    mapping(uint32 seatIndex => ElectionTypes.CongressSeatRecord seatRecord) private _seatRecords;
    mapping(address wallet => uint32 seatIndexPlusOne) private _activeSeatIndexPlusOne;

    ElectionTypes.CongressOfficeTerm private _currentOfficeTerm;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc ICongressCandidateRegistry
    function latestCycleId() external view returns (uint256 cycleId) {
        return _latestCycleId;
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getCycle(uint256 cycleId) external view returns (ElectionTypes.CongressCycleRecord memory record) {
        return _cycles[cycleId];
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getCandidate(uint256 cycleId, address candidate)
        external
        view
        returns (ElectionTypes.CongressCandidateRecord memory record)
    {
        return _candidateRecords[cycleId][candidate];
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getBallotReceipt(uint256 cycleId, address voter)
        external
        view
        returns (ElectionTypes.BallotReceipt memory receipt)
    {
        return _ballotReceipts[cycleId][voter];
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getBallotAllocationCount(uint256 cycleId, address voter) external view returns (uint256 count) {
        return _ballotAllocations[cycleId][voter].length;
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getBallotAllocationAt(uint256 cycleId, address voter, uint256 index)
        external
        view
        returns (ElectionTypes.BallotAllocation memory allocation)
    {
        return _ballotAllocations[cycleId][voter][index];
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getStandingBallotReceipt(address voter)
        external
        view
        returns (ElectionTypes.BallotReceipt memory receipt)
    {
        return _standingBallotReceipts[voter];
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getStandingBallotAllocationCount(address voter) external view returns (uint256 count) {
        return _standingBallotAllocations[voter].length;
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getStandingBallotAllocationAt(address voter, uint256 index)
        external
        view
        returns (ElectionTypes.BallotAllocation memory allocation)
    {
        return _standingBallotAllocations[voter][index];
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getCurrentOfficeTerm() external view returns (ElectionTypes.CongressOfficeTerm memory term) {
        return _currentOfficeTerm;
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getSeatRecord(uint32 seatIndex)
        external
        view
        returns (ElectionTypes.CongressSeatRecord memory seatRecord)
    {
        return _seatRecords[seatIndex];
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getCycleCandidateCount(uint256 cycleId) external view returns (uint256 count) {
        return _cycleCandidates[cycleId].length;
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getCycleCandidateAt(uint256 cycleId, uint256 index) external view returns (address candidate) {
        return _cycleCandidates[cycleId][index];
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getElectedCandidateCount(uint256 cycleId) external view returns (uint256 count) {
        return _electedCandidates[cycleId].length;
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getElectedCandidateAt(uint256 cycleId, uint256 index) external view returns (address candidate) {
        return _electedCandidates[cycleId][index];
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getRunnerUpCount(uint256 cycleId) external view returns (uint256 count) {
        return _runnerUpCandidates[cycleId].length;
    }

    /// @inheritdoc ICongressCandidateRegistry
    function getRunnerUpAt(uint256 cycleId, uint256 index) external view returns (address candidate) {
        return _runnerUpCandidates[cycleId][index];
    }

    /// @inheritdoc ICongressCandidateRegistry
    function cycleExists(uint256 cycleId) public view returns (bool exists) {
        return _cycles[cycleId].cycleId != 0;
    }

    /// @inheritdoc ICongressCandidateRegistry
    function isActiveCongressMember(address wallet) external view returns (bool active) {
        return _activeSeatIndexPlusOne[wallet] != 0;
    }

    /// @inheritdoc ICongressCandidateRegistry
    function currentCongressMembers() external view returns (address[] memory members) {
        ElectionTypes.CongressOfficeTerm memory currentOfficeTerm = _currentOfficeTerm;
        members = new address[](currentOfficeTerm.occupiedSeatCount);
        uint256 outputIndex = 0;
        for (uint32 seatIndex = 0; seatIndex < currentOfficeTerm.seatCount; ++seatIndex) {
            address holder = _seatRecords[seatIndex].holder;
            if (holder == address(0)) {
                continue;
            }

            members[outputIndex] = holder;
            outputIndex += 1;
        }
    }

    /// @inheritdoc ICongressCandidateRegistry
    function createCycle(uint256 cycleId, ElectionTypes.CongressCycleInput calldata cycleInput) external {
        _requireRegistryAuthority(msg.sender);

        if (cycleId == 0) {
            revert InvalidCycleId(cycleId);
        }
        if (cycleExists(cycleId)) {
            revert ElectionCycleAlreadyExists(cycleId);
        }

        uint256 expectedCycleId = _latestCycleId + 1;
        if (cycleId != expectedCycleId) {
            revert UnexpectedCycleId(expectedCycleId, cycleId);
        }
        if (cycleInput.nominationStart >= cycleInput.votingStart || cycleInput.votingStart >= cycleInput.votingEnd) {
            revert InvalidVotingWindow(cycleInput.nominationStart, cycleInput.votingStart, cycleInput.votingEnd);
        }
        if (cycleInput.seatCount == 0) {
            revert InvalidSeatCount(cycleInput.seatCount);
        }
        if (cycleInput.runnerUpCount == 0) {
            revert InvalidRunnerUpCount(cycleInput.runnerUpCount);
        }
        if (cycleInput.maxCandidateCount < uint256(cycleInput.seatCount) + uint256(cycleInput.runnerUpCount)) {
            revert InvalidCandidateCount(
                uint256(cycleInput.seatCount) + uint256(cycleInput.runnerUpCount), cycleInput.maxCandidateCount
            );
        }
        if (cycleInput.policyReference == bytes32(0)) {
            revert InvalidPolicyReference(cycleInput.policyReference);
        }

        ElectionTypes.ElectionStatus status = block.timestamp < cycleInput.nominationStart
            ? ElectionTypes.ElectionStatus.Scheduled
            : block.timestamp < cycleInput.votingStart
                ? ElectionTypes.ElectionStatus.CandidateRegistration
                : ElectionTypes.ElectionStatus.Voting;

        _cycles[cycleId] = ElectionTypes.CongressCycleRecord({
            cycleId: cycleId,
            status: status,
            nominationStart: cycleInput.nominationStart,
            votingStart: cycleInput.votingStart,
            votingEnd: cycleInput.votingEnd,
            finalizedAt: 0,
            seatCount: cycleInput.seatCount,
            runnerUpCount: cycleInput.runnerUpCount,
            maxCandidateCount: cycleInput.maxCandidateCount,
            candidateCount: 0,
            electedCount: 0,
            runnerUpSlotCount: 0,
            policyReference: cycleInput.policyReference
        });
        _latestCycleId = cycleId;

        emit CongressElectionCycleCreated(
            cycleId,
            cycleInput.nominationStart,
            cycleInput.votingStart,
            cycleInput.votingEnd,
            cycleInput.seatCount,
            cycleInput.runnerUpCount,
            cycleInput.maxCandidateCount,
            cycleInput.policyReference,
            msg.sender
        );
    }

    /// @inheritdoc ICongressCandidateRegistry
    function registerCandidate(
        uint256 cycleId,
        address candidate,
        bytes32 personId,
        bytes32 applicationHash,
        string calldata applicationURI
    ) external {
        _requireRegistryAuthority(msg.sender);

        ElectionTypes.CongressCycleRecord storage cycleRecord = _requireOpenCycle(cycleId);
        if (candidate == address(0)) {
            revert InvalidCandidate(candidate);
        }
        if (personId == bytes32(0)) {
            revert InvalidPersonId(personId);
        }
        if (applicationHash == bytes32(0)) {
            revert InvalidApplicationHash(applicationHash);
        }
        if (_candidateRecords[cycleId][candidate].candidate != address(0)) {
            revert CandidateAlreadyExists(cycleId, candidate);
        }
        if (_cycleCandidates[cycleId].length >= cycleRecord.maxCandidateCount) {
            revert InvalidCandidateCount(_cycleCandidates[cycleId].length + 1, cycleRecord.maxCandidateCount);
        }

        uint64 appliedAt = uint64(block.timestamp);
        _cycleCandidates[cycleId].push(candidate);
        _candidateIndexPlusOne[cycleId][candidate] = _cycleCandidates[cycleId].length;
        cycleRecord.candidateCount = uint32(_cycleCandidates[cycleId].length);
        cycleRecord.status = ElectionTypes.ElectionStatus.CandidateRegistration;

        _candidateRecords[cycleId][candidate] = ElectionTypes.CongressCandidateRecord({
            cycleId: cycleId,
            candidate: candidate,
            personId: personId,
            status: ElectionTypes.CandidateStatus.Accepted,
            applicationHash: applicationHash,
            applicationURI: applicationURI,
            appliedAt: appliedAt,
            updatedAt: appliedAt,
            voteTotal: _standingVoteTotals[candidate],
            rank: 0
        });

        emit CongressCandidateRegistered(
            cycleId, candidate, personId, applicationHash, applicationURI, appliedAt, msg.sender
        );
    }

    /// @inheritdoc ICongressCandidateRegistry
    function withdrawCandidate(uint256 cycleId, address candidate) external {
        _requireRegistryAuthority(msg.sender);

        ElectionTypes.CongressCycleRecord storage cycleRecord = _requireOpenCycle(cycleId);
        ElectionTypes.CongressCandidateRecord storage candidateRecord = _candidateRecords[cycleId][candidate];
        if (candidateRecord.status != ElectionTypes.CandidateStatus.Accepted) {
            revert CandidateNotActive(cycleId, candidate);
        }

        _removeCandidateFromActiveList(cycleId, candidate);

        uint64 updatedAt = uint64(block.timestamp);
        cycleRecord.candidateCount = uint32(_cycleCandidates[cycleId].length);
        cycleRecord.status = ElectionTypes.ElectionStatus.CandidateRegistration;

        candidateRecord.status = ElectionTypes.CandidateStatus.Withdrawn;
        candidateRecord.updatedAt = updatedAt;

        emit CongressCandidateWithdrawn(cycleId, candidate, updatedAt, msg.sender);
    }

    /// @inheritdoc ICongressCandidateRegistry
    function recordBallot(
        uint256 cycleId,
        address voter,
        address[] calldata candidates,
        int256[] calldata allocations,
        uint256 ballotWeight,
        uint32 maxPositiveCandidates,
        uint256 maxNegativeAllocation
    ) external {
        _requireRegistryAuthority(msg.sender);

        ElectionTypes.CongressCycleRecord storage cycleRecord = _requireOpenCycle(cycleId);
        if (voter == address(0)) {
            revert InvalidVoter(voter);
        }
        if (ballotWeight == 0) {
            revert InvalidVotingWeight(voter, ballotWeight);
        }
        if (candidates.length == 0 || candidates.length != allocations.length) {
            revert InvalidCandidateCount(candidates.length, allocations.length);
        }

        _clearStandingBallot(cycleId, voter);
        BallotConfig memory config = BallotConfig({
            cycleId: cycleId,
            voter: voter,
            ballotWeight: ballotWeight,
            allocationCount: candidates.length,
            maxPositiveCandidates: maxPositiveCandidates,
            maxNegativeAllocation: maxNegativeAllocation,
            updatedAt: uint64(block.timestamp)
        });
        BallotTotals memory totals = _storeBallotAllocations(config, candidates, allocations);

        _storeBallotReceipt(cycleRecord, config, totals);
    }

    /// @inheritdoc ICongressCandidateRegistry
    function clearBallot(uint256 cycleId, address voter) external {
        _requireRegistryAuthority(msg.sender);

        ElectionTypes.CongressCycleRecord storage cycleRecord = _requireOpenCycle(cycleId);
        if (voter == address(0)) {
            revert InvalidVoter(voter);
        }

        ElectionTypes.BallotReceipt memory existingReceipt = _standingBallotReceipts[voter];
        if (existingReceipt.voter == address(0)) {
            revert VoteNotFound(cycleId, voter);
        }

        uint256 ballotWeight = existingReceipt.ballotWeight;
        _clearStandingBallot(cycleId, voter);
        cycleRecord.status = ElectionTypes.ElectionStatus.Voting;

        emit CongressBallotCleared(cycleId, voter, ballotWeight, uint64(block.timestamp), msg.sender);
    }

    /// @inheritdoc ICongressCandidateRegistry
    function finalizeCycle(uint256 cycleId, ElectionTypes.CongressFinalizationInput calldata finalizationInput)
        external
    {
        _requireRegistryAuthority(msg.sender);

        ElectionTypes.CongressCycleRecord storage cycleRecord = _requireOpenCycle(cycleId);
        uint256 candidateCount = _cycleCandidates[cycleId].length;
        if (
            finalizationInput.rankedCandidates.length != candidateCount
                || finalizationInput.rankedVoteTotals.length != candidateCount
        ) {
            revert InvalidFinalizationShape(
                finalizationInput.rankedCandidates.length, finalizationInput.rankedVoteTotals.length
            );
        }
        if (
            finalizationInput.electedCount > cycleRecord.seatCount
                || finalizationInput.runnerUpCount > cycleRecord.runnerUpCount
                || uint256(finalizationInput.electedCount) + uint256(finalizationInput.runnerUpCount) > candidateCount
        ) {
            revert InvalidOutcomeCount(finalizationInput.electedCount, finalizationInput.runnerUpCount, candidateCount);
        }

        delete _electedCandidates[cycleId];
        delete _runnerUpCandidates[cycleId];

        uint64 finalizedAt = uint64(block.timestamp);
        uint256 electedBoundary = finalizationInput.electedCount;
        uint256 runnerUpBoundary = electedBoundary + finalizationInput.runnerUpCount;

        for (uint256 index = 0; index < candidateCount; ++index) {
            address candidate = finalizationInput.rankedCandidates[index];
            ElectionTypes.CongressCandidateRecord storage candidateRecord = _candidateRecords[cycleId][candidate];
            if (candidateRecord.status != ElectionTypes.CandidateStatus.Accepted) {
                revert CandidateNotActive(cycleId, candidate);
            }
            if (candidateRecord.voteTotal != finalizationInput.rankedVoteTotals[index]) {
                revert InvalidVoteSnapshot(
                    cycleId, candidate, finalizationInput.rankedVoteTotals[index], candidateRecord.voteTotal
                );
            }

            ElectionTypes.CandidateStatus status = index < electedBoundary
                ? ElectionTypes.CandidateStatus.Elected
                : index < runnerUpBoundary ? ElectionTypes.CandidateStatus.RunnerUp : ElectionTypes.CandidateStatus.Lost;

            candidateRecord.status = status;
            // forge-lint: disable-next-line(unsafe-typecast)
            candidateRecord.rank = uint32(index + 1);
            candidateRecord.updatedAt = finalizedAt;

            if (status == ElectionTypes.CandidateStatus.Elected) {
                _electedCandidates[cycleId].push(candidate);
            } else if (status == ElectionTypes.CandidateStatus.RunnerUp) {
                _runnerUpCandidates[cycleId].push(candidate);
            }

            emit CongressCandidateRanked(
                cycleId, candidate, status, candidateRecord.rank, candidateRecord.voteTotal, finalizedAt, msg.sender
            );
        }

        cycleRecord.status = ElectionTypes.ElectionStatus.Finalized;
        cycleRecord.finalizedAt = finalizedAt;
        cycleRecord.electedCount = finalizationInput.electedCount;
        cycleRecord.runnerUpSlotCount = finalizationInput.runnerUpCount;

        _activateOfficeTerm(cycleId, finalizationInput.electedCount, finalizationInput.runnerUpCount, finalizedAt);

        emit CongressElectionCycleFinalized(
            cycleId, finalizationInput.electedCount, finalizationInput.runnerUpCount, finalizedAt, msg.sender
        );
    }

    /// @inheritdoc ICongressCandidateRegistry
    function vacateAndFillSeat(address vacatingMember, bool hasReplacement, uint256 runnerUpIndex)
        external
        returns (uint32 seatIndex, address replacementCandidate)
    {
        _requireRegistryAuthority(msg.sender);

        uint32 seatIndexPlusOne = _activeSeatIndexPlusOne[vacatingMember];
        if (seatIndexPlusOne == 0) {
            revert NotActiveCongressMember(vacatingMember);
        }

        seatIndex = seatIndexPlusOne - 1;

        ElectionTypes.CongressOfficeTerm storage currentOfficeTerm = _currentOfficeTerm;
        uint256 cycleId = currentOfficeTerm.cycleId;
        uint64 updatedAt = uint64(block.timestamp);

        delete _activeSeatIndexPlusOne[vacatingMember];
        currentOfficeTerm.occupiedSeatCount -= 1;
        currentOfficeTerm.updatedAt = updatedAt;

        _seatRecords[seatIndex] = ElectionTypes.CongressSeatRecord({
            cycleId: cycleId,
            holder: address(0),
            seatIndex: seatIndex,
            sourceRank: 0,
            filledFromRunnerUp: false,
            assignedAt: 0,
            vacatedAt: updatedAt
        });

        emit CongressSeatVacated(cycleId, seatIndex, vacatingMember, updatedAt, msg.sender);

        // The caller (app) selects the next ELIGIBLE runner-up and passes its index. This lets the app
        // skip runner-ups who have lost candidacy eligibility since finalization, instead of blindly
        // promoting the next in line (M9). hasReplacement == false leaves the seat vacant.
        if (!hasReplacement) {
            emit CongressSeatLeftVacant(cycleId, seatIndex, updatedAt, msg.sender);
            return (seatIndex, address(0));
        }

        if (runnerUpIndex < currentOfficeTerm.nextRunnerUpIndex || runnerUpIndex >= _runnerUpCandidates[cycleId].length)
        {
            revert InvalidRunnerUpIndex(runnerUpIndex);
        }

        replacementCandidate = _runnerUpCandidates[cycleId][runnerUpIndex];
        if (_activeSeatIndexPlusOne[replacementCandidate] != 0) {
            revert CandidateAlreadySeated(replacementCandidate);
        }

        // Consume every runner-up up to and including the chosen one; skipped indices were ineligible.
        // forge-lint: disable-next-line(unsafe-typecast)
        currentOfficeTerm.nextRunnerUpIndex = uint32(runnerUpIndex) + 1;
        currentOfficeTerm.occupiedSeatCount += 1;
        currentOfficeTerm.updatedAt = updatedAt;

        ElectionTypes.CongressCandidateRecord storage candidateRecord = _candidateRecords[cycleId][replacementCandidate];
        candidateRecord.status = ElectionTypes.CandidateStatus.Elected;
        candidateRecord.updatedAt = updatedAt;

        _seatRecords[seatIndex] = ElectionTypes.CongressSeatRecord({
            cycleId: cycleId,
            holder: replacementCandidate,
            seatIndex: seatIndex,
            sourceRank: candidateRecord.rank,
            filledFromRunnerUp: true,
            assignedAt: updatedAt,
            vacatedAt: 0
        });
        _activeSeatIndexPlusOne[replacementCandidate] = seatIndex + 1;

        emit CongressCandidateRanked(
            cycleId,
            replacementCandidate,
            ElectionTypes.CandidateStatus.Elected,
            candidateRecord.rank,
            candidateRecord.voteTotal,
            updatedAt,
            msg.sender
        );
        emit CongressSeatAssigned(
            cycleId, seatIndex, replacementCandidate, candidateRecord.rank, true, updatedAt, msg.sender
        );
    }

    /// @inheritdoc ICongressCandidateRegistry
    function dropStandingBallot(uint256 cycleId, address voter) external {
        _requireRegistryAuthority(msg.sender);
        _requireOpenCycle(cycleId);
        if (voter == address(0)) {
            revert InvalidVoter(voter);
        }

        // Removes a voter's persisted standing ballot and its contribution to the open cycle's candidate
        // tallies. The app gates this on the voter no longer having voting power (welfare/ineligible), so a
        // stake-drawdown voter's frozen weight stops counting in future cycles (M2).
        _clearStandingBallot(cycleId, voter);
    }

    function _activateOfficeTerm(uint256 cycleId, uint32 electedCount, uint32 runnerUpCount, uint64 activatedAt)
        private
    {
        _clearActiveOfficeTerm();

        ElectionTypes.CongressCycleRecord storage cycleRecord = _cycles[cycleId];
        _currentOfficeTerm = ElectionTypes.CongressOfficeTerm({
            cycleId: cycleId,
            seatCount: cycleRecord.seatCount,
            occupiedSeatCount: electedCount,
            runnerUpCount: runnerUpCount,
            nextRunnerUpIndex: 0,
            activatedAt: activatedAt,
            updatedAt: activatedAt
        });

        for (uint32 seatIndex = 0; seatIndex < electedCount; ++seatIndex) {
            address holder = _electedCandidates[cycleId][seatIndex];
            ElectionTypes.CongressCandidateRecord storage candidateRecord = _candidateRecords[cycleId][holder];

            _seatRecords[seatIndex] = ElectionTypes.CongressSeatRecord({
                cycleId: cycleId,
                holder: holder,
                seatIndex: seatIndex,
                sourceRank: candidateRecord.rank,
                filledFromRunnerUp: false,
                assignedAt: activatedAt,
                vacatedAt: 0
            });
            _activeSeatIndexPlusOne[holder] = seatIndex + 1;

            emit CongressSeatAssigned(cycleId, seatIndex, holder, candidateRecord.rank, false, activatedAt, msg.sender);
        }
    }

    function _clearActiveOfficeTerm() private {
        ElectionTypes.CongressOfficeTerm memory currentOfficeTerm = _currentOfficeTerm;
        if (currentOfficeTerm.cycleId == 0) {
            return;
        }

        for (uint32 seatIndex = 0; seatIndex < currentOfficeTerm.seatCount; ++seatIndex) {
            address holder = _seatRecords[seatIndex].holder;
            if (holder != address(0)) {
                delete _activeSeatIndexPlusOne[holder];
            }

            delete _seatRecords[seatIndex];
        }

        delete _currentOfficeTerm;
    }

    function _requireOpenCycle(uint256 cycleId)
        private
        view
        returns (ElectionTypes.CongressCycleRecord storage cycleRecord)
    {
        cycleRecord = _cycles[cycleId];
        if (cycleRecord.cycleId == 0) {
            revert ElectionCycleNotFound(cycleId);
        }
        if (cycleRecord.status == ElectionTypes.ElectionStatus.Finalized) {
            revert ElectionCycleAlreadyFinalized(cycleId);
        }
    }

    function _requireActiveCandidate(uint256 cycleId, address candidate)
        private
        view
        returns (ElectionTypes.CongressCandidateRecord storage candidateRecord)
    {
        candidateRecord = _candidateRecords[cycleId][candidate];
        if (candidateRecord.candidate == address(0)) {
            revert CandidateNotFound(cycleId, candidate);
        }
        if (
            candidateRecord.status != ElectionTypes.CandidateStatus.Accepted
                || _candidateIndexPlusOne[cycleId][candidate] == 0
        ) {
            revert CandidateNotActive(cycleId, candidate);
        }
    }

    function _removeCandidateFromActiveList(uint256 cycleId, address candidate) private {
        uint256 index = _candidateIndexPlusOne[cycleId][candidate] - 1;
        uint256 lastIndex = _cycleCandidates[cycleId].length - 1;

        if (index != lastIndex) {
            address movedCandidate = _cycleCandidates[cycleId][lastIndex];
            _cycleCandidates[cycleId][index] = movedCandidate;
            _candidateIndexPlusOne[cycleId][movedCandidate] = index + 1;
        }

        _cycleCandidates[cycleId].pop();
        delete _candidateIndexPlusOne[cycleId][candidate];
    }

    function _clearStandingBallot(uint256 cycleId, address voter) private {
        ElectionTypes.BallotAllocation[] storage standingAllocations = _standingBallotAllocations[voter];
        uint256 allocationCount = standingAllocations.length;
        if (allocationCount == 0) {
            delete _ballotAllocations[cycleId][voter];
            delete _ballotReceipts[cycleId][voter];
            return;
        }

        uint64 updatedAt = uint64(block.timestamp);
        uint256 ballotWeight = _standingBallotReceipts[voter].ballotWeight;
        for (uint256 index = 0; index < allocationCount; ++index) {
            ElectionTypes.BallotAllocation storage allocation = standingAllocations[index];
            _standingVoteTotals[allocation.candidate] -= allocation.amount;
            _syncActiveCandidateVoteTotal(cycleId, allocation.candidate);
        }

        delete _standingBallotAllocations[voter];
        delete _standingBallotReceipts[voter];
        delete _ballotAllocations[cycleId][voter];
        delete _ballotReceipts[cycleId][voter];

        emit CongressStandingBallotCleared(voter, ballotWeight, updatedAt, msg.sender);
    }

    function _storeBallotAllocations(
        BallotConfig memory config,
        address[] calldata candidates,
        int256[] calldata allocations
    ) private returns (BallotTotals memory totals) {
        for (uint256 index = 0; index < config.allocationCount; ++index) {
            address candidate = candidates[index];
            int256 allocation = allocations[index];
            if (allocation == 0 || allocation == type(int256).min) {
                revert InvalidSignedAllocation(candidate, allocation);
            }

            _requireUniqueCandidate(config.cycleId, config.voter, candidates, index, candidate);
            totals =
                _applyBallotAllocation(config.cycleId, config.voter, candidate, allocation, totals, config.updatedAt);
        }

        if (totals.positiveCandidateCount > config.maxPositiveCandidates) {
            revert InvalidPositiveCandidateCount(totals.positiveCandidateCount, config.maxPositiveCandidates);
        }
        if (totals.negativeAllocationTotal > config.maxNegativeAllocation) {
            revert InvalidNegativeAllocation(totals.negativeAllocationTotal, config.maxNegativeAllocation);
        }
        if (totals.totalAllocation != config.ballotWeight) {
            revert InvalidTotalAllocation(totals.totalAllocation, config.ballotWeight);
        }
    }

    function _storeBallotReceipt(
        ElectionTypes.CongressCycleRecord storage cycleRecord,
        BallotConfig memory config,
        BallotTotals memory totals
    ) private {
        _ballotReceipts[config.cycleId][config.voter] = ElectionTypes.BallotReceipt({
            cycleId: config.cycleId,
            voter: config.voter,
            ballotWeight: config.ballotWeight,
            positiveAllocationTotal: totals.positiveAllocationTotal,
            negativeAllocationTotal: totals.negativeAllocationTotal,
            allocationCount: uint32(config.allocationCount),
            updatedAt: config.updatedAt
        });
        _standingBallotReceipts[config.voter] = ElectionTypes.BallotReceipt({
            cycleId: 0,
            voter: config.voter,
            ballotWeight: config.ballotWeight,
            positiveAllocationTotal: totals.positiveAllocationTotal,
            negativeAllocationTotal: totals.negativeAllocationTotal,
            allocationCount: uint32(config.allocationCount),
            updatedAt: config.updatedAt
        });
        cycleRecord.status = ElectionTypes.ElectionStatus.Voting;

        emit CongressBallotRecorded(
            config.cycleId,
            config.voter,
            config.ballotWeight,
            totals.positiveAllocationTotal,
            totals.negativeAllocationTotal,
            uint32(config.allocationCount),
            config.updatedAt,
            msg.sender
        );
        emit CongressStandingBallotUpdated(
            config.voter,
            config.ballotWeight,
            totals.positiveAllocationTotal,
            totals.negativeAllocationTotal,
            uint32(config.allocationCount),
            config.updatedAt,
            msg.sender
        );
    }

    function _requireUniqueCandidate(
        uint256 cycleId,
        address voter,
        address[] calldata candidates,
        uint256 index,
        address candidate
    ) private pure {
        for (uint256 inner = 0; inner < index; ++inner) {
            if (candidates[inner] == candidate) {
                revert DuplicateBallotCandidate(cycleId, voter, candidate);
            }
        }
    }

    function _applyBallotAllocation(
        uint256 cycleId,
        address voter,
        address candidate,
        int256 allocation,
        BallotTotals memory totals,
        uint64 updatedAt
    ) private returns (BallotTotals memory updatedTotals) {
        ElectionTypes.CongressCandidateRecord storage candidateRecord = _requireActiveCandidate(cycleId, candidate);
        uint256 absoluteAllocation = _absoluteValue(allocation);
        updatedTotals = totals;
        updatedTotals.totalAllocation += absoluteAllocation;

        if (allocation > 0) {
            updatedTotals.positiveAllocationTotal += absoluteAllocation;
            updatedTotals.positiveCandidateCount += 1;
        } else {
            updatedTotals.negativeAllocationTotal += absoluteAllocation;
        }

        int256 newVoteTotal = _standingVoteTotals[candidate] + allocation;
        _standingVoteTotals[candidate] = newVoteTotal;
        candidateRecord.voteTotal = newVoteTotal;
        _ballotAllocations[cycleId][voter].push(
            ElectionTypes.BallotAllocation({candidate: candidate, amount: allocation})
        );
        _standingBallotAllocations[voter].push(
            ElectionTypes.BallotAllocation({candidate: candidate, amount: allocation})
        );

        emit CongressBallotAllocationRecorded(
            cycleId, voter, candidate, allocation, candidateRecord.voteTotal, updatedAt, msg.sender
        );
    }

    function _absoluteValue(int256 value) private pure returns (uint256 amount) {
        if (value > 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            return uint256(value);
        }

        // `type(int256).min` is rejected before allocation storage because it cannot be negated.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(-value);
    }

    function _syncActiveCandidateVoteTotal(uint256 cycleId, address candidate) private {
        ElectionTypes.CongressCandidateRecord storage candidateRecord = _candidateRecords[cycleId][candidate];
        if (
            candidateRecord.candidate != address(0) && candidateRecord.status == ElectionTypes.CandidateStatus.Accepted
                && _candidateIndexPlusOne[cycleId][candidate] != 0
        ) {
            candidateRecord.voteTotal = _standingVoteTotals[candidate];
        }
    }

    function _requireRegistryAuthority(address caller) private view {
        // L7: resolve the primary authority through the same try/catch used for the setup-authority fallback so
        // that an unregistered CONGRESS_CANDIDATE_REGISTRY_AUTHORITY does not brick every write (or its fallback).
        if (_isModuleCaller(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, caller)) {
            return;
        }
        if (_isModuleCaller(KernelModuleIds.INITIAL_SETUP_AUTHORITY, caller)) {
            return;
        }

        revert UnauthorizedCongressCandidateRegistryCaller(caller);
    }
}
