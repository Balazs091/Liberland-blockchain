// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title OfficeTypes
/// @notice Shared enums and structs for executive and ministry office administration.
library OfficeTypes {
    enum OfficeKind {
        Undefined,
        MinistryOfFinance,
        IdentityOffice,
        LandRegistryOffice
    }

    enum OfficeRole {
        None,
        Admin,
        Clerk
    }

    enum OfficeActionClass {
        Undefined,
        ManageClerks,
        TransferAdmin,
        ProposeBudget,
        ProposePayout,
        RoutePayout,
        CancelPayout
    }

    struct OfficeRecord {
        bytes32 officeId;
        OfficeKind kind;
        string name;
        address admin;
        bool active;
        uint64 createdAt;
        uint64 lastUpdatedAt;
    }

    struct OfficeMembership {
        bytes32 officeId;
        address member;
        OfficeRole role;
        bool active;
        uint64 grantedAt;
        uint64 revokedAt;
    }
}
