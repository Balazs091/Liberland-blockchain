// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IGovernanceRouter} from "../../contracts/interfaces/IGovernanceRouter.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";

/// @title ActionLifecycleTest
/// @notice Milestone 1 coverage for queued governance action routing and execution.
contract ActionLifecycleTest is Test {
    bytes32 internal constant TARGET_MODULE_ID = keccak256("test.target-module");
    bytes32 internal constant UNREGISTERED_MODULE_ID = keccak256("test.unregistered-module");

    event ActionQueued(
        bytes32 indexed actionId,
        GovernanceTypes.ActionType indexed actionType,
        bytes32 indexed targetModule,
        GovernanceTypes.ActionOrigin origin,
        bytes32 originReference,
        bytes32 policyReference,
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
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(address(kernel));
        router = new GovernanceRouter(address(kernel), address(this));
        initialModule = new MockModule(keccak256("initial"));
        replacementModule = new MockModule(keccak256("replacement"));

        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));
        kernel.bootstrapSetModule(TARGET_MODULE_ID, address(initialModule));

        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, referendumAuthority);
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Senate, senateAuthority);

        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();
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

    function test_routeAction_RevertsForUnregisteredTargetModule() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(address(replacementModule));
        request.targetModule = UNREGISTERED_MODULE_ID;

        vm.prank(referendumAuthority);
        vm.expectRevert(abi.encodeWithSelector(IGovernanceRouter.InvalidTargetModule.selector, UNREGISTERED_MODULE_ID));
        router.routeAction(request);
    }

    function test_cancelAction_RevertsForUnauthorizedOriginCaller() public {
        bytes32 actionId = _queueModuleUpdate(referendumAuthority, address(replacementModule));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IGovernanceRouter.UnauthorizedGovernanceOrigin.selector, outsider));
        router.cancelAction(actionId);
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

    function _queueModuleUpdate(address caller, address newModuleAddress) internal returns (bytes32 actionId) {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(newModuleAddress);

        vm.prank(caller);
        actionId = router.routeAction(request);
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
}
