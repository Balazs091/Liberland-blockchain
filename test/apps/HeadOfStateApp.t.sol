// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {HeadOfStateApp} from "../../contracts/apps/HeadOfStateApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IHeadOfStateApp} from "../../contracts/interfaces/IHeadOfStateApp.sol";
import {IPresidentRegistry} from "../../contracts/interfaces/IPresidentRegistry.sol";
import {ISenateSeatRegistry} from "../../contracts/interfaces/ISenateSeatRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {PresidentRegistry} from "../../contracts/registries/PresidentRegistry.sol";
import {SenateSeatRegistry} from "../../contracts/registries/SenateSeatRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

/// @title HeadOfStateAppTest
/// @notice Covers the Senate-elected Head of State: seat-based majority election, occupancy-nonce ballot binding,
///         term expiry by passage of time, Vice President appointment constraints, resignation succession, and the
///         standing authority that keeps elections runnable after genesis bootstrap is disabled.
contract HeadOfStateAppTest is Test {
    uint64 internal constant PRESIDENT_TERM = 1825 days;

    address internal constant SENATOR_ONE = address(0x5E1);
    address internal constant SENATOR_TWO = address(0x5E2);
    address internal constant SENATOR_THREE = address(0x5E3);
    address internal constant SENATOR_FOUR = address(0x5E4);
    address internal constant SENATOR_FIVE = address(0x5E5);
    address internal constant SENATOR_SIX = address(0x5E6);
    address internal constant OUTSIDER = address(0x0175);
    address internal constant SENATOR_ONE_NEW = address(0x5E7);

    bytes32 internal constant PID_ONE = bytes32(uint256(1));
    bytes32 internal constant PID_TWO = bytes32(uint256(2));
    bytes32 internal constant PID_THREE = bytes32(uint256(3));
    bytes32 internal constant PID_FOUR = bytes32(uint256(4));
    bytes32 internal constant PID_FIVE = bytes32(uint256(5));
    bytes32 internal constant PID_SIX = bytes32(uint256(6));

    ConstitutionKernel internal kernel;
    PresidentRegistry internal presidentRegistry;
    SenateSeatRegistry internal senateSeatRegistry;
    IdentityRegistry internal identityRegistry;
    HeadOfStateApp internal headOfStateApp;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        presidentRegistry = new PresidentRegistry(address(kernel));
        senateSeatRegistry = new SenateSeatRegistry(address(kernel));
        identityRegistry = new IdentityRegistry(address(kernel));
        headOfStateApp = new HeadOfStateApp(address(presidentRegistry), address(senateSeatRegistry));

        kernel.bootstrapSetModule(KernelModuleIds.PRESIDENT_REGISTRY, address(presidentRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY, address(senateSeatRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.HEAD_OF_STATE_APP, address(headOfStateApp));
        kernel.bootstrapSetModule(KernelModuleIds.PRESIDENT_REGISTRY_AUTHORITY, address(headOfStateApp));
        // This test acts as the Senate-seat authority so it can seat, transfer, and vacate Senators directly.
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY, address(this));

        _registerCitizen(PID_ONE, SENATOR_ONE);
        _registerCitizen(PID_TWO, SENATOR_TWO);
        _registerCitizen(PID_THREE, SENATOR_THREE);
        _registerCitizen(PID_FOUR, SENATOR_FOUR);
        _registerCitizen(PID_FIVE, SENATOR_FIVE);
        _registerCitizen(PID_SIX, SENATOR_SIX);

        _assignSeat(0, SENATOR_ONE, PID_ONE);
        _assignSeat(1, SENATOR_TWO, PID_TWO);
        _assignSeat(2, SENATOR_THREE, PID_THREE);
        _assignSeat(3, SENATOR_FOUR, PID_FOUR);
        _assignSeat(4, SENATOR_FIVE, PID_FIVE);

        assertEq(senateSeatRegistry.occupiedSeatCount(), 5);
    }

    function test_HeadOfStateInterfacesExposeSelectors() public pure {
        assertTrue(IHeadOfStateApp.voteForPresident.selector != bytes4(0));
        assertTrue(IHeadOfStateApp.electPresident.selector != bytes4(0));
        assertTrue(IHeadOfStateApp.appointVicePresident.selector != bytes4(0));
        assertTrue(IHeadOfStateApp.resignPresident.selector != bytes4(0));
        assertTrue(IPresidentRegistry.isPresidentInTerm.selector != bytes4(0));
        assertTrue(IPresidentRegistry.vacatePresident.selector != bytes4(0));
    }

    function test_WiringAndConstantsAreExposed() public view {
        assertEq(headOfStateApp.presidentRegistry(), address(presidentRegistry));
        assertEq(headOfStateApp.senateSeatRegistry(), address(senateSeatRegistry));
        assertEq(headOfStateApp.kernel(), address(kernel));
        assertEq(headOfStateApp.presidentTerm(), PRESIDENT_TERM);
        assertEq(headOfStateApp.presidentTerm(), 5 * 365 days);
        assertEq(headOfStateApp.currentElectionCycle(), 1);
        assertEq(senateSeatRegistry.activeSeatHolderPersonId(SENATOR_ONE), PID_ONE);
    }

    function test_SeatHolderReverseLookupTracksTransfersAndRejectsIdentityMismatch() public {
        senateSeatRegistry.transferSeat(0, SENATOR_SIX, PID_SIX);
        assertEq(senateSeatRegistry.activeSeatHolderPersonId(SENATOR_ONE), bytes32(0));
        assertEq(senateSeatRegistry.activeSeatHolderPersonId(SENATOR_SIX), PID_SIX);

        vm.expectRevert(
            abi.encodeWithSelector(ISenateSeatRegistry.SeatHolderPersonMismatch.selector, SENATOR_SIX, PID_SIX, PID_TWO)
        );
        senateSeatRegistry.assignSeat(5, SENATOR_SIX, PID_TWO, false);
    }

    function test_SenateElectsPresident_FailsBelowMajoritySucceedsAtMajority() public {
        _vote(0, SENATOR_ONE, SENATOR_ONE);
        _vote(1, SENATOR_TWO, SENATOR_ONE);

        // Two of five occupied seats is not a strict majority (2 * 2 = 4 <= 5).
        assertEq(headOfStateApp.voteCountFor(SENATOR_ONE), 2);
        assertFalse(headOfStateApp.canElectPresident(SENATOR_ONE));
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.ElectionMajorityNotReached.selector, SENATOR_ONE, 2, 5));
        headOfStateApp.electPresident(SENATOR_ONE);

        _vote(2, SENATOR_THREE, SENATOR_ONE);
        assertEq(headOfStateApp.voteCountFor(SENATOR_ONE), 3);
        assertTrue(headOfStateApp.canElectPresident(SENATOR_ONE));

        uint64 expectedStart = uint64(block.timestamp);
        vm.expectEmit(true, true, false, true, address(headOfStateApp));
        emit IHeadOfStateApp.PresidentElected(
            SENATOR_ONE, PID_ONE, 3, 5, expectedStart, expectedStart + PRESIDENT_TERM, expectedStart
        );
        headOfStateApp.electPresident(SENATOR_ONE);

        assertEq(presidentRegistry.currentPresident(), SENATOR_ONE);
        assertEq(presidentRegistry.currentPresidentPersonId(), PID_ONE);
        assertEq(presidentRegistry.termStart(), expectedStart);
        assertEq(presidentRegistry.termEnd(), expectedStart + PRESIDENT_TERM);
        assertTrue(presidentRegistry.isPresidentInTerm());
        // A successful election voids all ballots for the next cycle.
        assertEq(headOfStateApp.currentElectionCycle(), 2);
    }

    function test_CannotPreloadBallotsWhilePresidentInTerm_ReelectsAfterTermEnds() public {
        _electPresident(SENATOR_ONE);
        uint64 termEnd = presidentRegistry.termEnd();

        // A future election cannot be decided years early while the sitting President remains in term.
        vm.prank(SENATOR_ONE);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.PresidentAlreadyInTerm.selector, SENATOR_ONE));
        headOfStateApp.voteForPresident(0, SENATOR_TWO);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.PresidentAlreadyInTerm.selector, SENATOR_ONE));
        headOfStateApp.electPresident(SENATOR_TWO);

        // The term ends purely by passage of time; a fresh majority can then elect the challenger.
        vm.warp(termEnd);
        assertFalse(presidentRegistry.isPresidentInTerm());
        _vote(0, SENATOR_ONE, SENATOR_TWO);
        _vote(1, SENATOR_TWO, SENATOR_TWO);
        _vote(2, SENATOR_THREE, SENATOR_TWO);
        assertTrue(headOfStateApp.canElectPresident(SENATOR_TWO));
        headOfStateApp.electPresident(SENATOR_TWO);

        assertEq(presidentRegistry.currentPresident(), SENATOR_TWO);
        assertEq(presidentRegistry.termEnd(), termEnd + PRESIDENT_TERM);
    }

    function test_NonSeatHolderCandidateRejected() public {
        vm.prank(SENATOR_ONE);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.CandidateNotSeatHolder.selector, OUTSIDER));
        headOfStateApp.voteForPresident(0, OUTSIDER);

        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.CandidateNotSeatHolder.selector, OUTSIDER));
        headOfStateApp.electPresident(OUTSIDER);
    }

    function test_NonSeatHolderCallerCannotVoteSeat() public {
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.NotSeatHolder.selector, uint32(0), OUTSIDER));
        headOfStateApp.voteForPresident(0, SENATOR_ONE);

        // A Senator may only vote the seat they actually hold.
        vm.prank(SENATOR_TWO);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.NotSeatHolder.selector, uint32(0), SENATOR_TWO));
        headOfStateApp.voteForPresident(0, SENATOR_ONE);
    }

    function test_StaleVoteAfterSeatTransferDoesNotCount() public {
        _vote(0, SENATOR_ONE, SENATOR_FIVE);
        _vote(1, SENATOR_TWO, SENATOR_FIVE);
        _vote(2, SENATOR_THREE, SENATOR_FIVE);
        assertEq(headOfStateApp.voteCountFor(SENATOR_FIVE), 3);
        assertTrue(headOfStateApp.canElectPresident(SENATOR_FIVE));

        // Transferring seat 0 bumps its occupancy nonce, so the stale ballot bound to the old nonce no longer counts.
        senateSeatRegistry.transferSeat(0, SENATOR_SIX, PID_SIX);
        assertEq(headOfStateApp.voteCountFor(SENATOR_FIVE), 2);
        assertFalse(headOfStateApp.canElectPresident(SENATOR_FIVE));
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.ElectionMajorityNotReached.selector, SENATOR_FIVE, 2, 5));
        headOfStateApp.electPresident(SENATOR_FIVE);

        // The new seat holder re-votes with the current nonce, restoring the majority.
        _vote(0, SENATOR_SIX, SENATOR_FIVE);
        assertEq(headOfStateApp.voteCountFor(SENATOR_FIVE), 3);
        headOfStateApp.electPresident(SENATOR_FIVE);
        assertEq(presidentRegistry.currentPresident(), SENATOR_FIVE);
    }

    function test_ReVoteReplacesPriorChoice() public {
        _vote(0, SENATOR_ONE, SENATOR_ONE);
        assertEq(headOfStateApp.voteCountFor(SENATOR_ONE), 1);

        _vote(0, SENATOR_ONE, SENATOR_TWO);
        assertEq(headOfStateApp.voteCountFor(SENATOR_ONE), 0);
        assertEq(headOfStateApp.voteCountFor(SENATOR_TWO), 1);
    }

    function test_PresidentAppointsTwoVicePresidents_Constraints() public {
        _electPresident(SENATOR_ONE);

        vm.prank(SENATOR_ONE);
        headOfStateApp.appointVicePresident(0, SENATOR_TWO, PID_TWO);
        vm.prank(SENATOR_ONE);
        headOfStateApp.appointVicePresident(1, SENATOR_THREE, PID_THREE);

        assertEq(presidentRegistry.vicePresident(0), SENATOR_TWO);
        assertEq(presidentRegistry.vicePresidentPersonId(0), PID_TWO);
        assertEq(presidentRegistry.vicePresident(1), SENATOR_THREE);
        assertEq(presidentRegistry.vicePresidentPersonId(1), PID_THREE);

        // Only the sitting President may appoint.
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.NotPresident.selector, OUTSIDER));
        headOfStateApp.appointVicePresident(0, SENATOR_FOUR, PID_FOUR);

        vm.prank(SENATOR_TWO);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.NotPresident.selector, SENATOR_TWO));
        headOfStateApp.appointVicePresident(0, SENATOR_FOUR, PID_FOUR);

        // A Vice President may not be the President nor the other Vice President.
        vm.prank(SENATOR_ONE);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.InvalidVicePresidentCandidate.selector, SENATOR_ONE));
        headOfStateApp.appointVicePresident(0, SENATOR_ONE, PID_ONE);

        vm.prank(SENATOR_ONE);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.InvalidVicePresidentCandidate.selector, SENATOR_THREE));
        headOfStateApp.appointVicePresident(0, SENATOR_THREE, PID_THREE);

        // A Vice President must be a sitting Senator, and the supplied person id must match the seat record.
        vm.prank(SENATOR_ONE);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.VicePresidentNotSeatHolder.selector, OUTSIDER));
        headOfStateApp.appointVicePresident(0, OUTSIDER, bytes32(uint256(99)));

        vm.prank(SENATOR_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHeadOfStateApp.VicePresidentPersonIdMismatch.selector, SENATOR_FOUR, bytes32(uint256(0xBAD)), PID_FOUR
            )
        );
        headOfStateApp.appointVicePresident(0, SENATOR_FOUR, bytes32(uint256(0xBAD)));
    }

    function test_AppointVicePresidentRevertsAfterTermEnds() public {
        _electPresident(SENATOR_ONE);
        vm.warp(presidentRegistry.termEnd());

        vm.prank(SENATOR_ONE);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.NotPresident.selector, SENATOR_ONE));
        headOfStateApp.appointVicePresident(0, SENATOR_TWO, PID_TWO);
    }

    function test_ResignSuccession_FirstVicePresidentAssumesRemainderOfTerm() public {
        _electPresident(SENATOR_ONE);
        uint64 termStart = presidentRegistry.termStart();
        uint64 termEnd = presidentRegistry.termEnd();

        vm.prank(SENATOR_ONE);
        headOfStateApp.appointVicePresident(0, SENATOR_TWO, PID_TWO);
        vm.prank(SENATOR_ONE);
        headOfStateApp.appointVicePresident(1, SENATOR_THREE, PID_THREE);

        // Resign partway through the term; the first-sworn VP succeeds for the SAME (remaining) term.
        vm.warp(termStart + 100 days);
        vm.prank(SENATOR_ONE);
        headOfStateApp.resignPresident();

        assertEq(presidentRegistry.currentPresident(), SENATOR_TWO);
        assertEq(presidentRegistry.currentPresidentPersonId(), PID_TWO);
        assertEq(presidentRegistry.termStart(), termStart);
        assertEq(presidentRegistry.termEnd(), termEnd);
        assertTrue(presidentRegistry.isPresidentInTerm());
        // Both VP slots are cleared so the successor appoints fresh Vice Presidents.
        assertEq(presidentRegistry.vicePresident(0), address(0));
        assertEq(presidentRegistry.vicePresident(1), address(0));

        vm.prank(SENATOR_TWO);
        headOfStateApp.appointVicePresident(0, SENATOR_THREE, PID_THREE);
        assertEq(presidentRegistry.vicePresident(0), SENATOR_THREE);
    }

    function test_ResignVacancy_NoVicePresidentLeavesOfficeVacantThenReelect() public {
        _electPresident(SENATOR_ONE);

        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.NotPresident.selector, OUTSIDER));
        headOfStateApp.resignPresident();

        vm.prank(SENATOR_ONE);
        headOfStateApp.resignPresident();

        assertEq(presidentRegistry.currentPresident(), address(0));
        assertEq(presidentRegistry.termEnd(), 0);
        assertFalse(presidentRegistry.isPresidentInTerm());

        // A fresh election runs immediately into the vacant office.
        _vote(0, SENATOR_ONE, SENATOR_TWO);
        _vote(1, SENATOR_TWO, SENATOR_TWO);
        _vote(2, SENATOR_THREE, SENATOR_TWO);
        headOfStateApp.electPresident(SENATOR_TWO);
        assertEq(presidentRegistry.currentPresident(), SENATOR_TWO);
    }

    function test_PostGenesisBootstrapDisabled_ElectionStillRuns() public {
        // Genesis path: the bootstrap authority (this test) seeds an initial President with a term.
        uint64 genesisStart = uint64(block.timestamp);
        presidentRegistry.setPresident(
            SENATOR_ONE, PID_ONE, keccak256("genesis-mandate"), genesisStart, genesisStart + PRESIDENT_TERM
        );
        assertEq(presidentRegistry.currentPresident(), SENATOR_ONE);

        // Freeze the setup: disable the kernel bootstrap authority, exactly as production genesis does.
        kernel.disableBootstrapAuthority();
        assertEq(kernel.bootstrapAuthority(), address(0));

        // The former bootstrap authority can no longer write the President registry directly,
        // but the standing HeadOfStateApp authority remains the sole live writer.
        vm.expectRevert(
            abi.encodeWithSelector(IPresidentRegistry.UnauthorizedPresidentRegistryCaller.selector, address(this))
        );
        presidentRegistry.setPresident(
            SENATOR_TWO, PID_TWO, keccak256("x"), genesisStart, genesisStart + PRESIDENT_TERM
        );

        // The genesis term ends by passage of time; the Senate then elects a successor through the standing authority.
        vm.warp(genesisStart + PRESIDENT_TERM);
        _vote(0, SENATOR_ONE, SENATOR_TWO);
        _vote(1, SENATOR_TWO, SENATOR_TWO);
        _vote(2, SENATOR_THREE, SENATOR_TWO);
        headOfStateApp.electPresident(SENATOR_TWO);

        assertEq(presidentRegistry.currentPresident(), SENATOR_TWO);
        assertTrue(presidentRegistry.isPresidentInTerm());
    }

    function test_SenatorAndPresidentAuthorityFollowActiveWalletMigration() public {
        _electPresident(SENATOR_ONE);

        identityRegistry.setWalletLink(PID_ONE, SENATOR_ONE, IdentityTypes.WalletLinkStatus.Revoked);
        identityRegistry.setWalletLink(PID_ONE, SENATOR_ONE_NEW, IdentityTypes.WalletLinkStatus.Active);

        vm.prank(SENATOR_ONE);
        vm.expectRevert(abi.encodeWithSelector(IHeadOfStateApp.NotPresident.selector, SENATOR_ONE));
        headOfStateApp.appointVicePresident(0, SENATOR_TWO, PID_TWO);

        vm.prank(SENATOR_ONE_NEW);
        headOfStateApp.appointVicePresident(0, SENATOR_TWO, PID_TWO);
        assertEq(presidentRegistry.vicePresident(0), SENATOR_TWO);

        vm.prank(SENATOR_ONE_NEW);
        headOfStateApp.resignPresident();
        assertEq(presidentRegistry.currentPresident(), SENATOR_TWO);
    }

    function _assignSeat(uint32 seatIndex, address holder, bytes32 personId) internal {
        senateSeatRegistry.assignSeat(seatIndex, holder, personId, false);
    }

    function _registerCitizen(bytes32 personId, address wallet) internal {
        identityRegistry.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256(abi.encode("senator", personId)),
                metadataURI: "",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identityRegistry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
    }

    function _vote(uint32 seatIndex, address holder, address candidate) internal {
        vm.prank(holder);
        headOfStateApp.voteForPresident(seatIndex, candidate);
    }

    function _electPresident(address candidate) internal {
        _vote(0, SENATOR_ONE, candidate);
        _vote(1, SENATOR_TWO, candidate);
        _vote(2, SENATOR_THREE, candidate);
        headOfStateApp.electPresident(candidate);
    }
}
