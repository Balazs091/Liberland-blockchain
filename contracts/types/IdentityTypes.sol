// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

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
        uint256 nonce;
        bool accepted;
        bool recovery;
        address proposer;
        address approver;
        bytes32 evidenceHash;
        bytes32 proposerAuthorizationId;
        bytes32 approverAuthorizationId;
    }

    /// @notice Civic fields only; metadata correction cannot change political rights.
    struct CivicStatusInput {
        VerificationStatus verificationStatus;
        CitizenshipStatus citizenshipStatus;
        AgeClass ageClass;
        bool correctionFlag;
        bool finalSuspension;
    }

    struct CivicChangeRequest {
        bytes32 requestId;
        bytes32 previousStateHash;
        bytes32 evidenceHash;
        address proposer;
        address approver;
        uint64 readyAt;
        CivicStatusInput proposed;
        address appealAuthority;
        bytes32 appealEvidenceHash;
        uint64 appealDeadline;
        bool appealResolved;
        bytes32 proposerAuthorizationId;
        bytes32 approverAuthorizationId;
    }
}
