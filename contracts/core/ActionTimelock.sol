// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IActionTimelock} from "../interfaces/IActionTimelock.sol";
import {IBudgetEnvelopeRegistry} from "../interfaces/IBudgetEnvelopeRegistry.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {ITreasuryVault} from "../interfaces/ITreasuryVault.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title ActionTimelock
/// @notice Delayed execution queue for explicit privileged governance actions.
contract ActionTimelock is IActionTimelock {
    uint64 internal constant MODULE_UPDATE_DELAY = 2 days;
    uint64 internal constant TREASURY_BUDGET_APPROVAL_DELAY = 2 days;
    uint64 internal constant LEGISLATION_ENACTMENT_DELAY = 2 days;
    uint64 internal constant TREASURY_DISBURSEMENT_DELAY = 2 days;
    uint64 internal constant DEFAULT_EXECUTION_WINDOW = 7 days;

    mapping(bytes32 actionId => GovernanceTypes.ActionRecord actionRecord) private _actions;

    IConstitutionKernel private immutable _kernel;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) {
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) {
            revert IConstitutionKernel.InvalidModuleAddress(bytes32(0), kernelAddress);
        }

        _kernel = IConstitutionKernel(kernelAddress);
    }

    /// @notice Returns the kernel used for module pointer execution.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress) {
        return address(_kernel);
    }

    /// @inheritdoc IActionTimelock
    function computeActionId(GovernanceTypes.ActionRequest calldata request) external view returns (bytes32 actionId) {
        (uint64 earliestExecutionTime, uint64 expiresAt) = _resolveActionSchedule(request, uint64(block.timestamp));
        return _computeActionId(request, earliestExecutionTime, expiresAt);
    }

    /// @inheritdoc IActionTimelock
    function queueAction(GovernanceTypes.ActionRequest calldata request) external returns (bytes32 actionId) {
        _requireRouterCaller(msg.sender);

        if (minimumDelay(request.actionType) == 0) {
            revert UnsupportedExecutionAction(request.actionType);
        }

        uint64 createdAt = uint64(block.timestamp);
        (uint64 earliestExecutionTime, uint64 expiresAt) = _resolveActionSchedule(request, createdAt);
        actionId = _computeActionId(request, earliestExecutionTime, expiresAt);

        GovernanceTypes.ActionState existingState = _loadActionState(actionId);
        if (existingState == GovernanceTypes.ActionState.Queued) {
            revert ActionAlreadyQueued(actionId);
        }
        if (existingState != GovernanceTypes.ActionState.Undefined) {
            revert ActionAlreadyFinalized(actionId, existingState);
        }

        if (expiresAt <= earliestExecutionTime) {
            revert InvalidActionExpiry(actionId, expiresAt, earliestExecutionTime);
        }

        // Defense in depth: queued updates may only target already-registered modules.
        address targetModuleAddress = _kernel.getModule(request.targetModule);
        if (targetModuleAddress == address(0)) {
            revert IConstitutionKernel.ModuleNotRegistered(request.targetModule);
        }
        _validateQueuedAction(request, actionId);

        _actions[actionId] = GovernanceTypes.ActionRecord({
            actionId: actionId,
            actionType: request.actionType,
            origin: request.origin,
            originReference: request.originReference,
            policyReference: request.policyReference,
            targetModule: request.targetModule,
            payload: request.payload,
            createdAt: createdAt,
            earliestExecutionTime: earliestExecutionTime,
            expiresAt: expiresAt,
            state: GovernanceTypes.ActionState.Queued
        });

        emit ActionQueued(
            actionId,
            request.actionType,
            request.targetModule,
            request.origin,
            request.originReference,
            request.policyReference,
            keccak256(request.payload),
            createdAt,
            earliestExecutionTime,
            expiresAt
        );
    }

    /// @inheritdoc IActionTimelock
    function cancelAction(bytes32 actionId) external {
        _requireRouterCaller(msg.sender);

        GovernanceTypes.ActionRecord storage actionRecord = _actions[actionId];
        if (actionRecord.actionId == bytes32(0)) {
            revert ActionNotFound(actionId);
        }

        GovernanceTypes.ActionState currentState = _deriveState(actionRecord);
        if (currentState != GovernanceTypes.ActionState.Queued) {
            revert ActionAlreadyFinalized(actionId, currentState);
        }

        actionRecord.state = GovernanceTypes.ActionState.Canceled;

        emit ActionCanceled(actionId, msg.sender);
    }

    /// @inheritdoc IActionTimelock
    function executeAction(bytes32 actionId) external {
        GovernanceTypes.ActionRecord storage actionRecord = _actions[actionId];
        if (actionRecord.actionId == bytes32(0)) {
            revert ActionNotFound(actionId);
        }

        GovernanceTypes.ActionState currentState = _deriveState(actionRecord);
        if (currentState == GovernanceTypes.ActionState.Expired) {
            revert ActionExpired(actionId, actionRecord.expiresAt);
        }
        if (currentState != GovernanceTypes.ActionState.Queued) {
            revert ActionAlreadyFinalized(actionId, currentState);
        }
        if (block.timestamp < actionRecord.earliestExecutionTime) {
            revert ActionNotReady(actionId, actionRecord.earliestExecutionTime);
        }

        actionRecord.state = GovernanceTypes.ActionState.Executed;
        _executeAction(actionRecord);

        emit ActionExecuted(actionId, msg.sender);
    }

    /// @inheritdoc IActionTimelock
    function expireAction(bytes32 actionId) external {
        GovernanceTypes.ActionRecord storage actionRecord = _actions[actionId];
        if (actionRecord.actionId == bytes32(0)) {
            revert ActionNotFound(actionId);
        }

        GovernanceTypes.ActionState currentState = _deriveState(actionRecord);
        if (currentState != GovernanceTypes.ActionState.Expired) {
            if (currentState != GovernanceTypes.ActionState.Queued) {
                revert ActionAlreadyFinalized(actionId, currentState);
            }

            revert ActionNotExpired(actionId, actionRecord.expiresAt);
        }

        actionRecord.state = GovernanceTypes.ActionState.Expired;

        emit ActionExpiredRecorded(actionId, actionRecord.expiresAt);
    }

    /// @inheritdoc IActionTimelock
    function getAction(bytes32 actionId) external view returns (GovernanceTypes.ActionRecord memory actionRecord) {
        actionRecord = _actions[actionId];
        if (actionRecord.actionId == bytes32(0)) {
            revert ActionNotFound(actionId);
        }

        actionRecord.state = _deriveMemoryState(actionRecord);
    }

    /// @inheritdoc IActionTimelock
    function getActionState(bytes32 actionId) external view returns (GovernanceTypes.ActionState state) {
        GovernanceTypes.ActionRecord storage actionRecord = _actions[actionId];
        if (actionRecord.actionId == bytes32(0)) {
            return GovernanceTypes.ActionState.Undefined;
        }

        return _deriveState(actionRecord);
    }

    /// @inheritdoc IActionTimelock
    function isActionExecutable(bytes32 actionId) external view returns (bool executable) {
        GovernanceTypes.ActionRecord storage actionRecord = _actions[actionId];
        if (actionRecord.actionId == bytes32(0)) {
            return false;
        }

        return _deriveState(actionRecord) == GovernanceTypes.ActionState.Queued
            && block.timestamp >= actionRecord.earliestExecutionTime;
    }

    /// @inheritdoc IActionTimelock
    function minimumDelay(GovernanceTypes.ActionType actionType) public pure returns (uint64 delaySeconds) {
        if (actionType == GovernanceTypes.ActionType.ModulePointerUpdate) {
            return MODULE_UPDATE_DELAY;
        }
        if (actionType == GovernanceTypes.ActionType.TreasuryBudgetApproval) {
            return TREASURY_BUDGET_APPROVAL_DELAY;
        }
        if (actionType == GovernanceTypes.ActionType.LegislationEnactment) {
            return LEGISLATION_ENACTMENT_DELAY;
        }
        if (actionType == GovernanceTypes.ActionType.TreasuryDisbursement) {
            return TREASURY_DISBURSEMENT_DELAY;
        }

        return 0;
    }

    function _executeAction(GovernanceTypes.ActionRecord storage actionRecord) private {
        if (actionRecord.actionType == GovernanceTypes.ActionType.ModulePointerUpdate) {
            GovernanceTypes.ModuleUpdatePayload memory payload =
                _decodeModuleUpdatePayload(actionRecord.payload, actionRecord.actionId, actionRecord.targetModule);

            _kernel.governanceUpdateModule(actionRecord.targetModule, payload.newModuleAddress);
            return;
        }
        if (actionRecord.actionType == GovernanceTypes.ActionType.TreasuryBudgetApproval) {
            GovernanceTypes.TreasuryBudgetApprovalPayload memory payload = _decodeTreasuryBudgetApprovalPayload(
                actionRecord.payload, actionRecord.actionId, actionRecord.targetModule
            );

            IBudgetEnvelopeRegistry(_kernel.getModule(actionRecord.targetModule))
                .recordBudgetApproval(
                    payload.budgetId,
                    TreasuryTypes.BudgetEnvelopeInput({
                        officeId: payload.officeId,
                        disbursementType: payload.disbursementType,
                        asset: payload.asset,
                        allocatedAmount: payload.allocatedAmount,
                        startsAt: payload.startsAt,
                        endsAt: payload.endsAt,
                        policyReference: payload.policyReference
                    })
                );
            return;
        }
        if (actionRecord.actionType == GovernanceTypes.ActionType.LegislationEnactment) {
            GovernanceTypes.LegislationEnactmentPayload memory payload = _decodeLegislationEnactmentPayload(
                actionRecord.payload, actionRecord.actionId, actionRecord.targetModule
            );

            ILegislationRegistry legislationRegistry =
                ILegislationRegistry(_kernel.getModule(actionRecord.targetModule));
            legislationRegistry.recordEnactment(
                payload.measureId,
                LegislationTypes.LegislationRecordInput({
                    tier: payload.tier,
                    textHash: payload.textHash,
                    proposerReference: payload.proposerReference,
                    enactedByReferendumId: payload.enactedByReferendumId,
                    amendsMeasureId: payload.amendsMeasureId
                })
            );
            return;
        }
        if (actionRecord.actionType == GovernanceTypes.ActionType.TreasuryDisbursement) {
            GovernanceTypes.TreasuryDisbursementPayload memory payload = _decodeTreasuryDisbursementPayload(
                actionRecord.payload, actionRecord.actionId, actionRecord.targetModule
            );

            ITreasuryVault(_kernel.getModule(actionRecord.targetModule)).executeDisbursement(payload);
            return;
        }

        revert UnsupportedExecutionAction(actionRecord.actionType);
    }

    function _resolveActionSchedule(GovernanceTypes.ActionRequest calldata request, uint64 currentTimestamp)
        private
        pure
        returns (uint64 earliestExecutionTime, uint64 expiresAt)
    {
        uint64 earliestAllowed = currentTimestamp + minimumDelay(request.actionType);
        earliestExecutionTime =
            request.requestedExecutionTime > earliestAllowed ? request.requestedExecutionTime : earliestAllowed;
        expiresAt = request.expiresAt == 0 ? earliestExecutionTime + DEFAULT_EXECUTION_WINDOW : request.expiresAt;
    }

    function _computeActionId(
        GovernanceTypes.ActionRequest calldata request,
        uint64 earliestExecutionTime,
        uint64 expiresAt
    ) private view returns (bytes32 actionId) {
        return keccak256(
            abi.encode(
                block.chainid,
                address(this),
                request.actionType,
                request.origin,
                request.originReference,
                request.policyReference,
                request.targetModule,
                keccak256(request.payload),
                earliestExecutionTime,
                expiresAt
            )
        );
    }

    function _validateQueuedAction(GovernanceTypes.ActionRequest calldata request, bytes32 actionId) private view {
        if (request.actionType == GovernanceTypes.ActionType.ModulePointerUpdate) {
            _decodeModuleUpdatePayload(request.payload, actionId, request.targetModule);
            return;
        }
        if (request.actionType == GovernanceTypes.ActionType.TreasuryBudgetApproval) {
            _decodeTreasuryBudgetApprovalPayload(request.payload, actionId, request.targetModule);
            return;
        }
        if (request.actionType == GovernanceTypes.ActionType.LegislationEnactment) {
            _decodeLegislationEnactmentPayload(request.payload, actionId, request.targetModule);
            return;
        }
        if (request.actionType == GovernanceTypes.ActionType.TreasuryDisbursement) {
            _decodeTreasuryDisbursementPayload(request.payload, actionId, request.targetModule);
            return;
        }

        revert UnsupportedExecutionAction(request.actionType);
    }

    function _decodeModuleUpdatePayload(bytes memory payloadData, bytes32 actionId, bytes32 targetModule)
        private
        view
        returns (GovernanceTypes.ModuleUpdatePayload memory payload)
    {
        if (payloadData.length != 32) {
            revert InvalidActionPayload(actionId);
        }

        payload = abi.decode(payloadData, (GovernanceTypes.ModuleUpdatePayload));
        if (payload.newModuleAddress == address(0) || payload.newModuleAddress.code.length == 0) {
            revert IConstitutionKernel.InvalidModuleAddress(targetModule, payload.newModuleAddress);
        }
    }

    function _decodeLegislationEnactmentPayload(bytes memory payloadData, bytes32 actionId, bytes32 targetModule)
        private
        pure
        returns (GovernanceTypes.LegislationEnactmentPayload memory payload)
    {
        if (targetModule != KernelModuleIds.LEGISLATION_REGISTRY || payloadData.length != 192) {
            revert InvalidActionPayload(actionId);
        }

        payload = abi.decode(payloadData, (GovernanceTypes.LegislationEnactmentPayload));
        if (
            payload.measureId == bytes32(0) || payload.textHash == bytes32(0) || payload.proposerReference == bytes32(0)
        ) {
            revert InvalidActionPayload(actionId);
        }
        if (payload.enactedByReferendumId == bytes32(0) || payload.tier == LegislationTypes.LegislationTier.Undefined) {
            revert InvalidActionPayload(actionId);
        }
    }

    function _decodeTreasuryBudgetApprovalPayload(bytes memory payloadData, bytes32 actionId, bytes32 targetModule)
        private
        pure
        returns (GovernanceTypes.TreasuryBudgetApprovalPayload memory payload)
    {
        if (targetModule != KernelModuleIds.BUDGET_ENVELOPE_REGISTRY || payloadData.length != 256) {
            revert InvalidActionPayload(actionId);
        }

        payload = abi.decode(payloadData, (GovernanceTypes.TreasuryBudgetApprovalPayload));
        if (
            payload.budgetId == bytes32(0) || payload.officeId == bytes32(0)
                || payload.disbursementType == TreasuryTypes.DisbursementType.Undefined || payload.allocatedAmount == 0
                || payload.asset != address(0) || payload.endsAt <= payload.startsAt
        ) {
            revert InvalidActionPayload(actionId);
        }
    }

    function _decodeTreasuryDisbursementPayload(bytes memory payloadData, bytes32 actionId, bytes32 targetModule)
        private
        pure
        returns (GovernanceTypes.TreasuryDisbursementPayload memory payload)
    {
        if (targetModule != KernelModuleIds.TREASURY_VAULT || payloadData.length != 192) {
            revert InvalidActionPayload(actionId);
        }

        payload = abi.decode(payloadData, (GovernanceTypes.TreasuryDisbursementPayload));
        if (payload.requestId == bytes32(0) || payload.recipient == address(0) || payload.amount == 0) {
            revert InvalidActionPayload(actionId);
        }
    }

    function _loadActionState(bytes32 actionId) private view returns (GovernanceTypes.ActionState state) {
        GovernanceTypes.ActionRecord storage actionRecord = _actions[actionId];
        if (actionRecord.actionId == bytes32(0)) {
            return GovernanceTypes.ActionState.Undefined;
        }

        return _deriveState(actionRecord);
    }

    function _deriveState(GovernanceTypes.ActionRecord storage actionRecord)
        private
        view
        returns (GovernanceTypes.ActionState state)
    {
        if (
            actionRecord.state == GovernanceTypes.ActionState.Queued && actionRecord.expiresAt != 0
                && block.timestamp > actionRecord.expiresAt
        ) {
            return GovernanceTypes.ActionState.Expired;
        }

        return actionRecord.state;
    }

    function _deriveMemoryState(GovernanceTypes.ActionRecord memory actionRecord)
        private
        view
        returns (GovernanceTypes.ActionState state)
    {
        if (
            actionRecord.state == GovernanceTypes.ActionState.Queued && actionRecord.expiresAt != 0
                && block.timestamp > actionRecord.expiresAt
        ) {
            return GovernanceTypes.ActionState.Expired;
        }

        return actionRecord.state;
    }

    function _requireRouterCaller(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.GOVERNANCE_ROUTER)) {
            revert UnauthorizedTimelockCaller(caller);
        }
    }
}
