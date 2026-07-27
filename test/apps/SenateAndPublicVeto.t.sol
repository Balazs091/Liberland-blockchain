// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {PublicVetoApp} from "../../contracts/apps/PublicVetoApp.sol";
import {SenateApp} from "../../contracts/apps/SenateApp.sol";
import {TreasuryVault} from "../../contracts/apps/TreasuryVault.sol";
import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {ICitizenEligibilityPolicy} from "../../contracts/interfaces/ICitizenEligibilityPolicy.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IGovernanceRouter} from "../../contracts/interfaces/IGovernanceRouter.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {ILegislationRegistry} from "../../contracts/interfaces/ILegislationRegistry.sol";
import {IPublicVetoApp} from "../../contracts/interfaces/IPublicVetoApp.sol";
import {IReferendumRegistry} from "../../contracts/interfaces/IReferendumRegistry.sol";
import {ISenateApp} from "../../contracts/interfaces/ISenateApp.sol";
import {ISenatePowersPolicy} from "../../contracts/interfaces/ISenatePowersPolicy.sol";
import {ISenateSeatRegistry} from "../../contracts/interfaces/ISenateSeatRegistry.sol";
import {IStakeRegistry} from "../../contracts/interfaces/IStakeRegistry.sol";
import {ITreasuryVault} from "../../contracts/interfaces/ITreasuryVault.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {MockUSDC} from "../../contracts/mocks/MockUSDC.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {SenatePowersPolicy} from "../../contracts/policies/SenatePowersPolicy.sol";
import {BudgetEnvelopeRegistry} from "../../contracts/registries/BudgetEnvelopeRegistry.sol";
import {ElectorateRegistry} from "../../contracts/registries/ElectorateRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LegislationRegistry} from "../../contracts/registries/LegislationRegistry.sol";
import {PresidentRegistry} from "../../contracts/registries/PresidentRegistry.sol";
import {ReferendumRegistry} from "../../contracts/registries/ReferendumRegistry.sol";
import {SenateSeatRegistry} from "../../contracts/registries/SenateSeatRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LegislationTypes} from "../../contracts/types/LegislationTypes.sol";
import {ReferendumTypes} from "../../contracts/types/ReferendumTypes.sol";
import {SenateTypes} from "../../contracts/types/SenateTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";
import {VetoTypes} from "../../contracts/types/VetoTypes.sol";

contract MockReferendumAppForSenate {
    address public immutable governanceRouter;
    address public immutable legislationRegistry;
    address public immutable referendumRegistry;

    constructor(
        address governanceRouterAddress,
        address legislationRegistryAddress,
        address referendumRegistryAddress
    ) {
        governanceRouter = governanceRouterAddress;
        legislationRegistry = legislationRegistryAddress;
        referendumRegistry = referendumRegistryAddress;
    }

    function cancelReferendumBySenate(bytes32 referendumId) external {
        IReferendumRegistry(referendumRegistry).cancelReferendum(referendumId);
    }

    function routeAction(GovernanceTypes.ActionRequest calldata request) external returns (bytes32 actionId) {
        return GovernanceRouter(governanceRouter).routeAction(request);
    }
}

/// @title SenateAndPublicVetoTest
/// @notice Covers v1 Senate succession, bounded Senate cancellation, and headcount-based public repeal.
contract SenateAndPublicVetoTest is Test {
    bytes32 internal constant DISBURSEMENT_SUSPENSION_REASON = keccak256("documented-treasury-risk");
    bytes32 internal constant DISBURSEMENT_RENEWAL_REASON = keccak256("documented-risk-still-active");
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint32 internal constant SENATE_CANCELLATION_THRESHOLD = 2;
    // Short window (well inside the queued disbursement's 7-day execution window) so the auto-lapse path is testable.
    uint64 internal constant DISBURSEMENT_SUSPENSION_PERIOD = 3 days;
    uint256 internal constant PUBLIC_VETO_THRESHOLD = 2;

    bytes32 internal constant TARGET_MODULE_ID = keccak256("test.senate.target-module");
    bytes32 internal constant ORDINARY_MEASURE_ID = keccak256("measure.ordinary");
    bytes32 internal constant ORDINARY_MEASURE_TWO_ID = keccak256("measure.ordinary.two");
    bytes32 internal constant CONSTITUTIONAL_MEASURE_ID = keccak256("measure.constitutional");
    bytes32 internal constant SUB_LEGAL_MEASURE_ID = keccak256("measure.sub-legal");
    bytes32 internal constant PENDING_MEASURE_ID = keccak256("measure.pending");
    bytes32 internal constant ACTIVE_REFERENDUM_ID = keccak256("referendum.active-law");
    bytes32 internal constant CONSTITUTIONAL_REFERENDUM_ID = keccak256("referendum.constitutional");
    bytes32 internal constant SENATE_SELF_REPLACEMENT_REFERENDUM_ID = keccak256("referendum.replace-senate-app");
    bytes32 internal constant TREASURY_REQUEST_ID = keccak256("treasury.request");
    bytes32 internal constant TREASURY_BUDGET_ID = keccak256("treasury.budget");

    bytes32 internal constant PERSON_ONE_ID = bytes32(uint256(1));
    bytes32 internal constant PERSON_TWO_ID = bytes32(uint256(2));
    bytes32 internal constant PERSON_THREE_ID = bytes32(uint256(3));
    bytes32 internal constant PERSON_FOUR_ID = bytes32(uint256(4));

    address internal constant WALLET_ONE = address(0xA11CE);
    address internal constant WALLET_TWO = address(0xB0B);
    address internal constant WALLET_THREE = address(0xCAFE);
    address internal constant WALLET_FOUR = address(0xD00D);
    address internal constant WALLET_ONE_NEW = address(0xA110);
    address internal constant TREASURY_RECIPIENT = address(0xBEEF);

    ConstitutionKernel internal kernel;
    ActionTimelock internal timelock;
    GovernanceRouter internal router;
    MockModule internal targetModule;
    MockModule internal replacementModule;
    MockModule internal identityAuthority;
    MockModule internal stakeAuthority;
    MockModule internal legislationAuthority;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    LegislationRegistry internal legislationRegistry;
    ReferendumRegistry internal referendumRegistry;
    PresidentRegistry internal presidentRegistry;
    TreasuryVault internal treasuryVault;
    BudgetEnvelopeRegistry internal budgetEnvelopeRegistry;
    MockUSDC internal usdc;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    ElectorateRegistry internal electorateRegistry;
    SenateSeatRegistry internal senateSeatRegistry;
    SenatePowersPolicy internal senatePowersPolicy;
    MockReferendumAppForSenate internal mockReferendumApp;
    SenateApp internal senateApp;
    PublicVetoApp internal publicVetoApp;

    address internal referendumAuthority = makeAddr("referendumAuthority");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        _deployFoundation();
        _registerDefaultCitizens();
        _enactMeasure(ORDINARY_MEASURE_ID, LegislationTypes.LegislationTier.Law);
        _enactMeasure(ORDINARY_MEASURE_TWO_ID, LegislationTypes.LegislationTier.Law);
        _enactMeasure(CONSTITUTIONAL_MEASURE_ID, LegislationTypes.LegislationTier.ConstitutionalOrInternationalTreaty);
        _enactMeasure(SUB_LEGAL_MEASURE_ID, LegislationTypes.LegislationTier.SubLegalTier3);
        _seedReferendum(ACTIVE_REFERENDUM_ID, ReferendumTypes.ReferendumClass.Legislation);
        _seedReferendum(CONSTITUTIONAL_REFERENDUM_ID, ReferendumTypes.ReferendumClass.ConstitutionalAmendment);
        _seedInitialSenateSeats();

        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();
    }

    function test_InterfacesExposeSelectors() public pure {
        assertTrue(ICitizenEligibilityPolicy.isCitizenInGoodStanding.selector != bytes4(0));
        assertTrue(IConstitutionKernel.bootstrapAuthority.selector != bytes4(0));
        assertTrue(IGovernanceRouter.cancelAction.selector != bytes4(0));
        assertTrue(IIdentityRegistry.getWalletLink.selector != bytes4(0));
        assertTrue(ILegislationRegistry.recordRepeal.selector != bytes4(0));
        assertTrue(IPublicVetoApp.castPublicVeto.selector != bytes4(0));
        assertTrue(ISenateApp.supportActionCancellation.selector != bytes4(0));
        assertTrue(ISenateApp.supportSubLegalMeasureRepeal.selector != bytes4(0));
        assertTrue(ISenateApp.transferMySeat.selector != bytes4(0));
        assertTrue(ISenatePowersPolicy.isActionCancellationAllowed.selector != bytes4(0));
        assertTrue(ISenateSeatRegistry.assignSeat.selector != bytes4(0));
        assertTrue(IStakeRegistry.activeStakeOf.selector != bytes4(0));
    }

    function test_SenateTransfer_RequiresCitizenInvalidatesOldSupportAndAllowsNewHolder() public {
        bytes32 actionId = _queueModuleUpdate();

        vm.prank(WALLET_ONE);
        senateApp.supportActionCancellation(actionId, 0);
        assertEq(senateApp.actionCancellationSupportCount(actionId), 1);

        bytes32 nonCitizenPersonId = keccak256("person.non-citizen");
        IdentityTypes.IdentityRecordInput memory nonCitizenIdentity = _defaultIdentityInput();
        nonCitizenIdentity.citizenshipStatus = IdentityTypes.CitizenshipStatus.EResident;
        _setIdentityRecord(nonCitizenPersonId, nonCitizenIdentity);
        _setWalletLink(nonCitizenPersonId, outsider, IdentityTypes.WalletLinkStatus.Active);

        vm.startPrank(WALLET_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(ISenateApp.SenateSeatRecipientNotCitizen.selector, outsider, nonCitizenPersonId)
        );
        senateApp.transferMySeat(0, outsider);
        vm.expectRevert(
            abi.encodeWithSelector(ISenateApp.SenateSeatRecipientNotCitizen.selector, outsider, nonCitizenPersonId)
        );
        senateApp.nominateSuccessor(0, outsider);
        vm.stopPrank();

        assertEq(senateSeatRegistry.getSeatRecord(0).holder, WALLET_ONE);
        assertEq(senateApp.actionCancellationSupportCount(actionId), 1);

        vm.prank(WALLET_ONE);
        senateApp.transferMySeat(0, WALLET_TWO);

        SenateTypes.SenateSeatRecord memory transferredSeat = senateSeatRegistry.getSeatRecord(0);
        assertEq(transferredSeat.holder, WALLET_TWO);
        assertEq(senateApp.actionCancellationSupportCount(actionId), 0);

        vm.prank(WALLET_TWO);
        senateApp.supportActionCancellation(actionId, 0);
        assertEq(senateApp.actionCancellationSupportCount(actionId), 1);
    }

    function test_SenateAndPresidentAuthorityFollowActiveWalletMigration() public {
        bytes32 actionId = _queueModuleUpdate();

        _setWalletLink(PERSON_ONE_ID, WALLET_ONE, IdentityTypes.WalletLinkStatus.Revoked);
        _setWalletLink(PERSON_ONE_ID, WALLET_ONE_NEW, IdentityTypes.WalletLinkStatus.Active);

        vm.prank(WALLET_ONE);
        vm.expectRevert(abi.encodeWithSelector(ISenateApp.NotSeatHolder.selector, 0, WALLET_ONE));
        senateApp.supportActionCancellation(actionId, 0);
        vm.prank(WALLET_ONE_NEW);
        senateApp.supportActionCancellation(actionId, 0);
        assertEq(senateApp.actionCancellationSupportCount(actionId), 1);

        vm.prank(WALLET_ONE);
        vm.expectRevert(abi.encodeWithSelector(ISenateApp.NotPresident.selector, WALLET_ONE));
        senateApp.castPresidentActionCancellationProxyVote(actionId, SenateTypes.VoteOption.For);
        vm.prank(WALLET_ONE_NEW);
        senateApp.castPresidentActionCancellationProxyVote(actionId, SenateTypes.VoteOption.For);
    }

    function test_SenateCancellation_UsesCurrentSeatOccupancyAndSupportsSuccession() public {
        bytes32 actionId = _queueModuleUpdate();

        vm.prank(WALLET_ONE);
        senateApp.supportActionCancellation(actionId, 0);
        assertEq(senateApp.actionCancellationSupportCount(actionId), 1);

        vm.prank(WALLET_ONE);
        senateApp.nominateSuccessor(0, WALLET_TWO);
        vm.prank(WALLET_ONE);
        senateApp.vacateMySeat(0);

        assertEq(senateApp.actionCancellationSupportCount(actionId), 0);
        SenateTypes.SenateSeatRecord memory vacantSeat = senateSeatRegistry.getSeatRecord(0);
        assertTrue(vacantSeat.vacant);
        assertEq(vacantSeat.nominatedSuccessor, WALLET_TWO);

        vm.prank(WALLET_TWO);
        senateApp.claimSeatBySuccession(0);

        SenateTypes.SenateSeatRecord memory claimedSeat = senateSeatRegistry.getSeatRecord(0);
        assertFalse(claimedSeat.vacant);
        assertEq(claimedSeat.holder, WALLET_TWO);
        assertEq(claimedSeat.transferCount, 2);
        assertEq(senateApp.actionCancellationSupportCount(actionId), 0);

        vm.prank(WALLET_TWO);
        senateApp.supportActionCancellation(actionId, 0);
        assertEq(senateApp.actionCancellationSupportCount(actionId), 1);

        vm.prank(WALLET_THREE);
        senateApp.supportActionCancellation(actionId, 1);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Queued));
        _finalizeActionCancellationAtDeadline(actionId);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));

        SenateTypes.ActionCancellationRecord memory cancellationRecord = senateApp.getActionCancellationRecord(actionId);
        assertTrue(cancellationRecord.finalized);
        assertTrue(cancellationRecord.canceled);
        assertEq(cancellationRecord.supportSnapshot, 2);
    }

    function test_SenateCancellation_CanCancelQueuedLegislationEnactment() public {
        bytes32 actionId = _queueLegislationEnactment();

        vm.prank(WALLET_ONE);
        senateApp.supportActionCancellation(actionId, 0);
        vm.prank(WALLET_THREE);
        senateApp.supportActionCancellation(actionId, 1);

        _finalizeActionCancellationAtDeadline(actionId);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));
    }

    function test_SenateCancellation_CanCancelQueuedTreasuryDisbursement() public {
        bytes32 actionId = _queueTreasuryDisbursement();

        vm.prank(WALLET_ONE);
        senateApp.supportActionCancellation(actionId, 0);
        vm.prank(WALLET_THREE);
        senateApp.supportActionCancellation(actionId, 1);

        _finalizeActionCancellationAtDeadline(actionId);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));
        assertEq(usdc.balanceOf(address(treasuryVault)), 1_000 * 1e6);
    }

    function test_CurrentAuditedOriginCanRouteTypedTreasuryDisbursement() public {
        GovernanceTypes.TreasuryDisbursementPayload memory payload = GovernanceTypes.TreasuryDisbursementPayload({
            requestId: TREASURY_REQUEST_ID,
            budgetId: TREASURY_BUDGET_ID,
            asset: address(usdc),
            recipient: TREASURY_RECIPIENT,
            amount: 250 * 1e6,
            noteHash: keccak256("treasury-note")
        });

        // The core authenticates the current audited origin module and the typed target/payload. Branch policy
        // stays in replaceable apps; the stable TreasuryVault still requires the exact budget commitment.
        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.TreasuryDisbursement,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: payload.requestId,
            policyReference: keccak256(abi.encode(TreasuryTypes.DisbursementType.Operations, payload.budgetId)),
            targetModule: KernelModuleIds.TREASURY_VAULT,
            payload: abi.encode(payload),
            requestedExecutionTime: 0,
            expiresAt: 0
        });

        bytes32 actionId = mockReferendumApp.routeAction(request);
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Queued));
    }

    function test_OfficeOriginCannotBypassStableBudgetCommitment() public {
        bytes32 uncommittedRequestId = keccak256("treasury.uncommitted-request");
        GovernanceTypes.TreasuryDisbursementPayload memory payload = GovernanceTypes.TreasuryDisbursementPayload({
            requestId: uncommittedRequestId,
            budgetId: TREASURY_BUDGET_ID,
            asset: address(usdc),
            recipient: TREASURY_RECIPIENT,
            amount: 250 * 1e6,
            noteHash: keccak256("uncommitted-note")
        });
        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.TreasuryDisbursement,
            origin: GovernanceTypes.ActionOrigin.Office,
            originReference: uncommittedRequestId,
            policyReference: keccak256(abi.encode(TreasuryTypes.DisbursementType.Operations, TREASURY_BUDGET_ID)),
            targetModule: KernelModuleIds.TREASURY_VAULT,
            payload: abi.encode(payload),
            requestedExecutionTime: 0,
            expiresAt: 0
        });

        bytes32 actionId = mockReferendumApp.routeAction(request);
        vm.warp(timelock.getAction(actionId).earliestExecutionTime);
        vm.expectRevert(
            abi.encodeWithSelector(ITreasuryVault.InvalidDisbursementRequest.selector, uncommittedRequestId)
        );
        timelock.executeAction(actionId);
    }

    function test_OfficeOriginCannotChangeCommittedDisbursementAmount() public {
        budgetEnvelopeRegistry.reserveBudget(TREASURY_REQUEST_ID, TREASURY_BUDGET_ID, 250 * 1e6);
        GovernanceTypes.TreasuryDisbursementPayload memory payload = GovernanceTypes.TreasuryDisbursementPayload({
            requestId: TREASURY_REQUEST_ID,
            budgetId: TREASURY_BUDGET_ID,
            asset: address(usdc),
            recipient: TREASURY_RECIPIENT,
            amount: 500 * 1e6,
            noteHash: keccak256("tampered-amount")
        });
        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.TreasuryDisbursement,
            origin: GovernanceTypes.ActionOrigin.Office,
            originReference: TREASURY_REQUEST_ID,
            policyReference: keccak256(abi.encode(TreasuryTypes.DisbursementType.Operations, TREASURY_BUDGET_ID)),
            targetModule: KernelModuleIds.TREASURY_VAULT,
            payload: abi.encode(payload),
            requestedExecutionTime: 0,
            expiresAt: 0
        });

        bytes32 actionId = mockReferendumApp.routeAction(request);
        vm.warp(timelock.getAction(actionId).earliestExecutionTime);
        vm.expectRevert(abi.encodeWithSelector(ITreasuryVault.InvalidDisbursementRequest.selector, TREASURY_REQUEST_ID));
        timelock.executeAction(actionId);
    }

    function test_FinalizeClosesActionCancellationWhenActionExpiredBeforeFinalization() public {
        bytes32 actionId = _queueModuleUpdate();

        vm.prank(WALLET_ONE);
        senateApp.supportActionCancellation(actionId, 0);
        vm.prank(WALLET_THREE);
        senateApp.supportActionCancellation(actionId, 1);
        assertEq(senateApp.actionCancellationSupportCount(actionId), 2);

        // Let the queued action expire before the (met) cancellation vote is finalized.
        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);
        vm.warp(actionRecord.expiresAt + 1);
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Expired));

        // Finalize must not revert; it closes the record without canceling and without the external sink.
        senateApp.finalizeActionCancellation(actionId);

        SenateTypes.ActionCancellationRecord memory cancellationRecord = senateApp.getActionCancellationRecord(actionId);
        assertTrue(cancellationRecord.finalized);
        assertFalse(cancellationRecord.canceled);
        assertEq(cancellationRecord.supportSnapshot, 2);
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Expired));
    }

    function test_SenateDisbursementSuspension_BlocksExecutionThenAutoLapses() public {
        bytes32 actionId = _queueTreasuryDisbursement();

        _supportDisbursementSuspension(actionId);
        vm.expectRevert(abi.encodeWithSelector(ISenateApp.InvalidDisbursementSuspensionReason.selector, bytes32(0)));
        senateApp.suspendDisbursement(actionId, 0, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(ISenateApp.NotSeatHolder.selector, 0, address(this)));
        senateApp.suspendDisbursement(actionId, 0, DISBURSEMENT_SUSPENSION_REASON);
        vm.prank(WALLET_ONE);
        senateApp.suspendDisbursement(actionId, 0, DISBURSEMENT_SUSPENSION_REASON);

        SenateTypes.DisbursementSuspension memory suspension = senateApp.getDisbursementSuspension(actionId);
        assertTrue(suspension.exists);
        assertEq(suspension.renewalCount, 0);
        assertEq(suspension.reasonHash, DISBURSEMENT_SUSPENSION_REASON);
        assertEq(suspension.suspendedUntil, uint64(block.timestamp) + DISBURSEMENT_SUSPENSION_PERIOD);

        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);
        vm.warp(actionRecord.earliestExecutionTime);
        assertFalse(timelock.isActionExecutable(actionId));
        vm.expectRevert(
            abi.encodeWithSelector(IActionTimelock.ActionSuspended.selector, actionId, suspension.suspendedUntil)
        );
        timelock.executeAction(actionId);

        // After the window lapses (no renewal) execution resumes with no explicit un-suspend call.
        vm.warp(suspension.suspendedUntil);
        assertTrue(timelock.isActionExecutable(actionId));
        timelock.executeAction(actionId);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Executed));
        assertEq(usdc.balanceOf(TREASURY_RECIPIENT), 250 * 1e6);
    }

    function test_SenateDisbursementSuspension_RenewalKeepsBlockingPastOriginalWindow() public {
        bytes32 actionId = _queueTreasuryDisbursement();

        _supportDisbursementSuspension(actionId);
        vm.prank(WALLET_ONE);
        senateApp.suspendDisbursement(actionId, 0, DISBURSEMENT_SUSPENSION_REASON);

        uint64 originalSuspendedUntil = senateApp.getDisbursementSuspension(actionId).suspendedUntil;

        // Renew before the original window lapses; the window extends and the renewal count increments.
        vm.warp(originalSuspendedUntil - 1 days);
        vm.expectRevert(abi.encodeWithSelector(ISenateApp.InvalidDisbursementSuspensionReason.selector, bytes32(0)));
        senateApp.renewDisbursementSuspension(actionId, 0, bytes32(0));
        vm.prank(WALLET_ONE);
        senateApp.renewDisbursementSuspension(actionId, 0, DISBURSEMENT_RENEWAL_REASON);

        SenateTypes.DisbursementSuspension memory suspension = senateApp.getDisbursementSuspension(actionId);
        assertEq(suspension.renewalCount, 1);
        assertEq(suspension.reasonHash, DISBURSEMENT_RENEWAL_REASON);
        assertEq(suspension.suspendedUntil, uint64(block.timestamp) + DISBURSEMENT_SUSPENSION_PERIOD);
        assertGt(suspension.suspendedUntil, originalSuspendedUntil);

        // At the original window boundary the disbursement is still blocked by the renewed suspension.
        vm.warp(originalSuspendedUntil);
        vm.expectRevert(
            abi.encodeWithSelector(IActionTimelock.ActionSuspended.selector, actionId, suspension.suspendedUntil)
        );
        timelock.executeAction(actionId);
    }

    function test_SenateDisbursementSuspension_ProxyOnlyCannotSuspend() public {
        bytes32 actionId = _queueTreasuryDisbursement();

        vm.prank(WALLET_ONE);
        senateApp.castPresidentDisbursementSuspensionProxyVote(actionId, SenateTypes.VoteOption.For);

        // Raw proxy support (2) reaches the threshold but violates the participation floor, so suspension is refused.
        vm.prank(WALLET_ONE);
        vm.expectRevert(abi.encodeWithSelector(ISenateApp.SenateSupportNotActive.selector, actionId, 0));
        senateApp.suspendDisbursement(actionId, 0, DISBURSEMENT_SUSPENSION_REASON);

        assertFalse(senateApp.getDisbursementSuspension(actionId).exists);
    }

    function _supportDisbursementSuspension(bytes32 actionId) internal {
        vm.prank(WALLET_ONE);
        senateApp.supportDisbursementSuspension(actionId, 0);
        vm.prank(WALLET_THREE);
        senateApp.supportDisbursementSuspension(actionId, 1);
    }

    function test_PresidentProxyVoteCountsForNonVotingSenatorsAtDeadline() public {
        bytes32 actionId = _queueModuleUpdate();

        // One explicit For (seat 1) plus a President proxy covering the remaining non-voting occupied seat (seat 0):
        // proxy amplifies direct support and the floor (proxy <= direct) is satisfied.
        vm.prank(WALLET_THREE);
        senateApp.supportActionCancellation(actionId, 1);
        vm.prank(WALLET_ONE);
        senateApp.castPresidentActionCancellationProxyVote(actionId, SenateTypes.VoteOption.For);

        assertEq(senateApp.actionCancellationSupportCount(actionId), 1);

        _finalizeActionCancellationAtDeadline(actionId);

        SenateTypes.ActionCancellationRecord memory cancellationRecord = senateApp.getActionCancellationRecord(actionId);
        assertTrue(cancellationRecord.canceled);
        assertEq(cancellationRecord.supportSnapshot, 2);
        assertEq(cancellationRecord.presidentProxySupportSnapshot, 1);
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));
    }

    function test_PresidentProxyOnlyCannotFabricateActionCancellation() public {
        bytes32 actionId = _queueModuleUpdate();

        // President proxy-votes For on every non-voting occupied seat, with zero explicit For votes.
        vm.prank(WALLET_ONE);
        senateApp.castPresidentActionCancellationProxyVote(actionId, SenateTypes.VoteOption.For);

        assertEq(senateApp.actionCancellationSupportCount(actionId), 0);

        _finalizeActionCancellationAtDeadline(actionId);

        SenateTypes.ActionCancellationRecord memory cancellationRecord = senateApp.getActionCancellationRecord(actionId);
        assertTrue(cancellationRecord.finalized);
        // Raw support reaches the threshold (2), but it is entirely proxy so the participation floor blocks it.
        assertFalse(cancellationRecord.canceled);
        assertEq(cancellationRecord.supportSnapshot, 2);
        assertEq(cancellationRecord.presidentProxySupportSnapshot, 2);
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Queued));
    }

    function test_SenateCancellation_BlocksExecutionUntilOpenedCancellationIsFinalized() public {
        bytes32 actionId = _queueModuleUpdate();

        // One explicit For plus a President proxy so the opened cancellation clears the participation floor on finalize.
        vm.prank(WALLET_THREE);
        senateApp.supportActionCancellation(actionId, 1);
        vm.prank(WALLET_ONE);
        senateApp.castPresidentActionCancellationProxyVote(actionId, SenateTypes.VoteOption.For);

        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);
        vm.warp(actionRecord.earliestExecutionTime);

        assertFalse(timelock.isActionExecutable(actionId));
        vm.expectRevert(
            abi.encodeWithSelector(
                IActionTimelock.ActionCancellationPending.selector, actionId, actionRecord.earliestExecutionTime
            )
        );
        timelock.executeAction(actionId);

        senateApp.finalizeActionCancellation(actionId);
        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));
    }

    function test_SenateReferendumVeto_CancelsActiveLawReferendum() public {
        vm.prank(WALLET_ONE);
        senateApp.supportReferendumVeto(ACTIVE_REFERENDUM_ID, 0);
        assertEq(senateApp.referendumVetoSupportCount(ACTIVE_REFERENDUM_ID), 1);

        vm.prank(WALLET_THREE);
        senateApp.supportReferendumVeto(ACTIVE_REFERENDUM_ID, 1);

        ReferendumTypes.ReferendumRecord memory referendumRecord =
            referendumRegistry.getReferendum(ACTIVE_REFERENDUM_ID);
        assertEq(uint256(referendumRecord.status), uint256(ReferendumTypes.ReferendumStatus.Active));

        vm.warp(referendumRecord.endTime);
        senateApp.finalizeReferendumVeto(ACTIVE_REFERENDUM_ID);

        referendumRecord = referendumRegistry.getReferendum(ACTIVE_REFERENDUM_ID);
        assertEq(uint256(referendumRecord.status), uint256(ReferendumTypes.ReferendumStatus.Canceled));

        SenateTypes.ReferendumVetoRecord memory vetoRecord = senateApp.getReferendumVetoRecord(ACTIVE_REFERENDUM_ID);
        assertTrue(vetoRecord.finalized);
        assertTrue(vetoRecord.vetoed);
        assertEq(vetoRecord.supportSnapshot, 2);
    }

    function test_PresidentProxyVoteAppliesToReferendumVetoAtDeadline() public {
        // One direct seat support so the President proxy amplifies WITHIN the H5 floor (proxy <= direct):
        // the proxy still applies (it carries the remaining non-voting seat), but cannot pass a veto alone.
        vm.prank(WALLET_ONE);
        senateApp.supportReferendumVeto(ACTIVE_REFERENDUM_ID, 0);

        vm.prank(WALLET_ONE);
        senateApp.castPresidentReferendumVetoProxyVote(ACTIVE_REFERENDUM_ID, SenateTypes.VoteOption.For);

        ReferendumTypes.ReferendumRecord memory referendumRecord =
            referendumRegistry.getReferendum(ACTIVE_REFERENDUM_ID);
        vm.warp(referendumRecord.endTime);
        senateApp.finalizeReferendumVeto(ACTIVE_REFERENDUM_ID);

        SenateTypes.ReferendumVetoRecord memory vetoRecord = senateApp.getReferendumVetoRecord(ACTIVE_REFERENDUM_ID);
        assertTrue(vetoRecord.vetoed);
        assertEq(vetoRecord.supportSnapshot, 2);
        assertEq(vetoRecord.presidentProxySupportSnapshot, 1);
    }

    function test_PresidentProxyOnlyCannotFabricateReferendumVeto() public {
        // President proxy-votes For on every non-voting occupied seat, with zero explicit For votes.
        vm.prank(WALLET_ONE);
        senateApp.castPresidentReferendumVetoProxyVote(ACTIVE_REFERENDUM_ID, SenateTypes.VoteOption.For);

        ReferendumTypes.ReferendumRecord memory referendumRecord =
            referendumRegistry.getReferendum(ACTIVE_REFERENDUM_ID);
        vm.warp(referendumRecord.endTime);
        senateApp.finalizeReferendumVeto(ACTIVE_REFERENDUM_ID);

        SenateTypes.ReferendumVetoRecord memory vetoRecord = senateApp.getReferendumVetoRecord(ACTIVE_REFERENDUM_ID);
        assertTrue(vetoRecord.finalized);
        // Raw support reaches the threshold (2), but it is entirely proxy so the H5 floor blocks the veto:
        // a solo President cannot cancel an active citizen referendum.
        assertFalse(vetoRecord.vetoed);
        assertEq(vetoRecord.supportSnapshot, 2);
        assertEq(vetoRecord.presidentProxySupportSnapshot, 2);
    }

    function test_SenateSubLegalRepeal_RepealsTier3AfterVotingPeriod() public {
        vm.prank(WALLET_ONE);
        senateApp.supportSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID, 0);
        vm.prank(WALLET_THREE);
        senateApp.supportSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID, 1);

        SenateTypes.SubLegalMeasureRepealRecord memory repealRecord =
            senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        assertTrue(repealRecord.exists);
        assertFalse(repealRecord.finalized);
        assertFalse(repealRecord.repealed);
        assertEq(senateApp.subLegalMeasureRepealSupportCount(SUB_LEGAL_MEASURE_ID), 2);

        vm.warp(repealRecord.deadline);
        senateApp.finalizeSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID);

        repealRecord = senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        assertTrue(repealRecord.finalized);
        assertTrue(repealRecord.repealed);
        assertEq(repealRecord.supportSnapshot, 2);

        LegislationTypes.LegislationRecord memory legislationRecord =
            legislationRegistry.getLegislationRecord(SUB_LEGAL_MEASURE_ID);
        assertFalse(legislationRecord.active);
        assertTrue(legislationRecord.repealed);
        assertEq(uint256(legislationRecord.repealOrigin), uint256(LegislationTypes.RepealOrigin.Senate));
        assertEq(legislationRecord.repealReference, repealRecord.repealId);
    }

    function test_SenateSubLegalRepeal_CanRetryFailedVoteWithoutCountingOldSupport() public {
        vm.prank(WALLET_ONE);
        senateApp.supportSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID, 0);

        SenateTypes.SubLegalMeasureRepealRecord memory firstAttempt =
            senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        assertEq(firstAttempt.attemptNonce, 1);
        assertEq(senateApp.subLegalMeasureRepealSupportCount(SUB_LEGAL_MEASURE_ID), 1);

        vm.warp(firstAttempt.deadline);
        senateApp.finalizeSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID);

        firstAttempt = senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        assertTrue(firstAttempt.finalized);
        assertFalse(firstAttempt.repealed);
        assertEq(firstAttempt.supportSnapshot, 1);
        assertEq(senateApp.subLegalMeasureRepealSupportCount(SUB_LEGAL_MEASURE_ID), 0);

        SenateTypes.VoteSupport memory oldSupport = senateApp.getSubLegalMeasureRepealSupport(SUB_LEGAL_MEASURE_ID, 0);
        assertFalse(oldSupport.supported);

        vm.prank(WALLET_THREE);
        senateApp.supportSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID, 1);

        SenateTypes.SubLegalMeasureRepealRecord memory secondAttempt =
            senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        assertEq(secondAttempt.attemptNonce, 2);
        assertNotEq(secondAttempt.repealId, firstAttempt.repealId);
        assertFalse(secondAttempt.finalized);
        assertEq(senateApp.subLegalMeasureRepealSupportCount(SUB_LEGAL_MEASURE_ID), 1);

        vm.warp(secondAttempt.deadline);
        senateApp.finalizeSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID);

        secondAttempt = senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        assertTrue(secondAttempt.finalized);
        assertFalse(secondAttempt.repealed);
        assertEq(secondAttempt.supportSnapshot, 1);

        vm.prank(WALLET_ONE);
        senateApp.supportSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID, 0);

        SenateTypes.SubLegalMeasureRepealRecord memory thirdAttempt =
            senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        assertEq(thirdAttempt.attemptNonce, 3);
        assertEq(senateApp.subLegalMeasureRepealSupportCount(SUB_LEGAL_MEASURE_ID), 1);

        vm.prank(WALLET_THREE);
        senateApp.supportSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID, 1);
        assertEq(senateApp.subLegalMeasureRepealSupportCount(SUB_LEGAL_MEASURE_ID), 2);

        vm.warp(thirdAttempt.deadline);
        senateApp.finalizeSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID);

        thirdAttempt = senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        assertTrue(thirdAttempt.finalized);
        assertTrue(thirdAttempt.repealed);
        assertEq(thirdAttempt.supportSnapshot, 2);
    }

    function test_SenateSubLegalRepeal_RevertsForLawTier() public {
        vm.prank(WALLET_ONE);
        vm.expectRevert(abi.encodeWithSelector(ISenateApp.SenateProcessNotAllowed.selector, ORDINARY_MEASURE_ID));
        senateApp.supportSubLegalMeasureRepeal(ORDINARY_MEASURE_ID, 0);
    }

    function test_PresidentProxyVoteAppliesToSubLegalMeasureRepealAtDeadline() public {
        // Explicit For (seat 1) plus a President proxy covering the remaining occupied seat: floor satisfied.
        vm.prank(WALLET_THREE);
        senateApp.supportSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID, 1);
        vm.prank(WALLET_ONE);
        senateApp.castPresidentSubLegalMeasureRepealProxyVote(SUB_LEGAL_MEASURE_ID, SenateTypes.VoteOption.For);

        SenateTypes.SubLegalMeasureRepealRecord memory repealRecord =
            senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        vm.warp(repealRecord.deadline);
        senateApp.finalizeSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID);

        repealRecord = senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        assertTrue(repealRecord.repealed);
        assertEq(repealRecord.supportSnapshot, 2);
        assertEq(repealRecord.presidentProxySupportSnapshot, 1);
    }

    function test_PresidentProxyOnlyCannotFabricateSubLegalRepeal() public {
        vm.prank(WALLET_ONE);
        senateApp.castPresidentSubLegalMeasureRepealProxyVote(SUB_LEGAL_MEASURE_ID, SenateTypes.VoteOption.For);

        SenateTypes.SubLegalMeasureRepealRecord memory repealRecord =
            senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        vm.warp(repealRecord.deadline);
        senateApp.finalizeSubLegalMeasureRepeal(SUB_LEGAL_MEASURE_ID);

        repealRecord = senateApp.getSubLegalMeasureRepealRecord(SUB_LEGAL_MEASURE_ID);
        assertTrue(repealRecord.finalized);
        // Proxy-only support reaches the raw threshold (2) but never clears the participation floor.
        assertFalse(repealRecord.repealed);
        assertEq(repealRecord.supportSnapshot, 2);
        assertEq(repealRecord.presidentProxySupportSnapshot, 2);

        LegislationTypes.LegislationRecord memory legislationRecord =
            legislationRegistry.getLegislationRecord(SUB_LEGAL_MEASURE_ID);
        assertTrue(legislationRecord.active);
        assertFalse(legislationRecord.repealed);
    }

    function test_SenateReferendumVeto_RevertsForConstitutionalReferendum() public {
        vm.prank(WALLET_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(ISenateApp.SenateProcessNotAllowed.selector, CONSTITUTIONAL_REFERENDUM_ID)
        );
        senateApp.supportReferendumVeto(CONSTITUTIONAL_REFERENDUM_ID, 0);
    }

    function test_SenateReferendumVeto_RevertsForSenateSelfReplacement() public {
        _seedSenateSelfReplacementReferendum();

        vm.prank(WALLET_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(ISenateApp.SenateProcessNotAllowed.selector, SENATE_SELF_REPLACEMENT_REFERENDUM_ID)
        );
        senateApp.supportReferendumVeto(SENATE_SELF_REPLACEMENT_REFERENDUM_ID, 0);
    }

    function test_PublicVeto_IsPersonCountedAndRepealsAtThreshold() public {
        bytes32 vetoId = publicVetoApp.previewVetoId(ORDINARY_MEASURE_ID);

        vm.prank(WALLET_ONE);
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_ID);

        VetoTypes.PublicVetoRecord memory firstRecord = publicVetoApp.getPublicVetoRecord(ORDINARY_MEASURE_ID);
        assertEq(firstRecord.vetoId, vetoId);
        assertEq(firstRecord.supportCount, 1);
        assertFalse(firstRecord.repealed);

        // The same person cannot double-cast; a second attempt reverts as already cast.
        vm.prank(WALLET_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(IPublicVetoApp.PublicVetoAlreadyCast.selector, ORDINARY_MEASURE_ID, PERSON_ONE_ID)
        );
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_ID);

        vm.prank(WALLET_THREE);
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_ID);

        VetoTypes.PublicVetoRecord memory vetoRecord = publicVetoApp.getPublicVetoRecord(ORDINARY_MEASURE_ID);
        assertEq(vetoRecord.supportCount, 2);
        assertTrue(vetoRecord.repealed);
        assertEq(vetoRecord.repealedAt, uint64(block.timestamp));

        LegislationTypes.LegislationRecord memory legislationRecord =
            legislationRegistry.getLegislationRecord(ORDINARY_MEASURE_ID);
        assertFalse(legislationRecord.active);
        assertTrue(legislationRecord.repealed);
        assertEq(uint256(legislationRecord.repealOrigin), uint256(LegislationTypes.RepealOrigin.PublicVeto));
        assertEq(legislationRecord.repealReference, vetoId);
    }

    function test_PublicVeto_RemoveSupportDoesNotUseMeritWeight() public {
        vm.prank(WALLET_ONE);
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_TWO_ID);

        VetoTypes.PublicVetoRecord memory vetoRecord = publicVetoApp.getPublicVetoRecord(ORDINARY_MEASURE_TWO_ID);
        assertEq(vetoRecord.supportCount, 1);

        vm.prank(WALLET_ONE);
        publicVetoApp.removePublicVeto(ORDINARY_MEASURE_TWO_ID);

        vetoRecord = publicVetoApp.getPublicVetoRecord(ORDINARY_MEASURE_TWO_ID);
        assertEq(vetoRecord.supportCount, 0);
        assertFalse(vetoRecord.repealed);

        LegislationTypes.LegislationRecord memory legislationRecord =
            legislationRegistry.getLegislationRecord(ORDINARY_MEASURE_TWO_ID);
        assertTrue(legislationRecord.active);
        assertFalse(legislationRecord.repealed);
    }

    function test_PublicVeto_RevertsForConstitutionalMeasure() public {
        vm.prank(WALLET_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(IPublicVetoApp.MeasureNotVetoEligible.selector, CONSTITUTIONAL_MEASURE_ID)
        );
        publicVetoApp.castPublicVeto(CONSTITUTIONAL_MEASURE_ID);
    }

    function test_PublicVeto_HelperViewsExposeEligibilityAndRemainingThreshold() public {
        assertEq(publicVetoApp.eligibleCitizenCount(), 4);
        assertEq(publicVetoApp.remainingRepealSupport(ORDINARY_MEASURE_ID), 2);

        vm.prank(WALLET_ONE);
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_ID);

        assertEq(publicVetoApp.remainingRepealSupport(ORDINARY_MEASURE_ID), 1);
    }

    function test_PublicVeto_EligibilityLossBeforeThresholdDoesNotRemainCounted() public {
        vm.prank(WALLET_ONE);
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_ID);

        IdentityTypes.IdentityRecordInput memory formerCitizen = _defaultIdentityInput();
        formerCitizen.citizenshipStatus = IdentityTypes.CitizenshipStatus.EResident;
        _setIdentityRecord(PERSON_ONE_ID, formerCitizen);

        assertFalse(publicVetoApp.hasActivePublicVeto(ORDINARY_MEASURE_ID, PERSON_ONE_ID));
        assertEq(publicVetoApp.currentPublicVetoSupportCount(ORDINARY_MEASURE_ID), 0);
        assertEq(publicVetoApp.getPublicVetoRecord(ORDINARY_MEASURE_ID).supportCount, 0);
        assertEq(publicVetoApp.remainingRepealSupport(ORDINARY_MEASURE_ID), 2);

        vm.prank(WALLET_THREE);
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_ID);

        VetoTypes.PublicVetoRecord memory vetoRecord = publicVetoApp.getPublicVetoRecord(ORDINARY_MEASURE_ID);
        assertEq(vetoRecord.supportCount, 1);
        assertFalse(vetoRecord.repealed);
        assertFalse(publicVetoApp.hasActivePublicVeto(ORDINARY_MEASURE_ID, PERSON_ONE_ID));

        vm.prank(WALLET_FOUR);
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_ID);

        vetoRecord = publicVetoApp.getPublicVetoRecord(ORDINARY_MEASURE_ID);
        assertEq(vetoRecord.supportCount, 2);
        assertTrue(vetoRecord.repealed);
    }

    function test_PublicVeto_ActiveSupportFollowsWalletMigration() public {
        vm.prank(WALLET_ONE);
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_TWO_ID);

        _setWalletLink(PERSON_ONE_ID, WALLET_ONE, IdentityTypes.WalletLinkStatus.Revoked);
        _setWalletLink(PERSON_ONE_ID, WALLET_ONE_NEW, IdentityTypes.WalletLinkStatus.Active);

        assertTrue(publicVetoApp.hasActivePublicVeto(ORDINARY_MEASURE_TWO_ID, PERSON_ONE_ID));
        assertEq(publicVetoApp.currentPublicVetoSupportCount(ORDINARY_MEASURE_TWO_ID), 1);

        vm.prank(WALLET_ONE);
        vm.expectRevert(abi.encodeWithSelector(IPublicVetoApp.NotEligiblePublicVetoer.selector, WALLET_ONE));
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_TWO_ID);

        vm.prank(WALLET_ONE_NEW);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPublicVetoApp.PublicVetoAlreadyCast.selector, ORDINARY_MEASURE_TWO_ID, PERSON_ONE_ID
            )
        );
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_TWO_ID);

        vm.prank(WALLET_THREE);
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_TWO_ID);

        VetoTypes.PublicVetoRecord memory vetoRecord = publicVetoApp.getPublicVetoRecord(ORDINARY_MEASURE_TWO_ID);
        assertEq(vetoRecord.supportCount, 2);
        assertTrue(vetoRecord.repealed);
    }

    function _deployFoundation() internal {
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(address(kernel), _defaultDelayConfig());
        router = new GovernanceRouter(address(kernel), address(this));
        targetModule = new MockModule(keccak256("target"));
        replacementModule = new MockModule(keccak256("replacement"));
        identityAuthority = new MockModule(keccak256("identity-authority"));
        stakeAuthority = new MockModule(keccak256("stake-authority"));
        legislationAuthority = new MockModule(keccak256("legislation-authority"));

        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));
        kernel.bootstrapSetModule(TARGET_MODULE_ID, address(targetModule));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(identityAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(stakeAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(stakeAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(legislationAuthority));

        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        legislationRegistry = new LegislationRegistry(address(kernel));
        referendumRegistry = new ReferendumRegistry(address(kernel));
        presidentRegistry = new PresidentRegistry(address(kernel));
        treasuryVault = new TreasuryVault(address(kernel));
        budgetEnvelopeRegistry = new BudgetEnvelopeRegistry(address(kernel));
        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);
        electorateRegistry = new ElectorateRegistry(address(kernel), address(identityRegistry), address(stakeRegistry));
        senateSeatRegistry = new SenateSeatRegistry(address(kernel));
        senatePowersPolicy = new SenatePowersPolicy(SENATE_CANCELLATION_THRESHOLD, DISBURSEMENT_SUSPENSION_PERIOD);
        mockReferendumApp =
            new MockReferendumAppForSenate(address(router), address(legislationRegistry), address(referendumRegistry));
        senateApp = new SenateApp(
            address(identityRegistry),
            address(senateSeatRegistry),
            address(senatePowersPolicy),
            address(presidentRegistry),
            address(router),
            address(timelock),
            address(mockReferendumApp)
        );
        publicVetoApp =
            new PublicVetoApp(address(legislationRegistry), address(citizenEligibilityPolicy), PUBLIC_VETO_THRESHOLD);

        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY, address(legislationRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(stakeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(citizenEligibilityPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.ELECTORATE_REGISTRY, address(electorateRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY, address(referendumRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.PRESIDENT_REGISTRY, address(presidentRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(mockReferendumApp));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_APP, address(mockReferendumApp));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY, address(senateApp));
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REPEAL_AUTHORITY, address(publicVetoApp));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY, address(senateSeatRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_POWERS_POLICY, address(senatePowersPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(senateApp));
        kernel.bootstrapSetModule(KernelModuleIds.PUBLIC_VETO_APP, address(publicVetoApp));
        kernel.bootstrapSetModule(KernelModuleIds.TREASURY_VAULT, address(treasuryVault));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY, address(budgetEnvelopeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, address(this));

        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, referendumAuthority);
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Senate, address(senateApp));
        // Treasury disbursements may only be routed by the Office origin, so the mock stands in for the
        // OfficeExecutor as the configured Office authority to keep queued-disbursement flows testable.
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Office, address(mockReferendumApp));

        usdc = new MockUSDC();
        usdc.mint(address(treasuryVault), 1_000 * 1e6);
        budgetEnvelopeRegistry.recordBudgetApproval(
            TREASURY_BUDGET_ID,
            TreasuryTypes.BudgetEnvelopeInput({
                officeId: keccak256("test.treasury-office"),
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(usdc),
                allocatedAmount: 1_000 * 1e6,
                startsAt: uint64(block.timestamp),
                endsAt: uint64(block.timestamp + 30 days),
                policyReference: keccak256("test.treasury-budget-policy")
            })
        );
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

    function _registerDefaultCitizens() internal {
        _registerCitizen(PERSON_ONE_ID, WALLET_ONE, 5_000);
        _registerCitizen(PERSON_TWO_ID, WALLET_TWO, 7_500);
        _registerCitizen(PERSON_THREE_ID, WALLET_THREE, 50_000);
        _registerCitizen(PERSON_FOUR_ID, WALLET_FOUR, 6_000);
        presidentRegistry.setPresident(
            WALLET_ONE, PERSON_ONE_ID, keccak256("president.mandate"), uint64(block.timestamp), type(uint64).max
        );
    }

    function _seedInitialSenateSeats() internal {
        senateApp.bootstrapAssignSeat(0, WALLET_ONE);
        senateApp.bootstrapAssignSeat(1, WALLET_THREE);

        assertEq(senateSeatRegistry.totalSeats(), 100);
        assertEq(senateSeatRegistry.occupiedSeatCount(), 2);
    }

    function _queueModuleUpdate() internal returns (bytes32 actionId) {
        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.ModulePointerUpdate,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: keccak256("test.senate.referendum"),
            policyReference: keccak256("test.senate.policy"),
            targetModule: TARGET_MODULE_ID,
            payload: abi.encode(GovernanceTypes.ModuleUpdatePayload({newModuleAddress: address(replacementModule)})),
            requestedExecutionTime: 0,
            expiresAt: 0
        });

        actionId = mockReferendumApp.routeAction(request);
    }

    function _finalizeActionCancellationAtDeadline(bytes32 actionId) internal {
        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);
        vm.warp(actionRecord.earliestExecutionTime);
        senateApp.finalizeActionCancellation(actionId);
    }

    function _queueLegislationEnactment() internal returns (bytes32 actionId) {
        GovernanceTypes.LegislationEnactmentPayload memory payload = GovernanceTypes.LegislationEnactmentPayload({
            measureId: PENDING_MEASURE_ID,
            tier: LegislationTypes.LegislationTier.Law,
            textHash: keccak256("pending-law"),
            proposerReference: PERSON_ONE_ID,
            enactedByReferendumId: keccak256("pending-referendum"),
            amendsMeasureId: bytes32(0)
        });

        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.LegislationEnactment,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: payload.enactedByReferendumId,
            policyReference: keccak256("test.senate.legislation-policy"),
            targetModule: KernelModuleIds.LEGISLATION_REGISTRY,
            payload: abi.encode(payload),
            requestedExecutionTime: uint64(block.timestamp + 7 days),
            expiresAt: 0
        });

        actionId = mockReferendumApp.routeAction(request);
    }

    function _queueTreasuryDisbursement() internal returns (bytes32 actionId) {
        budgetEnvelopeRegistry.reserveBudget(TREASURY_REQUEST_ID, TREASURY_BUDGET_ID, 250 * 1e6);

        GovernanceTypes.TreasuryDisbursementPayload memory payload = GovernanceTypes.TreasuryDisbursementPayload({
            requestId: TREASURY_REQUEST_ID,
            budgetId: TREASURY_BUDGET_ID,
            asset: address(usdc),
            recipient: TREASURY_RECIPIENT,
            amount: 250 * 1e6,
            noteHash: keccak256("treasury-note")
        });

        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.TreasuryDisbursement,
            origin: GovernanceTypes.ActionOrigin.Office,
            originReference: payload.requestId,
            policyReference: keccak256(abi.encode(TreasuryTypes.DisbursementType.Operations, payload.budgetId)),
            targetModule: KernelModuleIds.TREASURY_VAULT,
            payload: abi.encode(payload),
            requestedExecutionTime: 0,
            expiresAt: 0
        });

        actionId = mockReferendumApp.routeAction(request);
    }

    function _enactMeasure(bytes32 measureId, LegislationTypes.LegislationTier tier) internal {
        vm.prank(address(legislationAuthority));
        legislationRegistry.recordEnactment(
            measureId,
            LegislationTypes.LegislationRecordInput({
                tier: tier,
                textHash: keccak256(abi.encodePacked("text", measureId)),
                proposerReference: PERSON_ONE_ID,
                enactedByReferendumId: keccak256(abi.encodePacked("referendum", measureId)),
                amendsMeasureId: bytes32(0)
            })
        );
    }

    function _seedReferendum(bytes32 referendumId, ReferendumTypes.ReferendumClass referendumClass) internal {
        uint256 electorateHeadcountSnapshot =
            referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment ? 4 : 0;
        uint256 electorateVotingPowerSnapshot =
            referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment ? 68_500 : 0;

        vm.prank(address(mockReferendumApp));
        referendumRegistry.createReferendum(
            referendumId,
            ReferendumTypes.ReferendumRecordInput({
                referendumClass: referendumClass,
                proposalOrigin: ReferendumTypes.ProposalOrigin.Congress,
                proposalMetadataHash: keccak256(abi.encodePacked("proposal", referendumId)),
                proposedMeasureId: keccak256(abi.encodePacked("measure", referendumId)),
                amendsMeasureId: bytes32(0),
                legislationTextHash: keccak256(abi.encodePacked("text", referendumId)),
                legislationTier: referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment
                    ? LegislationTypes.LegislationTier.ConstitutionalOrInternationalTreaty
                    : LegislationTypes.LegislationTier.Law,
                targetModule: bytes32(0),
                proposedModuleAddress: address(0),
                registerNewModule: false,
                proposerReference: PERSON_ONE_ID,
                startTime: uint64(block.timestamp),
                endTime: uint64(block.timestamp + 7 days),
                adoptionDelay: 7 days,
                votingPowerSnapshotBlock: uint48(block.number),
                referendumPolicy: address(mockReferendumApp),
                votingPowerPolicy: address(mockReferendumApp),
                electorateHeadcountSnapshot: electorateHeadcountSnapshot,
                electorateVotingPowerSnapshot: electorateVotingPowerSnapshot,
                requiresSupermajority: false
            })
        );
    }

    function _seedSenateSelfReplacementReferendum() internal {
        vm.prank(address(mockReferendumApp));
        referendumRegistry.createReferendum(
            SENATE_SELF_REPLACEMENT_REFERENDUM_ID,
            ReferendumTypes.ReferendumRecordInput({
                referendumClass: ReferendumTypes.ReferendumClass.ModuleGovernance,
                proposalOrigin: ReferendumTypes.ProposalOrigin.Citizen,
                proposalMetadataHash: keccak256("replace-senate-app"),
                proposedMeasureId: keccak256("replace-senate-app-proposal"),
                amendsMeasureId: bytes32(0),
                legislationTextHash: bytes32(0),
                legislationTier: LegislationTypes.LegislationTier.Undefined,
                targetModule: KernelModuleIds.SENATE_APP,
                proposedModuleAddress: address(replacementModule),
                registerNewModule: false,
                proposerReference: PERSON_ONE_ID,
                startTime: uint64(block.timestamp),
                endTime: uint64(block.timestamp + 7 days),
                adoptionDelay: 7 days,
                votingPowerSnapshotBlock: uint48(block.number),
                referendumPolicy: address(mockReferendumApp),
                votingPowerPolicy: address(mockReferendumApp),
                electorateHeadcountSnapshot: 0,
                electorateVotingPowerSnapshot: 0,
                requiresSupermajority: false
            })
        );
    }

    function _registerCitizen(bytes32 personId, address wallet, uint256 activeStake) internal {
        _setIdentityRecord(personId, _defaultIdentityInput());
        _setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        _increaseStake(personId, activeStake);
    }

    function _setIdentityRecord(bytes32 personId, IdentityTypes.IdentityRecordInput memory input) internal {
        vm.prank(address(identityAuthority));
        identityRegistry.setIdentityRecord(personId, input);
    }

    function _setWalletLink(bytes32 personId, address wallet, IdentityTypes.WalletLinkStatus status) internal {
        vm.prank(address(identityAuthority));
        identityRegistry.setWalletLink(personId, wallet, status);
    }

    function _increaseStake(bytes32 personId, uint256 amount) internal {
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(personId, amount);
    }

    function _defaultIdentityInput() internal pure returns (IdentityTypes.IdentityRecordInput memory input) {
        return IdentityTypes.IdentityRecordInput({
            metadataHash: keccak256("identity"),
            metadataURI: "ipfs://identity",
            verificationStatus: IdentityTypes.VerificationStatus.Verified,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
            ageClass: IdentityTypes.AgeClass.Adult,
            correctionFlag: false,
            finalSuspension: false
        });
    }
}
