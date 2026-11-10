// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IdentityTypes} from "./IdentityTypes.sol";

/// @notice Fixed inputs for signed decisions. All case evidence is kept outside the public chain.
library JusticeTypes {
    enum Body {
        Admission,
        Annulment,
        AnnulmentReview,
        Council,
        Panel
    }

    enum Action {
        Admit,
        Annul,
        Recover,
        Restrict,
        RemoveMembership,
        RestoreMembership,
        StayOrder,
        ResumeOrder,
        RevokeOrder,
        Compensate,
        RestoreMerits,
        RecognizeAdulthood,
        RestoreCitizenship
    }

    enum AdmissionRoute {
        Regular,
        Descent,
        Birth
    }

    struct Charter {
        bytes32 rulesHash;
        uint64 termEndsAt;
        uint32 maxRestrictionDuration;
        uint16 allowedRights;
    }

    struct Decision {
        Action action;
        bytes32 decisionId;
        bytes32 personId;
        bytes32 effectHash;
        bytes32 reasonHash;
        bytes32 recordHash;
        uint64 noticeAt;
        uint64 deadline;
        uint256 stateRevision;
    }

    struct Signature {
        bytes32 personId;
        bytes signature;
    }

    struct Approvals {
        Signature[] first;
        Signature[] second;
        bytes minister;
        bytes president;
        bytes destination;
        string publicReasonURI;
    }

    struct IdentityEffect {
        address wallet;
        IdentityTypes.AgeClass ageClass;
        AdmissionRoute route;
        uint64 presidencyNonce;
        bytes32 ministerMandateHash;
        bytes32 priorDecisionId;
    }

    struct MembershipEffect {
        bytes32 orderId;
        uint256 revision;
        uint64 expiresAt;
        uint16 rights;
    }

    struct FinancialEffect {
        bytes32 referenceId;
        bytes32 beneficiary;
        uint128 amount;
        uint48 cutoffBlock;
        bytes32 termsHash;
    }
}
