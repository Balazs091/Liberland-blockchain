// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {CabinetApp} from "../../contracts/apps/CabinetApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ICabinetApp} from "../../contracts/interfaces/ICabinetApp.sol";
import {IExecutiveRegistry} from "../../contracts/interfaces/IExecutiveRegistry.sol";
import {IOfficeRegistry} from "../../contracts/interfaces/IOfficeRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {ExecutiveRegistry} from "../../contracts/registries/ExecutiveRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {ExecutiveTypes} from "../../contracts/types/ExecutiveTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

/// @title CabinetAppTest
/// @notice Covers the Congress-appointed Prime Minister and the four-seat Cabinet (Constitution Art V §1-2):
///         strict-majority appointment recording the winning tally, the owner's removal rule (removal needs at
///         least the recorded appointment tally, independent of current seat count), the "PM cannot fire"
///         constraint on ministers, Congress-only minister dismissal, resignation paths, and the standing
///         authority that keeps appointments runnable after genesis bootstrap is disabled.
contract CabinetAppTest is Test {
    uint64 internal constant PRIME_MINISTER_TERM = 1825 days;
    uint64 internal constant MINISTER_TERM = 1825 days;
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint256 internal constant CITIZEN_STAKE = 10_000;

    // Congress member wallets (up to nine for the seat-growth removal proof).
    address internal constant CM1 = address(0xC01);
    address internal constant CM2 = address(0xC02);
    address internal constant CM3 = address(0xC03);
    address internal constant CM4 = address(0xC04);
    address internal constant CM5 = address(0xC05);
    address internal constant CM6 = address(0xC06);
    address internal constant CM7 = address(0xC07);
    address internal constant CM8 = address(0xC08);
    address internal constant CM9 = address(0xC09);
    address internal constant CM1_NEW = address(0xC10);

    // Prime Minister and minister candidates (citizens in good standing, not necessarily Congress members).
    address internal constant PM_CANDIDATE = address(0x9111);
    address internal constant PM_CANDIDATE_TWO = address(0x9222);
    address internal constant MIN_A = address(0xA1);
    address internal constant MIN_B = address(0xA2);
    address internal constant MIN_C = address(0xA3);
    address internal constant MIN_D = address(0xA4);
    address internal constant MIN_E = address(0xA5);
    address internal constant MIN_A_NEW = address(0xA6);
    address internal constant PM_NEW_WALLET = address(0x9333);
    address internal constant OUTSIDER = address(0x0175);

    bytes32 internal constant PID_PM = bytes32(uint256(100));

    // The Finance ministry's operational office, wired into the CabinetApp, seeded with a genesis bootstrap admin.
    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    address internal constant FINANCE_GENESIS_ADMIN = address(0xF1);

    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    CongressCandidateRegistry internal congressCandidateRegistry;
    ExecutiveRegistry internal executiveRegistry;
    OfficeRegistry internal officeRegistry;
    CabinetApp internal cabinetApp;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);
        congressCandidateRegistry = new CongressCandidateRegistry(address(kernel));
        executiveRegistry = new ExecutiveRegistry(address(kernel));
        officeRegistry = new OfficeRegistry(address(kernel));
        cabinetApp = new CabinetApp(
            address(executiveRegistry),
            address(congressCandidateRegistry),
            address(citizenEligibilityPolicy),
            FINANCE_OFFICE_ID,
            address(officeRegistry)
        );

        kernel.bootstrapSetModule(KernelModuleIds.EXECUTIVE_REGISTRY, address(executiveRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.EXECUTIVE_REGISTRY_AUTHORITY, address(cabinetApp));
        // Register the CabinetApp module pointer so the OfficeRegistry accepts it as a registry authority for the
        // ministry office admin/active transitions that follow cabinet appointments.
        kernel.bootstrapSetModule(KernelModuleIds.CABINET_APP, address(cabinetApp));
        // This test acts as the identity, stake, Congress, and office authorities so it can seed citizens, a term,
        // and the finance office directly.
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(citizenEligibilityPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(this));

        // Seed the Finance office exactly as genesis does: a bootstrap admin holds it until a Finance Minister is
        // appointed, at which point the CabinetApp transfers the admin to the elected minister.
        officeRegistry.registerOffice(
            FINANCE_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "Ministry of Finance", FINANCE_GENESIS_ADMIN
        );

        // Seed a pool of citizens in good standing: nine Congress-capable members plus the Cabinet candidates.
        _seedCitizen(bytes32(uint256(1)), CM1);
        _seedCitizen(bytes32(uint256(2)), CM2);
        _seedCitizen(bytes32(uint256(3)), CM3);
        _seedCitizen(bytes32(uint256(4)), CM4);
        _seedCitizen(bytes32(uint256(5)), CM5);
        _seedCitizen(bytes32(uint256(6)), CM6);
        _seedCitizen(bytes32(uint256(7)), CM7);
        _seedCitizen(bytes32(uint256(8)), CM8);
        _seedCitizen(bytes32(uint256(9)), CM9);
        _seedCitizen(PID_PM, PM_CANDIDATE);
        _seedCitizen(bytes32(uint256(101)), PM_CANDIDATE_TWO);
        _seedCitizen(bytes32(uint256(111)), MIN_A);
        _seedCitizen(bytes32(uint256(112)), MIN_B);
        _seedCitizen(bytes32(uint256(113)), MIN_C);
        _seedCitizen(bytes32(uint256(114)), MIN_D);
        _seedCitizen(bytes32(uint256(115)), MIN_E);

        // Initial seven-seat Congress term (cycle 1); strict majority is four.
        _seedCongress(_firstMembers(7));
        assertEq(congressCandidateRegistry.getCurrentOfficeTerm().occupiedSeatCount, 7);
    }

    function test_CabinetInterfacesExposeSelectors() public pure {
        assertTrue(ICabinetApp.voteForPrimeMinister.selector != bytes4(0));
        assertTrue(ICabinetApp.appointPrimeMinister.selector != bytes4(0));
        assertTrue(ICabinetApp.voteToRemovePrimeMinister.selector != bytes4(0));
        assertTrue(ICabinetApp.removePrimeMinister.selector != bytes4(0));
        assertTrue(ICabinetApp.appointMinister.selector != bytes4(0));
        assertTrue(ICabinetApp.dismissMinister.selector != bytes4(0));
        assertTrue(IExecutiveRegistry.setPrimeMinister.selector != bytes4(0));
        assertTrue(IExecutiveRegistry.setMinister.selector != bytes4(0));
    }

    function test_WiringAndConstantsAreExposed() public view {
        assertEq(cabinetApp.executiveRegistry(), address(executiveRegistry));
        assertEq(cabinetApp.congressCandidateRegistry(), address(congressCandidateRegistry));
        assertEq(cabinetApp.citizenEligibilityPolicy(), address(citizenEligibilityPolicy));
        assertEq(cabinetApp.officeRegistry(), address(officeRegistry));
        assertEq(cabinetApp.identityRegistry(), address(identityRegistry));
        assertEq(cabinetApp.kernel(), address(kernel));
        // Only the Finance ministry is wired to an operational office; the other three are unwired.
        assertEq(cabinetApp.ministryOfficeId(ExecutiveTypes.MinistryKind.Finance), FINANCE_OFFICE_ID);
        assertEq(cabinetApp.ministryOfficeId(ExecutiveTypes.MinistryKind.ForeignAffairs), bytes32(0));
        assertEq(cabinetApp.ministryOfficeId(ExecutiveTypes.MinistryKind.Interior), bytes32(0));
        assertEq(cabinetApp.ministryOfficeId(ExecutiveTypes.MinistryKind.Justice), bytes32(0));
        assertEq(cabinetApp.primeMinisterTerm(), PRIME_MINISTER_TERM);
        assertEq(cabinetApp.ministerTerm(), MINISTER_TERM);
        assertEq(cabinetApp.primeMinisterTerm(), 5 * 365 days);
    }

    function test_VoteRejectsNonCongressMemberAndBadCandidate() public {
        // A non-member cannot cast a Congress ballot.
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.NotCongressMember.selector, OUTSIDER));
        cabinetApp.voteForPrimeMinister(PM_CANDIDATE);

        // A member cannot vote for a candidate who is not a citizen in good standing.
        vm.prank(CM1);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.CandidateNotInGoodStanding.selector, OUTSIDER));
        cabinetApp.voteForPrimeMinister(OUTSIDER);
    }

    function test_CongressAppointsPrimeMinister_MajorityRecordsSupportAndTerm() public {
        // Three of seven occupied seats is not a strict majority (3 * 2 = 6 <= 7).
        _voteForPm(CM1, PM_CANDIDATE);
        _voteForPm(CM2, PM_CANDIDATE);
        _voteForPm(CM3, PM_CANDIDATE);
        assertEq(cabinetApp.appointmentVoteCount(PM_CANDIDATE), 3);
        assertFalse(cabinetApp.canAppointPrimeMinister(PM_CANDIDATE));
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.AppointmentMajorityNotReached.selector, PM_CANDIDATE, 3, 7));
        cabinetApp.appointPrimeMinister(PM_CANDIDATE);

        // The fourth ballot crosses the strict majority.
        _voteForPm(CM4, PM_CANDIDATE);
        assertEq(cabinetApp.appointmentVoteCount(PM_CANDIDATE), 4);
        assertTrue(cabinetApp.canAppointPrimeMinister(PM_CANDIDATE));

        uint64 expectedStart = uint64(block.timestamp);
        vm.expectEmit(true, true, false, true, address(cabinetApp));
        emit ICabinetApp.PrimeMinisterAppointed(
            PM_CANDIDATE, PID_PM, 4, 7, expectedStart, expectedStart + PRIME_MINISTER_TERM, expectedStart
        );
        cabinetApp.appointPrimeMinister(PM_CANDIDATE);

        assertEq(executiveRegistry.primeMinister(), PM_CANDIDATE);
        assertEq(executiveRegistry.getPrimeMinister().personId, PID_PM);
        // The winning vote count is recorded as the removal threshold.
        assertEq(executiveRegistry.primeMinisterAppointmentSupport(), 4);
        assertEq(executiveRegistry.getPrimeMinister().termStart, expectedStart);
        assertEq(executiveRegistry.getPrimeMinister().termEnd, expectedStart + PRIME_MINISTER_TERM);
        assertEq(
            executiveRegistry.getPrimeMinister().termEnd - executiveRegistry.getPrimeMinister().termStart, 5 * 365 days
        );
        assertTrue(executiveRegistry.isPrimeMinisterInTerm());
        // A successful appointment voids all appointment ballots for the next contest.
        assertEq(cabinetApp.appointmentVoteCount(PM_CANDIDATE), 0);
    }

    function test_RemovalRequiresAtLeastAppointmentTally() public {
        // Appointed by six of seven; the recorded removal threshold is six.
        _appointPmWithVotes(PM_CANDIDATE, 6);
        assertEq(executiveRegistry.primeMinisterAppointmentSupport(), 6);

        // Five removal votes are already a strict majority of the seven seats (5 * 2 = 10 > 7) yet fall short of
        // the recorded appointment tally (6): removal is a fixed absolute count, not the current majority.
        _voteRemove(CM1);
        _voteRemove(CM2);
        _voteRemove(CM3);
        _voteRemove(CM4);
        _voteRemove(CM5);
        assertEq(cabinetApp.removalVoteCount(), 5);
        assertFalse(cabinetApp.canRemovePrimeMinister());
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.RemovalThresholdNotReached.selector, 5, 6));
        cabinetApp.removePrimeMinister();

        // The sixth removal vote reaches the recorded tally and removes the Prime Minister.
        _voteRemove(CM6);
        assertEq(cabinetApp.removalVoteCount(), 6);
        assertTrue(cabinetApp.canRemovePrimeMinister());
        cabinetApp.removePrimeMinister();

        assertEq(executiveRegistry.primeMinister(), address(0));
        assertEq(executiveRegistry.primeMinisterAppointmentSupport(), 0);
        assertFalse(executiveRegistry.isPrimeMinisterInTerm());
    }

    function test_RemovalThresholdIsRecordedTally_NotCurrentMajority() public {
        // Appointed by six of seven; the recorded threshold is six.
        _appointPmWithVotes(PM_CANDIDATE, 6);
        assertEq(executiveRegistry.primeMinisterAppointmentSupport(), 6);

        // Congress GROWS to nine seats in a fresh cycle; the strict majority of nine is only five.
        _seedCongress(_firstMembers(9));
        assertEq(congressCandidateRegistry.getCurrentOfficeTerm().occupiedSeatCount, 9);

        // Five removal votes are a current majority of the nine seats (5 * 2 = 10 > 9) but below the recorded 6.
        _voteRemove(CM1);
        _voteRemove(CM2);
        _voteRemove(CM3);
        _voteRemove(CM4);
        _voteRemove(CM5);
        assertEq(cabinetApp.removalVoteCount(), 5);
        assertFalse(cabinetApp.canRemovePrimeMinister());
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.RemovalThresholdNotReached.selector, 5, 6));
        cabinetApp.removePrimeMinister();

        // The recorded appointment tally (6) governs regardless of the grown seat count.
        _voteRemove(CM6);
        assertEq(cabinetApp.removalVoteCount(), 6);
        cabinetApp.removePrimeMinister();
        assertEq(executiveRegistry.primeMinister(), address(0));
    }

    function test_CannotAppointSecondPmWhileInTerm_ReappointsAfterTerm() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);
        uint64 termEnd = executiveRegistry.getPrimeMinister().termEnd;

        // A fresh majority for a challenger cannot install a second Prime Minister while one is in term.
        _voteForPm(CM1, PM_CANDIDATE_TWO);
        _voteForPm(CM2, PM_CANDIDATE_TWO);
        _voteForPm(CM3, PM_CANDIDATE_TWO);
        _voteForPm(CM4, PM_CANDIDATE_TWO);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.PrimeMinisterAlreadyInTerm.selector, PM_CANDIDATE));
        cabinetApp.appointPrimeMinister(PM_CANDIDATE_TWO);

        // The term ends purely by passage of time; the pending majority then appoints the challenger.
        vm.warp(termEnd);
        assertFalse(executiveRegistry.isPrimeMinisterInTerm());
        assertTrue(cabinetApp.canAppointPrimeMinister(PM_CANDIDATE_TWO));
        cabinetApp.appointPrimeMinister(PM_CANDIDATE_TWO);

        assertEq(executiveRegistry.primeMinister(), PM_CANDIDATE_TWO);
        assertEq(executiveRegistry.getPrimeMinister().termEnd, termEnd + PRIME_MINISTER_TERM);
    }

    function test_PrimeMinisterAppointsFourMinisters_CannotFire_NonPmCannot() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);

        // Neither an outsider nor a mere Congress member may appoint ministers.
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.NotPrimeMinister.selector, OUTSIDER));
        cabinetApp.appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        vm.prank(CM1);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.NotPrimeMinister.selector, CM1));
        cabinetApp.appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);

        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);

        // Appointees must be citizens in good standing; the Prime Minister may not double as a minister; and a
        // sitting minister may not hold a second ministry. Each is checked on a still-vacant slot.
        vm.prank(PM_CANDIDATE);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.CandidateNotInGoodStanding.selector, OUTSIDER));
        cabinetApp.appointMinister(ExecutiveTypes.MinistryKind.ForeignAffairs, OUTSIDER);
        vm.prank(PM_CANDIDATE);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.InvalidMinisterCandidate.selector, PM_CANDIDATE));
        cabinetApp.appointMinister(ExecutiveTypes.MinistryKind.ForeignAffairs, PM_CANDIDATE);
        vm.prank(PM_CANDIDATE);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.MinisterAlreadyServing.selector, MIN_A));
        cabinetApp.appointMinister(ExecutiveTypes.MinistryKind.ForeignAffairs, MIN_A);

        _appointMinister(ExecutiveTypes.MinistryKind.ForeignAffairs, MIN_B);
        _appointMinister(ExecutiveTypes.MinistryKind.Interior, MIN_C);
        _appointMinister(ExecutiveTypes.MinistryKind.Justice, MIN_D);

        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Finance).minister, MIN_A);
        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.ForeignAffairs).minister, MIN_B);
        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Interior).minister, MIN_C);
        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Justice).minister, MIN_D);
        assertTrue(executiveRegistry.isMinisterInTerm(ExecutiveTypes.MinistryKind.Finance));
        assertEq(
            executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Justice).termEnd
                - executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Justice).termStart,
            5 * 365 days
        );

        // "The PM cannot fire": reassigning a sitting in-term minister slot reverts.
        vm.prank(PM_CANDIDATE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICabinetApp.MinisterSlotOccupied.selector, ExecutiveTypes.MinistryKind.Finance, MIN_A
            )
        );
        cabinetApp.appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_E);
    }

    function test_OnlyCongressDismissesMinister_ThenPmReappoints_Resignations() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);

        // Three dismissal votes is not a strict majority of the seven seats (3 * 2 = 6 <= 7).
        _voteDismiss(CM1, ExecutiveTypes.MinistryKind.Finance);
        _voteDismiss(CM2, ExecutiveTypes.MinistryKind.Finance);
        _voteDismiss(CM3, ExecutiveTypes.MinistryKind.Finance);
        assertEq(cabinetApp.dismissalVoteCount(ExecutiveTypes.MinistryKind.Finance), 3);
        assertFalse(cabinetApp.canDismissMinister(ExecutiveTypes.MinistryKind.Finance));
        vm.expectRevert(
            abi.encodeWithSelector(
                ICabinetApp.DismissalMajorityNotReached.selector, ExecutiveTypes.MinistryKind.Finance, 3, 7
            )
        );
        cabinetApp.dismissMinister(ExecutiveTypes.MinistryKind.Finance);

        // The fourth vote is a strict majority; only Congress can dismiss, and the slot is left vacant.
        _voteDismiss(CM4, ExecutiveTypes.MinistryKind.Finance);
        assertTrue(cabinetApp.canDismissMinister(ExecutiveTypes.MinistryKind.Finance));
        cabinetApp.dismissMinister(ExecutiveTypes.MinistryKind.Finance);
        assertFalse(executiveRegistry.isMinisterInTerm(ExecutiveTypes.MinistryKind.Finance));
        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Finance).minister, address(0));

        // The now-vacant slot can be re-appointed by the Prime Minister.
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_E);
        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Finance).minister, MIN_E);
        assertTrue(executiveRegistry.isMinisterInTerm(ExecutiveTypes.MinistryKind.Finance));

        // A minister resigns their own ministry; a non-minister cannot.
        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(ICabinetApp.NotMinister.selector, ExecutiveTypes.MinistryKind.Finance, OUTSIDER)
        );
        cabinetApp.resignMinister(ExecutiveTypes.MinistryKind.Finance);
        vm.prank(MIN_E);
        cabinetApp.resignMinister(ExecutiveTypes.MinistryKind.Finance);
        assertFalse(executiveRegistry.isMinisterInTerm(ExecutiveTypes.MinistryKind.Finance));

        // The Prime Minister resigns; a non-Prime-Minister cannot.
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.NotPrimeMinister.selector, OUTSIDER));
        cabinetApp.resignPrimeMinister();
        vm.prank(PM_CANDIDATE);
        cabinetApp.resignPrimeMinister();
        assertEq(executiveRegistry.primeMinister(), address(0));
        assertFalse(executiveRegistry.isPrimeMinisterInTerm());
    }

    function test_ExecutiveRegistryGatesWritesAndRejectsUndefinedMinistry() public {
        // Only the bootstrap authority or the standing CabinetApp authority may write the registry.
        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutiveRegistry.UnauthorizedExecutiveRegistryCaller.selector, OUTSIDER)
        );
        executiveRegistry.setPrimeMinister(
            PM_CANDIDATE, PID_PM, uint64(block.timestamp), uint64(block.timestamp) + 1, 1
        );

        // The Undefined ministry sentinel is rejected even for an authorized caller (this test is bootstrap authority).
        vm.expectRevert(
            abi.encodeWithSelector(IExecutiveRegistry.InvalidMinistry.selector, ExecutiveTypes.MinistryKind.Undefined)
        );
        executiveRegistry.setMinister(
            ExecutiveTypes.MinistryKind.Undefined,
            MIN_A,
            bytes32(uint256(111)),
            uint64(block.timestamp),
            uint64(block.timestamp) + 1
        );
    }

    function test_PostGenesisBootstrapDisabled_AppointmentStillRuns() public {
        // A strict majority backs the candidate while bootstrap is still active.
        _voteForPm(CM1, PM_CANDIDATE);
        _voteForPm(CM2, PM_CANDIDATE);
        _voteForPm(CM3, PM_CANDIDATE);
        _voteForPm(CM4, PM_CANDIDATE);

        // Freeze the setup exactly as production genesis does.
        kernel.disableBootstrapAuthority();
        assertEq(kernel.bootstrapAuthority(), address(0));

        // The former bootstrap authority can no longer write the Executive registry directly, but the standing
        // CabinetApp authority remains the sole live writer.
        vm.expectRevert(
            abi.encodeWithSelector(IExecutiveRegistry.UnauthorizedExecutiveRegistryCaller.selector, address(this))
        );
        executiveRegistry.setPrimeMinister(
            PM_CANDIDATE, PID_PM, uint64(block.timestamp), uint64(block.timestamp) + 1, 4
        );

        cabinetApp.appointPrimeMinister(PM_CANDIDATE);
        assertEq(executiveRegistry.primeMinister(), PM_CANDIDATE);
        assertEq(executiveRegistry.primeMinisterAppointmentSupport(), 4);
        assertTrue(executiveRegistry.isPrimeMinisterInTerm());
    }

    function test_FinanceMinisterBecomesOfficeAdmin_OfficeActive() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);

        // The genesis bootstrap admin holds the finance office until a Finance Minister is appointed.
        assertEq(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).admin, FINANCE_GENESIS_ADMIN);
        assertTrue(officeRegistry.isOfficeAdmin(FINANCE_OFFICE_ID, FINANCE_GENESIS_ADMIN));

        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);

        // The elected Finance Minister now holds operational finance power, and the office is active.
        assertEq(uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, MIN_A)), uint256(OfficeTypes.OfficeRole.Admin));
        assertTrue(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).active);
        // The previous genesis admin is no longer admin.
        assertEq(
            uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, FINANCE_GENESIS_ADMIN)),
            uint256(OfficeTypes.OfficeRole.None)
        );
        assertEq(
            officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).adminAuthorizationEndsAt,
            executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Finance).termEnd
        );
    }

    function test_ExpiredMinisterImmediatelyLosesOfficeAuthorityBeforeRetirement() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        officeRegistry.setClerkStatus(FINANCE_OFFICE_ID, OUTSIDER, true);
        uint64 termEnd = executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Finance).termEnd;

        vm.warp(termEnd - 1);
        assertTrue(officeRegistry.isOfficeAdmin(FINANCE_OFFICE_ID, MIN_A));
        assertTrue(officeRegistry.isOfficeClerk(FINANCE_OFFICE_ID, OUTSIDER));

        vm.warp(termEnd);

        assertFalse(executiveRegistry.isMinisterInTerm(ExecutiveTypes.MinistryKind.Finance));
        assertEq(uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, MIN_A)), uint256(OfficeTypes.OfficeRole.None));
        assertEq(uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, OUTSIDER)), uint256(OfficeTypes.OfficeRole.None));
        assertFalse(officeRegistry.isOfficeAdmin(FINANCE_OFFICE_ID, MIN_A));
        assertFalse(officeRegistry.isOfficeClerk(FINANCE_OFFICE_ID, OUTSIDER));
        assertFalse(officeRegistry.getClerkRecord(FINANCE_OFFICE_ID, OUTSIDER).active);

        cabinetApp.retireExpiredMinister(ExecutiveTypes.MinistryKind.Finance);
        assertFalse(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).active);
    }

    function test_NewMinisterDoesNotInheritPriorMinistersClerks() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        officeRegistry.setClerkStatus(FINANCE_OFFICE_ID, OUTSIDER, true);
        assertTrue(officeRegistry.isOfficeClerk(FINANCE_OFFICE_ID, OUTSIDER));

        _voteDismiss(CM1, ExecutiveTypes.MinistryKind.Finance);
        _voteDismiss(CM2, ExecutiveTypes.MinistryKind.Finance);
        _voteDismiss(CM3, ExecutiveTypes.MinistryKind.Finance);
        _voteDismiss(CM4, ExecutiveTypes.MinistryKind.Finance);
        cabinetApp.dismissMinister(ExecutiveTypes.MinistryKind.Finance);
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_E);

        assertFalse(officeRegistry.isOfficeClerk(FINANCE_OFFICE_ID, OUTSIDER));
        assertFalse(officeRegistry.getClerkRecord(FINANCE_OFFICE_ID, OUTSIDER).active);
    }

    function test_MinisterWalletMigrationMovesOfficeAuthorityToActiveWallet() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);

        _setWalletLink(bytes32(uint256(111)), MIN_A, IdentityTypes.WalletLinkStatus.Revoked);
        _setWalletLink(bytes32(uint256(111)), MIN_A_NEW, IdentityTypes.WalletLinkStatus.Active);

        assertFalse(officeRegistry.isOfficeAdmin(FINANCE_OFFICE_ID, MIN_A));
        assertTrue(officeRegistry.isOfficeAdmin(FINANCE_OFFICE_ID, MIN_A_NEW));
        assertEq(identityRegistry.activeWalletOf(bytes32(uint256(111))), MIN_A_NEW);

        vm.prank(MIN_A_NEW);
        cabinetApp.resignMinister(ExecutiveTypes.MinistryKind.Finance);
        assertFalse(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).active);
    }

    function test_PrimeMinisterWalletMigrationPreservesPersonBoundAuthority() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);

        _setWalletLink(PID_PM, PM_CANDIDATE, IdentityTypes.WalletLinkStatus.Revoked);
        _setWalletLink(PID_PM, PM_NEW_WALLET, IdentityTypes.WalletLinkStatus.Active);

        vm.prank(PM_CANDIDATE);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.NotPrimeMinister.selector, PM_CANDIDATE));
        cabinetApp.appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);

        vm.prank(PM_NEW_WALLET);
        cabinetApp.appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Finance).minister, MIN_A);
    }

    function test_CongressAuthorityAndBallotFollowActiveWalletMigration() public {
        _setWalletLink(bytes32(uint256(1)), CM1, IdentityTypes.WalletLinkStatus.Revoked);
        _setWalletLink(bytes32(uint256(1)), CM1_NEW, IdentityTypes.WalletLinkStatus.Active);

        assertFalse(congressCandidateRegistry.isActiveCongressMember(CM1));
        assertTrue(congressCandidateRegistry.isActiveCongressMember(CM1_NEW));
        assertEq(congressCandidateRegistry.currentCongressMembers()[0], CM1_NEW);

        vm.prank(CM1);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.NotCongressMember.selector, CM1));
        cabinetApp.voteForPrimeMinister(PM_CANDIDATE);

        _voteForPm(CM1_NEW, PM_CANDIDATE);
        _voteForPm(CM2, PM_CANDIDATE);
        _voteForPm(CM3, PM_CANDIDATE);
        _voteForPm(CM4, PM_CANDIDATE);
        cabinetApp.appointPrimeMinister(PM_CANDIDATE);

        assertEq(executiveRegistry.getPrimeMinister().primeMinister, PM_CANDIDATE);
        assertEq(executiveRegistry.getPrimeMinister().appointmentSupport, 4);
    }

    function test_UnwiredMinistryAppointmentLeavesOfficesUntouched() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);

        // Interior has no mapped operational office (officeId 0), so its appointment touches no office.
        assertEq(cabinetApp.ministryOfficeId(ExecutiveTypes.MinistryKind.Interior), bytes32(0));
        address previousFinanceAdmin = officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).admin;

        // The unwired appointment must succeed without reverting and without disturbing the finance office.
        _appointMinister(ExecutiveTypes.MinistryKind.Interior, MIN_C);

        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Interior).minister, MIN_C);
        assertEq(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).admin, previousFinanceAdmin);
        assertTrue(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).active);
    }

    function test_DismissFinanceMinister_DeactivatesOffice_ReappointReactivates() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        assertTrue(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).active);

        // Congress dismisses the Finance Minister by strict majority of the seven seats.
        _voteDismiss(CM1, ExecutiveTypes.MinistryKind.Finance);
        _voteDismiss(CM2, ExecutiveTypes.MinistryKind.Finance);
        _voteDismiss(CM3, ExecutiveTypes.MinistryKind.Finance);
        _voteDismiss(CM4, ExecutiveTypes.MinistryKind.Finance);
        cabinetApp.dismissMinister(ExecutiveTypes.MinistryKind.Finance);

        // The office is deactivated: no operations run without a minister, so roleOf is None for everyone.
        assertFalse(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).active);
        assertEq(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).admin, address(0));
        assertEq(uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, MIN_A)), uint256(OfficeTypes.OfficeRole.None));
        assertEq(
            uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, FINANCE_GENESIS_ADMIN)),
            uint256(OfficeTypes.OfficeRole.None)
        );

        // Re-appointing a new Finance Minister reactivates the office with the new admin.
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_E);
        assertTrue(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).active);
        assertEq(uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, MIN_E)), uint256(OfficeTypes.OfficeRole.Admin));
        assertEq(uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, MIN_A)), uint256(OfficeTypes.OfficeRole.None));
    }

    function test_ResignFinanceMinister_DeactivatesOffice() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        assertTrue(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).active);

        // The Finance Minister resigns; the office is deactivated just like a dismissal.
        vm.prank(MIN_A);
        cabinetApp.resignMinister(ExecutiveTypes.MinistryKind.Finance);

        assertFalse(executiveRegistry.isMinisterInTerm(ExecutiveTypes.MinistryKind.Finance));
        assertFalse(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).active);
        assertEq(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).admin, address(0));
        assertEq(uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, MIN_A)), uint256(OfficeTypes.OfficeRole.None));
    }

    function test_OnlyCabinetAppPathMutatesOffice_UnauthorizedReverts() public {
        _appointPmWithVotes(PM_CANDIDATE, 4);

        // An unauthorized caller cannot transfer the office admin or flip its active flag directly.
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(IOfficeRegistry.UnauthorizedOfficeRegistryCaller.selector, OUTSIDER));
        officeRegistry.transferOfficeAdmin(FINANCE_OFFICE_ID, MIN_A);
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(IOfficeRegistry.UnauthorizedOfficeRegistryCaller.selector, OUTSIDER));
        officeRegistry.setOfficeActive(FINANCE_OFFICE_ID, false);

        // Only the CabinetApp path (a real minister appointment) mutates the office.
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        assertEq(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).admin, MIN_A);
        assertTrue(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).active);
    }

    function _seedCitizen(bytes32 personId, address wallet) internal {
        identityRegistry.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256(abi.encode("cabinet.citizen", personId)),
                metadataURI: "",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identityRegistry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        stakeRegistry.increaseStake(personId, CITIZEN_STAKE);
    }

    function _setWalletLink(bytes32 personId, address wallet, IdentityTypes.WalletLinkStatus status) internal {
        identityRegistry.setWalletLink(personId, wallet, status);
    }

    function _seedCongress(address[] memory members) internal returns (uint256 cycleId) {
        cycleId = congressCandidateRegistry.latestCycleId() + 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 seatCount = uint32(members.length);

        congressCandidateRegistry.createCycle(
            cycleId,
            ElectionTypes.CongressCycleInput({
                nominationStart: uint64(block.timestamp),
                votingStart: uint64(block.timestamp + 1),
                votingEnd: uint64(block.timestamp + 2),
                votingPowerSnapshotBlock: uint48(block.number),
                seatCount: seatCount,
                runnerUpCount: 1,
                maxCandidateCount: seatCount + 1,
                policy: address(cabinetApp),
                policyReference: keccak256("cabinet.test.congress")
            })
        );

        int256[] memory rankedVoteTotals = new int256[](members.length);
        for (uint256 index = 0; index < members.length; ++index) {
            bytes32 personId = identityRegistry.resolveWalletToPersonId(members[index]);
            congressCandidateRegistry.registerCandidate(
                cycleId,
                members[index],
                personId,
                keccak256(abi.encode("cabinet.candidate", cycleId, members[index])),
                ""
            );
        }

        congressCandidateRegistry.finalizeCycle(
            cycleId,
            ElectionTypes.CongressFinalizationInput({
                rankedCandidates: members, rankedVoteTotals: rankedVoteTotals, electedCount: seatCount, runnerUpCount: 0
            })
        );
    }

    function _firstMembers(uint256 count) internal pure returns (address[] memory members) {
        address[9] memory all = [CM1, CM2, CM3, CM4, CM5, CM6, CM7, CM8, CM9];
        members = new address[](count);
        for (uint256 index = 0; index < count; ++index) {
            members[index] = all[index];
        }
    }

    function _appointPmWithVotes(address candidate, uint256 voteCount) internal {
        address[] memory voters = _firstMembers(voteCount);
        for (uint256 index = 0; index < voters.length; ++index) {
            _voteForPm(voters[index], candidate);
        }
        cabinetApp.appointPrimeMinister(candidate);
    }

    function _voteForPm(address voter, address candidate) internal {
        vm.prank(voter);
        cabinetApp.voteForPrimeMinister(candidate);
    }

    function _voteRemove(address voter) internal {
        vm.prank(voter);
        cabinetApp.voteToRemovePrimeMinister();
    }

    function _voteDismiss(address voter, ExecutiveTypes.MinistryKind ministry) internal {
        vm.prank(voter);
        cabinetApp.voteToDismissMinister(ministry);
    }

    function _appointMinister(ExecutiveTypes.MinistryKind ministry, address minister) internal {
        vm.prank(PM_CANDIDATE);
        cabinetApp.appointMinister(ministry, minister);
    }
}
