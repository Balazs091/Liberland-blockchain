// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {JusticeApp} from "../../contracts/apps/JusticeApp.sol";
import {JusticeIdentityWriter} from "../../contracts/apps/JusticeIdentityWriter.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IJusticeApp} from "../../contracts/interfaces/IJusticeApp.sol";
import {IJusticeDecisions} from "../../contracts/interfaces/IJusticeDecisions.sol";
import {IJusticeCompensation} from "../../contracts/interfaces/IJusticeCompensation.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {ExecutiveRegistry} from "../../contracts/registries/ExecutiveRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {JusticeCompensation} from "../../contracts/registries/JusticeCompensation.sol";
import {JusticeDecisions} from "../../contracts/registries/JusticeDecisions.sol";
import {MembershipRegistry} from "../../contracts/registries/MembershipRegistry.sol";
import {PresidentRegistry} from "../../contracts/registries/PresidentRegistry.sol";
import {SenateSeatRegistry} from "../../contracts/registries/SenateSeatRegistry.sol";
import {LiberlandMerit} from "../../contracts/tokens/LiberlandMerit.sol";
import {ExecutiveTypes} from "../../contracts/types/ExecutiveTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {JusticeTypes} from "../../contracts/types/JusticeTypes.sol";
import {MembershipTypes} from "../../contracts/types/MembershipTypes.sol";

contract JusticeAppTest is Test {
    bytes32 private constant SUBJECT = bytes32(uint256(12));
    bytes32 private constant BENEFICIARY = bytes32(uint256(13));
    string private constant REASON_URI = "ipfs://public-ruling";
    uint64 private constant SERVED = 1_000_000;
    uint64 private constant TERM_END = SERVED + 365 days;
    ConstitutionKernel private kernel;
    IdentityRegistry private identities;
    MembershipRegistry private membership;
    JusticeIdentityWriter private writer;
    JusticeDecisions private decisions;
    JusticeCompensation private compensation;
    JusticeApp private app;
    ExecutiveRegistry private executive;
    PresidentRegistry private president;
    LiberlandMerit private token;

    function setUp() external {
        vm.warp(SERVED);
        vm.roll(100);
        kernel = new ConstitutionKernel(address(this));
        identities = new IdentityRegistry(address(kernel));
        membership = new MembershipRegistry(address(kernel), address(identities));
        writer = new JusticeIdentityWriter(address(identities));
        decisions = new JusticeDecisions(address(kernel));
        token = new LiberlandMerit(address(this), 1_000 ether);
        compensation = new JusticeCompensation(address(kernel), address(token), address(identities));
        executive = new ExecutiveRegistry(address(kernel));
        president = new PresidentRegistry(address(kernel));

        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identities));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.MEMBERSHIP_REGISTRY, address(membership));
        kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_DECISIONS, address(decisions));
        kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_COMPENSATION, address(compensation));
        kernel.bootstrapSetModule(KernelModuleIds.PRESIDENT_REGISTRY, address(president));
        kernel.bootstrapSetModule(KernelModuleIds.EXECUTIVE_REGISTRY, address(executive));
        kernel.bootstrapSetModule(
            KernelModuleIds.SENATE_SEAT_REGISTRY, address(new SenateSeatRegistry(address(kernel)))
        );
        kernel.bootstrapSetModule(
            KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY, address(new CongressCandidateRegistry(address(kernel)))
        );
        kernel.bootstrapSetModule(KernelModuleIds.PRESIDENT_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.EXECUTIVE_REGISTRY_AUTHORITY, address(this));
        for (uint256 i = 1; i <= 13; ++i) {
            _seedCitizen(i);
        }
        president.setPresident(vm.addr(10), bytes32(uint256(10)), bytes32("president"), SERVED, TERM_END);
        executive.setMinister(ExecutiveTypes.MinistryKind.Interior, vm.addr(11), bytes32(uint256(11)), SERVED, TERM_END);
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(writer));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));
        _install(_rosters());
        kernel.disableBootstrapAuthority();
    }

    /// @notice The offline operator example matches this contract's effect encoding and both signing digests.
    function test_OfflinePacketMatchesContractDigests() external {
        vm.chainId(31_337);
        address exampleApp = 0x1111111111111111111111111111111111111111;
        vm.etch(exampleApp, address(app).code);
        JusticeTypes.IdentityEffect memory effect = JusticeTypes.IdentityEffect({
            wallet: 0x5555555555555555555555555555555555555555,
            ageClass: IdentityTypes.AgeClass.Adult,
            route: JusticeTypes.AdmissionRoute.Regular,
            presidencyNonce: 7,
            ministerMandateHash: 0x6666666666666666666666666666666666666666666666666666666666666666,
            priorDecisionId: bytes32(0)
        });
        JusticeTypes.Decision memory decision = JusticeTypes.Decision({
            action: JusticeTypes.Action.Admit,
            decisionId: 0x2222222222222222222222222222222222222222222222222222222222222222,
            personId: 0x3333333333333333333333333333333333333333333333333333333333333333,
            effectHash: keccak256(abi.encode(effect)),
            reasonHash: keccak256("ipfs://synthetic-public-ruling"),
            recordHash: 0x4444444444444444444444444444444444444444444444444444444444444444,
            noticeAt: 0,
            deadline: 1_800_000_000,
            stateRevision: 9_007_199_254_740_993
        });
        assertEq(
            IJusticeApp(exampleApp).decisionDigest(decision),
            0x6d600e19242bb5eb93ff6ef6f999eaebed7a0ac000c1234e2b0109e3effcd696
        );
        assertEq(
            IJusticeApp(exampleApp).destinationConsentDigest(decision),
            0x9c3f62aa098cca3d8a7828fb8d92dfde3f22f9f3732990f75b0fb855cb6f26c7
        );
    }

    function test_DisciplineRequiresBothMajoritiesAndNoticeThenAnyCallerCanExecute() external {
        JusticeTypes.MembershipEffect memory effect = JusticeTypes.MembershipEffect(0, 0, SERVED + 35 days, 1);
        JusticeTypes.Decision memory d = _decision(JusticeTypes.Action.Restrict, "order", SUBJECT, abi.encode(effect));
        JusticeTypes.Approvals memory approvals = _approvals(d, 1, 4);

        vm.expectRevert(abi.encodeWithSelector(IJusticeApp.NoticePending.selector, uint256(SERVED + 21 days)));
        app.executeMembership(d, effect, approvals);
        vm.warp(SERVED + 21 days);

        JusticeTypes.Approvals memory short = approvals;
        short.second = new JusticeTypes.Signature[](1);
        short.second[0] = approvals.second[0];
        vm.expectRevert(abi.encodeWithSelector(IJusticeApp.InsufficientApproval.selector, JusticeTypes.Body.Panel, 2));
        app.executeMembership(d, effect, short);

        approvals = _approvals(d, 1, 4);
        vm.prank(address(0xCAFE));
        app.executeMembership(d, effect, approvals);
        assertTrue(decisions.used(d.decisionId));
        assertTrue(membership.isRestrictedNow(SUBJECT, MembershipTypes.Right.Political));
        assertFalse(membership.membershipRemoved(SUBJECT));
        vm.expectRevert(abi.encodeWithSelector(IJusticeDecisions.DecisionAlreadyUsed.selector, d.decisionId));
        app.executeMembership(d, effect, approvals);
        vm.warp(SERVED + 35 days);
        assertFalse(membership.isRestrictedNow(SUBJECT, MembershipTypes.Right.Political));
    }

    function test_MembershipLossPreservesCitizenshipAndRestorationDoesNotResetOtherOrders() external {
        vm.warp(SERVED + 21 days);
        JusticeTypes.MembershipEffect memory order = JusticeTypes.MembershipEffect(0, 0, SERVED + 35 days, 1);
        _membershipDecision(JusticeTypes.Action.Restrict, "order", order);
        JusticeTypes.MembershipEffect memory remove =
            JusticeTypes.MembershipEffect(0, membership.membershipRevisionOf(SUBJECT), 0, 0);
        _membershipDecision(JusticeTypes.Action.RemoveMembership, "remove", remove);
        assertTrue(membership.membershipRemoved(SUBJECT));
        (, IdentityTypes.CitizenshipStatus status,,) = identities.getCitizenshipSummary(SUBJECT);
        assertEq(uint8(status), uint8(IdentityTypes.CitizenshipStatus.Citizen));

        remove.revision = membership.membershipRevisionOf(SUBJECT);
        _membershipDecision(JusticeTypes.Action.RestoreMembership, "restore", remove);
        assertFalse(membership.membershipRemoved(SUBJECT));
        assertTrue(membership.isRestrictedNow(SUBJECT, MembershipTypes.Right.Political));

        JusticeTypes.MembershipEffect memory relief = JusticeTypes.MembershipEffect("order", 1, 0, 0);
        _membershipDecision(JusticeTypes.Action.StayOrder, "stay", relief);
        assertFalse(membership.isRestrictedNow(SUBJECT, MembershipTypes.Right.Political));
        relief.revision = 2;
        _membershipDecision(JusticeTypes.Action.ResumeOrder, "resume", relief);
        assertEq(membership.orderOf(SUBJECT, "order").expiresAt, order.expiresAt);
        relief.revision = 3;
        _membershipDecision(JusticeTypes.Action.RevokeOrder, "revoke", relief);
        assertFalse(membership.isRestrictedNow(SUBJECT, MembershipTypes.Right.Political));
    }

    function test_CitizenshipLifecycleUsesIndependentApprovals() external {
        bytes32 applicant = bytes32(uint256(14));
        JusticeTypes.IdentityEffect memory effect = _identityEffect(vm.addr(14));
        effect.ageClass = IdentityTypes.AgeClass.Minor;
        effect.presidencyNonce = president.presidencyNonce();
        effect.ministerMandateHash = keccak256(abi.encode(executive.getMinister(ExecutiveTypes.MinistryKind.Interior)));
        JusticeTypes.Decision memory d = _decision(JusticeTypes.Action.Admit, "admit", applicant, abi.encode(effect));
        d.noticeAt = 0;
        JusticeTypes.Approvals memory approvals = _approvals(d, 1, 0);
        bytes32 digest = app.decisionDigest(d);
        approvals.minister = _sign(11, digest);
        approvals.president = _sign(10, digest);
        approvals.destination = _sign(14, app.destinationConsentDigest(d));

        bytes memory original = approvals.president;
        approvals.president = approvals.minister;
        vm.expectRevert(abi.encodeWithSelector(IJusticeApp.InvalidApproval.selector, bytes32(uint256(10))));
        app.executeIdentity(d, effect, approvals);
        approvals.president = original;
        app.executeIdentity(d, effect, approvals);
        assertEq(identities.activeWalletOf(applicant), vm.addr(14));
        assertTrue(decisions.admittedBy(applicant, bytes32(uint256(1))));
        assertTrue(decisions.admittedBy(applicant, bytes32(uint256(2))));
        _recognizeAdulthood(applicant);

        vm.warp(SERVED + 21 days);
        JusticeTypes.IdentityEffect memory annulment = _identityEffect(address(0));
        JusticeTypes.Decision memory annul =
            _decision(JusticeTypes.Action.Annul, "annul", applicant, abi.encode(annulment));
        app.executeIdentity(annul, annulment, _approvals(annul, 4, 7));
        (, IdentityTypes.CitizenshipStatus status,,) = identities.getCitizenshipSummary(applicant);
        assertEq(uint8(status), uint8(IdentityTypes.CitizenshipStatus.Revoked));
        assertEq(decisions.annulmentOf(applicant), annul.decisionId);
        _restoreCitizenship(applicant, annul.decisionId);
    }

    function _recognizeAdulthood(bytes32 applicant) private {
        JusticeTypes.IdentityEffect memory adulthood = _identityEffect(vm.addr(14));
        JusticeTypes.Decision memory recognition =
            _decision(JusticeTypes.Action.RecognizeAdulthood, "adult", applicant, abi.encode(adulthood));
        recognition.noticeAt = 0;
        JusticeTypes.Approvals memory approvals = _approvals(recognition, 1, 0);
        approvals.destination = _sign(14, app.destinationConsentDigest(recognition));
        app.executeIdentity(recognition, adulthood, approvals);
        (,, IdentityTypes.AgeClass age,) = identities.getCitizenshipSummary(applicant);
        assertEq(uint8(age), uint8(IdentityTypes.AgeClass.Adult));
    }

    function _restoreCitizenship(bytes32 applicant, bytes32 annulmentId) private {
        JusticeTypes.IdentityEffect memory reversal = _identityEffect(address(0));
        reversal.priorDecisionId = "wrong-case";
        JusticeTypes.Decision memory decision =
            _decision(JusticeTypes.Action.RestoreCitizenship, "restore-citizen", applicant, abi.encode(reversal));
        JusticeTypes.Approvals memory approvals = _approvals(decision, 4, 7);
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeDecisions.AnnulmentMismatch.selector, bytes32("wrong-case"), annulmentId)
        );
        app.executeIdentity(decision, reversal, approvals);
        assertFalse(decisions.used(decision.decisionId));

        reversal.priorDecisionId = annulmentId;
        decision.effectHash = keccak256(abi.encode(reversal));
        app.executeIdentity(decision, reversal, _approvals(decision, 4, 7));
        (, IdentityTypes.CitizenshipStatus status,,) = identities.getCitizenshipSummary(applicant);
        assertEq(uint8(status), uint8(IdentityTypes.CitizenshipStatus.Citizen));
        assertEq(decisions.annulmentOf(applicant), bytes32(0));
    }

    function test_RecoveryNeedsDestinationConsentAndCannotReuseAnOldDecision() external {
        JusticeTypes.IdentityEffect memory effect = _identityEffect(vm.addr(14));
        JusticeTypes.Decision memory d = _decision(JusticeTypes.Action.Recover, "recover", SUBJECT, abi.encode(effect));
        JusticeTypes.Approvals memory approvals = _approvals(d, 1, 4);
        approvals.destination = _sign(14, app.destinationConsentDigest(d));
        vm.warp(SERVED + 30 days - 1);
        vm.expectRevert(abi.encodeWithSelector(IJusticeApp.NoticePending.selector, uint256(SERVED + 30 days)));
        app.executeIdentity(d, effect, approvals);
        vm.warp(SERVED + 30 days);
        approvals.destination = _sign(13, app.destinationConsentDigest(d));
        vm.expectRevert(abi.encodeWithSelector(IJusticeApp.InvalidApproval.selector, SUBJECT));
        app.executeIdentity(d, effect, approvals);
        approvals.destination = _sign(14, app.destinationConsentDigest(d));
        // The old key holder can move the current link, but cannot invalidate the approved recovery.
        vm.prank(vm.addr(12));
        bytes32 move = writer.requestWalletMigration(vm.addr(15), uint64(block.timestamp + 1 days));
        vm.prank(vm.addr(15));
        writer.acceptWalletMigration(SUBJECT, move);
        assertEq(identities.activeWalletOf(SUBJECT), vm.addr(15));

        app.executeIdentity(d, effect, approvals);
        assertEq(identities.activeWalletOf(SUBJECT), vm.addr(14));
        assertFalse(identities.hasActiveWalletLink(vm.addr(15)));
        assertFalse(identities.hasActiveWalletLink(vm.addr(12)));
        vm.expectRevert(IJusticeApp.InvalidDecision.selector);
        app.executeIdentity(d, effect, approvals);
    }

    function test_OfficeProtectionAndOrderLimitCannotBeBypassedByAValidVote() external {
        vm.warp(SERVED + 21 days);
        JusticeTypes.MembershipEffect memory effect = JusticeTypes.MembershipEffect(0, 0, SERVED + 80 days, 1);
        JusticeTypes.Decision memory d =
            _decision(JusticeTypes.Action.Restrict, "office", bytes32(uint256(10)), abi.encode(effect));
        JusticeTypes.Approvals memory approvals = _approvals(d, 1, 4);
        vm.expectRevert(abi.encodeWithSelector(IJusticeApp.ProtectedOffice.selector, bytes32(uint256(10))));
        app.executeMembership(d, effect, approvals);
        d = _decision(JusticeTypes.Action.Restrict, "long", SUBJECT, abi.encode(effect));
        approvals = _approvals(d, 1, 4);
        vm.expectRevert(IJusticeApp.InvalidEffect.selector);
        app.executeMembership(d, effect, approvals);
        assertFalse(decisions.used(d.decisionId));
    }

    function test_ExactDecisionAndStableReplayAcrossRosterReplacement() external {
        vm.warp(SERVED + 21 days);
        JusticeTypes.MembershipEffect memory effect = JusticeTypes.MembershipEffect(0, 0, SERVED + 35 days, 1);
        JusticeTypes.Decision memory d = _decision(JusticeTypes.Action.Restrict, "order", SUBJECT, abi.encode(effect));
        JusticeTypes.Approvals memory original = _approvals(d, 1, 4);
        effect.rights = 2;
        vm.expectRevert(IJusticeApp.InvalidDecision.selector);
        app.executeMembership(d, effect, original);
        effect.rights = 1;
        original.publicReasonURI = "ipfs://substituted-ruling";
        vm.expectRevert(IJusticeApp.InvalidDecision.selector);
        app.executeMembership(d, effect, original);
        original.publicReasonURI = REASON_URI;
        app.executeMembership(d, effect, original);

        JusticeApp retired = app;
        _install(_rosters());
        vm.expectRevert(IJusticeApp.InactiveJustice.selector);
        retired.executeMembership(d, effect, original);
        vm.expectRevert(abi.encodeWithSelector(IJusticeApp.InvalidApproval.selector, bytes32(uint256(1))));
        app.executeMembership(d, effect, original);
        JusticeTypes.Approvals memory reSigned = _approvals(d, 1, 4);
        vm.expectRevert(abi.encodeWithSelector(IJusticeDecisions.DecisionAlreadyUsed.selector, d.decisionId));
        app.executeMembership(d, effect, reSigned);
    }

    function test_CompensationAndRestorationUseSeparateFundedEffects() external {
        token.transfer(vm.addr(12), 50 ether);
        vm.startPrank(vm.addr(12));
        token.approve(address(compensation), 50 ether);
        compensation.deposit("lot", 50 ether, "terms", uint48(SERVED + 60 days));
        vm.stopPrank();
        vm.warp(SERVED + 21 days);
        vm.roll(101);
        JusticeTypes.FinancialEffect memory effect =
            JusticeTypes.FinancialEffect("lot", BENEFICIARY, 20 ether, 100, "terms");
        JusticeTypes.Decision memory award =
            _decision(JusticeTypes.Action.Compensate, "award", SUBJECT, abi.encode(effect));
        app.executeFinancial(award, effect, _approvals(award, 1, 4));
        assertEq(compensation.claimableOf(BENEFICIARY), 20 ether);

        effect = JusticeTypes.FinancialEffect("award", 0, 20 ether, 0, 0);
        JusticeTypes.Decision memory restore =
            _decision(JusticeTypes.Action.RestoreMerits, "refund", SUBJECT, abi.encode(effect));
        JusticeTypes.Approvals memory approvals = _approvals(restore, 1, 4);
        vm.expectRevert(
            abi.encodeWithSelector(
                IJusticeCompensation.InsufficientRestorationFunding.selector, bytes32("award"), 0, 20 ether
            )
        );
        app.executeFinancial(restore, effect, approvals);
        assertFalse(decisions.used(restore.decisionId));
        token.approve(address(compensation), 20 ether);
        compensation.fundRestoration("award", 20 ether);
        app.executeFinancial(restore, effect, approvals);
        assertEq(compensation.claimableOf(SUBJECT), 20 ether);
        assertEq(compensation.claimableOf(BENEFICIARY), 20 ether);
    }

    function _install(bytes32[][5] memory rosters) private {
        app = new JusticeApp(
            address(kernel),
            address(identities),
            address(membership),
            address(decisions),
            address(writer),
            address(compensation),
            JusticeTypes.Charter("rules", TERM_END, 30 days, 31),
            rosters
        );
        if (kernel.bootstrapAuthority() == address(0)) {
            kernel.governanceUpdateModule(KernelModuleIds.JUSTICE_APP, address(app));
            kernel.governanceUpdateModule(KernelModuleIds.IDENTITY_WRITER, address(app));
        } else {
            kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_APP, address(app));
            kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_WRITER, address(app));
        }
    }

    function _rosters() private pure returns (bytes32[][5] memory rosters) {
        for (uint256 body; body < 5; ++body) {
            rosters[body] = new bytes32[](3);
            for (uint256 j; j < 3; ++j) {
                rosters[body][j] = bytes32(body % 3 * 3 + j + 1);
            }
        }
    }

    function _seedCitizen(uint256 key) private {
        bytes32 personId = bytes32(key);
        identities.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput(
                "metadata",
                "",
                IdentityTypes.VerificationStatus.Verified,
                IdentityTypes.CitizenshipStatus.Citizen,
                IdentityTypes.AgeClass.Adult,
                false,
                false
            )
        );
        identities.setWalletLink(personId, vm.addr(key), IdentityTypes.WalletLinkStatus.Active);
    }

    function _decision(JusticeTypes.Action action, bytes32 id, bytes32 subject, bytes memory effect)
        private
        view
        returns (JusticeTypes.Decision memory)
    {
        return JusticeTypes.Decision(
            action,
            id,
            subject,
            keccak256(effect),
            keccak256(bytes(REASON_URI)),
            "record",
            SERVED,
            TERM_END,
            app.decisionStateRevision(action, subject)
        );
    }

    function _identityEffect(address wallet) private pure returns (JusticeTypes.IdentityEffect memory) {
        return JusticeTypes.IdentityEffect(
            wallet, IdentityTypes.AgeClass.Undefined, JusticeTypes.AdmissionRoute.Regular, 0, 0, 0
        );
    }

    function _membershipDecision(JusticeTypes.Action action, bytes32 id, JusticeTypes.MembershipEffect memory effect)
        private
    {
        JusticeTypes.Decision memory d = _decision(action, id, SUBJECT, abi.encode(effect));
        app.executeMembership(d, effect, _approvals(d, 1, 4));
    }

    function _approvals(JusticeTypes.Decision memory d, uint256 first, uint256 second)
        private
        view
        returns (JusticeTypes.Approvals memory approvals)
    {
        bytes32 digest = app.decisionDigest(d);
        approvals.publicReasonURI = REASON_URI;
        approvals.first = _signPair(first, digest);
        if (second != 0) approvals.second = _signPair(second, digest);
    }

    function _signPair(uint256 key, bytes32 digest) private pure returns (JusticeTypes.Signature[] memory signatures) {
        signatures = new JusticeTypes.Signature[](2);
        signatures[0] = JusticeTypes.Signature(bytes32(key), _sign(key, digest));
        signatures[1] = JusticeTypes.Signature(bytes32(key + 1), _sign(key + 1, digest));
    }

    function _sign(uint256 key, bytes32 digest) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }
}
