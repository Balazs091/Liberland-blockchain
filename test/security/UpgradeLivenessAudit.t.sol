// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ReferendumApp} from "../../contracts/apps/ReferendumApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {IReferendumApp} from "../../contracts/interfaces/IReferendumApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {BoundedGovernanceHook} from "../../contracts/libraries/BoundedGovernanceHook.sol";
import {ISenateApp} from "../../contracts/interfaces/ISenateApp.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {SenateTypes} from "../../contracts/types/SenateTypes.sol";
import {ReferendumTypes} from "../../contracts/types/ReferendumTypes.sol";

/// @notice A well-encoded hostile replacement used to expose cross-hook liveness dependencies.
contract UpgradeLivenessBlockingHooks {
    function getActionCancellationRecord(bytes32 actionId)
        external
        pure
        returns (SenateTypes.ActionCancellationRecord memory record)
    {
        record.actionId = actionId;
        record.deadline = 1;
        record.exists = true;
    }

    function isActionExecutionPaused(bytes32) external pure returns (bool) {
        return true;
    }

    function getReferendumVetoRecord(bytes32 referendumId)
        external
        pure
        returns (SenateTypes.ReferendumVetoRecord memory record)
    {
        record.referendumId = referendumId;
        record.deadline = 1;
        record.exists = true;
    }
}

/// @notice A successful call with an incomplete ABI response is not an external-call revert.
contract UpgradeLivenessMalformedHook {
    fallback() external {
        assembly ("memory-safe") {
            return(0, 0)
        }
    }
}

/// @notice A successful bool response whose word is outside the ABI bool domain.
contract UpgradeLivenessInvalidBoolHook {
    fallback() external {
        assembly ("memory-safe") {
            mstore(0, 2)
            return(0, 32)
        }
    }
}

/// @notice Models a broken view hook that consumes its entire forwarded gas allowance.
contract UpgradeLivenessGasBurningHook {
    fallback() external {
        assembly ("memory-safe") {
            for {} 1 {} {}
        }
    }
}

contract UpgradeLivenessOversizedHook {
    fallback() external {
        assembly ("memory-safe") {
            let response := mload(0x40)
            mstore(response, 1)
            return(response, 16384)
        }
    }
}

contract UpgradeLivenessRawHook {
    bytes private _response;

    constructor(bytes memory response) {
        _response = response;
    }

    fallback() external {
        bytes memory response = _response;
        assembly ("memory-safe") {
            return(add(response, 32), mload(response))
        }
    }
}

contract UpgradeLivenessHookProbe {
    function review(address hook) external view returns (bool paused) {
        return BoundedGovernanceHook.executionPaused(hook, bytes32(uint256(1)));
    }

    function records(address hook) external view returns (bool cancellation, bool veto, bool suspension) {
        cancellation = BoundedGovernanceHook.actionCancellation(hook, bytes32(uint256(1))).exists;
        veto = BoundedGovernanceHook.referendumVeto(hook, bytes32(uint256(1))).exists;
        suspension = BoundedGovernanceHook.disbursementSuspension(hook, bytes32(uint256(1))).exists;
    }
}

/// @notice Isolates the real ReferendumApp finalization hook from voting/registry behavior tested elsewhere.
contract UpgradeLivenessReferendumFixture {
    bool public finalized;

    function getReferendum(bytes32 id) external view returns (ReferendumTypes.ReferendumRecord memory record) {
        record.referendumId = id;
        record.referendumClass = ReferendumTypes.ReferendumClass.Legislation;
        record.referendumPolicy = address(this);
    }

    function evaluateOutcome(
        ReferendumTypes.ReferendumClass,
        ReferendumTypes.ProposalOrigin,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        bool
    ) external pure returns (ReferendumTypes.PolicyOutcome memory outcome) {
        return outcome;
    }

    function finalizeReferendum(bytes32, ReferendumTypes.ReferendumResultInput calldata) external {
        finalized = true;
    }
}

/// @notice Characterization evidence for the exact 8b6798f upgrade-liveness review, not exploit deployment code.
contract UpgradeLivenessAuditTest is Test {
    ConstitutionKernel internal kernel;
    GovernanceRouter internal router;
    ActionTimelock internal timelock;
    MockModule internal replacement;
    address internal referendumOrigin;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(
            address(kernel),
            GovernanceTypes.TimelockDelayConfig({
                moduleGovernanceDelay: 2 days,
                treasuryBudgetApprovalDelay: 1 days,
                legislationEnactmentDelay: 1 days,
                treasuryDisbursementDelay: 2 days,
                defaultExecutionWindow: 7 days
            })
        );
        router = new GovernanceRouter(address(kernel), address(this));
        replacement = new MockModule(keccak256("replacement"));
        referendumOrigin = address(new MockModule(keccak256("referendum-origin")));
        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_APP, referendumOrigin);
        kernel.bootstrapSetModule(KernelModuleIds.DECISION_APP, address(new MockModule(keccak256("old"))));
        router.disableBootstrapAuthority();
    }

    function _queue(bytes32 moduleId) internal returns (bytes32 actionId) {
        vm.prank(referendumOrigin);
        return router.routeAction(
            GovernanceTypes.ActionRequest({
                actionType: GovernanceTypes.ActionType.ModulePointerUpdate,
                origin: GovernanceTypes.ActionOrigin.Referendum,
                originReference: keccak256(abi.encode("approved-referendum", moduleId)),
                policyReference: keccak256("approved-policy-bundle"),
                targetModule: moduleId,
                payload: abi.encode(GovernanceTypes.ModuleUpdatePayload({newModuleAddress: address(replacement)})),
                requestedExecutionTime: 0,
                expiresAt: 0
            })
        );
    }

    /// @notice Neither self-replacement exemption protects against the other incumbent's negative hook.
    function test_Audit_CrossVetoLocksBothIndividuallyExemptReplacementActions() public {
        UpgradeLivenessBlockingHooks incumbentSenate = new UpgradeLivenessBlockingHooks();
        UpgradeLivenessBlockingHooks incumbentReview = new UpgradeLivenessBlockingHooks();
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(incumbentSenate));
        kernel.bootstrapSetModule(KernelModuleIds.CONSTITUTIONAL_REVIEW, address(incumbentReview));
        kernel.disableBootstrapAuthority();
        bytes32 senateAction = _queue(KernelModuleIds.SENATE_APP);
        bytes32 reviewAction = _queue(KernelModuleIds.CONSTITUTIONAL_REVIEW);
        vm.warp(timelock.getAction(senateAction).earliestExecutionTime);

        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.ActionUnderConstitutionalReview.selector, senateAction));
        timelock.executeAction(senateAction);
        vm.expectRevert(
            abi.encodeWithSelector(IActionTimelock.ActionCancellationPending.selector, reviewAction, uint64(1))
        );
        timelock.executeAction(reviewAction);

        bytes32[] memory actions = new bytes32[](2);
        actions[0] = senateAction;
        actions[1] = reviewAction;
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.ActionUnderConstitutionalReview.selector, senateAction));
        timelock.executeActions(actions);
        actions[0] = reviewAction;
        actions[1] = senateAction;
        vm.expectRevert(
            abi.encodeWithSelector(IActionTimelock.ActionCancellationPending.selector, reviewAction, uint64(1))
        );
        timelock.executeActions(actions);

        assertEq(kernel.getModule(KernelModuleIds.SENATE_APP), address(incumbentSenate));
        assertEq(kernel.getModule(KernelModuleIds.CONSTITUTIONAL_REVIEW), address(incumbentReview));
    }

    /// @notice Empty successful returndata used to revert outside try/catch; it now disables the optional hook.
    function test_Audit_MalformedSenateResponseDoesNotFreezeUnrelatedQueuedUpgrade() public {
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(new UpgradeLivenessMalformedHook()));
        kernel.disableBootstrapAuthority();
        bytes32 actionId = _queue(KernelModuleIds.DECISION_APP);
        vm.warp(timelock.getAction(actionId).earliestExecutionTime);
        assertTrue(timelock.isActionExecutable(actionId));
        timelock.executeAction(actionId);
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Executed));
    }

    /// @notice Invalid ABI bool values are rejected before decoding, without blocking the action.
    function test_Audit_InvalidReviewBoolDoesNotFreezeUnrelatedQueuedUpgrade() public {
        kernel.bootstrapSetModule(KernelModuleIds.CONSTITUTIONAL_REVIEW, address(new UpgradeLivenessInvalidBoolHook()));
        kernel.disableBootstrapAuthority();
        bytes32 actionId = _queue(KernelModuleIds.DECISION_APP);
        vm.warp(timelock.getAction(actionId).earliestExecutionTime);
        assertTrue(timelock.isActionExecutable(actionId));
        timelock.executeAction(actionId);
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Executed));
    }

    /// @notice Two gas-burning hooks cannot successively consume the caller's full gas budget.
    function test_Audit_TwoBrokenHooksCannotExhaustExecutionGas() public {
        UpgradeLivenessGasBurningHook incumbent = new UpgradeLivenessGasBurningHook();
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(incumbent));
        kernel.bootstrapSetModule(KernelModuleIds.CONSTITUTIONAL_REVIEW, address(incumbent));
        kernel.disableBootstrapAuthority();
        bytes32 actionId = _queue(KernelModuleIds.DECISION_APP);
        vm.warp(timelock.getAction(actionId).earliestExecutionTime);
        (bool success,) = address(timelock).call{gas: 16_000_000}(abi.encodeCall(timelock.executeAction, (actionId)));
        assertTrue(success);
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Executed));
    }

    /// @notice A caller cannot deliberately underfund the bounded callback to bypass a valid pause.
    function test_Audit_UnderfundedOptionalHookRevertsInsteadOfFailingOpen() public {
        UpgradeLivenessHookProbe probe = new UpgradeLivenessHookProbe();
        UpgradeLivenessBlockingHooks hook = new UpgradeLivenessBlockingHooks();
        assertTrue(probe.review(address(hook)));
        (bool success, bytes memory reason) =
            address(probe).staticcall{gas: 100_000}(abi.encodeCall(probe.review, (address(hook))));
        assertFalse(success);
        assertEq(bytes4(reason), BoundedGovernanceHook.InsufficientHookGas.selector);
    }

    /// @notice Narrow integers and bools must be canonical before the shared helper decodes hook records.
    function testFuzz_Audit_NoncanonicalRecordWordsNeverReachABIDecoder(uint8 rawIndex) public {
        uint256 index = bound(uint256(rawIndex), 1, 9);
        uint256[10] memory words;
        words[7] = 1;
        words[index] = type(uint256).max;
        UpgradeLivenessRawHook hook = new UpgradeLivenessRawHook(abi.encode(words));
        UpgradeLivenessHookProbe probe = new UpgradeLivenessHookProbe();
        (bool cancellation, bool veto, bool suspension) = probe.records(address(hook));
        assertFalse(cancellation);
        assertFalse(veto);
        assertFalse(suspension);
    }

    /// @notice An oversized successful response cannot force the caller to allocate unbounded memory.
    function test_Audit_OversizedResponseIsIgnored() public {
        UpgradeLivenessOversizedHook hook = new UpgradeLivenessOversizedHook();
        (bool succeeded, bytes memory response) = address(hook).staticcall{gas: 100_000}(hex"aabbccdd");
        assertTrue(succeeded);
        assertEq(response.length, 16_384);
        UpgradeLivenessHookProbe probe = new UpgradeLivenessHookProbe();
        assertFalse(probe.review(address(hook)));
        (bool cancellation, bool veto, bool suspension) = probe.records(address(hook));
        assertFalse(cancellation);
        assertFalse(veto);
        assertFalse(suspension);
    }

    /// @notice Canonical active records are preserved instead of accidentally treating every response as empty.
    function test_Audit_CanonicalResponsesRetainNegativePowers() public {
        UpgradeLivenessHookProbe probe = new UpgradeLivenessHookProbe();
        uint256[10] memory words;
        words[7] = 1;
        UpgradeLivenessRawHook recordHook = new UpgradeLivenessRawHook(abi.encode(words));
        (bool cancellation, bool veto,) = probe.records(address(recordHook));
        assertTrue(cancellation);
        assertTrue(veto);
        UpgradeLivenessRawHook suspensionHook =
            new UpgradeLivenessRawHook(abi.encode(true, uint64(type(uint64).max), uint32(1), bytes32(uint256(1))));
        (,, bool suspension) = probe.records(address(suspensionHook));
        assertTrue(suspension);
    }

    /// @notice Measures the production Senate getter bytecode with cold account/storage accesses.
    /// @dev These getters read their own records only, so constructor immutables are irrelevant to this gas probe.
    function test_Audit_ProductionSenateColdGettersFitHookBudget() public {
        address senateRuntime = address(0x5EAA7E);
        vm.etch(senateRuntime, vm.getDeployedCode("SenateApp.sol:SenateApp"));
        bytes4[3] memory selectors = [
            ISenateApp.getActionCancellationRecord.selector,
            ISenateApp.getReferendumVetoRecord.selector,
            ISenateApp.getDisbursementSuspension.selector
        ];
        for (uint256 index; index < selectors.length; ++index) {
            bytes memory callData = abi.encodeWithSelector(selectors[index], bytes32(uint256(1)));
            vm.cool(senateRuntime);
            uint256 beforeCall = gasleft();
            (bool success,) = senateRuntime.staticcall{gas: 100_000}(callData);
            uint256 used = beforeCall - gasleft();
            assertTrue(success);
            assertLt(used, 25_000);
            emit log_named_uint(
                index == 0 ? "cold cancellation getter" : index == 1 ? "cold veto getter" : "cold suspension getter",
                used
            );
        }
    }

    /// @notice Every non-Core module class supports the approved queued replacement mechanism when dependencies work.
    /// @dev Referendum threshold checks are exercised in Referenda.t.sol; this fixture models its authorized origin.
    function test_Audit_HealthyQueuedReplacementsWorkForEveryNonCoreClass() public {
        bytes32[5] memory modules = [
            KernelModuleIds.IDENTITY_REGISTRY,
            KernelModuleIds.VOTING_POWER_POLICY,
            KernelModuleIds.DECISION_APP,
            KernelModuleIds.LAND_REGISTRY_APP,
            keccak256("audit.extension")
        ];
        GovernanceTypes.ModuleClass[5] memory classes = [
            GovernanceTypes.ModuleClass.State,
            GovernanceTypes.ModuleClass.Policy,
            GovernanceTypes.ModuleClass.Authority,
            GovernanceTypes.ModuleClass.Application,
            GovernanceTypes.ModuleClass.Undefined
        ];
        address incumbent = address(new MockModule(keccak256("healthy-incumbent")));
        for (uint256 index; index < modules.length; ++index) {
            if (modules[index] != KernelModuleIds.DECISION_APP) kernel.bootstrapSetModule(modules[index], incumbent);
            assertEq(uint256(kernel.moduleClass(modules[index])), uint256(classes[index]));
        }
        kernel.disableBootstrapAuthority();
        bytes32[] memory actions = new bytes32[](modules.length);
        for (uint256 index; index < modules.length; ++index) {
            actions[index] = _queue(modules[index]);
        }
        vm.warp(timelock.getAction(actions[0]).earliestExecutionTime);
        timelock.executeActions(actions);
        for (uint256 index; index < modules.length; ++index) {
            assertEq(kernel.getModule(modules[index]), address(replacement));
        }
    }

    /// @notice The kernel independently rejects queued Core replacements even if an origin attempts to send one.
    function test_Audit_CoreExecutionModulesRemainDeliberatelyImmutable() public {
        kernel.disableBootstrapAuthority();
        bytes32 routerAction = _queue(KernelModuleIds.GOVERNANCE_ROUTER);
        bytes32 timelockAction = _queue(KernelModuleIds.ACTION_TIMELOCK);
        vm.warp(timelock.getAction(routerAction).earliestExecutionTime);
        vm.expectRevert(
            abi.encodeWithSelector(ConstitutionKernel.CoreModuleImmutable.selector, KernelModuleIds.GOVERNANCE_ROUTER)
        );
        timelock.executeAction(routerAction);
        vm.expectRevert(
            abi.encodeWithSelector(ConstitutionKernel.CoreModuleImmutable.selector, KernelModuleIds.ACTION_TIMELOCK)
        );
        timelock.executeAction(timelockAction);
        assertEq(kernel.getModule(KernelModuleIds.GOVERNANCE_ROUTER), address(router));
        assertEq(kernel.getModule(KernelModuleIds.ACTION_TIMELOCK), address(timelock));
    }

    /// @notice The real referendum finalization path also survives a successful malformed Senate response.
    function test_Audit_ReferendumFinalizationIgnoresMalformedSenateResponse() public {
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(new UpgradeLivenessMalformedHook()));
        kernel.disableBootstrapAuthority();
        UpgradeLivenessReferendumFixture fixture = new UpgradeLivenessReferendumFixture();
        ReferendumApp app = _referendumApp(fixture);
        app.finalizeReferendum(bytes32(uint256(1)));
        assertTrue(fixture.finalized());
    }

    /// @notice Insufficient caller gas cannot turn a real active referendum veto into a successful finalization.
    function test_Audit_ReferendumFinalizationCannotUnderfundActiveVeto() public {
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(new UpgradeLivenessBlockingHooks()));
        kernel.disableBootstrapAuthority();
        UpgradeLivenessReferendumFixture fixture = new UpgradeLivenessReferendumFixture();
        ReferendumApp app = _referendumApp(fixture);
        bytes32 referendumId = bytes32(uint256(1));
        vm.expectRevert(abi.encodeWithSelector(IReferendumApp.SenateVetoPending.selector, referendumId, uint64(1)));
        app.finalizeReferendum(referendumId);
        (bool success, bytes memory reason) =
            address(app).call{gas: 100_000}(abi.encodeCall(app.finalizeReferendum, (referendumId)));
        assertFalse(success);
        assertEq(bytes4(reason), BoundedGovernanceHook.InsufficientHookGas.selector);
        assertFalse(fixture.finalized());
    }

    function _referendumApp(UpgradeLivenessReferendumFixture fixture) private returns (ReferendumApp app) {
        return new ReferendumApp(
            address(replacement),
            address(replacement),
            address(fixture),
            address(fixture),
            address(router),
            address(replacement)
        );
    }
}
