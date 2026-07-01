// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title OfficeTypes
/// @notice Shared enums and structs for executive and ministry office administration.
library OfficeTypes {
    enum OfficeKind {
        Undefined,
        MinistryOfFinance,
        IdentityOffice,
        LandRegistryOffice,
        CompanyRegistryOffice
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
        CancelPayout,
        ManageLandRegistry,
        ManageCompanyRegistry,
        ManageOfficeMetadata,
        SetOfficeActive
    }

    struct OfficeRecord {
        bytes32 officeId;
        string name;
        // `kind`, `active`, and the timestamps pack alongside `admin` in a single slot (E2).
        address admin;
        OfficeKind kind;
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
