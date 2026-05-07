// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IBudgetEnvelopeRegistry} from "../interfaces/IBudgetEnvelopeRegistry.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title BudgetEnvelopeRegistry
/// @notice Stable fact registry for approved budget envelopes and committed outflows.
contract BudgetEnvelopeRegistry is IBudgetEnvelopeRegistry {
    struct BudgetCommitment {
        bytes32 budgetId;
        uint256 amount;
        bool active;
    }

    IConstitutionKernel private immutable _kernel;

    mapping(bytes32 budgetId => TreasuryTypes.BudgetEnvelope envelope) private _budgetEnvelopes;
    mapping(bytes32 requestId => BudgetCommitment commitment) private _budgetCommitments;
    bytes32[] private _budgetIds;

    constructor(address kernelAddress) {
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) {
            revert IConstitutionKernel.InvalidModuleAddress(bytes32(0), kernelAddress);
        }

        _kernel = IConstitutionKernel(kernelAddress);
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function kernel() external view returns (address kernelAddress) {
        return address(_kernel);
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function getBudgetEnvelope(bytes32 budgetId) external view returns (TreasuryTypes.BudgetEnvelope memory envelope) {
        return _budgetEnvelopes[budgetId];
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function budgetExists(bytes32 budgetId) public view returns (bool exists) {
        return _budgetEnvelopes[budgetId].budgetId != bytes32(0);
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function totalBudgetCount() external view returns (uint256 count) {
        return _budgetIds.length;
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function budgetIdAt(uint256 index) external view returns (bytes32 budgetId) {
        return _budgetIds[index];
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function availableAmount(bytes32 budgetId) public view returns (uint256 amount) {
        TreasuryTypes.BudgetEnvelope storage envelope = _budgetEnvelopes[budgetId];
        if (envelope.budgetId == bytes32(0)) {
            return 0;
        }

        return envelope.allocatedAmount - envelope.committedAmount - envelope.spentAmount;
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function isBudgetActive(bytes32 budgetId) public view returns (bool active) {
        TreasuryTypes.BudgetEnvelope storage envelope = _budgetEnvelopes[budgetId];
        if (envelope.budgetId == bytes32(0)) {
            return false;
        }
        if (
            envelope.status == TreasuryTypes.BudgetStatus.Canceled
                || envelope.status == TreasuryTypes.BudgetStatus.Closed
        ) {
            return false;
        }

        return block.timestamp >= envelope.startsAt && block.timestamp <= envelope.endsAt;
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function hasCommittedRequest(bytes32 requestId) external view returns (bool committed) {
        return _budgetCommitments[requestId].active;
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function recordBudgetApproval(bytes32 budgetId, TreasuryTypes.BudgetEnvelopeInput calldata input) external {
        _requireBudgetAuthority(msg.sender);

        if (budgetId == bytes32(0)) {
            revert InvalidBudgetId(budgetId);
        }
        if (input.officeId == bytes32(0)) {
            revert InvalidBudgetOffice(input.officeId);
        }
        if (input.disbursementType == TreasuryTypes.DisbursementType.Undefined) {
            revert InvalidBudgetAmount(0);
        }
        if (input.asset != address(0)) {
            revert InvalidBudgetAsset(input.asset);
        }
        if (input.allocatedAmount == 0) {
            revert InvalidBudgetAmount(input.allocatedAmount);
        }
        if (input.endsAt <= input.startsAt) {
            revert InvalidBudgetWindow(input.startsAt, input.endsAt);
        }
        if (budgetExists(budgetId)) {
            revert BudgetAlreadyRecorded(budgetId);
        }

        TreasuryTypes.BudgetStatus status =
            input.startsAt > block.timestamp ? TreasuryTypes.BudgetStatus.Approved : TreasuryTypes.BudgetStatus.Active;

        _budgetEnvelopes[budgetId] = TreasuryTypes.BudgetEnvelope({
            budgetId: budgetId,
            officeId: input.officeId,
            disbursementType: input.disbursementType,
            asset: input.asset,
            allocatedAmount: input.allocatedAmount,
            committedAmount: 0,
            spentAmount: 0,
            status: status,
            startsAt: input.startsAt,
            endsAt: input.endsAt,
            policyReference: input.policyReference
        });
        _budgetIds.push(budgetId);

        emit BudgetEnvelopeRecorded(
            budgetId,
            input.officeId,
            input.disbursementType,
            input.asset,
            input.allocatedAmount,
            input.policyReference,
            input.startsAt,
            input.endsAt,
            uint64(block.timestamp),
            msg.sender
        );
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function reserveBudget(bytes32 requestId, bytes32 budgetId, uint256 amount) external {
        _requireAccountingAuthority(msg.sender);

        if (requestId == bytes32(0)) {
            revert InvalidBudgetRequest(requestId);
        }
        if (amount == 0) {
            revert InvalidBudgetAmount(amount);
        }

        TreasuryTypes.BudgetEnvelope storage envelope = _budgetEnvelopes[budgetId];
        if (envelope.budgetId == bytes32(0)) {
            revert BudgetNotFound(budgetId);
        }
        if (!isBudgetActive(budgetId)) {
            revert BudgetNotActive(budgetId);
        }

        BudgetCommitment storage commitment = _budgetCommitments[requestId];
        if (commitment.active) {
            revert BudgetRequestAlreadyCommitted(requestId);
        }

        uint256 available = availableAmount(budgetId);
        if (available < amount) {
            revert BudgetAmountExceeded(budgetId, available, amount);
        }

        envelope.committedAmount += amount;
        commitment.budgetId = budgetId;
        commitment.amount = amount;
        commitment.active = true;

        emit BudgetCommitmentRecorded(
            requestId, budgetId, amount, available - amount, uint64(block.timestamp), msg.sender
        );
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function releaseBudget(bytes32 requestId) external {
        _requireAccountingAuthority(msg.sender);

        BudgetCommitment storage commitment = _budgetCommitments[requestId];
        if (!commitment.active) {
            revert BudgetRequestCommitmentMissing(requestId);
        }

        TreasuryTypes.BudgetEnvelope storage envelope = _budgetEnvelopes[commitment.budgetId];
        envelope.committedAmount -= commitment.amount;

        emit BudgetCommitmentReleased(
            requestId,
            commitment.budgetId,
            commitment.amount,
            availableAmount(commitment.budgetId),
            uint64(block.timestamp),
            msg.sender
        );

        delete _budgetCommitments[requestId];
    }

    /// @inheritdoc IBudgetEnvelopeRegistry
    function recordDisbursement(bytes32 requestId) external {
        _requireAccountingAuthority(msg.sender);

        BudgetCommitment storage commitment = _budgetCommitments[requestId];
        if (!commitment.active) {
            revert BudgetRequestCommitmentMissing(requestId);
        }

        TreasuryTypes.BudgetEnvelope storage envelope = _budgetEnvelopes[commitment.budgetId];
        envelope.committedAmount -= commitment.amount;
        envelope.spentAmount += commitment.amount;
        if (envelope.spentAmount == envelope.allocatedAmount && envelope.committedAmount == 0) {
            envelope.status = TreasuryTypes.BudgetStatus.Closed;
        } else if (envelope.status == TreasuryTypes.BudgetStatus.Approved && block.timestamp >= envelope.startsAt) {
            envelope.status = TreasuryTypes.BudgetStatus.Active;
        }

        emit BudgetDisbursementRecorded(
            requestId, commitment.budgetId, commitment.amount, envelope.spentAmount, uint64(block.timestamp), msg.sender
        );

        delete _budgetCommitments[requestId];
    }

    function _requireBudgetAuthority(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY)) {
            revert UnauthorizedBudgetEnvelopeRegistryCaller(caller);
        }
    }

    function _requireAccountingAuthority(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY)) {
            revert UnauthorizedBudgetEnvelopeRegistryCaller(caller);
        }
    }
}
