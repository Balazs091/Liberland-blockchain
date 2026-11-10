// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

/// @title MembershipTypes
/// @notice Independent restriction facts; full membership removal is a separate registry lifecycle flag.
library MembershipTypes {
    /// @dev Bit positions follow the five privileges in the implementation brief. A policy must define their
    ///      specific consumers; a restriction never implicitly grants a financial or property power.
    enum Right {
        Political,
        Community,
        Appointive,
        Representation,
        AppointmentEligibility
    }

    /// @dev Unstayed is a procedural state, not a claim that the order has not expired.
    enum OrderStatus {
        Unset,
        Unstayed,
        Stayed,
        Revoked
    }

    uint16 internal constant SUPPORTED_RIGHTS_MASK = (1 << 5) - 1;

    struct OrderInput {
        bytes32 personId;
        bytes32 orderId;
        uint16 restrictedMask;
        uint64 effectiveAt;
        uint64 expiresAt;
        bool indefinite;
    }

    struct RestrictionOrder {
        bytes32 sourceReceiptId;
        uint256 revision;
        uint16 restrictedMask;
        uint64 effectiveAt;
        uint64 expiresAt;
        bool indefinite;
        OrderStatus status;
    }

    /// @dev Zero restrictedUntil means no finite current restriction for that bit. indefiniteMask distinguishes
    ///      an indefinite restriction explicitly. These are current restriction facts, not an eligibility grant.
    struct RightsSummary {
        uint16 restrictedMask;
        uint16 indefiniteMask;
        uint64[5] restrictedUntil;
        uint256 personRevision;
    }
}
