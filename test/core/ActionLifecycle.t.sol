// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IGovernanceRouter} from "../../contracts/interfaces/IGovernanceRouter.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockConstitutionalReview} from "../../contracts/mocks/MockConstitutionalReview.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {SenateTypes} from "../../contracts/types/SenateTypes.sol";

contract AdversarialSenateHook {
    bool private immutable _fabricatePendingCancellation;
    bool private immutable _fabricateDisbursementSuspension;

    constructor(bool fabricatePendingCancellation, bool fabricateDisbursementSuspension) {
        _fabricatePendingCancellation = fabricatePendingCancellation;
        _fabricateDisbursementSuspension = fabricateDisbursementSuspension;
    }

    function getActionCancellationRecord(bytes32 actionId)
        external
        view
        returns (SenateTypes.ActionCancellationRecord memory record)
    {
        record.actionId = actionId;
        record.deadline = 1;
        record.exists = _fabricatePendingCancellation;
    }

    function getDisbursementSuspension(bytes32)
        external
        view
        returns (SenateTypes.DisbursementSuspension memory suspension)
    {
        suspension.exists = _fabricateDisbursementSuspension;
        suspension.suspendedUntil = type(uint64).max;
    }
}

/// @title ActionLifecycleTest
/// @notice Covers queued governance action routing and execution.
contract ActionLifecycleTest is Test {
    bytes32 internal constant TARGET_MODULE_ID = KernelModuleIds.DECISION_APP;
    bytes32 internal constant UNREGISTERED_MODULE_ID = keccak256("test.unregistered-module");

    event ActionQueued(
        bytes32 indexed actionId,
        GovernanceTypes.ActionType indexed actionType,
        bytes32 indexed targetModule,
        GovernanceTypes.ActionOrigin origin,
        bytes32 originReference,
        bytes32 policyReference,
        address targetModuleAddress,
        bytes32 payloadHash,
        uint64 createdAt,
        uint64 earliestExecutionTime,
        uint64 expiresAt
    );

    ActionTimelock internal timelock;
    ConstitutionKernel internal kernel;
    GovernanceRouter internal router;
    MockModule internal initialModule;
    MockModule internal replacementModule;

    address internal referendumAuthority = makeAddr("referendumAuthority");
    address internal senateAuthority = makeAddr("senateAuthority");
    address internal congressAuthority = makeAddr("congressAuthority");
    address internal officeAuthority = makeAddr("officeAuthority");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(address(kernel), _defaultDelayConfig());
        router = new GovernanceRouter(address(kernel), address(this));
        initialModule = new MockModule(keccak256("initial"));
        replacementModule = new MockModule(keccak256("replacement"));

        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));
        kernel.bootstrapSetModule(TARGET_MODULE_ID, address(initialModule));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(initialModule));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(initialModule));

        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, referendumAuthority);
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Senate, senateAuthority);
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Congress, congressAuthority);
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Office, officeAuthority);

        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();
    }

    function _defaultDelayConfig() internal pure returns (GovernanceTypes.TimelockDelayConfig memory config) {
        config = GovernanceTypes.TimelockDelayConfig({
            moduleGovernanceDelay: 2 days,
            treasuryBudgetApprovalDelay: 1 days,
            legislationEnactmentDelay: 1 days,
            treasuryDisbursementDelay: 2 days,
            defaultExecutionWindow: 7 days
        });
    }

    function test_queueAction_StoresDeterministicAction() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(address(replacementModule));
        bytes32 previewedActionId = router.previewActionId(request);

        vm.prank(referendumAuthority);
        bytes32 actionId = router.routeAction(request);

        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);

        assertEq(actionId, previewedActionId);
        assertEq(actionRecord.actionId, previewedActionId);
        assertEq(uint256(actionRecord.state), uint256(GovernanceTypes.ActionState.Queued));
        assertEq(uint256(actionRecord.actionType), uint256(GovernanceTypes.ActionType.ModulePointerUpdate));
        assertEq(uint256(actionRecord.origin), uint256(GovernanceTypes.ActionOrigin.Referendum));
        assertEq(actionRecord.targetModule, TARGET_MODULE_ID);
        assertEq(actionRecord.targetModuleAddress, address(initialModule));
        assertEq(actionRecord.createdAt, uint64(block.timestamp));
        assertEq(
            actionRecord.earliestExecutionTime, uint64(block.timestamp) + timelock.minimumDelay(request.actionType)
        );
        assertEq(actionRecord.expiresAt, actionRecord.earliestExecutionTime + 7 days);
    }

    function test_queueAction_EmitsFullAuditEvent() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(address(replacementModule));
        bytes32 actionId = router.previewActionId(request);
        uint64 createdAt = uint64(block.timestamp);
        uint64 earliestExecutionTime = createdAt + timelock.minimumDelay(request.actionType);
        uint64 expiresAt = earliestExecutionTime + 7 days;

        vm.expectEmit(address(timelock));
        emit ActionQueued(
            actionId,
            request.actionType,
            request.targetModule,
            request.origin,
            request.originReference,
            request.policyReference,
            address(initialModule),
            keccak256(request.payload),
            createdAt,
            earliestExecutionTime,
            expiresAt
        );

        vm.prank(referendumAuthority);
        router.routeAction(request);
    }

    function test_queueAction_RevertsForEquivalentRequestWithShiftedRequestedExecutionTime() public {
        GovernanceTypes.ActionRequest memory canonicalRequest = _buildModuleUpdateRequest(address(replacementModule));
        GovernanceTypes.ActionRequest memory equivalentRequest = _buildModuleUpdateRequest(address(replacementModule));
        equivalentRequest.requestedExecutionTime = 1;

        bytes32 canonicalActionId = router.previewActionId(canonicalRequest);
        assertEq(canonicalActionId, router.previewActionId(equivalentRequest));

        vm.prank(referendumAuthority);
        router.routeAction(canonicalRequest);

        vm.prank(referendumAuthority);
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.ActionAlreadyQueued.selector, canonicalActionId));
        router.routeAction(equivalentRequest);
    }

    function test_queueAction_RevertsForEquivalentRequestWithExplicitDefaultExpiry() public {
        GovernanceTypes.ActionRequest memory canonicalRequest = _buildModuleUpdateRequest(address(replacementModule));
        GovernanceTypes.ActionRequest memory equivalentRequest = _buildModuleUpdateRequest(address(replacementModule));
        equivalentRequest.expiresAt =
            uint64(block.timestamp) + timelock.minimumDelay(equivalentRequest.actionType) + 7 days;

        bytes32 canonicalActionId = router.previewActionId(canonicalRequest);
        assertEq(canonicalActionId, router.previewActionId(equivalentRequest));

        vm.prank(referendumAuthority);
        router.routeAction(canonicalRequest);

        vm.prank(referendumAuthority);
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.ActionAlreadyQueued.selector, canonicalActionId));
        router.routeAction(equivalentRequest);
    }

    function test_cancelAction_AuthorizedOriginCancelsQueuedAction() public {
        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));

        vm.prank(referendumAuthority);
        router.cancelAction(actionId);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));
    }

    function test_cancelAction_RevertsWhenCallerBypassesRouter() public {
        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.UnauthorizedTimelockCaller.selector, outsider));
        timelock.cancelAction(actionId);
    }

    function test_executeAction_AfterDelayUpdatesKernelModule() public {
        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);

        vm.warp(actionRecord.earliestExecutionTime);
        timelock.executeAction(actionId);

        assertEq(kernel.getModule(TARGET_MODULE_ID), address(replacementModule));
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Executed));
    }

    function test_executeAction_AfterDelayRegistersNewKernelModule() public {
        MockModule newModule = new MockModule(keccak256("new-module"));
        GovernanceTypes.ActionRequest memory request = _buildModuleRegistrationRequest(address(newModule));

        vm.prank(referendumAuthority);
        bytes32 actionId = router.routeAction(request);

        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);
        assertEq(uint256(actionRecord.actionType), uint256(GovernanceTypes.ActionType.ModuleRegistration));
        assertEq(actionRecord.targetModule, UNREGISTERED_MODULE_ID);
        assertEq(
            actionRecord.earliestExecutionTime, uint64(block.timestamp) + timelock.minimumDelay(request.actionType)
        );

        vm.warp(actionRecord.earliestExecutionTime);
        timelock.executeAction(actionId);

        assertEq(kernel.getModule(UNREGISTERED_MODULE_ID), address(newModule));
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Executed));
    }

    function test_executeAction_ConstitutionalReviewRegisteredAfterBootstrapCanPauseThenReleaseExecution() public {
        // A future Judiciary is added AFTER bootstrap is disabled (setUp already disabled it) via an ordinary
        // module-registration action — the same governance path a constitutional court would use in production —
        // then it pauses/releases timelock execution through the CONSTITUTIONAL_REVIEW hook.
        MockConstitutionalReview review = new MockConstitutionalReview();
        GovernanceTypes.ActionRequest memory registration = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.ModuleRegistration,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: bytes32(uint256(505)),
            policyReference: bytes32(uint256(606)),
            targetModule: KernelModuleIds.CONSTITUTIONAL_REVIEW,
            payload: abi.encode(GovernanceTypes.ModuleUpdatePayload({newModuleAddress: address(review)})),
            requestedExecutionTime: 0,
            expiresAt: 0
        });

        vm.prank(referendumAuthority);
        bytes32 registrationId = router.routeAction(registration);
        vm.warp(timelock.getAction(registrationId).earliestExecutionTime);
        timelock.executeAction(registrationId);
        assertEq(kernel.getModule(KernelModuleIds.CONSTITUTIONAL_REVIEW), address(review));

        // A queued action is now pausable by the registered review module.
        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);
        vm.warp(actionRecord.earliestExecutionTime);

        review.setActionPaused(actionId, true);
        assertFalse(timelock.isActionExecutable(actionId));
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.ActionUnderConstitutionalReview.selector, actionId));
        timelock.executeAction(actionId);

        // Releasing review lets execution proceed — the court's pause is not permanent.
        review.setActionPaused(actionId, false);
        assertTrue(timelock.isActionExecutable(actionId));
        timelock.executeAction(actionId);
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Executed));
        assertEq(kernel.getModule(TARGET_MODULE_ID), address(replacementModule));
    }

    function test_executeAction_RevertsBeforeDelay() public {
        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);

        vm.warp(actionRecord.earliestExecutionTime - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IActionTimelock.ActionNotReady.selector, actionId, actionRecord.earliestExecutionTime
            )
        );
        timelock.executeAction(actionId);
    }

    function test_isActionExecutable_ReturnsFalseAfterTargetPointerChanges() public {
        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);
        MockModule interveningModule = new MockModule(keccak256("intervening-module"));
        vm.prank(address(timelock));
        kernel.governanceUpdateModule(TARGET_MODULE_ID, address(interveningModule));

        vm.warp(actionRecord.earliestExecutionTime);
        assertFalse(timelock.isActionExecutable(actionId));
        vm.expectRevert(
            abi.encodeWithSelector(
                IActionTimelock.QueuedTargetModuleChanged.selector,
                actionId,
                TARGET_MODULE_ID,
                address(initialModule),
                address(interveningModule)
            )
        );
        timelock.executeAction(actionId);
    }

    function test_executeAction_CannotExecuteTwice() public {
        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);

        vm.warp(actionRecord.earliestExecutionTime);
        timelock.executeAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IActionTimelock.ActionAlreadyFinalized.selector, actionId, GovernanceTypes.ActionState.Executed
            )
        );
        timelock.executeAction(actionId);
    }

    function test_executeActions_AtomicallyUpdatesLinkedPointers() public {
        GovernanceTypes.ActionRequest memory appRequest = _buildModuleUpdateRequest(address(replacementModule));
        vm.prank(referendumAuthority);
        bytes32 appActionId = router.routeAction(appRequest);

        GovernanceTypes.ActionRequest memory authorityRequest = _buildModuleUpdateRequest(address(replacementModule));
        authorityRequest.targetModule = KernelModuleIds.STAKE_REGISTRY_AUTHORITY;
        authorityRequest.originReference = bytes32(uint256(303));
        vm.prank(referendumAuthority);
        bytes32 authorityActionId = router.routeAction(authorityRequest);

        vm.warp(timelock.getAction(appActionId).earliestExecutionTime);
        bytes32[] memory actionIds = new bytes32[](2);
        actionIds[0] = appActionId;
        actionIds[1] = authorityActionId;
        timelock.executeActions(actionIds);

        assertEq(kernel.getModule(TARGET_MODULE_ID), address(replacementModule));
        assertEq(kernel.getModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY), address(replacementModule));
    }

    function test_executeActions_RevertsEntireBatchWhenOneTargetChanged() public {
        GovernanceTypes.ActionRequest memory appRequest = _buildModuleUpdateRequest(address(replacementModule));
        vm.prank(referendumAuthority);
        bytes32 appActionId = router.routeAction(appRequest);

        GovernanceTypes.ActionRequest memory authorityRequest = _buildModuleUpdateRequest(address(replacementModule));
        authorityRequest.targetModule = KernelModuleIds.STAKE_REGISTRY_AUTHORITY;
        authorityRequest.originReference = bytes32(uint256(303));
        vm.prank(referendumAuthority);
        bytes32 authorityActionId = router.routeAction(authorityRequest);

        MockModule interveningModule = new MockModule(keccak256("intervening-authority"));
        vm.prank(address(timelock));
        kernel.governanceUpdateModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(interveningModule));

        vm.warp(timelock.getAction(appActionId).earliestExecutionTime);
        bytes32[] memory actionIds = new bytes32[](2);
        actionIds[0] = appActionId;
        actionIds[1] = authorityActionId;
        vm.expectRevert(
            abi.encodeWithSelector(
                IActionTimelock.QueuedTargetModuleChanged.selector,
                authorityActionId,
                KernelModuleIds.STAKE_REGISTRY_AUTHORITY,
                address(initialModule),
                address(interveningModule)
            )
        );
        timelock.executeActions(actionIds);

        assertEq(kernel.getModule(TARGET_MODULE_ID), address(initialModule));
        assertEq(uint256(timelock.getActionState(appActionId)), uint256(GovernanceTypes.ActionState.Queued));
    }

    function test_executeActions_RejectsEmptyBatch() public {
        bytes32[] memory actionIds = new bytes32[](0);
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.InvalidActionBatchLength.selector, 0));
        timelock.executeActions(actionIds);
    }

    function test_expireAction_RecordsExpiredState() public {
        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);

        vm.warp(actionRecord.expiresAt + 1);
        timelock.expireAction(actionId);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Expired));
    }

    function test_routeAction_RevertsForUnsupportedActionType() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(address(replacementModule));
        request.actionType = GovernanceTypes.ActionType.PolicyPointerUpdate;

        vm.prank(referendumAuthority);
        vm.expectRevert(abi.encodeWithSelector(IGovernanceRouter.UnsupportedActionType.selector, request.actionType));
        router.routeAction(request);
    }

    function test_routeAction_RevertsForUnauthorizedOriginCaller() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(address(replacementModule));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IGovernanceRouter.UnauthorizedGovernanceOrigin.selector, outsider));
        router.routeAction(request);
    }

    function test_routeAction_AllowsCurrentAuditedOriginsToRouteSupportedTypedActions() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(address(replacementModule));

        request.origin = GovernanceTypes.ActionOrigin.Congress;
        vm.prank(congressAuthority);
        bytes32 congressActionId = router.routeAction(request);
        assertEq(uint256(timelock.getActionState(congressActionId)), uint256(GovernanceTypes.ActionState.Queued));

        request.origin = GovernanceTypes.ActionOrigin.Senate;
        vm.prank(senateAuthority);
        bytes32 senateActionId = router.routeAction(request);
        assertEq(uint256(timelock.getActionState(senateActionId)), uint256(GovernanceTypes.ActionState.Queued));

        request.origin = GovernanceTypes.ActionOrigin.Office;
        vm.prank(officeAuthority);
        bytes32 officeActionId = router.routeAction(request);
        assertEq(uint256(timelock.getActionState(officeActionId)), uint256(GovernanceTypes.ActionState.Queued));
    }

    function test_routeAction_RevertsForUnregisteredTargetModule() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(address(replacementModule));
        request.targetModule = UNREGISTERED_MODULE_ID;

        vm.prank(referendumAuthority);
        vm.expectRevert(abi.encodeWithSelector(IGovernanceRouter.InvalidTargetModule.selector, UNREGISTERED_MODULE_ID));
        router.routeAction(request);
    }

    function test_routeAction_RevertsWhenRegisteringExistingTargetModule() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleRegistrationRequest(address(replacementModule));
        request.targetModule = TARGET_MODULE_ID;

        vm.prank(referendumAuthority);
        vm.expectRevert(abi.encodeWithSelector(IGovernanceRouter.InvalidTargetModule.selector, TARGET_MODULE_ID));
        router.routeAction(request);
    }

    function test_cancelAction_RevertsForUnauthorizedOriginCaller() public {
        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IGovernanceRouter.UnauthorizedGovernanceOrigin.selector, outsider));
        router.cancelAction(actionId);
    }

    function test_SenateCannotDirectlyCancelItsOwnPointerReplacement_ButCanCancelOtherAction() public {
        AdversarialSenateHook incumbentSenate = new AdversarialSenateHook(false, false);
        _registerModule(KernelModuleIds.SENATE_APP, address(incumbentSenate));

        MockModule replacementSenate = new MockModule(keccak256("replacement-senate"));
        GovernanceTypes.ActionRequest memory selfReplacement = _buildModuleUpdateRequest(address(replacementSenate));
        selfReplacement.targetModule = KernelModuleIds.SENATE_APP;
        vm.prank(referendumAuthority);
        bytes32 selfReplacementId = router.routeAction(selfReplacement);

        vm.prank(address(incumbentSenate));
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceRouter.SelfReplacementCancellationForbidden.selector,
                selfReplacementId,
                KernelModuleIds.SENATE_APP
            )
        );
        router.cancelAction(selfReplacementId);

        bytes32 ordinaryActionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        vm.prank(address(incumbentSenate));
        router.cancelAction(ordinaryActionId);

        assertEq(uint256(timelock.getActionState(ordinaryActionId)), uint256(GovernanceTypes.ActionState.Canceled));
        assertEq(uint256(timelock.getActionState(selfReplacementId)), uint256(GovernanceTypes.ActionState.Queued));

        vm.prank(referendumAuthority);
        router.cancelAction(selfReplacementId);
        assertEq(uint256(timelock.getActionState(selfReplacementId)), uint256(GovernanceTypes.ActionState.Canceled));
    }

    function test_SenateCannotCancelOwnReplacementThroughAliasedOriginRole() public {
        AdversarialSenateHook incumbentSenate = new AdversarialSenateHook(false, false);
        _registerModule(KernelModuleIds.SENATE_APP, address(incumbentSenate));
        _registerModule(KernelModuleIds.REFERENDUM_APP, address(incumbentSenate));

        MockModule replacementSenate = new MockModule(keccak256("replacement-senate"));
        GovernanceTypes.ActionRequest memory selfReplacement = _buildModuleUpdateRequest(address(replacementSenate));
        selfReplacement.targetModule = KernelModuleIds.SENATE_APP;
        vm.prank(address(incumbentSenate));
        bytes32 selfReplacementId = router.routeAction(selfReplacement);

        vm.prank(address(incumbentSenate));
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceRouter.SelfReplacementCancellationForbidden.selector,
                selfReplacementId,
                KernelModuleIds.SENATE_APP
            )
        );
        router.cancelAction(selfReplacementId);

        assertEq(uint256(timelock.getActionState(selfReplacementId)), uint256(GovernanceTypes.ActionState.Queued));
    }

    function test_SenateFabricatedHooksCannotBlockOwnPointerReplacement_ButPendingCancellationBlocksOtherAction()
        public
    {
        AdversarialSenateHook incumbentSenate = new AdversarialSenateHook(true, true);
        _registerModule(KernelModuleIds.SENATE_APP, address(incumbentSenate));

        MockModule replacementSenate = new MockModule(keccak256("replacement-senate"));
        GovernanceTypes.ActionRequest memory selfReplacement = _buildModuleUpdateRequest(address(replacementSenate));
        selfReplacement.targetModule = KernelModuleIds.SENATE_APP;
        vm.prank(referendumAuthority);
        bytes32 selfReplacementId = router.routeAction(selfReplacement);

        bytes32 ordinaryActionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        vm.warp(timelock.getAction(selfReplacementId).earliestExecutionTime);

        assertFalse(timelock.isActionExecutable(ordinaryActionId));
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.ActionCancellationPending.selector, ordinaryActionId, 1));
        timelock.executeAction(ordinaryActionId);

        assertTrue(timelock.isActionExecutable(selfReplacementId));
        timelock.executeAction(selfReplacementId);
        assertEq(kernel.getModule(KernelModuleIds.SENATE_APP), address(replacementSenate));
    }

    function test_SenateSuspensionHookOnlyBlocksTreasuryDisbursements() public {
        MockModule treasuryVault = new MockModule(keccak256("treasury-vault"));
        _registerModule(KernelModuleIds.TREASURY_VAULT, address(treasuryVault));

        AdversarialSenateHook incumbentSenate = new AdversarialSenateHook(false, true);
        _registerModule(KernelModuleIds.SENATE_APP, address(incumbentSenate));

        bytes32 ordinaryActionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        GovernanceTypes.ActionRequest memory disbursement = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.TreasuryDisbursement,
            origin: GovernanceTypes.ActionOrigin.Office,
            originReference: keccak256("adversarial-suspension"),
            policyReference: keccak256("treasury-policy"),
            targetModule: KernelModuleIds.TREASURY_VAULT,
            payload: abi.encode(
                GovernanceTypes.TreasuryDisbursementPayload({
                    requestId: keccak256("request"),
                    budgetId: keccak256("budget"),
                    asset: address(initialModule),
                    recipient: outsider,
                    amount: 1,
                    noteHash: bytes32(0)
                })
            ),
            requestedExecutionTime: 0,
            expiresAt: 0
        });
        vm.prank(officeAuthority);
        bytes32 disbursementId = router.routeAction(disbursement);

        vm.warp(timelock.getAction(disbursementId).earliestExecutionTime);

        assertTrue(timelock.isActionExecutable(ordinaryActionId));
        assertFalse(timelock.isActionExecutable(disbursementId));
        vm.expectRevert(
            abi.encodeWithSelector(IActionTimelock.ActionSuspended.selector, disbursementId, type(uint64).max)
        );
        timelock.executeAction(disbursementId);
    }

    function test_ConstitutionalReviewCannotBlockOwnPointerReplacement_ButCanPauseOtherAction() public {
        MockConstitutionalReview incumbentReview = new MockConstitutionalReview();
        _registerModule(KernelModuleIds.CONSTITUTIONAL_REVIEW, address(incumbentReview));

        MockModule replacementReview = new MockModule(keccak256("replacement-review"));
        GovernanceTypes.ActionRequest memory selfReplacement = _buildModuleUpdateRequest(address(replacementReview));
        selfReplacement.targetModule = KernelModuleIds.CONSTITUTIONAL_REVIEW;
        vm.prank(referendumAuthority);
        bytes32 selfReplacementId = router.routeAction(selfReplacement);

        bytes32 ordinaryActionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        incumbentReview.setActionPaused(selfReplacementId, true);
        incumbentReview.setActionPaused(ordinaryActionId, true);
        vm.warp(timelock.getAction(selfReplacementId).earliestExecutionTime);

        assertFalse(timelock.isActionExecutable(ordinaryActionId));
        vm.expectRevert(
            abi.encodeWithSelector(IActionTimelock.ActionUnderConstitutionalReview.selector, ordinaryActionId)
        );
        timelock.executeAction(ordinaryActionId);

        assertTrue(timelock.isActionExecutable(selfReplacementId));
        timelock.executeAction(selfReplacementId);
        assertEq(kernel.getModule(KernelModuleIds.CONSTITUTIONAL_REVIEW), address(replacementReview));
    }

    function test_queueAction_RevertsWhenCallerBypassesRouter() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(address(replacementModule));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.UnauthorizedTimelockCaller.selector, outsider));
        timelock.queueAction(request);
    }

    function test_queueAction_RevertsForMalformedPayload() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(address(replacementModule));
        request.payload = hex"1234";
        bytes32 actionId = router.previewActionId(request);

        vm.prank(referendumAuthority);
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.InvalidActionPayload.selector, actionId));
        router.routeAction(request);
    }

    function test_queueAction_RevertsForInvalidReplacementAddress() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(outsider);

        vm.prank(referendumAuthority);
        vm.expectRevert(
            abi.encodeWithSelector(IConstitutionKernel.InvalidModuleAddress.selector, TARGET_MODULE_ID, outsider)
        );
        router.routeAction(request);
    }

    function test_governanceUpdateModule_RevertsForUnauthorizedCaller() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IConstitutionKernel.UnauthorizedKernelCaller.selector, outsider));
        kernel.governanceUpdateModule(TARGET_MODULE_ID, address(replacementModule));
    }

    function test_governanceUpdateModule_RevertsWhenTargetModuleNotRegistered() public {
        MockModule unregisteredModule = new MockModule(keccak256("unregistered"));

        vm.prank(address(timelock));
        vm.expectRevert(
            abi.encodeWithSelector(IConstitutionKernel.ModuleNotRegistered.selector, UNREGISTERED_MODULE_ID)
        );
        kernel.governanceUpdateModule(UNREGISTERED_MODULE_ID, address(unregisteredModule));
    }

    function test_governanceUpdateModule_AllowsStateMigrationAndUnclassifiedExtensionReplacement() public {
        vm.startPrank(address(timelock));
        kernel.governanceUpdateModule(KernelModuleIds.IDENTITY_REGISTRY, address(replacementModule));

        MockModule extensionModule = new MockModule(keccak256("extension"));
        kernel.governanceRegisterModule(UNREGISTERED_MODULE_ID, address(extensionModule));
        kernel.governanceUpdateModule(UNREGISTERED_MODULE_ID, address(replacementModule));
        vm.stopPrank();

        assertEq(kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY), address(replacementModule));
        assertEq(kernel.getModule(UNREGISTERED_MODULE_ID), address(replacementModule));
    }

    function test_executeAction_BrokenFutureSenateInterfaceCannotBrickQueue() public {
        MockModule incompatibleSenate = new MockModule(keccak256("future-senate-interface"));
        GovernanceTypes.ActionRequest memory registration = _buildModuleRegistrationRequest(address(incompatibleSenate));
        registration.targetModule = KernelModuleIds.SENATE_APP;

        vm.prank(referendumAuthority);
        bytes32 registrationId = router.routeAction(registration);
        vm.warp(timelock.getAction(registrationId).earliestExecutionTime);
        timelock.executeAction(registrationId);

        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));
        vm.warp(timelock.getAction(actionId).earliestExecutionTime);

        assertTrue(timelock.isActionExecutable(actionId));
        timelock.executeAction(actionId);
        assertEq(kernel.getModule(TARGET_MODULE_ID), address(replacementModule));
    }

    function test_governanceRegisterModule_RevertsForUnauthorizedCaller() public {
        MockModule unregisteredModule = new MockModule(keccak256("unregistered"));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IConstitutionKernel.UnauthorizedKernelCaller.selector, outsider));
        kernel.governanceRegisterModule(UNREGISTERED_MODULE_ID, address(unregisteredModule));
    }

    function test_governanceRegisterModule_RevertsWhenTargetModuleAlreadyRegistered() public {
        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(IConstitutionKernel.ModuleAlreadyRegistered.selector, TARGET_MODULE_ID));
        kernel.governanceRegisterModule(TARGET_MODULE_ID, address(replacementModule));
    }

    function _queueModuleUpdate(address caller, address newModuleAddress) internal returns (bytes32 actionId) {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(newModuleAddress);

        vm.prank(caller);
        actionId = router.routeAction(request);
    }

    function _registerModule(bytes32 moduleId, address moduleAddress) internal returns (bytes32 actionId) {
        GovernanceTypes.ActionRequest memory request = _buildModuleRegistrationRequest(moduleAddress);
        request.targetModule = moduleId;
        request.originReference = keccak256(abi.encode("register", moduleId));

        vm.prank(referendumAuthority);
        actionId = router.routeAction(request);
        vm.warp(timelock.getAction(actionId).earliestExecutionTime);
        timelock.executeAction(actionId);
    }

    function _buildModuleUpdateRequest(address newModuleAddress)
        internal
        pure
        returns (GovernanceTypes.ActionRequest memory request)
    {
        request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.ModulePointerUpdate,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: bytes32(uint256(101)),
            policyReference: bytes32(uint256(202)),
            targetModule: TARGET_MODULE_ID,
            payload: abi.encode(GovernanceTypes.ModuleUpdatePayload({newModuleAddress: newModuleAddress})),
            requestedExecutionTime: 0,
            expiresAt: 0
        });
    }

    function _buildModuleRegistrationRequest(address newModuleAddress)
        internal
        pure
        returns (GovernanceTypes.ActionRequest memory request)
    {
        request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.ModuleRegistration,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: bytes32(uint256(303)),
            policyReference: bytes32(uint256(404)),
            targetModule: UNREGISTERED_MODULE_ID,
            payload: abi.encode(GovernanceTypes.ModuleUpdatePayload({newModuleAddress: newModuleAddress})),
            requestedExecutionTime: 0,
            expiresAt: 0
        });
    }
}
