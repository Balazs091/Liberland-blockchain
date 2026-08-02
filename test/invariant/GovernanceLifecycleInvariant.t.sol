// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";

contract GovernanceLifecycleHandler is Test {
    bytes32 internal constant TARGET_MODULE_ID = KernelModuleIds.DECISION_APP;

    ConstitutionKernel public immutable kernel;
    GovernanceRouter public immutable router;
    ActionTimelock public immutable timelock;
    address public immutable initialModule;
    address public immutable replacementOne;
    address public immutable replacementTwo;

    bytes32[] private _actionIds;
    mapping(bytes32 actionId => uint256 executions) public successfulExecutions;
    bool public repeatedExecutionSucceeded;

    constructor(
        ConstitutionKernel kernel_,
        GovernanceRouter router_,
        ActionTimelock timelock_,
        address initialModule_,
        address replacementOne_,
        address replacementTwo_
    ) {
        kernel = kernel_;
        router = router_;
        timelock = timelock_;
        initialModule = initialModule_;
        replacementOne = replacementOne_;
        replacementTwo = replacementTwo_;
    }

    /// @notice Queues a replacement selected from the reviewed fixture set when no action is currently live.
    function queueModuleReplacement(uint256 seed) external {
        address current = kernel.getModule(TARGET_MODULE_ID);
        address replacement = seed % 2 == 0 ? replacementOne : replacementTwo;
        if (replacement == current) {
            replacement = replacement == replacementOne ? replacementTwo : replacementOne;
        }

        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.ModulePointerUpdate,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: keccak256(abi.encode("invariant.referendum", seed, _actionIds.length)),
            policyReference: keccak256("invariant.constitutional-policy"),
            targetModule: TARGET_MODULE_ID,
            payload: abi.encode(GovernanceTypes.ModuleUpdatePayload({newModuleAddress: replacement})),
            requestedExecutionTime: 0,
            expiresAt: 0
        });

        try router.routeAction(request) returns (bytes32 actionId) {
            _actionIds.push(actionId);
        } catch {}
    }

    /// @notice Attempts an authorized cancellation of one tracked action.
    function cancelAction(uint256 seed) external {
        uint256 count = _actionIds.length;
        if (count == 0) {
            return;
        }
        try router.cancelAction(_actionIds[seed % count]) {} catch {}
    }

    /// @notice Attempts execution of one tracked action and records successful terminal execution.
    function executeAction(uint256 seed) external {
        uint256 count = _actionIds.length;
        if (count == 0) {
            return;
        }
        bytes32 actionId = _actionIds[seed % count];
        GovernanceTypes.ActionRecord memory action = timelock.getAction(actionId);
        if (action.state != GovernanceTypes.ActionState.Queued) {
            return;
        }
        if (block.timestamp < action.earliestExecutionTime) {
            vm.warp(action.earliestExecutionTime);
        }

        try timelock.executeAction(actionId) {
            successfulExecutions[actionId] += 1;
            try timelock.executeAction(actionId) {
                repeatedExecutionSucceeded = true;
            } catch {}
        } catch {}
    }

    /// @notice Advances and records expiry for one tracked queued action when eligible.
    function expireAction(uint256 seed) external {
        uint256 count = _actionIds.length;
        if (count == 0) {
            return;
        }
        bytes32 actionId = _actionIds[seed % count];
        GovernanceTypes.ActionRecord memory action = timelock.getAction(actionId);
        if (action.state != GovernanceTypes.ActionState.Queued) {
            return;
        }
        if (block.timestamp <= action.expiresAt) {
            vm.warp(uint256(action.expiresAt) + 1);
        }
        try timelock.expireAction(actionId) {} catch {}
    }

    /// @notice Advances invariant time by a bounded amount.
    function advanceTime(uint64 rawSeconds) external {
        vm.warp(block.timestamp + bound(uint256(rawSeconds), 1, 30 days));
    }

    /// @notice Returns the number of action identifiers tracked by the handler.
    function actionCount() external view returns (uint256 count) {
        return _actionIds.length;
    }

    /// @notice Returns a tracked action identifier by index.
    function actionIdAt(uint256 index) external view returns (bytes32 actionId) {
        return _actionIds[index];
    }
}

/// @title GovernanceLifecycleInvariantTest
/// @notice Stateful coverage for queue terminal states, single execution, immutable core, and router-origin tiers.
contract GovernanceLifecycleInvariantTest is Test {
    ConstitutionKernel internal kernel;
    GovernanceRouter internal router;
    ActionTimelock internal timelock;
    MockModule internal initialModule;
    MockModule internal replacementOne;
    MockModule internal replacementTwo;
    GovernanceLifecycleHandler internal handler;

    /// @notice Deploys and seals the governance lifecycle invariant fixture.
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
        initialModule = new MockModule(keccak256("invariant.initial"));
        replacementOne = new MockModule(keccak256("invariant.replacement.one"));
        replacementTwo = new MockModule(keccak256("invariant.replacement.two"));
        handler = new GovernanceLifecycleHandler(
            kernel, router, timelock, address(initialModule), address(replacementOne), address(replacementTwo)
        );

        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.DECISION_APP, address(initialModule));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_APP, address(handler));
        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();

        targetContract(address(handler));
    }

    /// @notice Proves no action observed as executed can return to a non-executed state or execute repeatedly.
    function invariant_QueuedActionsNeverExecuteTwice() public view {
        assertFalse(handler.repeatedExecutionSucceeded());
        uint256 count = handler.actionCount();
        for (uint256 index = 0; index < count; ++index) {
            assertLe(handler.successfulExecutions(handler.actionIdAt(index)), 1);
        }
    }

    /// @notice Proves the core trust-root pointers stay fixed and bootstrap remains disabled.
    function invariant_CorePointersRemainImmutableAndBootstrapStaysSealed() public view {
        assertEq(kernel.getModule(KernelModuleIds.GOVERNANCE_ROUTER), address(router));
        assertEq(kernel.getModule(KernelModuleIds.ACTION_TIMELOCK), address(timelock));
        assertEq(kernel.bootstrapAuthority(), address(0));
        assertEq(router.bootstrapAuthority(), address(0));
    }

    /// @notice Proves every router origin and the constitutional-review hook retain the Authority class.
    function invariant_RouterOriginsAndReviewRemainConstitutionalAuthorities() public view {
        assertEq(
            uint256(kernel.moduleClass(KernelModuleIds.REFERENDUM_APP)), uint256(GovernanceTypes.ModuleClass.Authority)
        );
        assertEq(
            uint256(kernel.moduleClass(KernelModuleIds.CONGRESS_ELECTION_APP)),
            uint256(GovernanceTypes.ModuleClass.Authority)
        );
        assertEq(
            uint256(kernel.moduleClass(KernelModuleIds.SENATE_APP)), uint256(GovernanceTypes.ModuleClass.Authority)
        );
        assertEq(
            uint256(kernel.moduleClass(KernelModuleIds.OFFICE_EXECUTOR)), uint256(GovernanceTypes.ModuleClass.Authority)
        );
        assertEq(
            uint256(kernel.moduleClass(KernelModuleIds.CONSTITUTIONAL_REVIEW)),
            uint256(GovernanceTypes.ModuleClass.Authority)
        );
    }

    /// @notice Proves the exercised replaceable pointer can only select a reviewed fixture address.
    function invariant_OperationalTargetCanOnlyPointToReviewedFixtureBytecode() public view {
        address current = kernel.getModule(KernelModuleIds.DECISION_APP);
        assertTrue(
            current == address(initialModule) || current == address(replacementOne)
                || current == address(replacementTwo)
        );
    }
}
