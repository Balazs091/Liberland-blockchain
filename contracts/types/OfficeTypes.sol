// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

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
        // `kind`, `active`, and the timestamps pack alongside `admin` in a single slot.
        address admin;
        OfficeKind kind;
        bool active;
        uint64 createdAt;
        uint64 lastUpdatedAt;
        // Zero means the admin appointment is permanent. Cabinet appointments use their ministerial term end.
        uint64 adminAuthorizationEndsAt;
        // Zero keeps generic offices wallet-bound. Cabinet appointments bind authority to the minister's person ID.
        bytes32 adminPersonId;
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
