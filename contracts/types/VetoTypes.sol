// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title VetoTypes
/// @notice Shared structs for public headcount-based veto state.
library VetoTypes {
    struct PublicVetoRecord {
        bytes32 vetoId;
        bytes32 measureId;
        uint256 supportCount;
        uint64 createdAt;
        uint64 repealedAt;
        bool repealed;
    }

    struct PublicVetoReceipt {
        bytes32 personId;
        bool active;
        uint64 updatedAt;
    }
}
