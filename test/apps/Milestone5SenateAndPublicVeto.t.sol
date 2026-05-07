// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {PublicVetoApp} from "../../contracts/apps/PublicVetoApp.sol";
import {SenateApp} from "../../contracts/apps/SenateApp.sol";
import {TreasuryVault} from "../../contracts/apps/TreasuryVault.sol";
import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {ICitizenEligibilityPolicy} from "../../contracts/interfaces/ICitizenEligibilityPolicy.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IGovernanceRouter} from "../../contracts/interfaces/IGovernanceRouter.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {ILegislationRegistry} from "../../contracts/interfaces/ILegislationRegistry.sol";
import {IPublicVetoApp} from "../../contracts/interfaces/IPublicVetoApp.sol";
import {ISenateApp} from "../../contracts/interfaces/ISenateApp.sol";
import {ISenatePowersPolicy} from "../../contracts/interfaces/ISenatePowersPolicy.sol";
import {ISenateSeatRegistry} from "../../contracts/interfaces/ISenateSeatRegistry.sol";
import {IStakeRegistry} from "../../contracts/interfaces/IStakeRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {SenatePowersPolicy} from "../../contracts/policies/SenatePowersPolicy.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LegislationRegistry} from "../../contracts/registries/LegislationRegistry.sol";
import {SenateSeatRegistry} from "../../contracts/registries/SenateSeatRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LegislationTypes} from "../../contracts/types/LegislationTypes.sol";
import {SenateTypes} from "../../contracts/types/SenateTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";
import {VetoTypes} from "../../contracts/types/VetoTypes.sol";

/// @title Milestone5SenateAndPublicVetoTest
/// @notice Covers v1 Senate succession, bounded Senate cancellation, and headcount-based public repeal.
contract Milestone5SenateAndPublicVetoTest is Test {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint32 internal constant SENATE_CANCELLATION_THRESHOLD = 2;
    uint256 internal constant PUBLIC_VETO_THRESHOLD = 2;

    bytes32 internal constant TARGET_MODULE_ID = keccak256("milestone5.target-module");
    bytes32 internal constant ORDINARY_MEASURE_ID = keccak256("measure.ordinary");
    bytes32 internal constant ORDINARY_MEASURE_TWO_ID = keccak256("measure.ordinary.two");
    bytes32 internal constant CONSTITUTIONAL_MEASURE_ID = keccak256("measure.constitutional");
    bytes32 internal constant PENDING_MEASURE_ID = keccak256("measure.pending");
    bytes32 internal constant TREASURY_REQUEST_ID = keccak256("treasury.request");
    bytes32 internal constant TREASURY_BUDGET_ID = keccak256("treasury.budget");

    bytes32 internal constant PERSON_ONE_ID = bytes32(uint256(1));
    bytes32 internal constant PERSON_TWO_ID = bytes32(uint256(2));
    bytes32 internal constant PERSON_THREE_ID = bytes32(uint256(3));
    bytes32 internal constant PERSON_FOUR_ID = bytes32(uint256(4));

    address internal constant WALLET_ONE = address(0xA11CE);
    address internal constant WALLET_ONE_ALT = address(0xA11CF);
    address internal constant WALLET_TWO = address(0xB0B);
    address internal constant WALLET_THREE = address(0xCAFE);
    address internal constant WALLET_FOUR = address(0xD00D);
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
    TreasuryVault internal treasuryVault;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    SenateSeatRegistry internal senateSeatRegistry;
    SenatePowersPolicy internal senatePowersPolicy;
    SenateApp internal senateApp;
    PublicVetoApp internal publicVetoApp;

    address internal referendumAuthority = makeAddr("referendumAuthority");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        _deployFoundation();
        _registerDefaultCitizens();
        _enactMeasure(ORDINARY_MEASURE_ID, LegislationTypes.LegislationTier.OrdinaryLaw);
        _enactMeasure(ORDINARY_MEASURE_TWO_ID, LegislationTypes.LegislationTier.OrdinaryLaw);
        _enactMeasure(CONSTITUTIONAL_MEASURE_ID, LegislationTypes.LegislationTier.ConstitutionalLaw);
        _seedInitialSenateSeats();

        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();
    }

    function test_Milestone5InterfacesExposeSelectors() public pure {
        assertTrue(ICitizenEligibilityPolicy.isCitizenInGoodStanding.selector != bytes4(0));
        assertTrue(IConstitutionKernel.bootstrapAuthority.selector != bytes4(0));
        assertTrue(IGovernanceRouter.cancelAction.selector != bytes4(0));
        assertTrue(IIdentityRegistry.getWalletLink.selector != bytes4(0));
        assertTrue(ILegislationRegistry.recordRepeal.selector != bytes4(0));
        assertTrue(IPublicVetoApp.castPublicVeto.selector != bytes4(0));
        assertTrue(ISenateApp.supportActionCancellation.selector != bytes4(0));
        assertTrue(ISenateApp.transferMySeat.selector != bytes4(0));
        assertTrue(ISenatePowersPolicy.isActionCancellationAllowed.selector != bytes4(0));
        assertTrue(ISenateSeatRegistry.assignSeat.selector != bytes4(0));
        assertTrue(IStakeRegistry.activeStakeOf.selector != bytes4(0));
    }

    function test_SenateTransfer_InvalidatesOldSeatSupportAndAllowsNewHolder() public {
        bytes32 actionId = _queueModuleUpdate();

        vm.prank(WALLET_ONE);
        senateApp.supportActionCancellation(actionId, 0);
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

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));

        SenateTypes.ActionCancellationRecord memory cancellationRecord = senateApp.getActionCancellationRecord(actionId);
        assertTrue(cancellationRecord.canceled);
        assertEq(cancellationRecord.supportSnapshot, 2);
    }

    function test_SenateCancellation_CanCancelQueuedLegislationEnactment() public {
        bytes32 actionId = _queueLegislationEnactment();

        vm.prank(WALLET_ONE);
        senateApp.supportActionCancellation(actionId, 0);
        vm.prank(WALLET_THREE);
        senateApp.supportActionCancellation(actionId, 1);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));
    }

    function test_SenateCancellation_CanCancelQueuedTreasuryDisbursement() public {
        bytes32 actionId = _queueTreasuryDisbursement();

        vm.prank(WALLET_ONE);
        senateApp.supportActionCancellation(actionId, 0);
        vm.prank(WALLET_THREE);
        senateApp.supportActionCancellation(actionId, 1);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));
        assertEq(address(treasuryVault).balance, 1 ether);
    }

    function test_PublicVeto_IsPersonCountedAndRepealsAtThreshold() public {
        bytes32 vetoId = publicVetoApp.previewVetoId(ORDINARY_MEASURE_ID);

        vm.prank(WALLET_ONE);
        publicVetoApp.castPublicVeto(ORDINARY_MEASURE_ID);

        VetoTypes.PublicVetoRecord memory firstRecord = publicVetoApp.getPublicVetoRecord(ORDINARY_MEASURE_ID);
        assertEq(firstRecord.vetoId, vetoId);
        assertEq(firstRecord.supportCount, 1);
        assertFalse(firstRecord.repealed);

        vm.prank(WALLET_ONE_ALT);
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

    function _deployFoundation() internal {
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(address(kernel));
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
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(legislationAuthority));

        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        legislationRegistry = new LegislationRegistry(address(kernel));
        treasuryVault = new TreasuryVault(address(kernel));
        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);
        senateSeatRegistry = new SenateSeatRegistry(address(kernel));
        senatePowersPolicy = new SenatePowersPolicy(SENATE_CANCELLATION_THRESHOLD);
        senateApp = new SenateApp(
            address(identityRegistry),
            address(senateSeatRegistry),
            address(senatePowersPolicy),
            address(router),
            address(timelock)
        );
        publicVetoApp =
            new PublicVetoApp(address(legislationRegistry), address(citizenEligibilityPolicy), PUBLIC_VETO_THRESHOLD);

        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY, address(legislationRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY, address(senateApp));
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REPEAL_AUTHORITY, address(publicVetoApp));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY, address(senateSeatRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_POWERS_POLICY, address(senatePowersPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(senateApp));
        kernel.bootstrapSetModule(KernelModuleIds.PUBLIC_VETO_APP, address(publicVetoApp));
        kernel.bootstrapSetModule(KernelModuleIds.TREASURY_VAULT, address(treasuryVault));

        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, referendumAuthority);
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Senate, address(senateApp));

        vm.deal(address(this), 1 ether);
        (bool funded,) = address(treasuryVault).call{value: 1 ether}("");
        require(funded, "treasury funding failed");
    }

    function _registerDefaultCitizens() internal {
        _registerCitizen(PERSON_ONE_ID, WALLET_ONE, 5_000);
        _setWalletLink(PERSON_ONE_ID, WALLET_ONE_ALT, IdentityTypes.WalletLinkStatus.Active);
        _registerCitizen(PERSON_TWO_ID, WALLET_TWO, 7_500);
        _registerCitizen(PERSON_THREE_ID, WALLET_THREE, 50_000);
        _registerCitizen(PERSON_FOUR_ID, WALLET_FOUR, 6_000);
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
            originReference: keccak256("milestone5-referendum"),
            policyReference: keccak256("milestone5-policy"),
            targetModule: TARGET_MODULE_ID,
            payload: abi.encode(GovernanceTypes.ModuleUpdatePayload({newModuleAddress: address(replacementModule)})),
            requestedExecutionTime: 0,
            expiresAt: 0
        });

        vm.prank(referendumAuthority);
        actionId = router.routeAction(request);
    }

    function _queueLegislationEnactment() internal returns (bytes32 actionId) {
        GovernanceTypes.LegislationEnactmentPayload memory payload = GovernanceTypes.LegislationEnactmentPayload({
            measureId: PENDING_MEASURE_ID,
            tier: LegislationTypes.LegislationTier.OrdinaryLaw,
            textHash: keccak256("pending-law"),
            proposerReference: PERSON_ONE_ID,
            enactedByReferendumId: keccak256("pending-referendum"),
            amendsMeasureId: bytes32(0)
        });

        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.LegislationEnactment,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: payload.enactedByReferendumId,
            policyReference: keccak256("milestone5-legislation-policy"),
            targetModule: KernelModuleIds.LEGISLATION_REGISTRY,
            payload: abi.encode(payload),
            requestedExecutionTime: 0,
            expiresAt: 0
        });

        vm.prank(referendumAuthority);
        actionId = router.routeAction(request);
    }

    function _queueTreasuryDisbursement() internal returns (bytes32 actionId) {
        GovernanceTypes.TreasuryDisbursementPayload memory payload = GovernanceTypes.TreasuryDisbursementPayload({
            requestId: TREASURY_REQUEST_ID,
            budgetId: TREASURY_BUDGET_ID,
            asset: address(0),
            recipient: TREASURY_RECIPIENT,
            amount: 0.25 ether,
            noteHash: keccak256("treasury-note")
        });

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

        vm.prank(referendumAuthority);
        actionId = router.routeAction(request);
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
