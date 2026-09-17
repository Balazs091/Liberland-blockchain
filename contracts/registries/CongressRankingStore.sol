// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ICongressRankingStore} from "../interfaces/ICongressRankingStore.sol";
import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {ElectionTypes} from "../types/ElectionTypes.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @notice Derived ranking storage, created once by its registry and gated by that registry's governed authority.
///         There is no owner key, pointer update, arbitrary call, or independent upgrade surface.
contract CongressRankingStore is ICongressRankingStore {
    struct Entry {
        address candidate;
        int256 votes;
        uint64 appliedAt;
        bytes32 personId;
    }

    struct State {
        uint256 total;
        uint256 processed;
        uint256 slots;
        bool started;
        Entry[] heap;
        Entry[] selected;
    }
    /// @inheritdoc ICongressRankingStore
    address public immutable registry;
    mapping(uint256 cycleId => State state) private _states;
    /// @inheritdoc ICongressRankingStore
    mapping(uint256 cycleId => mapping(address candidate => bool)) public disqualified;

    constructor() {
        registry = msg.sender;
    }

    /// @inheritdoc ICongressRankingStore
    function finalizationInput(uint256 cycleId)
        external
        view
        returns (ElectionTypes.CongressFinalizationInput memory input)
    {
        State storage s = _states[cycleId];
        ElectionTypes.CongressCycleRecord memory cycle = ICongressCandidateRegistry(registry).getCycle(cycleId);
        uint256 selectedCount = s.selected.length;
        if (!s.started || s.processed != s.total || (selectedCount < s.slots && s.heap.length != 0)) {
            revert ICongressCandidateRegistry.FinalizationNotReady(cycleId);
        }
        input.rankedCandidates = new address[](selectedCount);
        input.rankedVoteTotals = new int256[](selectedCount);
        for (uint256 i; i < selectedCount; ++i) {
            input.rankedCandidates[i] = s.selected[i].candidate;
            input.rankedVoteTotals[i] = s.selected[i].votes;
        }
        // The immutable helper enforces at most 32 selected entries.
        input.electedCount = selectedCount < cycle.seatCount ? uint32(selectedCount) : cycle.seatCount;
        input.runnerUpCount = uint32(selectedCount) - input.electedCount;
    }

    modifier onlyRegistryAuthority(uint256 cycleId) {
        ICongressCandidateRegistry source = ICongressCandidateRegistry(registry);
        if (
            msg.sender
                != IConstitutionKernel(source.kernel()).getModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY)
        ) revert RegistryOnly();
        ElectionTypes.CongressCycleRecord memory cycle = source.getCycle(cycleId);
        if (
            cycle.cycleId == 0 || cycle.status == ElectionTypes.ElectionStatus.Finalized
                || block.timestamp < cycle.votingEnd
        ) revert RankingNotReady();
        _;
    }

    /// @inheritdoc ICongressRankingStore
    function progress(uint256 cycleId) external view returns (ElectionTypes.FinalizationProgress memory) {
        State storage s = _states[cycleId];
        return ElectionTypes.FinalizationProgress(s.total, s.processed, s.heap.length, s.selected.length, s.started);
    }

    /// @inheritdoc ICongressRankingStore
    function process(uint256 cycleId, uint256 maxCount) external onlyRegistryAuthority(cycleId) {
        ICongressCandidateRegistry source = ICongressCandidateRegistry(registry);
        ElectionTypes.CongressCycleRecord memory cycle = source.getCycle(cycleId);
        uint256 total = source.getCycleCandidateCount(cycleId);
        uint256 slots = uint256(cycle.seatCount) + cycle.runnerUpCount;
        if (maxCount == 0 || maxCount > 32 || slots == 0 || slots > 32) revert RankingNotReady();
        State storage s = _states[cycleId];
        if (!s.started) {
            s.started = true;
            s.total = total;
            s.slots = slots;
        }
        if (total != s.total || slots != s.slots) revert RankingNotReady();
        uint256 end = s.processed + maxCount;
        if (end > total) end = total;
        for (uint256 i = s.processed; i < end; ++i) {
            _insertCandidate(cycleId, i);
        }
        s.processed = end;
        emit CongressRankingProgress(cycleId, end, total);
    }

    function _insertCandidate(uint256 cycleId, uint256 index) private {
        ICongressCandidateRegistry source = ICongressCandidateRegistry(registry);
        Entry memory entry = Entry({
            candidate: source.getCycleCandidateAt(cycleId, index), votes: 0, appliedAt: 0, personId: bytes32(0)
        });
        (entry.votes, entry.appliedAt, entry.personId) = source.getCandidateRankingData(cycleId, entry.candidate);
        if (entry.votes >= 0) _insert(_states[cycleId].heap, entry);
    }

    /// @inheritdoc ICongressRankingStore
    function peek(uint256 cycleId) external view returns (address candidate, bytes32 personId) {
        Entry[] storage heap = _states[cycleId].heap;
        if (heap.length != 0) return (heap[0].candidate, heap[0].personId);
    }

    /// @inheritdoc ICongressRankingStore
    function consider(uint256 cycleId, bool eligible)
        external
        onlyRegistryAuthority(cycleId)
        returns (address candidate)
    {
        State storage s = _states[cycleId];
        if (!s.started || s.processed != s.total || s.heap.length == 0) revert RankingNotReady();
        Entry memory entry = _pop(s.heap);
        candidate = entry.candidate;
        if (eligible) {
            if (s.selected.length >= s.slots) revert RankingNotReady();
            s.selected.push(entry);
        } else {
            disqualified[cycleId][candidate] = true;
        }
        emit CongressCandidateConsidered(cycleId, candidate, eligible);
    }

    /// @inheritdoc ICongressRankingStore
    function selectedAt(uint256 cycleId, uint256 index) external view returns (address candidate, bytes32 personId) {
        Entry storage entry = _states[cycleId].selected[index];
        return (entry.candidate, entry.personId);
    }

    /// @inheritdoc ICongressRankingStore
    function removeSelected(uint256 cycleId, uint256 index)
        external
        onlyRegistryAuthority(cycleId)
        returns (address candidate)
    {
        Entry[] storage selected = _states[cycleId].selected;
        candidate = selected[index].candidate;
        for (uint256 i = index; i + 1 < selected.length; ++i) {
            selected[i] = selected[i + 1];
        }
        selected.pop();
        disqualified[cycleId][candidate] = true;
        emit CongressCandidateConsidered(cycleId, candidate, false);
    }

    function _insert(Entry[] storage heap, Entry memory entry) private {
        // Reserve the new leaf. Each displaced parent or final entry is then written exactly once.
        heap.push();
        uint256 position = heap.length - 1;
        while (position != 0) {
            uint256 parent = (position - 1) / 2;
            if (!_ahead(entry, heap[parent])) break;
            heap[position] = heap[parent];
            position = parent;
        }
        heap[position] = entry;
    }

    function _pop(Entry[] storage heap) private returns (Entry memory candidate) {
        candidate = heap[0];
        Entry memory last = heap[heap.length - 1];
        heap.pop();
        if (heap.length == 0) return candidate;
        uint256 position;
        while (2 * position + 1 < heap.length) {
            uint256 child = 2 * position + 1;
            if (child + 1 < heap.length && _ahead(heap[child + 1], heap[child])) ++child;
            if (!_ahead(heap[child], last)) break;
            heap[position] = heap[child];
            position = child;
        }
        heap[position] = last;
    }

    function _ahead(Entry memory left, Entry memory right) private pure returns (bool) {
        if (left.votes != right.votes) return left.votes > right.votes;
        if (left.appliedAt != right.appliedAt) return left.appliedAt < right.appliedAt;
        return uint160(left.candidate) < uint160(right.candidate);
    }
}
