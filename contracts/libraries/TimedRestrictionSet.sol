// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

/// @title TimedRestrictionSet
/// @notice Indexed maximum-expiry set for restrictions that are already effective and combine by logical OR.
/// @dev Internal-only mechanical primitive, with no authority, legal rules, activation scheduling or deployment.
///      Consumers own one set per independent permission/subject and handle stays by removing/re-adding entries.
///      Reads never require expired-entry cleanup. Insertion and arbitrary removal take O(log n) storage work;
///      latest-expiry and current-restriction reads take O(1). Consumers must not insert future-start restrictions.
///      This set does not certify historical electorate aggregates or prove that any restriction is authorised.
library TimedRestrictionSet {
    error InvalidOrderId();
    error InvalidExpiry(uint64 expiresAt, bool indefinite);
    error OrderAlreadyPresent(bytes32 orderId);
    error OrderNotPresent(bytes32 orderId);

    struct Entry {
        bytes32 orderId;
        uint64 expiresAt;
        bool indefinite;
    }

    struct Set {
        Entry[] heap;
        mapping(bytes32 orderId => uint256 indexPlusOne) positions;
    }

    /// @notice Adds a unique, nonzero order identifier to this set.
    /// @param self The consumer-owned set.
    /// @param orderId Identifier unique within this set; other sets may reuse it.
    /// @param expiresAt Nonzero exclusive end timestamp for finite entries, zero for indefinite entries.
    /// @param indefinite True only for entries without a finite expiry; zero has no implicit indefinite meaning.
    /// @dev Expired finite entries are allowed; effective-start checks and authorisation belong to the consumer.
    function add(Set storage self, bytes32 orderId, uint64 expiresAt, bool indefinite) internal {
        if (orderId == bytes32(0)) revert InvalidOrderId();
        if ((indefinite && expiresAt != 0) || (!indefinite && expiresAt == 0)) {
            revert InvalidExpiry(expiresAt, indefinite);
        }
        if (self.positions[orderId] != 0) revert OrderAlreadyPresent(orderId);
        uint256 index = self.heap.length;
        self.heap.push(Entry(orderId, expiresAt, indefinite));
        self.positions[orderId] = index + 1;
        _siftUp(self, index);
    }

    /// @notice Physically removes an existing order, including an expired or indefinite order.
    /// @param self The consumer-owned set.
    /// @param orderId The order to remove; absent orders revert without changing the set.
    /// @return removed The removed entry, available for a consumer to retain as separate case/order provenance.
    function remove(Set storage self, bytes32 orderId) internal returns (Entry memory removed) {
        uint256 position = self.positions[orderId];
        if (position == 0) revert OrderNotPresent(orderId);
        uint256 index = position - 1;
        uint256 lastIndex = self.heap.length - 1;
        removed = self.heap[index];
        if (index != lastIndex) {
            Entry memory replacement = self.heap[lastIndex];
            self.heap[index] = replacement;
            self.positions[replacement.orderId] = position;
        }
        self.heap.pop();
        delete self.positions[orderId];

        if (index < self.heap.length) {
            if (index != 0 && _higher(self.heap[index], self.heap[(index - 1) / 2])) {
                _siftUp(self, index);
            } else {
                _siftDown(self, index);
            }
        }
    }

    /// @notice Returns whether an order is present, irrespective of expiry.
    function contains(Set storage self, bytes32 orderId) internal view returns (bool) {
        return self.positions[orderId] != 0;
    }

    /// @notice Returns the stored entry count, including expired entries not explicitly removed by the consumer.
    function length(Set storage self) internal view returns (uint256) {
        return self.heap.length;
    }

    /// @notice Retrieves an order without scanning; absence is explicit and returns a zero-initialised entry.
    function get(Set storage self, bytes32 orderId) internal view returns (bool exists, Entry memory entry) {
        uint256 position = self.positions[orderId];
        if (position == 0) return (false, entry);
        return (true, self.heap[position - 1]);
    }

    /// @notice Returns the maximum entry, or explicit absence for an empty set.
    /// @dev Indefinite entries outrank all finite entries. Equal expiries are ordered by descending orderId.
    ///      Presence does not imply currently restricted: the returned finite expiry may already have passed.
    function latest(Set storage self) internal view returns (bool exists, Entry memory entry) {
        if (self.heap.length == 0) return (false, entry);
        return (true, self.heap[0]);
    }

    /// @notice Evaluates the OR of all already-effective restrictions at a supplied timestamp.
    /// @param timestamp Timestamp to compare to exclusive finite expiry; equality is not restricted.
    /// @dev This is not a historical lookup: removals/stays have already changed the set. It is a pure time
    ///      predicate over its current entries. An indefinite entry remains restricted at every timestamp.
    function isRestrictedAt(Set storage self, uint256 timestamp) internal view returns (bool) {
        if (self.heap.length == 0) return false;
        Entry storage root = self.heap[0];
        return root.indefinite || timestamp < uint256(root.expiresAt);
    }

    function _siftUp(Set storage self, uint256 index) private {
        Entry memory entry = self.heap[index];
        uint256 originalIndex = index;
        while (index != 0) {
            uint256 parentIndex = (index - 1) / 2;
            Entry memory parent = self.heap[parentIndex];
            if (!_higher(entry, parent)) break;
            self.heap[index] = parent;
            self.positions[parent.orderId] = index + 1;
            index = parentIndex;
        }
        if (index != originalIndex) {
            self.heap[index] = entry;
            self.positions[entry.orderId] = index + 1;
        }
    }

    function _siftDown(Set storage self, uint256 index) private {
        Entry memory entry = self.heap[index];
        uint256 originalIndex = index;
        uint256 count = self.heap.length;
        while (true) {
            uint256 childIndex = index * 2 + 1;
            if (childIndex >= count) break;
            uint256 rightIndex = childIndex + 1;
            if (rightIndex < count && _higher(self.heap[rightIndex], self.heap[childIndex])) {
                childIndex = rightIndex;
            }
            Entry memory child = self.heap[childIndex];
            if (!_higher(child, entry)) break;
            self.heap[index] = child;
            self.positions[child.orderId] = index + 1;
            index = childIndex;
        }
        if (index != originalIndex) {
            self.heap[index] = entry;
            self.positions[entry.orderId] = index + 1;
        }
    }

    function _higher(Entry memory first, Entry memory second) private pure returns (bool) {
        if (first.indefinite != second.indefinite) return first.indefinite;
        if (first.expiresAt != second.expiresAt) return first.expiresAt > second.expiresAt;
        return first.orderId > second.orderId;
    }
}
