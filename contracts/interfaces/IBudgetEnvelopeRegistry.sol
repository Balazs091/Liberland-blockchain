// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

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
    error BudgetRequestAlreadyExecuted(bytes32 requestId);
    error BudgetRequestCommitmentMissing(bytes32 requestId);
    error BudgetRequestNotExecuted(bytes32 requestId);
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

    event TreasuryExecutionMarked(
        bytes32 indexed requestId, bytes32 indexed budgetId, uint256 amount, address indexed vault, uint64 executedAt
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
    /// @notice Returns the original accounting writer for an active commitment, or zero after settlement.
    /// @param requestId The payout request identifier.
    /// @return authority The writer allowed to reconcile this commitment even after its module is replaced.
    function commitmentAuthority(bytes32 requestId) external view returns (address authority);
    /// @notice Returns the permanent one-shot treasury execution receipt, preserved across queue/vault replacement.
    function isRequestExecuted(bytes32 requestId) external view returns (bool executed);
    /// @notice Marks an active commitment executed once, callable only by the current canonical TreasuryVault.
    /// @dev The vault validates exact payout terms and calls before transferring; transfer failure rolls back this
    ///      receipt atomically. Budget spending is reconciled separately by the commitment's accounting writer.
    function markExecution(bytes32 requestId) external;
    /// @notice Reserves a new commitment through the current accounting authority; executed IDs can never be reused.
    function reserveBudget(bytes32 requestId, bytes32 budgetId, uint256 amount) external;
    /// @notice Releases an unexecuted active commitment through the current authority or its original writer.
    /// @dev An executed commitment must be recorded as spent and cannot restore available budget capacity.
    function releaseBudget(bytes32 requestId) external;
    /// @notice Records an executed active commitment as spent through the current authority or its original writer.
    /// @dev Requires the permanent execution receipt marked atomically by the canonical TreasuryVault.
    function recordDisbursement(bytes32 requestId) external;
}
