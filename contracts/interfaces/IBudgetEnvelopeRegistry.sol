// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IKernelModule} from "./IKernelModule.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title IBudgetEnvelopeRegistry
/// @notice Stable fact registry for approved budget envelopes and committed treasury outflows.
interface IBudgetEnvelopeRegistry is IKernelModule {
    error BudgetAlreadyRecorded(bytes32 budgetId);
    error BudgetAmountExceeded(bytes32 budgetId, uint256 availableAmount, uint256 requestedAmount);
    error BudgetNotActive(bytes32 budgetId);
    error BudgetNotFound(bytes32 budgetId);
    error BudgetRequestAlreadyCommitted(bytes32 requestId);
    error BudgetRequestCommitmentMissing(bytes32 requestId);
    error InvalidBudgetRequest(bytes32 requestId);
    error InvalidBudgetAmount(uint256 amount);
    error InvalidBudgetAsset(address asset);
    error InvalidBudgetId(bytes32 budgetId);
    error InvalidBudgetOffice(bytes32 officeId);
    error InvalidBudgetWindow(uint64 startsAt, uint64 endsAt);
    error UnauthorizedBudgetEnvelopeRegistryCaller(address caller);

    event BudgetEnvelopeRecorded(
        bytes32 indexed budgetId,
        bytes32 indexed officeId,
        TreasuryTypes.DisbursementType disbursementType,
        address asset,
        uint256 allocatedAmount,
        bytes32 policyReference,
        uint64 startsAt,
        uint64 endsAt,
        uint64 recordedAt,
        address indexed recordedBy
    );

    event BudgetCommitmentRecorded(
        bytes32 indexed requestId,
        bytes32 indexed budgetId,
        uint256 amount,
        uint256 remainingAvailable,
        uint64 recordedAt,
        address indexed recordedBy
    );

    event BudgetCommitmentReleased(
        bytes32 indexed requestId,
        bytes32 indexed budgetId,
        uint256 amount,
        uint256 remainingAvailable,
        uint64 releasedAt,
        address indexed releasedBy
    );

    event BudgetDisbursementRecorded(
        bytes32 indexed requestId,
        bytes32 indexed budgetId,
        uint256 amount,
        uint256 totalSpentAmount,
        uint64 recordedAt,
        address indexed recordedBy
    );

    function getBudgetEnvelope(bytes32 budgetId) external view returns (TreasuryTypes.BudgetEnvelope memory envelope);
    function budgetExists(bytes32 budgetId) external view returns (bool exists);
    function totalBudgetCount() external view returns (uint256 count);
    function budgetIdAt(uint256 index) external view returns (bytes32 budgetId);
    function availableAmount(bytes32 budgetId) external view returns (uint256 amount);
    function isBudgetActive(bytes32 budgetId) external view returns (bool active);
    function hasCommittedRequest(bytes32 requestId) external view returns (bool committed);
    /// @notice Returns the immutable accounting terms reserved for a payout request.
    /// @param requestId The payout request identifier.
    /// @return budgetId The budget charged by the request.
    /// @return amount The exact reserved amount.
    /// @return active Whether the commitment is still active.
    function getBudgetCommitment(bytes32 requestId)
        external
        view
        returns (bytes32 budgetId, uint256 amount, bool active);
    function recordBudgetApproval(bytes32 budgetId, TreasuryTypes.BudgetEnvelopeInput calldata input) external;
    function reserveBudget(bytes32 requestId, bytes32 budgetId, uint256 amount) external;
    function releaseBudget(bytes32 requestId) external;
    function recordDisbursement(bytes32 requestId) external;
}
