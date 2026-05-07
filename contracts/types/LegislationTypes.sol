// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title LegislationTypes
/// @notice Shared enums and structs for legislation text records and enactment metadata.
library LegislationTypes {
    enum LegislationTier {
        Undefined,
        OrdinaryLaw,
        ConstitutionalLaw
    }

    enum RepealOrigin {
        Undefined,
        Referendum,
        Senate,
        PublicVeto
    }

    struct LegislationRecordInput {
        LegislationTier tier;
        bytes32 textHash;
        bytes32 proposerReference;
        bytes32 enactedByReferendumId;
        bytes32 amendsMeasureId;
    }

    struct LegislationRecord {
        bytes32 measureId;
        LegislationTier tier;
        bytes32 textHash;
        bytes32 proposerReference;
        bytes32 enactedByReferendumId;
        bytes32 amendsMeasureId;
        RepealOrigin repealOrigin;
        bytes32 repealReference;
        bool active;
        bool repealed;
        uint64 enactedAt;
        uint64 repealedAt;
    }
}
