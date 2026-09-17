// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {LegislationTypes} from "../../contracts/types/LegislationTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";

/// @notice A selected typed target may be hostile; its callback must not replay its executing action.
contract ReentrantTypedTreasuryTarget {
    error TargetRejected();

    IActionTimelock public immutable timelock;
    bytes32 public actionId;
    uint256 public calls;
    bool public rejectAfterCallback;
    bool public replaySucceeded;
    bytes4 public replayFailure;

    constructor(IActionTimelock timelock_) {
        timelock = timelock_;
    }

    function configure(bytes32 actionId_, bool rejectAfterCallback_) external {
        actionId = actionId_;
        rejectAfterCallback = rejectAfterCallback_;
    }

    function executeDisbursement(GovernanceTypes.TreasuryDisbursementPayload calldata) external {
        require(msg.sender == address(timelock));
        ++calls;
        bytes memory reason;
        (replaySucceeded, reason) = address(timelock).call(abi.encodeCall(timelock.executeAction, (actionId)));
        replayFailure = bytes4(reason);
        if (rejectAfterCallback) revert TargetRejected();
    }
}

/// @notice Independent minimal core fixture; no inherited test cases inflate the regression count.
contract CoreAdversarialSafetyTest is Test {
    bytes32 private constant EXTENSION = keccak256("adversarial.extension");
    bytes32 private constant REFERENCE = keccak256("approved.reference");

    ConstitutionKernel private kernel;
    GovernanceRouter private router;
    ActionTimelock private timelock;
    MockModule private original;
    MockModule private replacement;
    ReentrantTypedTreasuryTarget private treasury;
    address private origin;

    function setUp() public {
        vm.warp(1 days);
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
        original = new MockModule(keccak256("original"));
        replacement = new MockModule(keccak256("replacement"));
        treasury = new ReentrantTypedTreasuryTarget(timelock);
        origin = address(new MockModule(keccak256("origin")));
        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_APP, origin);
        kernel.bootstrapSetModule(KernelModuleIds.DECISION_APP, address(original));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY, address(original));
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY, address(original));
        kernel.bootstrapSetModule(KernelModuleIds.TREASURY_VAULT, address(treasury));
        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();
    }

    function test_TypedExecutionTargetCannotReplayExecutingAction() public {
        bytes32 id = _queue(_request(5));
        treasury.configure(id, false);
        vm.warp(timelock.getAction(id).earliestExecutionTime);
        timelock.executeAction(id);
        assertEq(treasury.calls(), 1);
        assertFalse(treasury.replaySucceeded());
        assertEq(treasury.replayFailure(), IActionTimelock.ActionAlreadyFinalized.selector);
        assertEq(uint256(timelock.getActionState(id)), uint256(GovernanceTypes.ActionState.Executed));
    }

    function test_ExternalTargetRevertRollsBackEntireBatchAndEveryReceipt() public {
        bytes32 first = _queue(_request(0));
        bytes32 second = _queue(_request(5));
        treasury.configure(second, true);
        vm.warp(timelock.getAction(second).earliestExecutionTime);
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = first;
        ids[1] = second;
        vm.expectRevert(ReentrantTypedTreasuryTarget.TargetRejected.selector);
        timelock.executeActions(ids);
        assertEq(kernel.getModule(KernelModuleIds.DECISION_APP), address(original));
        assertEq(uint256(timelock.getActionState(first)), uint256(GovernanceTypes.ActionState.Queued));
        assertEq(uint256(timelock.getActionState(second)), uint256(GovernanceTypes.ActionState.Queued));
        assertEq(treasury.calls(), 0);

        treasury.configure(second, false);
        timelock.executeActions(ids);
        assertEq(kernel.getModule(KernelModuleIds.DECISION_APP), address(replacement));
        assertEq(treasury.calls(), 1);
    }

    function test_AllSixActionsRejectShortAndTrailingPayloadBytesWithoutQueueWrites() public {
        for (uint256 kind; kind < 6; ++kind) {
            for (uint256 variant; variant < 2; ++variant) {
                GovernanceTypes.ActionRequest memory request = _request(kind);
                request.payload = new bytes(request.payload.length + variant * 2 - 1);
                _expectInvalidPayload(request);
            }
        }
    }

    function test_AllSixActionsRejectMissingRequiredPayloadFields() public {
        for (uint256 kind; kind < 6; ++kind) {
            uint256 mask = kind < 2 ? 1 : kind == 2 ? 95 : kind == 3 ? 31 : kind == 4 ? 3 : 29;
            for (uint256 word; word < 8; ++word) {
                if ((mask & (uint256(1) << word)) == 0) continue;
                GovernanceTypes.ActionRequest memory request = _request(kind);
                _setWord(request.payload, word, 0);
                if (kind < 2) {
                    vm.expectRevert(
                        abi.encodeWithSelector(
                            IConstitutionKernel.InvalidModuleAddress.selector, request.targetModule, address(0)
                        )
                    );
                    vm.prank(origin);
                    router.routeAction(request);
                } else {
                    _expectInvalidPayload(request);
                }
            }
        }
    }

    function test_BoundedDomainActionsRejectWrongRegisteredTarget() public {
        for (uint256 kind = 2; kind < 6; ++kind) {
            GovernanceTypes.ActionRequest memory request = _request(kind);
            request.targetModule = KernelModuleIds.DECISION_APP;
            _expectInvalidPayload(request);
        }
    }

    function test_CodeBearingModuleAndTreasuryAssetAddressesAreRequired() public {
        for (uint256 kind; kind < 6; ++kind) {
            if (kind == 3 || kind == 4) continue;
            GovernanceTypes.ActionRequest memory request = _request(kind);
            _setWord(request.payload, kind < 2 ? 0 : kind == 2 ? 3 : 2, uint256(uint160(address(0xBEEF))));
            if (kind < 2) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IConstitutionKernel.InvalidModuleAddress.selector, request.targetModule, address(0xBEEF)
                    )
                );
                vm.prank(origin);
                router.routeAction(request);
            } else {
                _expectInvalidPayload(request);
            }
        }
    }

    function test_EnumAndAddressDecodersRejectNoncanonicalWords() public {
        for (uint256 variant; variant < 3; ++variant) {
            GovernanceTypes.ActionRequest memory request = _request(variant == 0 ? 0 : variant == 1 ? 2 : 3);
            _setWord(request.payload, variant == 0 ? 0 : variant == 1 ? 2 : 1, type(uint256).max);
            vm.expectRevert();
            vm.prank(origin);
            router.routeAction(request);
        }
    }

    function test_PublicRepealCannotMisstateItsOriginReference() public {
        GovernanceTypes.ActionRequest memory request = _request(4);
        request.originReference = bytes32(uint256(77));
        _expectInvalidPayload(request);
    }

    function test_AllSixCanceledActionsRejectExecutionAndDuplicateQueue() public {
        for (uint256 kind; kind < 6; ++kind) {
            GovernanceTypes.ActionRequest memory request = _request(kind);
            bytes32 id = _queue(request);
            vm.prank(origin);
            router.cancelAction(id);
            bytes memory expected = abi.encodeWithSelector(
                IActionTimelock.ActionAlreadyFinalized.selector, id, GovernanceTypes.ActionState.Canceled
            );
            vm.expectRevert(expected);
            timelock.executeAction(id);
            vm.expectRevert(expected);
            timelock.expireAction(id);
            vm.expectRevert(expected);
            vm.prank(origin);
            router.cancelAction(id);
            vm.expectRevert(expected);
            vm.prank(origin);
            router.routeAction(request);
        }
    }

    function test_AllSixActionsRejectExecutionAndCancellationAfterExpiry() public {
        for (uint256 kind; kind < 6; ++kind) {
            bytes32 id = _queue(_request(kind));
            GovernanceTypes.ActionRecord memory record = timelock.getAction(id);
            vm.expectRevert(abi.encodeWithSelector(IActionTimelock.ActionNotExpired.selector, id, record.expiresAt));
            timelock.expireAction(id);
            vm.warp(uint256(record.expiresAt) + 1);
            assertFalse(timelock.isActionExecutable(id));
            vm.expectRevert(abi.encodeWithSelector(IActionTimelock.ActionExpired.selector, id, record.expiresAt));
            timelock.executeAction(id);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IActionTimelock.ActionAlreadyFinalized.selector, id, GovernanceTypes.ActionState.Expired
                )
            );
            vm.prank(origin);
            router.cancelAction(id);
            timelock.expireAction(id);
            assertEq(uint256(timelock.getAction(id).state), uint256(GovernanceTypes.ActionState.Expired));
        }
    }

    function test_UnknownActionsHaveNoExecutableLifecycle() public {
        bytes32 id = keccak256("unknown");
        assertEq(uint256(timelock.getActionState(id)), uint256(GovernanceTypes.ActionState.Undefined));
        assertFalse(timelock.isActionExecutable(id));
        bytes memory expected = abi.encodeWithSelector(IActionTimelock.ActionNotFound.selector, id);
        vm.expectRevert(expected);
        timelock.getAction(id);
        vm.expectRevert(expected);
        timelock.executeAction(id);
        vm.expectRevert(expected);
        timelock.expireAction(id);
        vm.expectRevert(expected);
        vm.prank(address(router));
        timelock.cancelAction(id);
    }

    function test_ExpiryMustStrictlyFollowExecutionTime() public {
        GovernanceTypes.ActionRequest memory request = _request(0);
        request.requestedExecutionTime = uint64(block.timestamp + 3 days);
        request.expiresAt = request.requestedExecutionTime;
        bytes32 id = router.previewActionId(request);
        vm.expectRevert(
            abi.encodeWithSelector(
                IActionTimelock.InvalidActionExpiry.selector, id, request.expiresAt, request.requestedExecutionTime
            )
        );
        vm.prank(origin);
        router.routeAction(request);
    }

    function test_TimelockIndependentlyRejectsUnsupportedActionFromRouter() public {
        GovernanceTypes.ActionRequest memory request = _request(0);
        request.actionType = GovernanceTypes.ActionType.EmergencyPause;
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.UnsupportedExecutionAction.selector, request.actionType));
        vm.prank(address(router));
        timelock.queueAction(request);
    }

    function _expectInvalidPayload(GovernanceTypes.ActionRequest memory request) private {
        bytes32 id = router.previewActionId(request);
        vm.expectRevert(abi.encodeWithSelector(IActionTimelock.InvalidActionPayload.selector, id));
        vm.prank(origin);
        router.routeAction(request);
        assertEq(uint256(timelock.getActionState(id)), uint256(GovernanceTypes.ActionState.Undefined));
    }

    function _queue(GovernanceTypes.ActionRequest memory request) private returns (bytes32) {
        vm.prank(origin);
        return router.routeAction(request);
    }

    function _setWord(bytes memory data, uint256 word, uint256 value) private pure {
        assembly ("memory-safe") {
            mstore(add(add(data, 32), mul(word, 32)), value)
        }
    }

    function _request(uint256 kind) private view returns (GovernanceTypes.ActionRequest memory request) {
        request.origin = GovernanceTypes.ActionOrigin.Referendum;
        request.originReference = REFERENCE;
        if (kind < 2) {
            request.actionType = kind == 0
                ? GovernanceTypes.ActionType.ModulePointerUpdate
                : GovernanceTypes.ActionType.ModuleRegistration;
            request.targetModule = kind == 0 ? KernelModuleIds.DECISION_APP : EXTENSION;
            request.payload = abi.encode(GovernanceTypes.ModuleUpdatePayload(address(replacement)));
        } else if (kind == 2) {
            request.actionType = GovernanceTypes.ActionType.TreasuryBudgetApproval;
            request.targetModule = KernelModuleIds.BUDGET_ENVELOPE_REGISTRY;
            request.payload = abi.encode(
                GovernanceTypes.TreasuryBudgetApprovalPayload(
                    bytes32(uint256(1)),
                    bytes32(uint256(2)),
                    TreasuryTypes.DisbursementType.Operations,
                    address(original),
                    10,
                    uint64(block.timestamp),
                    uint64(block.timestamp + 100 days),
                    bytes32(0)
                )
            );
        } else if (kind == 3) {
            request.actionType = GovernanceTypes.ActionType.LegislationEnactment;
            request.targetModule = KernelModuleIds.LEGISLATION_REGISTRY;
            request.payload = abi.encode(
                GovernanceTypes.LegislationEnactmentPayload(
                    bytes32(uint256(1)),
                    LegislationTypes.LegislationTier.Law,
                    bytes32(uint256(2)),
                    bytes32(uint256(3)),
                    REFERENCE,
                    bytes32(0)
                )
            );
        } else if (kind == 4) {
            request.actionType = GovernanceTypes.ActionType.LegislationRepeal;
            request.targetModule = KernelModuleIds.LEGISLATION_REGISTRY;
            request.payload = abi.encode(GovernanceTypes.LegislationRepealPayload(bytes32(uint256(1)), REFERENCE));
        } else {
            request.actionType = GovernanceTypes.ActionType.TreasuryDisbursement;
            request.targetModule = KernelModuleIds.TREASURY_VAULT;
            request.payload = abi.encode(
                GovernanceTypes.TreasuryDisbursementPayload(
                    bytes32(uint256(1)), bytes32(uint256(2)), address(original), address(0xBEEF), 10, bytes32(0)
                )
            );
        }
    }
}
