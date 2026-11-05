// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ModuleUpgradePlanRegistry} from "../../contracts/registries/ModuleUpgradePlanRegistry.sol";
import {IModuleUpgradePlanRegistry} from "../../contracts/interfaces/IModuleUpgradePlanRegistry.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {MockConstitutionalReview} from "../../contracts/mocks/MockConstitutionalReview.sol";
import {ModuleUpgradeRules} from "../../contracts/libraries/ModuleUpgradeRules.sol";
import {ModuleUpgradePlanHash} from "../../contracts/libraries/ModuleUpgradePlanHash.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {SenateTypes} from "../../contracts/types/SenateTypes.sol";

contract AtomicUpgradeRebuildObserver {
    IConstitutionKernel private immutable _kernel;
    address private immutable _citizen;
    bytes32 private immutable _peerId;
    address private immutable _peer;
    bool private immutable _fail;
    uint256 public calls;

    constructor(address kernel, address citizen, bytes32 peerId, address peer, bool fail) {
        _kernel = IConstitutionKernel(kernel);
        _citizen = citizen;
        _peerId = peerId;
        _peer = peer;
        _fail = fail;
    }

    function beginPolicyRebuild() external {
        require(msg.sender == address(_kernel), "not kernel");
        require(_kernel.getModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY) == _citizen, "partial citizen pointer");
        require(_kernel.getModule(KernelModuleIds.ELECTORATE_REGISTRY) == address(this), "partial electorate pointer");
        require(_kernel.getModule(_peerId) == _peer, "partial peer pointer");
        ++calls;
        require(!_fail, "rebuild refused");
    }
}

contract AtomicUpgradeSenateHook {
    bool public pending;

    function setPending(bool value) external {
        pending = value;
    }

    function getActionCancellationRecord(bytes32 id)
        external
        view
        returns (SenateTypes.ActionCancellationRecord memory record)
    {
        if (pending) {
            record.actionId = id;
            record.exists = true;
            record.deadline = 1;
        }
    }

    function cancel(GovernanceRouter router, bytes32 id) external {
        router.cancelAction(id);
    }
}

contract AtomicMutablePlan {
    address public immutable kernel;
    GovernanceTypes.ModuleUpdate[] private _updates;
    bytes32 private _evidence;

    constructor(address kernel_) {
        kernel = kernel_;
    }

    function set(GovernanceTypes.ModuleUpdate[] memory updates, bytes32 evidence) external {
        delete _updates;
        for (uint256 i; i < updates.length; ++i) {
            _updates.push(updates[i]);
        }
        _evidence = evidence;
    }

    function getPlan(bytes32) external view returns (GovernanceTypes.ModuleUpdate[] memory, bytes32) {
        return (_updates, _evidence);
    }
}

/// @notice Core execution tests use an authenticated synthetic referendum origin; full ballots are separate tests.
contract AtomicModuleUpgradeTest is Test {
    bytes32 private constant A = bytes32(uint256(100));
    bytes32 private constant B = bytes32(uint256(200));
    bytes32 private constant EVIDENCE = keccak256("reviewed exact upgrade and state-continuity plan");
    ConstitutionKernel private kernel;
    GovernanceRouter private router;
    ActionTimelock private timelock;
    ModuleUpgradePlanRegistry private plans;
    AtomicUpgradeSenateHook private senate;
    MockConstitutionalReview private review;
    MockModule private oldA;
    MockModule private oldB;
    MockModule private nextA;
    MockModule private nextB;
    MockModule private oldCitizen;
    MockModule private oldElectorate;

    function setUp() public {
        vm.warp(1_900_000_000);
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(
            address(kernel), GovernanceTypes.TimelockDelayConfig(2 days, 1 days, 1 days, 2 days, 7 days)
        );
        router = new GovernanceRouter(address(kernel), address(this));
        plans = new ModuleUpgradePlanRegistry(address(kernel));
        senate = new AtomicUpgradeSenateHook();
        review = new MockConstitutionalReview();
        oldA = new MockModule(keccak256("old A"));
        oldB = new MockModule(keccak256("old B"));
        nextA = new MockModule(keccak256("next A"));
        nextB = new MockModule(keccak256("next B"));
        oldCitizen = new MockModule(keccak256("old citizen"));
        oldElectorate = new MockModule(keccak256("old electorate"));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_APP, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_APP, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY, address(plans));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(senate));
        kernel.bootstrapSetModule(KernelModuleIds.CONSTITUTIONAL_REVIEW, address(review));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(oldCitizen));
        kernel.bootstrapSetModule(KernelModuleIds.ELECTORATE_REGISTRY, address(oldElectorate));
        kernel.bootstrapSetModule(A, address(oldA));
        kernel.bootstrapSetModule(B, address(oldB));
        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();
    }

    function test_PermissionlessPlanIsImmutableAndSuppliesNoExecutionAuthority() public {
        GovernanceTypes.ModuleUpdate[] memory entries = _pair();
        bytes32 computed = plans.computePlanId(entries, EVIDENCE);
        vm.prank(address(0xB0B));
        bytes32 id = plans.publishPlan(entries, EVIDENCE);
        assertEq(id, computed);
        assertTrue(plans.planExists(id));
        (GovernanceTypes.ModuleUpdate[] memory stored, bytes32 evidence) = plans.getPlan(id);
        assertEq(keccak256(abi.encode(stored)), keccak256(abi.encode(entries)));
        assertEq(evidence, EVIDENCE);
        vm.expectRevert(abi.encodeWithSelector(IModuleUpgradePlanRegistry.UpgradePlanAlreadyPublished.selector, id));
        plans.publishPlan(entries, EVIDENCE);
        vm.expectRevert();
        kernel.governanceUpdateModules(entries);
        assertEq(kernel.getModule(A), address(oldA));
        assertEq(kernel.getModule(B), address(oldB));
    }

    function test_HashBindsChainKernelRegistryEvidenceAndEveryEntryField() public {
        GovernanceTypes.ModuleUpdate[] memory entries = _pair();
        bytes32 id = plans.computePlanId(entries, EVIDENCE);
        ModuleUpgradePlanRegistry other = new ModuleUpgradePlanRegistry(address(kernel));
        assertTrue(other.computePlanId(entries, EVIDENCE) != id);
        assertTrue(plans.computePlanId(entries, bytes32(uint256(9))) != id);
        entries[0].expectedCurrentAddress = address(oldB);
        assertTrue(plans.computePlanId(entries, EVIDENCE) != id);
        entries = _pair();
        entries[0].newRuntimeCodeHash = bytes32(uint256(8));
        assertTrue(plans.computePlanId(entries, EVIDENCE) != id);
        entries = _pair();
        vm.chainId(block.chainid + 1);
        assertTrue(plans.computePlanId(entries, EVIDENCE) != id);
    }

    function test_PlansRejectZeroEvidenceEmptyOversizeUnsortedDuplicateAndWrongRuntime() public {
        GovernanceTypes.ModuleUpdate[] memory entries = _pair();
        vm.expectRevert(IModuleUpgradePlanRegistry.InvalidPlanEvidence.selector);
        plans.publishPlan(entries, bytes32(0));
        entries = new GovernanceTypes.ModuleUpdate[](0);
        vm.expectRevert();
        plans.publishPlan(entries, EVIDENCE);
        entries = new GovernanceTypes.ModuleUpdate[](17);
        vm.expectRevert();
        plans.publishPlan(entries, EVIDENCE);
        entries = _pair();
        entries[1] = entries[0];
        vm.expectRevert();
        plans.publishPlan(entries, EVIDENCE);
        entries = _pair();
        (entries[0], entries[1]) = (entries[1], entries[0]);
        vm.expectRevert();
        plans.publishPlan(entries, EVIDENCE);
        entries = _pair();
        entries[1].newRuntimeCodeHash = bytes32(uint256(1));
        vm.expectRevert();
        plans.publishPlan(entries, EVIDENCE);
        entries = _pair();
        entries[0].newModuleAddress = entries[0].expectedCurrentAddress;
        entries[0].newRuntimeCodeHash = entries[0].newModuleAddress.codehash;
        vm.expectRevert();
        plans.publishPlan(entries, EVIDENCE);
    }

    function test_MaximumSixteenEntriesCanBePublishedAndAppliedAtomically() public {
        ConstitutionKernel local = new ConstitutionKernel(address(this));
        ModuleUpgradePlanRegistry registry = new ModuleUpgradePlanRegistry(address(local));
        local.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));
        GovernanceTypes.ModuleUpdate[] memory entries = new GovernanceTypes.ModuleUpdate[](16);
        for (uint256 i; i < 16; ++i) {
            bytes32 id = bytes32(uint256(1_000 + i));
            local.bootstrapSetModule(id, address(oldA));
            entries[i] = _entry(id, address(oldA), address(nextA));
        }
        registry.publishPlan(entries, EVIDENCE);
        local.disableBootstrapAuthority();
        local.governanceUpdateModules(entries);
        for (uint256 i; i < 16; ++i) {
            assertEq(local.getModule(entries[i].moduleId), address(nextA));
        }
        assertFalse(local.isAuthorizedModule(address(oldA)));
        assertTrue(local.isAuthorizedModule(address(nextA)));
    }

    function test_CoreAndNegativeAuthorityReplacementsCannotPiggybackInBundle() public {
        bytes32[4] memory forbidden = [
            KernelModuleIds.GOVERNANCE_ROUTER,
            KernelModuleIds.ACTION_TIMELOCK,
            KernelModuleIds.SENATE_APP,
            KernelModuleIds.CONSTITUTIONAL_REVIEW
        ];
        GovernanceTypes.ModuleUpdate[] memory entries = new GovernanceTypes.ModuleUpdate[](1);
        for (uint256 i; i < forbidden.length; ++i) {
            entries[0] = _entry(forbidden[i], kernel.getModule(forbidden[i]), address(nextA));
            vm.expectRevert(abi.encodeWithSelector(ModuleUpgradeRules.ForbiddenBundledModule.selector, forbidden[i]));
            plans.publishPlan(entries, EVIDENCE);
        }
    }

    function test_FutureExpectedPointerAllowsAPlanForPreopenedRollback() public {
        GovernanceTypes.ModuleUpdate[] memory entries = new GovernanceTypes.ModuleUpdate[](1);
        entries[0] = _entry(A, address(nextA), address(oldA));
        bytes32 id = plans.publishPlan(entries, EVIDENCE);
        vm.expectRevert();
        _queue(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        bytes32 cutover = router.routeAction(_single(A, address(nextA), bytes32(uint256(123))));
        _ready(cutover);
        timelock.executeAction(cutover);
        bytes32 rollback = _queue(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        _ready(rollback);
        timelock.executeAction(rollback);
        assertEq(kernel.getModule(A), address(oldA));
    }

    function test_BundleHasOneActionAndNoIndividuallyExecutableMembers() public {
        bytes32 id = plans.publishPlan(_pair(), EVIDENCE);
        bytes32 action = _queue(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        GovernanceTypes.ActionRecord memory record = timelock.getAction(action);
        assertEq(uint256(record.actionType), 13);
        assertEq(record.targetModule, KernelModuleIds.ACTION_TIMELOCK);
        vm.expectRevert();
        timelock.executeAction(action);
        _ready(action);
        bytes32 nonexistent = timelock.computeActionId(_single(A, address(nextA), id));
        vm.expectRevert();
        timelock.executeAction(nonexistent);
        assertEq(kernel.getModule(A), address(oldA));
        assertEq(kernel.getModule(B), address(oldB));
        timelock.executeAction(action);
        assertEq(kernel.getModule(A), address(nextA));
        assertEq(kernel.getModule(B), address(nextB));
        vm.expectRevert();
        timelock.executeAction(action);
        assertEq(uint256(timelock.getActionState(action)), uint256(GovernanceTypes.ActionState.Executed));
    }

    function test_QueuedBundleRejectsNewRuntimeDriftWithoutWritingFirstMember() public {
        bytes32 id = plans.publishPlan(_pair(), EVIDENCE);
        bytes32 action = _queue(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        vm.etch(address(nextB), hex"00");
        _ready(action);
        assertFalse(timelock.isActionExecutable(action));
        vm.expectRevert();
        timelock.executeAction(action);
        assertEq(kernel.getModule(A), address(oldA));
        assertEq(kernel.getModule(B), address(oldB));
        assertEq(uint256(timelock.getActionState(action)), uint256(GovernanceTypes.ActionState.Queued));
    }

    function test_StaleMemberBlocksEntireBundleAndReadiness() public {
        bytes32 id = plans.publishPlan(_pair(), EVIDENCE);
        bytes32 bundle = _queue(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        MockModule other = new MockModule(keccak256("other approved update"));
        bytes32 single = router.routeAction(_single(B, address(other), bytes32(uint256(456))));
        _ready(single);
        timelock.executeAction(single);
        assertFalse(timelock.isActionExecutable(bundle));
        vm.expectRevert();
        timelock.executeAction(bundle);
        assertEq(kernel.getModule(A), address(oldA));
        assertEq(kernel.getModule(B), address(other));
    }

    function test_RebuildObservesAllNewPointersExactlyOnce() public {
        MockModule citizen = new MockModule(keccak256("new citizen"));
        AtomicUpgradeRebuildObserver observer =
            new AtomicUpgradeRebuildObserver(address(kernel), address(citizen), A, address(nextA), false);
        bytes32 id = plans.publishPlan(_rebuildEntries(address(citizen), address(observer)), EVIDENCE);
        bytes32 action = _queue(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        _ready(action);
        timelock.executeAction(action);
        assertEq(observer.calls(), 1);
        assertEq(kernel.getModule(A), address(nextA));
    }

    function test_FailedRebuildRollsBackEveryPointerAndActionState() public {
        MockModule citizen = new MockModule(keccak256("new citizen"));
        AtomicUpgradeRebuildObserver observer =
            new AtomicUpgradeRebuildObserver(address(kernel), address(citizen), A, address(nextA), true);
        bytes32 id = plans.publishPlan(_rebuildEntries(address(citizen), address(observer)), EVIDENCE);
        bytes32 action = _queue(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        _ready(action);
        vm.expectRevert("rebuild refused");
        timelock.executeAction(action);
        assertEq(observer.calls(), 0);
        assertEq(kernel.getModule(A), address(oldA));
        assertEq(kernel.getModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY), address(oldCitizen));
        assertEq(kernel.getModule(KernelModuleIds.ELECTORATE_REGISTRY), address(oldElectorate));
        assertEq(uint256(timelock.getActionState(action)), uint256(GovernanceTypes.ActionState.Queued));
    }

    function test_NormalReviewAndSenateNegativeControlsStillBlockOrCancelBundle() public {
        bytes32 id = plans.publishPlan(_pair(), EVIDENCE);
        bytes32 action = _queue(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        _ready(action);
        review.setActionPaused(action, true);
        assertFalse(timelock.isActionExecutable(action));
        vm.expectRevert();
        timelock.executeAction(action);
        review.setActionPaused(action, false);
        senate.setPending(true);
        assertFalse(timelock.isActionExecutable(action));
        vm.expectRevert();
        timelock.executeAction(action);
        senate.setPending(false);
        senate.cancel(router, action);
        assertEq(uint256(timelock.getActionState(action)), uint256(GovernanceTypes.ActionState.Canceled));
        assertEq(kernel.getModule(A), address(oldA));
    }

    function test_ExpiredBundleDoesNotChangePointersAndCanBeRecordedTerminal() public {
        bytes32 id = plans.publishPlan(_pair(), EVIDENCE);
        bytes32 action = _queue(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        vm.warp(uint256(timelock.getAction(action).expiresAt) + 1);
        vm.expectRevert();
        timelock.executeAction(action);
        timelock.expireAction(action);
        assertEq(kernel.getModule(A), address(oldA));
        assertEq(uint256(timelock.getActionState(action)), uint256(GovernanceTypes.ActionState.Expired));
    }

    function test_OriginalPlanRegistryIsPinnedAcrossItsOwnPointerReplacement() public {
        bytes32 id = plans.publishPlan(_pair(), EVIDENCE);
        bytes32 bundle = _queue(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        ModuleUpgradePlanRegistry successor = new ModuleUpgradePlanRegistry(address(kernel));
        bytes32 update = router.routeAction(
            _single(KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY, address(successor), bytes32(uint256(678)))
        );
        _ready(update);
        timelock.executeAction(update);
        assertFalse(successor.planExists(id));
        assertTrue(plans.planExists(id));
        assertTrue(timelock.isActionExecutable(bundle));
        timelock.executeAction(bundle);
        assertEq(kernel.getModule(A), address(nextA));
    }

    function test_ChangedOrForgedPlanContentsCannotReplaceCommittedMembers() public {
        AtomicMutablePlan fake = new AtomicMutablePlan(address(kernel));
        GovernanceTypes.ModuleUpdate[] memory entries = _pair();
        fake.set(entries, EVIDENCE);
        bytes32 id = ModuleUpgradePlanHash.hash(block.chainid, address(kernel), address(fake), EVIDENCE, entries);
        bytes32 bundle = _queue(address(fake), id, GovernanceTypes.ActionOrigin.Referendum);
        entries[1].newModuleAddress = address(nextA);
        entries[1].newRuntimeCodeHash = address(nextA).codehash;
        fake.set(entries, EVIDENCE);
        _ready(bundle);
        assertFalse(timelock.isActionExecutable(bundle));
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.InvalidActionPayload.selector, bundle));
        timelock.executeAction(bundle);
        assertEq(kernel.getModule(A), address(oldA));
        assertEq(kernel.getModule(B), address(oldB));
    }

    function test_WrongOriginTargetKernelOrPlanIsRejectedBeforeQueue() public {
        bytes32 id = plans.publishPlan(_pair(), EVIDENCE);
        vm.expectRevert();
        _queue(address(plans), id, GovernanceTypes.ActionOrigin.Congress);
        GovernanceTypes.ActionRequest memory request =
            _bundle(address(plans), id, GovernanceTypes.ActionOrigin.Referendum);
        request.targetModule = A;
        vm.expectRevert();
        router.routeAction(request);
        request = _bundle(address(plans), bytes32(uint256(999)), GovernanceTypes.ActionOrigin.Referendum);
        vm.expectRevert();
        router.routeAction(request);
        ConstitutionKernel otherKernel = new ConstitutionKernel(address(this));
        ModuleUpgradePlanRegistry foreign = new ModuleUpgradePlanRegistry(address(otherKernel));
        vm.expectRevert();
        _queue(address(foreign), id, GovernanceTypes.ActionOrigin.Referendum);
    }

    function _entry(bytes32 id, address prior, address next)
        private
        view
        returns (GovernanceTypes.ModuleUpdate memory)
    {
        return GovernanceTypes.ModuleUpdate(id, prior, next, next.codehash);
    }

    function _pair() private view returns (GovernanceTypes.ModuleUpdate[] memory entries) {
        entries = new GovernanceTypes.ModuleUpdate[](2);
        entries[0] = _entry(A, address(oldA), address(nextA));
        entries[1] = _entry(B, address(oldB), address(nextB));
    }

    function _rebuildEntries(address citizen, address observer)
        private
        view
        returns (GovernanceTypes.ModuleUpdate[] memory entries)
    {
        entries = new GovernanceTypes.ModuleUpdate[](3);
        entries[0] = _entry(A, address(oldA), address(nextA));
        entries[1] = _entry(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(oldCitizen), citizen);
        entries[2] = _entry(KernelModuleIds.ELECTORATE_REGISTRY, address(oldElectorate), observer);
        for (uint256 i; i < entries.length; ++i) {
            for (uint256 j = i + 1; j < entries.length; ++j) {
                if (uint256(entries[j].moduleId) < uint256(entries[i].moduleId)) {
                    (entries[i], entries[j]) = (entries[j], entries[i]);
                }
            }
        }
    }

    function _queue(address registry, bytes32 id, GovernanceTypes.ActionOrigin origin) private returns (bytes32) {
        return router.routeAction(_bundle(registry, id, origin));
    }

    function _bundle(address registry, bytes32 id, GovernanceTypes.ActionOrigin origin)
        private
        pure
        returns (GovernanceTypes.ActionRequest memory)
    {
        return GovernanceTypes.ActionRequest(
            GovernanceTypes.ActionType.ModuleBundleUpdate,
            origin,
            id,
            EVIDENCE,
            KernelModuleIds.ACTION_TIMELOCK,
            abi.encode(GovernanceTypes.ModuleBundleUpdatePayload(registry, id)),
            0,
            0
        );
    }

    function _single(bytes32 moduleId, address next, bytes32 originReference)
        private
        pure
        returns (GovernanceTypes.ActionRequest memory)
    {
        return GovernanceTypes.ActionRequest(
            GovernanceTypes.ActionType.ModulePointerUpdate,
            GovernanceTypes.ActionOrigin.Referendum,
            originReference,
            EVIDENCE,
            moduleId,
            abi.encode(GovernanceTypes.ModuleUpdatePayload(next)),
            0,
            0
        );
    }

    function _ready(bytes32 action) private {
        vm.warp(timelock.getAction(action).earliestExecutionTime);
    }
}
