// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {TimedRestrictionSet} from "../../contracts/libraries/TimedRestrictionSet.sol";

contract TimedRestrictionSetHarness {
    using TimedRestrictionSet for TimedRestrictionSet.Set;

    mapping(uint256 namespace => TimedRestrictionSet.Set set) private _sets;

    function add(uint256 namespace, bytes32 id, uint64 expiry, bool indefinite) external {
        _sets[namespace].add(id, expiry, indefinite);
    }

    function remove(uint256 namespace, bytes32 id) external returns (TimedRestrictionSet.Entry memory) {
        return _sets[namespace].remove(id);
    }

    function contains(uint256 namespace, bytes32 id) external view returns (bool) {
        return _sets[namespace].contains(id);
    }

    function length(uint256 namespace) external view returns (uint256) {
        return _sets[namespace].length();
    }

    function get(uint256 namespace, bytes32 id) external view returns (bool, TimedRestrictionSet.Entry memory) {
        return _sets[namespace].get(id);
    }

    function latest(uint256 namespace) external view returns (bool, TimedRestrictionSet.Entry memory) {
        return _sets[namespace].latest();
    }

    function restrictedAt(uint256 namespace, uint256 timestamp) external view returns (bool) {
        return _sets[namespace].isRestrictedAt(timestamp);
    }

    function verifyIndicesAndOrder(uint256 namespace) external view returns (bool) {
        TimedRestrictionSet.Set storage set = _sets[namespace];
        for (uint256 i; i < set.heap.length; ++i) {
            TimedRestrictionSet.Entry memory entry = set.heap[i];
            if (set.positions[entry.orderId] != i + 1) return false;
            if (i == 0) continue;
            TimedRestrictionSet.Entry memory parent = set.heap[(i - 1) / 2];
            if (entry.indefinite != parent.indefinite) {
                if (entry.indefinite) return false;
            } else if (entry.expiresAt > parent.expiresAt) {
                return false;
            } else if (entry.expiresAt == parent.expiresAt && entry.orderId > parent.orderId) {
                return false;
            }
        }
        return true;
    }
}

/// @dev Independent linear baseline: O(1) add/remove, O(n) latest-expiry summary, same entry storage fields.
contract ScanningRestrictionSetHarness {
    TimedRestrictionSet.Entry[] private _entries;
    mapping(bytes32 id => uint256 indexPlusOne) private _positions;

    function add(bytes32 id, uint64 expiry, bool indefinite) external {
        require(id != bytes32(0) && _positions[id] == 0);
        require((indefinite && expiry == 0) || (!indefinite && expiry != 0));
        _entries.push(TimedRestrictionSet.Entry(id, expiry, indefinite));
        _positions[id] = _entries.length;
    }

    function remove(bytes32 id) external {
        uint256 position = _positions[id];
        require(position != 0);
        uint256 index = position - 1;
        uint256 last = _entries.length - 1;
        if (index != last) {
            _entries[index] = _entries[last];
            _positions[_entries[index].orderId] = position;
        }
        _entries.pop();
        delete _positions[id];
    }

    function latest() external view returns (bool exists, TimedRestrictionSet.Entry memory entry) {
        for (uint256 i; i < _entries.length; ++i) {
            TimedRestrictionSet.Entry memory candidate = _entries[i];
            if (
                !exists || (candidate.indefinite && !entry.indefinite)
                    || (candidate.indefinite == entry.indefinite
                        && (candidate.expiresAt > entry.expiresAt
                            || (candidate.expiresAt == entry.expiresAt && candidate.orderId > entry.orderId)))
            ) {
                exists = true;
                entry = candidate;
            }
        }
    }
}

contract TimedRestrictionSetTest is Test {
    TimedRestrictionSetHarness private _set;

    struct OracleEntry {
        uint64 expiry;
        bool indefinite;
        bool present;
    }

    function setUp() public {
        _set = new TimedRestrictionSetHarness();
    }

    function testEmptySetHasExplicitAbsence() public view {
        (bool exists, TimedRestrictionSet.Entry memory entry) = _set.latest(0);
        assertFalse(exists);
        assertEq(entry.orderId, bytes32(0));
        assertEq(_set.length(0), 0);
        assertFalse(_set.restrictedAt(0, 0));
        assertFalse(_set.restrictedAt(0, type(uint256).max));
        (exists, entry) = _set.get(0, bytes32(0));
        assertFalse(exists);
        assertEq(entry.expiresAt, 0);
        assertFalse(entry.indefinite);
    }

    function testRejectsZeroIdAndAmbiguousExpiryForms() public {
        vm.expectRevert(TimedRestrictionSet.InvalidOrderId.selector);
        _set.add(0, bytes32(0), 1, false);
        vm.expectRevert(abi.encodeWithSelector(TimedRestrictionSet.InvalidExpiry.selector, uint64(0), false));
        _set.add(0, _id(1), 0, false);
        vm.expectRevert(abi.encodeWithSelector(TimedRestrictionSet.InvalidExpiry.selector, uint64(9), true));
        _set.add(0, _id(1), 9, true);
        assertEq(_set.length(0), 0);
    }

    function testDuplicateAndAbsentRemovalRevert() public {
        _set.add(0, _id(1), 20, false);
        vm.expectRevert(abi.encodeWithSelector(TimedRestrictionSet.OrderAlreadyPresent.selector, _id(1)));
        _set.add(0, _id(1), 30, false);
        vm.expectRevert(abi.encodeWithSelector(TimedRestrictionSet.OrderNotPresent.selector, _id(2)));
        _set.remove(0, _id(2));
        vm.expectRevert(abi.encodeWithSelector(TimedRestrictionSet.OrderNotPresent.selector, bytes32(0)));
        _set.remove(0, bytes32(0));
        _assertLatest(0, _id(1), 20, false);
    }

    function testExpiryIsExclusiveAndNoCleanupIsRequired() public {
        _set.add(0, _id(1), 10, false);
        _set.add(0, _id(2), 20, false);
        assertTrue(_set.restrictedAt(0, 9));
        assertTrue(_set.restrictedAt(0, 10));
        assertTrue(_set.restrictedAt(0, 19));
        assertFalse(_set.restrictedAt(0, 20));
        assertFalse(_set.restrictedAt(0, type(uint256).max));
        assertEq(_set.length(0), 2);
        assertTrue(_set.contains(0, _id(1)));
        _assertLatest(0, _id(2), 20, false);
    }

    function testIndefiniteIsExplicitAndOutranksMaximumFiniteTime() public {
        _set.add(0, _id(2), type(uint64).max, false);
        _set.add(0, _id(1), 0, true);
        _assertLatest(0, _id(1), 0, true);
        assertTrue(_set.restrictedAt(0, type(uint256).max));
        _set.remove(0, _id(1));
        assertTrue(_set.restrictedAt(0, uint256(type(uint64).max) - 1));
        assertFalse(_set.restrictedAt(0, type(uint64).max));
    }

    function testNamespacesDoNotShareMembershipOrRemoveEachOther() public {
        _set.add(0, _id(1), 10, false);
        _set.add(1, _id(1), 0, true);
        _set.remove(0, _id(1));
        assertFalse(_set.contains(0, _id(1)));
        _assertLatest(1, _id(1), 0, true);
    }

    function testRemovingLaterOrderRevealsEarlierOrderAndStayCanResume() public {
        _set.add(0, _id(1), 10, false);
        _set.add(0, _id(2), 20, false);
        _set.add(1, _id(3), 30, false);
        TimedRestrictionSet.Entry memory stayed = _set.remove(0, _id(2));
        _assertLatest(0, _id(1), 10, false);
        assertFalse(_set.restrictedAt(0, 10));
        assertTrue(_set.restrictedAt(1, 10));
        _set.add(0, stayed.orderId, stayed.expiresAt, stayed.indefinite);
        assertTrue(_set.restrictedAt(0, 10));
        _set.remove(0, _id(1));
        _assertLatest(0, _id(2), 20, false);
    }

    function testEqualExpiryAndMultipleIndefiniteEntriesRemainIndependent() public {
        _set.add(0, _id(1), 10, false);
        _set.add(0, _id(3), 10, false);
        _set.add(0, _id(2), 0, true);
        _set.add(0, _id(4), 0, true);
        _assertLatest(0, _id(4), 0, true);
        _set.remove(0, _id(4));
        _assertLatest(0, _id(2), 0, true);
        _set.remove(0, _id(2));
        _assertLatest(0, _id(3), 10, false);
        _set.remove(0, _id(3));
        _assertLatest(0, _id(1), 10, false);
    }

    function testRootInteriorAndLeafDeletionMaintainEveryIndex() public {
        for (uint256 i = 1; i <= 32; ++i) {
            _set.add(0, _id(i), uint64((i * 71) % 131 + 1), false);
        }
        uint256[8] memory removals = [uint256(24), 1, 32, 13, 4, 19, 7, 16];
        for (uint256 i; i < removals.length; ++i) {
            _set.remove(0, _id(removals[i]));
            assertFalse(_set.contains(0, _id(removals[i])));
            assertTrue(_set.verifyIndicesAndOrder(0));
        }
        for (uint256 i = 1; i <= 32; ++i) {
            if (_set.contains(0, _id(i))) _set.remove(0, _id(i));
            assertTrue(_set.verifyIndicesAndOrder(0));
        }
        assertEq(_set.length(0), 0);
        _set.add(0, _id(1), 1, false);
        _assertLatest(0, _id(1), 1, false);
    }

    function testArbitraryRemovalCanRequireUpwardRepair() public {
        uint64[15] memory expiries = [uint64(100), 50, 90, 40, 45, 80, 85, 10, 20, 30, 35, 70, 75, 60, 65];
        for (uint256 i; i < expiries.length; ++i) {
            _set.add(0, _id(i + 1), expiries[i], false);
        }
        // Removing expiry 10 moves the final expiry 65 below 40, requiring upward rather than downward repair.
        _set.remove(0, _id(8));
        assertTrue(_set.verifyIndicesAndOrder(0));
        assertEq(_set.length(0), 14);
        _assertLatest(0, _id(1), 100, false);
        for (uint256 i; i < expiries.length; ++i) {
            (bool exists, TimedRestrictionSet.Entry memory entry) = _set.get(0, _id(i + 1));
            assertEq(exists, i != 7);
            if (exists) assertEq(entry.expiresAt, expiries[i]);
        }
    }

    /// @dev Independent array oracle scans each namespace, not a copy of heap insertion/removal logic.
    function testFuzzDifferentialStatefulOperations(uint256 seed) public {
        OracleEntry[64] memory oracle;
        for (uint256 step; step < 128; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            uint256 namespace = (seed >> 8) % 2;
            uint256 index = (seed >> 16) % 32;
            uint256 oracleIndex = namespace * 32 + index;
            bytes32 id = _id(index + 1);
            uint256 operation = seed % 4;
            OracleEntry memory prior = oracle[oracleIndex];
            if (operation == 0) {
                bool indefinite = ((seed >> 32) % 8) == 0;
                uint64 expiry = indefinite ? 0 : uint64((seed >> 40) % 1_024 + 1);
                if (prior.present) {
                    vm.expectRevert(abi.encodeWithSelector(TimedRestrictionSet.OrderAlreadyPresent.selector, id));
                } else {
                    oracle[oracleIndex] = OracleEntry(expiry, indefinite, true);
                }
                _set.add(namespace, id, expiry, indefinite);
            } else if (operation == 1) {
                if (!prior.present) {
                    vm.expectRevert(abi.encodeWithSelector(TimedRestrictionSet.OrderNotPresent.selector, id));
                } else {
                    oracle[oracleIndex].present = false;
                }
                _set.remove(namespace, id);
            } else if (operation == 2 && prior.present) {
                _set.remove(namespace, id);
                oracle[oracleIndex].present = false;
                _assertOracle(oracle, namespace, (seed >> 64) % 1_025);
                if (((seed >> 24) & 1) == 1) {
                    _set.add(namespace, id, prior.expiry, prior.indefinite);
                    oracle[oracleIndex].present = true;
                }
            }
            _assertOracle(oracle, namespace, (seed >> 64) % 1_025);
        }
        _assertOracle(oracle, 0, type(uint256).max);
        _assertOracle(oracle, 1, type(uint256).max);
    }

    function _assertOracle(OracleEntry[64] memory oracle, uint256 namespace, uint256 timestamp) private view {
        uint256 count;
        bool expectedRestricted;
        bool hasIndefinite;
        uint64 latestFinite;
        for (uint256 i; i < 32; ++i) {
            OracleEntry memory expected = oracle[namespace * 32 + i];
            (bool entryExists, TimedRestrictionSet.Entry memory actual) = _set.get(namespace, _id(i + 1));
            assertEq(entryExists, expected.present);
            assertEq(_set.contains(namespace, _id(i + 1)), expected.present);
            if (!expected.present) {
                assertEq(actual.orderId, bytes32(0));
                continue;
            }
            ++count;
            assertEq(actual.orderId, _id(i + 1));
            assertEq(actual.expiresAt, expected.expiry);
            assertEq(actual.indefinite, expected.indefinite);
            if (expected.indefinite) hasIndefinite = true;
            if (expected.expiry > latestFinite) latestFinite = expected.expiry;
            if (expected.indefinite || timestamp < expected.expiry) expectedRestricted = true;
        }
        assertEq(_set.length(namespace), count);
        assertEq(_set.restrictedAt(namespace, timestamp), expectedRestricted);
        (bool exists, TimedRestrictionSet.Entry memory latest) = _set.latest(namespace);
        assertEq(exists, count != 0);
        if (exists) {
            assertEq(latest.indefinite, hasIndefinite);
            assertEq(latest.expiresAt, hasIndefinite ? 0 : latestFinite);
        }
        assertTrue(_set.verifyIndicesAndOrder(namespace));
    }

    function _assertLatest(uint256 namespace, bytes32 id, uint64 expiry, bool indefinite) private view {
        (bool exists, TimedRestrictionSet.Entry memory entry) = _set.latest(namespace);
        assertTrue(exists);
        assertEq(entry.orderId, id);
        assertEq(entry.expiresAt, expiry);
        assertEq(entry.indefinite, indefinite);
        assertTrue(_set.verifyIndicesAndOrder(namespace));
    }

    function _id(uint256 id) private pure returns (bytes32) {
        return bytes32(id);
    }
}

/// @dev Fixtures are committed by setUp before each test. Measurements include an external harness call and
///      execution work, not full transaction receipts/refunds. vm.coolSlot resets each observed fixture slot.
contract TimedRestrictionSetGasTest is Test {
    TimedRestrictionSetHarness[3] private _heaps;
    ScanningRestrictionSetHarness[3] private _scans;
    mapping(address target => bytes32[] slots) private _reads;
    mapping(address target => bytes32[] slots) private _writes;

    function setUp() public {
        uint256[3] memory sizes = [uint256(8), 64, 256];
        vm.record();
        for (uint256 fixture; fixture < sizes.length; ++fixture) {
            TimedRestrictionSetHarness heap = new TimedRestrictionSetHarness();
            ScanningRestrictionSetHarness scan = new ScanningRestrictionSetHarness();
            _heaps[fixture] = heap;
            _scans[fixture] = scan;
            for (uint256 i = 1; i <= sizes[fixture]; ++i) {
                heap.add(0, bytes32(i), uint64(i + 1_000), false);
                scan.add(bytes32(i), uint64(i + 1_000), false);
            }
            (_reads[address(heap)], _writes[address(heap)]) = vm.accesses(address(heap));
            (_reads[address(scan)], _writes[address(scan)]) = vm.accesses(address(scan));
        }
    }

    function testGasColdPersistedReadAndAdd8() public {
        _measureReadAndAdd(0, 8);
    }

    function testGasColdPersistedReadAndAdd64() public {
        _measureReadAndAdd(1, 64);
    }

    function testGasColdPersistedReadAndAdd256() public {
        _measureReadAndAdd(2, 256);
    }

    function testGasColdPersistedRemoval8() public {
        _measureRemoval(0, 8);
    }

    function testGasColdPersistedRemoval64() public {
        _measureRemoval(1, 64);
    }

    function testGasColdPersistedRemoval256() public {
        _measureRemoval(2, 256);
    }

    function _measureReadAndAdd(uint256 fixture, uint256 size) private {
        TimedRestrictionSetHarness heap = _heaps[fixture];
        ScanningRestrictionSetHarness scan = _scans[fixture];
        _coolFixture(address(heap));
        uint256 before = gasleft();
        (bool heapExists, TimedRestrictionSet.Entry memory heapEntry) = heap.latest(0);
        uint256 heapRead = before - gasleft();
        _coolFixture(address(scan));
        before = gasleft();
        (bool scanExists, TimedRestrictionSet.Entry memory scanEntry) = scan.latest();
        uint256 scanRead = before - gasleft();
        assertTrue(heapExists && scanExists);
        assertEq(heapEntry.orderId, scanEntry.orderId);
        assertEq(heapEntry.expiresAt, scanEntry.expiresAt);
        assertLt(heapRead, scanRead);
        emit log_named_uint("persisted entries", size);
        emit log_named_uint("cold latest heap execution gas", heapRead);
        emit log_named_uint("cold latest scan execution gas", scanRead);

        _coolFixture(address(heap));
        before = gasleft();
        heap.add(0, bytes32(size + 1), uint64(size + 2_000), false);
        emit log_named_uint("cold add heap execution gas", before - gasleft());
        _coolFixture(address(scan));
        before = gasleft();
        scan.add(bytes32(size + 1), uint64(size + 2_000), false);
        emit log_named_uint("cold add scan execution gas", before - gasleft());
    }

    function _measureRemoval(uint256 fixture, uint256 size) private {
        TimedRestrictionSetHarness heap = _heaps[fixture];
        ScanningRestrictionSetHarness scan = _scans[fixture];
        emit log_named_uint("persisted entries", size);
        _coolFixture(address(heap));
        uint256 before = gasleft();
        heap.remove(0, bytes32(size));
        emit log_named_uint("cold remove-root heap execution gas", before - gasleft());
        _coolFixture(address(scan));
        before = gasleft();
        scan.remove(bytes32(size));
        emit log_named_uint("cold remove scan execution gas", before - gasleft());
    }

    function _coolFixture(address target) private {
        bytes32[] storage reads = _reads[target];
        bytes32[] storage writes = _writes[target];
        for (uint256 i; i < reads.length; ++i) {
            vm.coolSlot(target, reads[i]);
        }
        for (uint256 i; i < writes.length; ++i) {
            vm.coolSlot(target, writes[i]);
        }
        vm.cool(target);
    }
}
