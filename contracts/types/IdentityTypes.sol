// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title IdentityTypes
/// @notice Shared enums and structs for identity and citizenship state.
library IdentityTypes {
    enum VerificationStatus {
        Undefined,
        Pending,
        Verified,
        Rejected,
        Revoked
    }

    enum CitizenshipStatus {
        Undefined,
        None,
        EResident,
        Citizen,
        Suspended,
        Revoked
    }

    enum AgeClass {
        Undefined,
        Minor,
        Adult
    }

    enum WalletLinkStatus {
        Undefined,
        Pending,
        Active,
        Revoked
    }

    struct IdentityRecord {
        bytes32 personId;
        bytes32 metadataHash;
        string metadataURI;
        VerificationStatus verificationStatus;
        CitizenshipStatus citizenshipStatus;
        AgeClass ageClass;
        bool correctionFlag;
        bool finalSuspension;
        uint64 updatedAt;
    }

    struct IdentityRecordInput {
        bytes32 metadataHash;
        string metadataURI;
        VerificationStatus verificationStatus;
        CitizenshipStatus citizenshipStatus;
        AgeClass ageClass;
        bool correctionFlag;
        bool finalSuspension;
    }

    struct WalletLink {
        address wallet;
        bytes32 personId;
        WalletLinkStatus status;
        uint64 linkedAt;
        uint64 unlinkedAt;
    }

    struct MigrationRequest {
        address oldWallet;
        address newWallet;
        uint64 requestedAt;
        uint64 approvedAt;
        bool approved;
        bool exists;
    }
}
