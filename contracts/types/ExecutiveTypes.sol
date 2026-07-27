// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title ExecutiveTypes
/// @notice Shared enums and structs for the Congress-appointed Prime Minister and the four-seat Cabinet
///         (Constitution Art V §1-2). This is a political cabinet record layer decoupled from the operational
///         OfficeRegistry: ministers here are cabinet office-holders, not office admins.
library ExecutiveTypes {
    /// @notice The four constitutional ministries plus an Undefined sentinel used to reject the zero slot.
    enum MinistryKind {
        Undefined,
        Finance,
        ForeignAffairs,
        Interior,
        Justice
    }

    /// @notice The sitting Prime Minister, its fixed-length term, and the Congress vote tally that appointed it.
    /// @dev `appointmentSupport` records the winning appointment vote count; Congress removal requires at least
    ///      this many valid removal votes (owner's rule: appointed by N ⇒ removal needs >= N).
    struct PrimeMinisterRecord {
        address primeMinister;
        bytes32 personId;
        uint64 termStart;
        uint64 termEnd;
        uint32 appointmentSupport;
        bool active;
    }

    /// @notice A sitting Cabinet minister for one ministry and its fixed-length term.
    struct MinisterRecord {
        address minister;
        bytes32 personId;
        MinistryKind ministry;
        uint64 termStart;
        uint64 termEnd;
        bool active;
    }
}
