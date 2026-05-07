// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {LegislationTypes} from "./LegislationTypes.sol";
import {TreasuryTypes} from "./TreasuryTypes.sol";

/// @title GovernanceTypes
/// @notice Shared enums and structs for the queued governance action lifecycle.
library GovernanceTypes {
    enum ActionType {
        Undefined,
        ModulePointerUpdate,
        PolicyPointerUpdate,
        RegistryRoleChange,
        OfficePermissionChange,
        TreasuryDisbursement,
        TreasuryBudgetApproval,
        CourtOrderExecution,
        EmergencyPause,
        EmergencyUnpause,
        LegislationEnactment,
        LegislationRepeal
    }

    enum ActionOrigin {
        Undefined,
        Referendum,
        Congress,
        Senate,
        Court,
        Office
    }

    enum ActionState {
        Undefined,
        Queued,
        Canceled,
        Executed,
        Expired
    }

    enum ModuleStatus {
        Undefined,
        Active,
        Deprecated
    }

    struct ActionRequest {
        ActionType actionType;
        ActionOrigin origin;
        bytes32 originReference;
        bytes32 policyReference;
        bytes32 targetModule;
        bytes payload;
        uint64 requestedExecutionTime;
        uint64 expiresAt;
    }

    struct ModuleUpdatePayload {
        address newModuleAddress;
    }

    struct LegislationEnactmentPayload {
        bytes32 measureId;
        LegislationTypes.LegislationTier tier;
        bytes32 textHash;
        bytes32 proposerReference;
        bytes32 enactedByReferendumId;
        bytes32 amendsMeasureId;
    }

    struct TreasuryDisbursementPayload {
        bytes32 requestId;
        bytes32 budgetId;
        address asset;
        address recipient;
        uint256 amount;
        bytes32 noteHash;
    }

    struct TreasuryBudgetApprovalPayload {
        bytes32 budgetId;
        bytes32 officeId;
        TreasuryTypes.DisbursementType disbursementType;
        address asset;
        uint256 allocatedAmount;
        uint64 startsAt;
        uint64 endsAt;
        bytes32 policyReference;
    }

    struct ActionRecord {
        bytes32 actionId;
        ActionType actionType;
        ActionOrigin origin;
        bytes32 originReference;
        bytes32 policyReference;
        bytes32 targetModule;
        bytes payload;
        uint64 createdAt;
        uint64 earliestExecutionTime;
        uint64 expiresAt;
        ActionState state;
    }

    struct ModuleRecord {
        bytes32 moduleId;
        address moduleAddress;
        ModuleStatus status;
        uint64 activatedAt;
        uint64 lastUpdatedAt;
    }
}
