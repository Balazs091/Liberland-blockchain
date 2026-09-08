// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IdentityApp} from "../../contracts/apps/IdentityApp.sol";
import {CivicAppealReview} from "../../contracts/apps/CivicAppealReview.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

/// @notice Multi-person state-machine driver. Ghost consent and ruling records are independent of app storage.
contract IdentityLifecycleHandler is Test {
    IdentityApp public immutable app;
    CivicAppealReview public immutable review;
    IdentityRegistry public immutable identities;
    OfficeRegistry public immutable offices;
    address public immutable fixtureAuthority;
    address public constant ADMIN = address(0xA100);
    address public constant CLERK = address(0xA101);
    bytes32 public constant OFFICE = keccak256("identity.lifecycle.office");
    bool public unexpectedBehavior;
    bool public consentOrRulingBypassed;
    uint256 public migrationsCompleted;
    uint256 public civicChangesCompleted;
    mapping(bytes32 request => bool) public seenRequests;
    mapping(bytes32 request => bool) public consent;
    mapping(bytes32 request => bool) public upheld;
    mapping(bytes32 person => bytes32 request) public priorMigration;

    constructor(
        IdentityApp app_,
        CivicAppealReview review_,
        IdentityRegistry identities_,
        OfficeRegistry offices_,
        address authority_
    ) {
        app = app_;
        review = review_;
        identities = identities_;
        offices = offices_;
        fixtureAuthority = authority_;
    }

    /// @notice Starts either an ordinary wallet migration or an admin-proposed exceptional recovery.
    function proposeMigration(uint8 personSeed, uint8 destinationSeed, bool recovery) external {
        bytes32 person = _person(personSeed);
        if (app.getWalletMigration(person).exists) return;
        address old = identities.activeWalletOf(person);
        address next = address(uint160(0xB000 + uint256(person) * 16 + destinationSeed % 3));
        if (next == old) return;
        vm.prank(recovery ? ADMIN : old);
        if (recovery) app.proposeWalletRecovery(person, next, keccak256("recovery evidence"));
        else app.requestWalletMigration(next);
        bytes32 id = app.walletMigrationId(person);
        if (id == bytes32(0) || seenRequests[id]) unexpectedBehavior = true;
        seenRequests[id] = true;
    }

    /// @notice Destination consent is exact-request-bound; sometimes attempts a canceled request's stale ID.
    function acceptMigration(uint8 personSeed, bool stale) external {
        bytes32 person = _person(personSeed);
        IdentityTypes.MigrationRequest memory m = app.getWalletMigration(person);
        if (!m.exists) return;
        bytes32 id = app.walletMigrationId(person);
        bytes32 supplied = stale ? priorMigration[person] : id;
        vm.prank(m.newWallet);
        try app.acceptWalletMigration(person, supplied) {
            if (supplied != id) unexpectedBehavior = true;
            consent[id] = true;
        } catch {
            if (supplied == id) unexpectedBehavior = true;
        }
    }

    /// @notice Exercises approval before/after consent, revoked appointments and recovery separation of duties.
    function approveMigration(uint8 personSeed, bool useAdmin, bool stale) external {
        bytes32 person = _person(personSeed);
        IdentityTypes.MigrationRequest memory m = app.getWalletMigration(person);
        if (!m.exists) return;
        address officer = useAdmin ? ADMIN : CLERK;
        bytes32 id = app.walletMigrationId(person);
        bytes32 supplied = stale ? priorMigration[person] : id;
        bool expected = supplied == id && !m.approved && consent[id]
            && offices.authorizationId(OFFICE, officer) != bytes32(0)
            && (!m.recovery || (officer != m.proposer && _authorized(m.proposer, m.proposerAuthorizationId)));
        vm.prank(officer);
        try app.approveWalletMigration(person, supplied) {
            if (!expected) unexpectedBehavior = true;
        } catch {
            if (expected) unexpectedBehavior = true;
        }
    }

    /// @notice Tries finalization on either side of the notice boundary and after appointment churn.
    function finalizeMigration(uint8 personSeed) external {
        bytes32 person = _person(personSeed);
        IdentityTypes.MigrationRequest memory m = app.getWalletMigration(person);
        if (!m.exists) return;
        bytes32 id = app.walletMigrationId(person);
        bool expected = m.approved && consent[id]
            && block.timestamp >= uint256(m.approvedAt) + (m.recovery ? 7 days : 2 days)
            && _authorized(m.approver, m.approverAuthorizationId)
            && (!m.recovery || _authorized(m.proposer, m.proposerAuthorizationId));
        try app.finalizeWalletMigration(person) {
            if (!expected || !consent[id]) consentOrRulingBypassed = true;
            if (identities.activeWalletOf(person) != m.newWallet) unexpectedBehavior = true;
            priorMigration[person] = id;
            ++migrationsCompleted;
        } catch {
            if (expected) unexpectedBehavior = true;
        }
    }

    /// @notice Cancels a request from its old wallet, retaining the stale ID for replay probes.
    function cancelMigration(uint8 personSeed) external {
        bytes32 person = _person(personSeed);
        IdentityTypes.MigrationRequest memory m = app.getWalletMigration(person);
        if (!m.exists) return;
        priorMigration[person] = app.walletMigrationId(person);
        vm.prank(m.oldWallet);
        app.cancelWalletMigration(person);
    }

    /// @notice Starts a documented suspension or restoration without directly writing registry civic state.
    function proposeCivic(uint8 personSeed, bool suspend) external {
        bytes32 person = _person(personSeed);
        if (app.getCivicChange(person).requestId != bytes32(0)) return;
        vm.prank(ADMIN);
        bytes32 id = app.proposeCivicChange(
            person,
            IdentityTypes.CivicStatusInput({
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: suspend
                    ? IdentityTypes.CitizenshipStatus.Suspended
                    : IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: suspend
            }),
            keccak256("civic evidence")
        );
        if (seenRequests[id] || id == bytes32(0)) unexpectedBehavior = true;
        seenRequests[id] = true;
    }

    /// @notice A second officer approves a civic proposal under the current appointment.
    function approveCivic(uint8 personSeed) external {
        bytes32 person = _person(personSeed);
        IdentityTypes.CivicChangeRequest memory r = app.getCivicChange(person);
        if (r.requestId == bytes32(0)) return;
        bool expected = r.approver == address(0) && _authorized(r.proposer, r.proposerAuthorizationId)
            && offices.authorizationId(OFFICE, CLERK) != bytes32(0);
        vm.prank(CLERK);
        try app.approveCivicChange(person, r.requestId) {
            if (!expected) unexpectedBehavior = true;
        } catch {
            if (expected) unexpectedBehavior = true;
        }
    }

    /// @notice The current subject wallet attempts its one appeal, including before approval and after deadlines.
    function appeal(uint8 personSeed) external {
        bytes32 person = _person(personSeed);
        IdentityTypes.CivicChangeRequest memory r = app.getCivicChange(person);
        if (r.requestId == bytes32(0)) return;
        bool expected = r.approver != address(0) && block.timestamp < r.readyAt && r.appealEvidenceHash == bytes32(0);
        vm.prank(identities.activeWalletOf(person));
        try app.appealCivicChange(person, r.requestId, keccak256("subject appeal")) {
            if (!expected) unexpectedBehavior = true;
        } catch {
            if (expected) unexpectedBehavior = true;
        }
    }

    /// @notice Drives distinct review accounts with either insufficient support or a complete exact-case quorum.
    function rule(uint8 personSeed, bool uphold, bool quorum) external {
        bytes32 person = _person(personSeed);
        IdentityTypes.CivicChangeRequest memory r = app.getCivicChange(person);
        if (
            r.requestId == bytes32(0) || r.appealEvidenceHash == bytes32(0) || r.appealResolved
                || block.timestamp >= r.appealDeadline
        ) return;
        bytes32 evidence = keccak256(abi.encode("reasoned outcome", r.requestId, uphold));
        for (uint256 i; i < (quorum ? 3 : 1); ++i) {
            vm.prank(review.reviewerAt(i));
            review.castRulingVote(person, r.requestId, uphold, evidence, true);
        }
        // A previous sufficient vote set would already have resolved the case, so the one-vote branch cannot pass.
        try review.executeRuling(person, r.requestId, uphold, evidence) {
            if (!quorum) consentOrRulingBypassed = true;
            upheld[r.requestId] = uphold;
            if (uphold && app.getCivicChange(person).readyAt < block.timestamp + 2 days) unexpectedBehavior = true;
        } catch {
            if (quorum) unexpectedBehavior = true;
        }
    }

    /// @notice Civic execution must have fresh officers, elapsed delay and a binding ruling if appealed.
    function finalizeCivic(uint8 personSeed) external {
        bytes32 person = _person(personSeed);
        IdentityTypes.CivicChangeRequest memory r = app.getCivicChange(person);
        if (r.requestId == bytes32(0)) return;
        bool expected = r.approver != address(0) && block.timestamp >= r.readyAt
            && _authorized(r.proposer, r.proposerAuthorizationId) && _authorized(r.approver, r.approverAuthorizationId)
            && (r.appealEvidenceHash == bytes32(0) || upheld[r.requestId]);
        try app.finalizeCivicChange(person, r.requestId) {
            if (!expected) consentOrRulingBypassed = true;
            IdentityTypes.IdentityRecord memory result = identities.getIdentityRecord(person);
            if (
                result.finalSuspension != r.proposed.finalSuspension
                    || result.citizenshipStatus != r.proposed.citizenshipStatus
            ) unexpectedBehavior = true;
            ++civicChangesCompleted;
        } catch {
            if (expected) unexpectedBehavior = true;
        }
    }

    /// @notice Dismisses unanswered appeals, including probes before their timeout.
    function expireAppeal(uint8 personSeed) external {
        bytes32 person = _person(personSeed);
        IdentityTypes.CivicChangeRequest memory r = app.getCivicChange(person);
        if (r.requestId == bytes32(0)) return;
        bool expected = r.appealEvidenceHash != bytes32(0) && !r.appealResolved && block.timestamp >= r.appealDeadline;
        try app.expireCivicAppeal(person, r.requestId) {
            if (!expected) unexpectedBehavior = true;
        } catch {
            if (expected) unexpectedBehavior = true;
        }
    }

    /// @notice Permits independent officer withdrawal so fresh requests can follow revoked approvals.
    function withdrawCivic(uint8 personSeed) external {
        bytes32 person = _person(personSeed);
        bytes32 id = app.getCivicChange(person).requestId;
        if (id == bytes32(0)) return;
        vm.prank(ADMIN);
        app.cancelCivicChange(person, id);
    }

    /// @notice Repeated same-block reappointments must not revive prior consent-to-appointment bindings.
    function changeOfficer(bool active) external {
        vm.prank(fixtureAuthority);
        offices.setClerkStatus(OFFICE, CLERK, active);
    }

    /// @notice Advances notice, recovery and appeal clocks across exact execution boundaries.
    function advanceTime(uint32 rawSeconds) external {
        vm.warp(block.timestamp + bound(uint256(rawSeconds), 1, 9 days));
        vm.roll(block.number + 1);
    }

    function _authorized(address officer, bytes32 id) private view returns (bool) {
        return id != bytes32(0) && offices.authorizationId(OFFICE, officer) == id;
    }

    function _person(uint8 seed) private pure returns (bytes32) {
        return bytes32(uint256(seed % 3) + 1);
    }
}

contract IdentityLifecycleInvariantTest is Test {
    IdentityLifecycleHandler internal handler;
    IdentityRegistry internal identities;
    StakeRegistry internal stakes;

    function setUp() public {
        ConstitutionKernel kernel = new ConstitutionKernel(address(this));
        identities = new IdentityRegistry(address(kernel));
        OfficeRegistry offices = new OfficeRegistry(address(kernel));
        stakes = new StakeRegistry(address(kernel));
        bytes32 office = keccak256("identity.lifecycle.office");
        IdentityApp app = new IdentityApp(address(identities), address(offices), office, 2 days);
        CivicAppealReview review = new CivicAppealReview(
            address(app), [address(0xA001), address(0xA002), address(0xA003), address(0xA004), address(0xA005)]
        );
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identities));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(app));
        kernel.bootstrapSetModule(KernelModuleIds.CIVIC_APPEAL_AUTHORITY, address(review));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY, address(offices));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(this));
        kernel.disableBootstrapAuthority();
        offices.registerOffice(office, OfficeTypes.OfficeKind.IdentityOffice, "Identity", address(0xA100));
        offices.setClerkStatus(office, address(0xA101), true);
        for (uint256 i = 1; i <= 3; ++i) {
            bytes32 person = bytes32(i);
            address wallet = address(uint160(0xB000 + i * 16));
            vm.startPrank(address(0xA100));
            app.registerIdentity(
                person,
                IdentityTypes.IdentityRecordInput({
                    metadataHash: keccak256(abi.encode(i)),
                    metadataURI: "ipfs://invariant",
                    verificationStatus: IdentityTypes.VerificationStatus.Verified,
                    citizenshipStatus: IdentityTypes.CitizenshipStatus.None,
                    ageClass: IdentityTypes.AgeClass.Adult,
                    correctionFlag: false,
                    finalSuspension: false
                })
            );
            app.linkWallet(person, wallet, IdentityTypes.WalletLinkStatus.Active);
            app.setCitizenship(person, IdentityTypes.CitizenshipStatus.Citizen);
            vm.stopPrank();
            vm.prank(wallet);
            app.acceptInitialWallet(person);
            stakes.increaseStake(person, 10_000);
        }
        handler = new IdentityLifecycleHandler(app, review, identities, offices, address(this));
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = handler.proposeMigration.selector;
        selectors[1] = handler.acceptMigration.selector;
        selectors[2] = handler.approveMigration.selector;
        selectors[3] = handler.finalizeMigration.selector;
        selectors[4] = handler.cancelMigration.selector;
        selectors[5] = handler.proposeCivic.selector;
        selectors[6] = handler.approveCivic.selector;
        selectors[7] = handler.appeal.selector;
        selectors[8] = handler.rule.selector;
        selectors[9] = handler.finalizeCivic.selector;
        selectors[10] = handler.expireAppeal.selector;
        selectors[11] = handler.withdrawCivic.selector;
        selectors[12] = handler.changeOfficer.selector;
        selectors[13] = handler.advanceTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_ConsentRulingsAndAppointmentNoncesCannotBeBypassed() public view {
        assertFalse(handler.consentOrRulingBypassed());
        assertFalse(handler.unexpectedBehavior());
    }

    function invariant_OneActiveWalletAndPersonKeyedStakeSurviveAllTransitions() public view {
        for (uint256 i = 1; i <= 3; ++i) {
            assertEq(identities.activeWalletCountOf(bytes32(i)), 1);
            assertTrue(identities.hasActiveWalletLink(identities.activeWalletOf(bytes32(i))));
            assertEq(stakes.activeStakeOf(bytes32(i)), 10_000);
        }
    }

    function test_StatefulDriverCanCompleteConsentAndBindingAppealPaths() public {
        handler.proposeMigration(0, 1, true);
        handler.acceptMigration(0, false);
        handler.approveMigration(0, false, false);
        handler.advanceTime(uint32(7 days));
        handler.finalizeMigration(0);
        assertEq(handler.migrationsCompleted(), 1);
        handler.proposeCivic(0, true);
        handler.approveCivic(0);
        handler.appeal(0);
        handler.rule(0, true, true);
        handler.advanceTime(uint32(7 days));
        handler.finalizeCivic(0);
        assertEq(handler.civicChangesCompleted(), 1);
        assertFalse(handler.unexpectedBehavior());
        assertFalse(handler.consentOrRulingBypassed());
    }
}
