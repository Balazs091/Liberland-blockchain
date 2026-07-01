// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title CompanyTypes
/// @notice Shared enums and structs for the company registry domain.
library CompanyTypes {
    enum CompanyStatus {
        Undefined,
        Pending,
        Active,
        ComplianceWarning,
        Suspended,
        Dissolving,
        Dissolved,
        Rejected
    }

    enum FilingType {
        Undefined,
        Incorporation,
        ArticlesUpdate,
        DirectorChange,
        ShareClassChange,
        ShareTransfer,
        Compliance,
        Dissolution,
        Other
    }

    struct CompanyInput {
        bytes32 registrationNumberHash;
        bytes32 nameHash;
        bytes32 jurisdictionHash;
        bytes32 registeredOfficeHash;
        bytes32 metadataHash;
        bytes32 articlesHash;
        bytes32 uboHash;
        uint256 registeredCapital;
    }

    struct CompanyRecord {
        bytes32 companyId;
        bytes32 registrationNumberHash;
        bytes32 nameHash;
        bytes32 jurisdictionHash;
        bytes32 registeredOfficeHash;
        bytes32 metadataHash;
        bytes32 articlesHash;
        bytes32 uboHash;
        uint256 registeredCapital;
        address founder;
        CompanyStatus status;
        uint32 activeDirectorCount;
        uint32 shareClassCount;
        uint64 submittedAt;
        uint64 approvedAt;
        uint64 updatedAt;
    }

    struct DirectorRecord {
        address director;
        bytes32 roleHash;
        bool active;
        uint64 appointedAt;
        uint64 removedAt;
    }

    struct ShareClassRecord {
        bytes32 companyId;
        bytes32 classId;
        bytes32 metadataHash;
        uint256 authorizedShares;
        uint256 issuedShares;
        uint16 votingWeightBps;
        bool fractional;
        bool active;
        uint64 createdAt;
        uint64 updatedAt;
    }

    struct FilingRecord {
        bytes32 filingId;
        bytes32 companyId;
        bytes32 documentHash;
        // `filingType` packs alongside `filedBy` and `filedAt` in a single slot (E2).
        address filedBy;
        FilingType filingType;
        uint64 filedAt;
    }
}
