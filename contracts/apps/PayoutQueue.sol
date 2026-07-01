// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {KernelModule} from "../base/KernelModule.sol";
import {IActionTimelock} from "../interfaces/IActionTimelock.sol";
import {IBudgetEnvelopeRegistry} from "../interfaces/IBudgetEnvelopeRegistry.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IPayoutQueue} from "../interfaces/IPayoutQueue.sol";
import {ITreasuryVault} from "../interfaces/ITreasuryVault.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title PayoutQueue
/// @notice Audited payout request queue that reserves budgets before routing office-origin treasury actions.
contract PayoutQueue is IPayoutQueue, KernelModule {
    IBudgetEnvelopeRegistry private immutable _budgetEnvelopeRegistry;

    mapping(bytes32 requestId => TreasuryTypes.DisbursementRequest request) private _requests;
    bytes32[] private _requestIds;

    constructor(address kernelAddress, address budgetEnvelopeRegistryAddress) KernelModule(kernelAddress) {
        if (budgetEnvelopeRegistryAddress == address(0) || budgetEnvelopeRegistryAddress.code.length == 0) {
            revert IConstitutionKernel.InvalidModuleAddress(
                KernelModuleIds.BUDGET_ENVELOPE_REGISTRY, budgetEnvelopeRegistryAddress
            );
        }

        _budgetEnvelopeRegistry = IBudgetEnvelopeRegistry(budgetEnvelopeRegistryAddress);
    }

    /// @inheritdoc IPayoutQueue
    function getDisbursementRequest(bytes32 requestId)
        external
        view
        returns (TreasuryTypes.DisbursementRequest memory request)
    {
        return _requests[requestId];
    }

    /// @inheritdoc IPayoutQueue
    function requestExists(bytes32 requestId) public view returns (bool exists) {
        return _requests[requestId].requestId != bytes32(0);
    }

    /// @inheritdoc IPayoutQueue
    function totalDisbursementRequestCount() external view returns (uint256 count) {
        return _requestIds.length;
    }

    /// @inheritdoc IPayoutQueue
    function disbursementRequestIdAt(uint256 index) external view returns (bytes32 requestId) {
        return _requestIds[index];
    }

    /// @inheritdoc IPayoutQueue
    function proposePayout(TreasuryTypes.DisbursementRequestInput calldata input, uint64 routeAfter) external {
        _requireOfficeExecutor(msg.sender);

        if (
            input.requestId == bytes32(0) || input.budgetId == bytes32(0) || input.officeId == bytes32(0)
                || input.disbursementType == TreasuryTypes.DisbursementType.Undefined || input.recipient == address(0)
                || input.amount == 0
        ) {
            revert InvalidPayoutRequest(input.requestId);
        }
        if (requestExists(input.requestId)) {
            revert PayoutRequestAlreadyExists(input.requestId);
        }
        if (!_budgetEnvelopeRegistry.budgetExists(input.budgetId)) {
            revert InvalidPayoutRequest(input.requestId);
        }

        _requests[input.requestId] = TreasuryTypes.DisbursementRequest({
            requestId: input.requestId,
            budgetId: input.budgetId,
            officeId: input.officeId,
            disbursementType: input.disbursementType,
            asset: input.asset,
            recipient: input.recipient,
            amount: input.amount,
            policyReference: input.policyReference,
            noteHash: input.noteHash,
            noteURI: input.noteURI,
            state: TreasuryTypes.DisbursementState.Proposed,
            createdAt: uint64(block.timestamp),
            routeAfter: routeAfter,
            actionId: bytes32(0)
        });
        _requestIds.push(input.requestId);

        emit PayoutProposed(
            input.requestId,
            input.budgetId,
            input.officeId,
            input.disbursementType,
            input.recipient,
            input.amount,
            input.policyReference,
            input.noteHash,
            uint64(block.timestamp),
            routeAfter,
            msg.sender
        );
    }

    /// @inheritdoc IPayoutQueue
    function prepareRouting(bytes32 requestId)
        external
        returns (GovernanceTypes.TreasuryDisbursementPayload memory payload)
    {
        _requireOfficeExecutor(msg.sender);

        TreasuryTypes.DisbursementRequest storage request = _requests[requestId];
        if (request.requestId == bytes32(0)) {
            revert InvalidPayoutRequest(requestId);
        }
        if (request.state != TreasuryTypes.DisbursementState.Proposed) {
            revert PayoutRequestAlreadyFinalized(requestId, request.state);
        }
        if (block.timestamp < request.routeAfter) {
            revert PayoutRequestNotReady(requestId, request.routeAfter);
        }

        TreasuryTypes.BudgetEnvelope memory budgetEnvelope = _budgetEnvelopeRegistry.getBudgetEnvelope(request.budgetId);
        if (
            budgetEnvelope.officeId != request.officeId || budgetEnvelope.disbursementType != request.disbursementType
                || budgetEnvelope.asset != request.asset
        ) {
            revert InvalidPayoutRequest(requestId);
        }

        _budgetEnvelopeRegistry.reserveBudget(requestId, request.budgetId, request.amount);

        return GovernanceTypes.TreasuryDisbursementPayload({
            requestId: request.requestId,
            budgetId: request.budgetId,
            asset: request.asset,
            recipient: request.recipient,
            amount: request.amount,
            noteHash: request.noteHash
        });
    }

    /// @inheritdoc IPayoutQueue
    function confirmRouted(bytes32 requestId, bytes32 actionId) external {
        _requireOfficeExecutor(msg.sender);

        TreasuryTypes.DisbursementRequest storage request = _requests[requestId];
        if (request.requestId == bytes32(0)) {
            revert InvalidPayoutRequest(requestId);
        }
        if (request.actionId != bytes32(0) || request.state == TreasuryTypes.DisbursementState.Queued) {
            revert PayoutRequestAlreadyQueued(requestId, request.actionId);
        }

        request.state = TreasuryTypes.DisbursementState.Queued;
        request.actionId = actionId;

        emit PayoutQueued(requestId, actionId, uint64(block.timestamp), msg.sender);
    }

    /// @inheritdoc IPayoutQueue
    function cancelPayout(bytes32 requestId) external {
        _requireOfficeExecutor(msg.sender);

        TreasuryTypes.DisbursementRequest storage request = _requests[requestId];
        if (request.requestId == bytes32(0)) {
            revert InvalidPayoutRequest(requestId);
        }
        if (request.state != TreasuryTypes.DisbursementState.Proposed) {
            revert PayoutRequestAlreadyFinalized(requestId, request.state);
        }

        request.state = TreasuryTypes.DisbursementState.Canceled;

        emit PayoutCanceled(requestId, uint64(block.timestamp), msg.sender);
    }

    /// @inheritdoc IPayoutQueue
    function syncPayoutState(bytes32 requestId) external returns (TreasuryTypes.DisbursementState state) {
        TreasuryTypes.DisbursementRequest storage request = _requests[requestId];
        if (request.requestId == bytes32(0)) {
            revert InvalidPayoutRequest(requestId);
        }

        state = request.state;
        if (state != TreasuryTypes.DisbursementState.Queued) {
            return state;
        }

        GovernanceTypes.ActionState actionState =
            IActionTimelock(_kernel.getModule(KernelModuleIds.ACTION_TIMELOCK)).getActionState(request.actionId);
        if (actionState == GovernanceTypes.ActionState.Executed) {
            if (!ITreasuryVault(_kernel.getModule(KernelModuleIds.TREASURY_VAULT)).isDisbursementExecuted(requestId)) {
                revert PayoutRequestNotQueued(requestId);
            }

            request.state = TreasuryTypes.DisbursementState.Executed;
            emit PayoutExecuted(requestId, request.actionId, uint64(block.timestamp), msg.sender);
            _budgetEnvelopeRegistry.recordDisbursement(requestId);
            return request.state;
        }
        if (actionState == GovernanceTypes.ActionState.Canceled) {
            request.state = TreasuryTypes.DisbursementState.Vetoed;
            emit PayoutVetoed(requestId, request.actionId, uint64(block.timestamp), msg.sender);
            _budgetEnvelopeRegistry.releaseBudget(requestId);
            return request.state;
        }
        if (actionState == GovernanceTypes.ActionState.Expired) {
            request.state = TreasuryTypes.DisbursementState.Expired;
            emit PayoutExpired(requestId, request.actionId, uint64(block.timestamp), msg.sender);
            _budgetEnvelopeRegistry.releaseBudget(requestId);
            return request.state;
        }

        return request.state;
    }

    function _requireOfficeExecutor(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.OFFICE_EXECUTOR)) {
            revert UnauthorizedPayoutQueueCaller(caller);
        }
    }
}
