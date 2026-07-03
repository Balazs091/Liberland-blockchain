// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IActionTimelock} from "../interfaces/IActionTimelock.sol";
import {IBudgetEnvelopeRegistry} from "../interfaces/IBudgetEnvelopeRegistry.sol";
import {IConstitutionalReview} from "../interfaces/IConstitutionalReview.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {ISenateApp} from "../interfaces/ISenateApp.sol";
import {ITreasuryVault} from "../interfaces/ITreasuryVault.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {SenateTypes} from "../types/SenateTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title ActionTimelock
/// @notice Delayed execution queue for explicit privileged governance actions.
contract ActionTimelock is IActionTimelock {
    uint64 internal constant DEFAULT_MODULE_GOVERNANCE_DELAY = 2 days;
    uint64 internal constant DEFAULT_TREASURY_BUDGET_APPROVAL_DELAY = 1 days;
    uint64 internal constant DEFAULT_LEGISLATION_ENACTMENT_DELAY = 1 days;
    uint64 internal constant DEFAULT_TREASURY_DISBURSEMENT_DELAY = 2 days;
    uint64 internal constant DEFAULT_EXECUTION_WINDOW = 7 days;

    mapping(bytes32 actionId => GovernanceTypes.ActionRecord actionRecord) private _actions;

    IConstitutionKernel private immutable _kernel;
    uint64 private immutable _moduleGovernanceDelay;
    uint64 private immutable _treasuryBudgetApprovalDelay;
    uint64 private immutable _legislationEnactmentDelay;
    uint64 private immutable _treasuryDisbursementDelay;
    uint64 private immutable _defaultExecutionWindow;

    /// @param kernelAddress The canonical kernel registry address.
    /// @param delayConfig The minimum action delays and default execution window to use for this deployment.
    constructor(address kernelAddress, GovernanceTypes.TimelockDelayConfig memory delayConfig) {
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) {
            revert IConstitutionKernel.InvalidModuleAddress(bytes32(0), kernelAddress);
        }
        if (delayConfig.defaultExecutionWindow == 0) {
            revert InvalidDelayConfig(delayConfig);
        }

        _kernel = IConstitutionKernel(kernelAddress);
        _moduleGovernanceDelay = delayConfig.moduleGovernanceDelay;
        _treasuryBudgetApprovalDelay = delayConfig.treasuryBudgetApprovalDelay;
        _legislationEnactmentDelay = delayConfig.legislationEnactmentDelay;
        _treasuryDisbursementDelay = delayConfig.treasuryDisbursementDelay;
        _defaultExecutionWindow = delayConfig.defaultExecutionWindow;
    }

    /// @notice Returns the conservative default timelock delays used by production scripts.
    /// @return delayConfig The default delay configuration.
    function defaultDelayConfig() external pure returns (GovernanceTypes.TimelockDelayConfig memory delayConfig) {
        delayConfig = GovernanceTypes.TimelockDelayConfig({
            moduleGovernanceDelay: DEFAULT_MODULE_GOVERNANCE_DELAY,
            treasuryBudgetApprovalDelay: DEFAULT_TREASURY_BUDGET_APPROVAL_DELAY,
            legislationEnactmentDelay: DEFAULT_LEGISLATION_ENACTMENT_DELAY,
            treasuryDisbursementDelay: DEFAULT_TREASURY_DISBURSEMENT_DELAY,
            defaultExecutionWindow: DEFAULT_EXECUTION_WINDOW
        });
    }

    /// @notice Returns the kernel used for module pointer execution.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress) {
        return address(_kernel);
    }

    /// @inheritdoc IActionTimelock
    function computeActionId(GovernanceTypes.ActionRequest calldata request) external view returns (bytes32 actionId) {
        (uint64 earliestExecutionTime, uint64 expiresAt) = _resolveActionSchedule(request, uint64(block.timestamp));
        return _computeActionId(request, _targetModuleAddressForId(request), earliestExecutionTime, expiresAt);
    }

    /// @inheritdoc IActionTimelock
    function queueAction(GovernanceTypes.ActionRequest calldata request) external returns (bytes32 actionId) {
        _requireRouterCaller(msg.sender);

        if (!isActionTypeSupported(request.actionType)) {
            revert UnsupportedExecutionAction(request.actionType);
        }

        uint64 createdAt = uint64(block.timestamp);
        (uint64 earliestExecutionTime, uint64 expiresAt) = _resolveActionSchedule(request, createdAt);
        address targetModuleAddress = _targetModuleAddressForQueue(request);
        actionId = _computeActionId(request, targetModuleAddress, earliestExecutionTime, expiresAt);

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

        _validateQueuedAction(request, actionId);

        _actions[actionId] = GovernanceTypes.ActionRecord({
            actionId: actionId,
            actionType: request.actionType,
            origin: request.origin,
            originReference: request.originReference,
            policyReference: request.policyReference,
            targetModule: request.targetModule,
            targetModuleAddress: targetModuleAddress,
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
            targetModuleAddress,
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
        _requireNoPendingSenateCancellation(actionId);
        _requireNoActiveSenateSuspension(actionId);
        _requireNotUnderConstitutionalReview(actionId);
        _requireQueuedTargetUnchanged(actionRecord);

        actionRecord.state = GovernanceTypes.ActionState.Executed;
        emit ActionExecuted(actionId, msg.sender);

        _executeAction(actionRecord);
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
            && block.timestamp >= actionRecord.earliestExecutionTime && !_hasPendingSenateCancellation(actionId)
            && !_hasActiveSenateSuspension(actionId) && !_isUnderConstitutionalReview(actionId);
    }

    /// @inheritdoc IActionTimelock
    function minimumDelay(GovernanceTypes.ActionType actionType) public view returns (uint64 delaySeconds) {
        if (
            actionType == GovernanceTypes.ActionType.ModulePointerUpdate
                || actionType == GovernanceTypes.ActionType.ModuleRegistration
        ) {
            return _moduleGovernanceDelay;
        }
        if (actionType == GovernanceTypes.ActionType.TreasuryBudgetApproval) {
            return _treasuryBudgetApprovalDelay;
        }
        if (actionType == GovernanceTypes.ActionType.LegislationEnactment) {
            return _legislationEnactmentDelay;
        }
        if (actionType == GovernanceTypes.ActionType.TreasuryDisbursement) {
            return _treasuryDisbursementDelay;
        }

        return 0;
    }

    /// @inheritdoc IActionTimelock
    function isActionTypeSupported(GovernanceTypes.ActionType actionType) public pure returns (bool supported) {
        return actionType == GovernanceTypes.ActionType.ModulePointerUpdate
            || actionType == GovernanceTypes.ActionType.ModuleRegistration
            || actionType == GovernanceTypes.ActionType.TreasuryBudgetApproval
            || actionType == GovernanceTypes.ActionType.LegislationEnactment
            || actionType == GovernanceTypes.ActionType.TreasuryDisbursement;
    }

    function _executeAction(GovernanceTypes.ActionRecord storage actionRecord) private {
        if (actionRecord.actionType == GovernanceTypes.ActionType.ModulePointerUpdate) {
            GovernanceTypes.ModuleUpdatePayload memory payload =
                _decodeModuleUpdatePayload(actionRecord.payload, actionRecord.actionId, actionRecord.targetModule);

            _kernel.governanceUpdateModule(actionRecord.targetModule, payload.newModuleAddress);
            return;
        }
        if (actionRecord.actionType == GovernanceTypes.ActionType.ModuleRegistration) {
            GovernanceTypes.ModuleUpdatePayload memory payload =
                _decodeModuleUpdatePayload(actionRecord.payload, actionRecord.actionId, actionRecord.targetModule);

            _kernel.governanceRegisterModule(actionRecord.targetModule, payload.newModuleAddress);
            return;
        }
        if (actionRecord.actionType == GovernanceTypes.ActionType.TreasuryBudgetApproval) {
            GovernanceTypes.TreasuryBudgetApprovalPayload memory payload = _decodeTreasuryBudgetApprovalPayload(
                actionRecord.payload, actionRecord.actionId, actionRecord.targetModule
            );

            IBudgetEnvelopeRegistry(actionRecord.targetModuleAddress)
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

            ILegislationRegistry legislationRegistry = ILegislationRegistry(actionRecord.targetModuleAddress);
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

            ITreasuryVault(actionRecord.targetModuleAddress).executeDisbursement(payload);
            return;
        }

        revert UnsupportedExecutionAction(actionRecord.actionType);
    }

    function _resolveActionSchedule(GovernanceTypes.ActionRequest calldata request, uint64 currentTimestamp)
        private
        view
        returns (uint64 earliestExecutionTime, uint64 expiresAt)
    {
        uint64 earliestAllowed = currentTimestamp + minimumDelay(request.actionType);
        earliestExecutionTime =
            request.requestedExecutionTime > earliestAllowed ? request.requestedExecutionTime : earliestAllowed;
        expiresAt = request.expiresAt == 0 ? earliestExecutionTime + _defaultExecutionWindow : request.expiresAt;
    }

    function _computeActionId(
        GovernanceTypes.ActionRequest calldata request,
        address targetModuleAddress,
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
                targetModuleAddress,
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
        if (request.actionType == GovernanceTypes.ActionType.ModuleRegistration) {
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
        if (
            payload.enactedByReferendumId == bytes32(0)
                || (!LegislationTypes.isConstitutionalTier(payload.tier) && !LegislationTypes.isLawTier(payload.tier))
        ) {
            revert InvalidActionPayload(actionId);
        }
    }

    function _decodeTreasuryBudgetApprovalPayload(bytes memory payloadData, bytes32 actionId, bytes32 targetModule)
        private
        view
        returns (GovernanceTypes.TreasuryBudgetApprovalPayload memory payload)
    {
        if (targetModule != KernelModuleIds.BUDGET_ENVELOPE_REGISTRY || payloadData.length != 256) {
            revert InvalidActionPayload(actionId);
        }

        payload = abi.decode(payloadData, (GovernanceTypes.TreasuryBudgetApprovalPayload));
        if (
            payload.budgetId == bytes32(0) || payload.officeId == bytes32(0)
                || payload.disbursementType == TreasuryTypes.DisbursementType.Undefined || payload.allocatedAmount == 0
                || payload.asset == address(0) || payload.asset.code.length == 0 || payload.endsAt <= payload.startsAt
        ) {
            revert InvalidActionPayload(actionId);
        }
    }

    function _decodeTreasuryDisbursementPayload(bytes memory payloadData, bytes32 actionId, bytes32 targetModule)
        private
        view
        returns (GovernanceTypes.TreasuryDisbursementPayload memory payload)
    {
        if (targetModule != KernelModuleIds.TREASURY_VAULT || payloadData.length != 192) {
            revert InvalidActionPayload(actionId);
        }

        payload = abi.decode(payloadData, (GovernanceTypes.TreasuryDisbursementPayload));
        if (
            payload.requestId == bytes32(0) || payload.asset == address(0) || payload.asset.code.length == 0
                || payload.recipient == address(0) || payload.amount == 0
        ) {
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
        return _effectiveState(actionRecord.state, actionRecord.expiresAt);
    }

    function _deriveMemoryState(GovernanceTypes.ActionRecord memory actionRecord)
        private
        view
        returns (GovernanceTypes.ActionState state)
    {
        return _effectiveState(actionRecord.state, actionRecord.expiresAt);
    }

    /// @dev A still-`Queued` action whose expiry has passed reports as `Expired` without a state write; every other
    ///      state is returned verbatim. Shared by the storage and memory derivations so the rule lives in one place.
    function _effectiveState(GovernanceTypes.ActionState storedState, uint64 expiresAt)
        private
        view
        returns (GovernanceTypes.ActionState state)
    {
        if (storedState == GovernanceTypes.ActionState.Queued && expiresAt != 0 && block.timestamp > expiresAt) {
            return GovernanceTypes.ActionState.Expired;
        }

        return storedState;
    }

    function _requireRouterCaller(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.GOVERNANCE_ROUTER)) {
            revert UnauthorizedTimelockCaller(caller);
        }
    }

    function _targetModuleAddressForId(GovernanceTypes.ActionRequest calldata request)
        private
        view
        returns (address targetModuleAddress)
    {
        if (request.actionType == GovernanceTypes.ActionType.ModuleRegistration) {
            return address(0);
        }

        try _kernel.getModule(request.targetModule) returns (address moduleAddress) {
            return moduleAddress;
        } catch {
            return address(0);
        }
    }

    function _targetModuleAddressForQueue(GovernanceTypes.ActionRequest calldata request)
        private
        view
        returns (address targetModuleAddress)
    {
        if (request.actionType == GovernanceTypes.ActionType.ModuleRegistration) {
            _requireUnregisteredTargetModule(request.targetModule);
            return address(0);
        }

        targetModuleAddress = _kernel.getModule(request.targetModule);
        if (targetModuleAddress == address(0)) {
            revert IConstitutionKernel.ModuleNotRegistered(request.targetModule);
        }
    }

    function _requireQueuedTargetUnchanged(GovernanceTypes.ActionRecord storage actionRecord) private view {
        if (actionRecord.actionType == GovernanceTypes.ActionType.ModuleRegistration) {
            _requireUnregisteredTargetModule(actionRecord.targetModule);
            return;
        }

        address currentTargetModuleAddress = _kernel.getModule(actionRecord.targetModule);
        if (currentTargetModuleAddress != actionRecord.targetModuleAddress) {
            revert QueuedTargetModuleChanged(
                actionRecord.actionId,
                actionRecord.targetModule,
                actionRecord.targetModuleAddress,
                currentTargetModuleAddress
            );
        }
    }

    function _requireNoPendingSenateCancellation(bytes32 actionId) private view {
        (bool pending, uint64 deadline) = _senateCancellationPending(actionId);
        if (pending) {
            revert ActionCancellationPending(actionId, deadline);
        }
    }

    function _hasPendingSenateCancellation(bytes32 actionId) private view returns (bool pending) {
        (pending,) = _senateCancellationPending(actionId);
    }

    function _senateCancellationPending(bytes32 actionId) private view returns (bool pending, uint64 deadline) {
        address senateAppAddress = address(0);
        try _kernel.getModule(KernelModuleIds.SENATE_APP) returns (address moduleAddress) {
            senateAppAddress = moduleAddress;
        } catch {
            return (false, 0);
        }

        SenateTypes.ActionCancellationRecord memory cancellationRecord =
            ISenateApp(senateAppAddress).getActionCancellationRecord(actionId);
        deadline = cancellationRecord.deadline;
        pending =
            cancellationRecord.exists && !cancellationRecord.finalized && deadline != 0 && block.timestamp >= deadline;
    }

    function _requireNoActiveSenateSuspension(bytes32 actionId) private view {
        (bool suspended, uint64 suspendedUntil) = _senateSuspensionActive(actionId);
        if (suspended) {
            revert ActionSuspended(actionId, suspendedUntil);
        }
    }

    function _hasActiveSenateSuspension(bytes32 actionId) private view returns (bool active) {
        (active,) = _senateSuspensionActive(actionId);
    }

    function _senateSuspensionActive(bytes32 actionId) private view returns (bool active, uint64 suspendedUntil) {
        address senateAppAddress = address(0);
        try _kernel.getModule(KernelModuleIds.SENATE_APP) returns (address moduleAddress) {
            senateAppAddress = moduleAddress;
        } catch {
            return (false, 0);
        }

        SenateTypes.DisbursementSuspension memory suspension =
            ISenateApp(senateAppAddress).getDisbursementSuspension(actionId);
        suspendedUntil = suspension.suspendedUntil;
        // Auto-lapses once suspendedUntil passes: no un-suspend call is required for execution to resume.
        active = suspension.exists && block.timestamp < suspendedUntil;
    }

    function _requireNotUnderConstitutionalReview(bytes32 actionId) private view {
        if (_isUnderConstitutionalReview(actionId)) {
            revert ActionUnderConstitutionalReview(actionId);
        }
    }

    function _isUnderConstitutionalReview(bytes32 actionId) private view returns (bool paused) {
        // Optional judiciary hook: a court module registered under CONSTITUTIONAL_REVIEW can pause execution of a
        // queued action pending review. Fail-open (not paused) when no such module is registered or the call fails,
        // so the deliberately un-repointable core timelock is never bricked by an absent or broken review module — a
        // future constitutional court is a pure add-on registered via an ordinary module-registration referendum.
        address reviewAddress;
        try _kernel.getModule(KernelModuleIds.CONSTITUTIONAL_REVIEW) returns (address moduleAddress) {
            reviewAddress = moduleAddress;
        } catch {
            return false;
        }

        try IConstitutionalReview(reviewAddress).isActionExecutionPaused(actionId) returns (bool actionPaused) {
            return actionPaused;
        } catch {
            return false;
        }
    }

    function _requireUnregisteredTargetModule(bytes32 moduleId) private view {
        if (moduleId == bytes32(0)) {
            revert IConstitutionKernel.ModuleNotRegistered(moduleId);
        }

        try _kernel.getModuleRecord(moduleId) returns (GovernanceTypes.ModuleRecord memory moduleRecord) {
            if (moduleRecord.moduleAddress == address(0)) {
                return;
            }

            revert IConstitutionKernel.ModuleAlreadyRegistered(moduleId);
        } catch {
            return;
        }
    }
}
