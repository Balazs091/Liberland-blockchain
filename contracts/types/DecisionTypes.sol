// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OfficeTypes} from "./OfficeTypes.sol";

/// @title DecisionTypes
/// @notice Shared enums and structs for bounded Congress and ministry decisions.
library DecisionTypes {
    enum DecisionScope {
        Undefined,
        Congress,
        Ministry
    }

    enum DecisionAction {
        Undefined,
        ERC20Transfer,
        LLMTransferAndStake,
        ClerkStatus,
        RegisterOffice,
        FundMinistry
    }

    enum DecisionStatus {
        Undefined,
        Prepared,
        Executed,
        Canceled
    }

    struct DecisionRecord {
        bytes32 decisionId;
        DecisionScope scope;
        DecisionAction action;
        DecisionStatus status;
        // For Ministry decisions this is the acting office; for a Congress RegisterOffice decision it is the
        // identifier of the new office to create; for a Congress FundMinistry decision it is the office to credit.
        bytes32 officeId;
        uint256 congressCycleId;
        address preparedBy;
        address executedBy;
        address source;
        address token;
        // For a RegisterOffice decision this is the admin granted to the newly created office.
        address recipient;
        bytes32 recipientPersonId;
        uint256 amount;
        address clerk;
        bool clerkActive;
        // Office kind and name for a RegisterOffice decision (unused by other actions).
        OfficeTypes.OfficeKind officeKind;
        string officeName;
        bytes32 metadataHash;
        string metadataURI;
        uint32 supportCount;
        uint32 supportRequired;
        uint64 preparedAt;
        uint64 executedAt;
    }
}
