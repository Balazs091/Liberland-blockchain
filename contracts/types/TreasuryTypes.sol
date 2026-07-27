// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title TreasuryTypes
/// @notice Shared enums and structs for treasury envelopes and payout requests.
library TreasuryTypes {
    enum BudgetStatus {
        Undefined,
        Draft,
        Approved,
        Active,
        Closed,
        Canceled
    }

    enum DisbursementType {
        Undefined,
        Operations,
        Salary,
        Grant,
        Refund,
        CourtOrder,
        CapitalExpenditure,
        ContributionReward
    }

    enum DisbursementState {
        Undefined,
        Proposed,
        Queued,
        Vetoed,
        Executed,
        Canceled,
        Expired
    }

    struct BudgetEnvelopeInput {
        bytes32 officeId;
        DisbursementType disbursementType;
        address asset;
        uint256 allocatedAmount;
        uint64 startsAt;
        uint64 endsAt;
        bytes32 policyReference;
    }

    struct BudgetEnvelope {
        bytes32 budgetId;
        bytes32 officeId;
        DisbursementType disbursementType;
        address asset;
        uint256 allocatedAmount;
        uint256 committedAmount;
        uint256 spentAmount;
        BudgetStatus status;
        uint64 startsAt;
        uint64 endsAt;
        bytes32 policyReference;
    }

    struct DisbursementRequestInput {
        bytes32 requestId;
        bytes32 budgetId;
        bytes32 officeId;
        DisbursementType disbursementType;
        address asset;
        address recipient;
        uint256 amount;
        bytes32 policyReference;
        bytes32 noteHash;
        string noteURI;
    }

    struct DisbursementRequest {
        bytes32 requestId;
        bytes32 budgetId;
        bytes32 officeId;
        DisbursementType disbursementType;
        address asset;
        address recipient;
        uint256 amount;
        bytes32 policyReference;
        bytes32 noteHash;
        string noteURI;
        DisbursementState state;
        uint64 createdAt;
        uint64 routeAfter;
        bytes32 actionId;
    }
}
