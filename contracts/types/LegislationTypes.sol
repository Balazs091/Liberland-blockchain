// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title LegislationTypes
/// @notice Shared enums and structs for legislation text records and enactment metadata.
library LegislationTypes {
    enum LegislationTier {
        Undefined,
        ConstitutionalOrInternationalTreaty,
        Law,
        SubLegalTier3,
        SubLegalTier4,
        Decision
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

    function isConstitutionalTier(LegislationTier tier) internal pure returns (bool eligible) {
        return tier == LegislationTier.ConstitutionalOrInternationalTreaty;
    }

    function isLawTier(LegislationTier tier) internal pure returns (bool eligible) {
        return tier == LegislationTier.Law;
    }

    function isSubLegalTier(LegislationTier tier) internal pure returns (bool eligible) {
        return tier == LegislationTier.SubLegalTier3 || tier == LegislationTier.SubLegalTier4
            || tier == LegislationTier.Decision;
    }
}
