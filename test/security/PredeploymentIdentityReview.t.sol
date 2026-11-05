// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {CabinetApp} from "../../contracts/apps/CabinetApp.sol";
import {DecisionApp} from "../../contracts/apps/DecisionApp.sol";
import {LLMStakingVault} from "../../contracts/apps/LLMStakingVault.sol";
import {IdentityApp} from "../../contracts/apps/IdentityApp.sol";
import {CivicAppealReview} from "../../contracts/apps/CivicAppealReview.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ICabinetApp} from "../../contracts/interfaces/ICabinetApp.sol";
import {IDecisionApp} from "../../contracts/interfaces/IDecisionApp.sol";
import {IIdentityApp} from "../../contracts/interfaces/IIdentityApp.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {IOfficeRegistry} from "../../contracts/interfaces/IOfficeRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {ExecutiveRegistry} from "../../contracts/registries/ExecutiveRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {LiberlandMerit} from "../../contracts/tokens/LiberlandMerit.sol";
import {DecisionTypes} from "../../contracts/types/DecisionTypes.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {ExecutiveTypes} from "../../contracts/types/ExecutiveTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

/// @notice Independent end-user/authority replacement fixture; no inherited application tests are counted twice.
contract PredeploymentCabinetReviewTest is Test {
    bytes32 private constant FINANCE = keccak256("predeployment.finance");
    bytes32 private constant PM_PERSON = bytes32(uint256(100));
    bytes32 private constant MINISTER_PERSON = bytes32(uint256(101));
    address private constant PM = address(0x9111);
    address private constant MINISTER = address(0x9222);
    address private constant MINISTER_NEW = address(0x9333);
    address private constant NEXT_MINISTER = address(0x9444);
    ConstitutionKernel private kernel;
    IdentityRegistry private identity;
    StakeRegistry private stake;
    CitizenEligibilityPolicy private citizenPolicy;
    CongressCandidateRegistry private congress;
    ExecutiveRegistry private executive;
    OfficeRegistry private offices;
    CabinetApp private cabinet;

    function setUp() public {
        vm.warp(1_900_000_000);
        kernel = new ConstitutionKernel(address(this));
        identity = new IdentityRegistry(address(kernel));
        stake = new StakeRegistry(address(kernel));
        citizenPolicy = new CitizenEligibilityPolicy(address(identity), address(stake), 5_000);
        congress = new CongressCandidateRegistry(address(kernel));
        executive = new ExecutiveRegistry(address(kernel));
        offices = new OfficeRegistry(address(kernel));
        cabinet = _newCabinet();
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identity));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(citizenPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.EXECUTIVE_REGISTRY_AUTHORITY, address(cabinet));
        kernel.bootstrapSetModule(KernelModuleIds.CABINET_APP, address(cabinet));
        offices.registerOffice(FINANCE, OfficeTypes.OfficeKind.MinistryOfFinance, "Synthetic Finance", address(0xF1));
        address[] memory members = new address[](7);
        for (uint256 i; i < members.length; ++i) {
            members[i] = _member(i);
            _seedPerson(bytes32(i + 1), members[i]);
        }
        _seedPerson(PM_PERSON, PM);
        _seedPerson(MINISTER_PERSON, MINISTER);
        _seedPerson(bytes32(uint256(102)), NEXT_MINISTER);
        congress.createCycle(
            1,
            ElectionTypes.CongressCycleInput({
                nominationStart: uint64(block.timestamp),
                votingStart: uint64(block.timestamp + 1),
                votingEnd: uint64(block.timestamp + 2),
                votingPowerSnapshotBlock: uint48(block.number),
                seatCount: 7,
                runnerUpCount: 1,
                maxCandidateCount: 8,
                policy: address(cabinet),
                policyReference: keccak256("predeployment-cabinet")
            })
        );
        for (uint256 i; i < members.length; ++i) {
            congress.registerCandidate(1, members[i], bytes32(i + 1), keccak256(abi.encode(i)), "");
        }
        congress.finalizeCycle(
            1,
            ElectionTypes.CongressFinalizationInput({
                rankedCandidates: members, rankedVoteTotals: new int256[](7), electedCount: 7, runnerUpCount: 0
            })
        );
        kernel.disableBootstrapAuthority();
    }

    function testFuzz_SittingMinisterCannotBecomePrimeMinister(uint8 ministryValue) public {
        ExecutiveTypes.MinistryKind ministry = ExecutiveTypes.MinistryKind(bound(ministryValue, 1, 4));
        _prepareMinisterCandidate(ministry);
        assertEq(cabinet.appointmentVoteCount(MINISTER), 4);
        assertFalse(cabinet.canAppointPrimeMinister(MINISTER));
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.MinisterAlreadyServing.selector, MINISTER));
        cabinet.appointPrimeMinister(MINISTER);
        assertEq(executive.primeMinister(), address(0));
        assertEq(executive.getMinister(ministry).personId, MINISTER_PERSON);
    }

    function test_PredeploymentApi_CabinetViewsFollowAppointmentSupportDismissalAndRemoval() public {
        assertEq(cabinet.primeMinister(), address(0));
        assertEq(cabinet.getPrimeMinister().personId, bytes32(0));
        assertFalse(cabinet.isPrimeMinisterInTerm());
        assertEq(cabinet.primeMinisterAppointmentSupport(), 0);
        assertFalse(cabinet.getMinister(ExecutiveTypes.MinistryKind.Finance).active);
        assertFalse(cabinet.isMinisterInTerm(ExecutiveTypes.MinistryKind.Finance));

        _voteFor(cabinet, PM);
        cabinet.appointPrimeMinister(PM);
        assertEq(cabinet.primeMinister(), PM);
        assertEq(cabinet.getPrimeMinister().personId, PM_PERSON);
        assertTrue(cabinet.isPrimeMinisterInTerm());
        assertEq(cabinet.primeMinisterAppointmentSupport(), 4);
        vm.prank(PM);
        cabinet.appointMinister(ExecutiveTypes.MinistryKind.Finance, MINISTER);
        assertEq(cabinet.getMinister(ExecutiveTypes.MinistryKind.Finance).personId, MINISTER_PERSON);
        assertTrue(cabinet.isMinisterInTerm(ExecutiveTypes.MinistryKind.Finance));
        _castRemovalAndDismissal(_member(0));
        (address removalTarget, uint256 removalCycle, uint64 removalNonce) = cabinet.getRemovalBallot(_member(0));
        assertEq(removalTarget, PM);
        assertEq(removalCycle, 1);
        assertGt(removalNonce, 0);
        (address dismissalTarget, uint256 dismissalCycle, uint64 dismissalNonce) =
            cabinet.getDismissalBallot(ExecutiveTypes.MinistryKind.Finance, _member(0));
        assertEq(dismissalTarget, MINISTER);
        assertEq(dismissalCycle, 1);
        assertGt(dismissalNonce, 0);
        for (uint256 i = 1; i < 4; ++i) {
            _castRemovalAndDismissal(_member(i));
        }
        assertTrue(cabinet.canDismissMinister(ExecutiveTypes.MinistryKind.Finance));
        cabinet.dismissMinister(ExecutiveTypes.MinistryKind.Finance);
        assertFalse(cabinet.isMinisterInTerm(ExecutiveTypes.MinistryKind.Finance));
        assertFalse(cabinet.getMinister(ExecutiveTypes.MinistryKind.Finance).active);
        assertTrue(cabinet.canRemovePrimeMinister());
        cabinet.removePrimeMinister();
        assertEq(cabinet.primeMinister(), address(0));
        assertEq(cabinet.getPrimeMinister().personId, bytes32(0));
        assertEq(cabinet.primeMinisterAppointmentSupport(), 0);
        assertFalse(cabinet.isPrimeMinisterInTerm());
        assertFalse(cabinet.canRemovePrimeMinister());
    }

    function test_MinisterWalletMigrationCannotBypassPrimeMinisterIncompatibility() public {
        _prepareMinisterCandidate(ExecutiveTypes.MinistryKind.Finance);
        identity.setWalletLink(MINISTER_PERSON, MINISTER, IdentityTypes.WalletLinkStatus.Revoked);
        identity.setWalletLink(MINISTER_PERSON, MINISTER_NEW, IdentityTypes.WalletLinkStatus.Active);
        _voteFor(cabinet, MINISTER_NEW);
        assertEq(uint8(offices.roleOf(FINANCE, MINISTER_NEW)), uint8(OfficeTypes.OfficeRole.Admin));
        assertEq(uint8(offices.roleOf(FINANCE, MINISTER)), uint8(OfficeTypes.OfficeRole.None));
        assertFalse(cabinet.canAppointPrimeMinister(MINISTER_NEW));
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.MinisterAlreadyServing.selector, MINISTER_NEW));
        cabinet.appointPrimeMinister(MINISTER_NEW);
    }

    function test_MinisterCanResignThenUseTheAlreadyCastAppointmentVotes() public {
        _prepareMinisterCandidate(ExecutiveTypes.MinistryKind.Finance);
        vm.prank(MINISTER);
        cabinet.resignMinister(ExecutiveTypes.MinistryKind.Finance);
        assertEq(uint8(offices.roleOf(FINANCE, MINISTER)), uint8(OfficeTypes.OfficeRole.None));
        assertFalse(offices.getOfficeRecord(FINANCE).active);
        assertTrue(cabinet.canAppointPrimeMinister(MINISTER));
        cabinet.appointPrimeMinister(MINISTER);
        assertEq(executive.getPrimeMinister().personId, MINISTER_PERSON);
    }

    function test_ExpiredMinisterCanBecomePrimeMinisterWithoutCleanup() public {
        _prepareMinisterCandidate(ExecutiveTypes.MinistryKind.Finance);
        vm.warp(executive.getMinister(ExecutiveTypes.MinistryKind.Finance).termEnd);
        // Registry audit record remains active, but the term and office powers have expired in reads.
        assertTrue(executive.getMinister(ExecutiveTypes.MinistryKind.Finance).active);
        assertFalse(executive.isMinisterInTerm(ExecutiveTypes.MinistryKind.Finance));
        assertEq(uint8(offices.roleOf(FINANCE, MINISTER)), uint8(OfficeTypes.OfficeRole.None));
        assertTrue(cabinet.canAppointPrimeMinister(MINISTER));
        cabinet.appointPrimeMinister(MINISTER);
        assertEq(executive.getPrimeMinister().personId, MINISTER_PERSON);
    }

    function test_PairedCabinetAuthorityReplacementPreservesFactsAndRecoversFromIntermediateState() public {
        _voteFor(cabinet, PM);
        cabinet.appointPrimeMinister(PM);
        ExecutiveTypes.PrimeMinisterRecord memory originalTerm = executive.getPrimeMinister();
        CabinetApp successor = _newCabinet();
        kernel.governanceUpdateModule(KernelModuleIds.EXECUTIVE_REGISTRY_AUTHORITY, address(successor));
        vm.prank(PM);
        vm.expectRevert(
            abi.encodeWithSelector(IOfficeRegistry.UnauthorizedOfficeRegistryCaller.selector, address(successor))
        );
        successor.appointMinister(ExecutiveTypes.MinistryKind.Finance, MINISTER);
        // The failed office write rolls the preceding ExecutiveRegistry write back too.
        assertFalse(executive.getMinister(ExecutiveTypes.MinistryKind.Finance).active);
        assertEq(offices.getOfficeRecord(FINANCE).admin, address(0xF1));
        kernel.governanceUpdateModule(KernelModuleIds.CABINET_APP, address(successor));
        vm.prank(PM);
        successor.appointMinister(ExecutiveTypes.MinistryKind.Finance, MINISTER);
        assertEq(executive.getPrimeMinister().personId, PM_PERSON);
        assertEq(executive.getPrimeMinister().termStart, originalTerm.termStart);
        assertEq(executive.getPrimeMinister().termEnd, originalTerm.termEnd);
        assertEq(successor.primeMinisterAppointmentSupport(), 4);
        assertEq(executive.getMinister(ExecutiveTypes.MinistryKind.Finance).personId, MINISTER_PERSON);
        assertEq(uint8(offices.roleOf(FINANCE, MINISTER)), uint8(OfficeTypes.OfficeRole.Admin));
    }

    function test_CabinetPointerReplacementDoesNotImportVotesButRecastingRestoresProgress() public {
        _voteFor(cabinet, PM);
        assertTrue(cabinet.canAppointPrimeMinister(PM));
        CabinetApp successor = _newCabinet();
        kernel.governanceUpdateModule(KernelModuleIds.EXECUTIVE_REGISTRY_AUTHORITY, address(successor));
        kernel.governanceUpdateModule(KernelModuleIds.CABINET_APP, address(successor));
        assertEq(successor.appointmentVoteCount(PM), 0);
        assertFalse(successor.canAppointPrimeMinister(PM));
        vm.expectRevert();
        cabinet.appointPrimeMinister(PM);
        _voteFor(successor, PM);
        successor.appointPrimeMinister(PM);
        assertEq(executive.getPrimeMinister().personId, PM_PERSON);
    }

    function test_ReturningToAnOldWalletCannotResurrectASupersededAppointmentChoice() public {
        _voteFor(cabinet, PM);
        address original = _member(0);
        address migrated = address(0xC99);
        _moveMemberOne(original, migrated);
        vm.prank(migrated);
        cabinet.voteForPrimeMinister(MINISTER);
        assertEq(cabinet.appointmentVoteCount(PM), 3);
        assertEq(cabinet.appointmentVoteCount(MINISTER), 1);
        _moveMemberOne(migrated, original);
        // The latest choice was MINISTER. Returning to the earlier key must not manufacture a majority for PM.
        assertEq(cabinet.appointmentVoteCount(PM), 3);
        assertFalse(cabinet.canAppointPrimeMinister(PM));
        vm.prank(original);
        cabinet.voteForPrimeMinister(MINISTER);
        assertEq(cabinet.appointmentVoteCount(MINISTER), 1);
    }

    function test_PositiveRemovalBooksCannotDoubleCountOrSurviveTheirCompletedTenures() public {
        _voteFor(cabinet, PM);
        cabinet.appointPrimeMinister(PM);
        vm.prank(PM);
        cabinet.appointMinister(ExecutiveTypes.MinistryKind.Finance, MINISTER);
        address original = _member(0);
        address migrated = address(0xC99);
        _castRemovalAndDismissal(original);
        _moveMemberOne(original, migrated);
        _castRemovalAndDismissal(migrated);
        assertEq(cabinet.removalVoteCount(), 1);
        assertEq(cabinet.dismissalVoteCount(ExecutiveTypes.MinistryKind.Finance), 1);
        for (uint256 i = 1; i < 4; ++i) {
            _castRemovalAndDismissal(_member(i));
        }
        cabinet.dismissMinister(ExecutiveTypes.MinistryKind.Finance);
        cabinet.removePrimeMinister();
        _voteFor(cabinet, MINISTER);
        cabinet.appointPrimeMinister(MINISTER);
        vm.prank(MINISTER);
        cabinet.appointMinister(ExecutiveTypes.MinistryKind.Finance, NEXT_MINISTER);
        _moveMemberOne(migrated, original);
        assertEq(cabinet.removalVoteCount(), 0);
        assertEq(cabinet.dismissalVoteCount(ExecutiveTypes.MinistryKind.Finance), 0);
    }

    function test_RecastingFromMigratedWalletDoesNotEraseTheNewHolderOfItsEarlierWallet() public {
        _voteFor(cabinet, PM);
        address firstOriginal = _member(0);
        address firstMigrated = address(0xC99);
        _moveMemberOne(firstOriginal, firstMigrated);
        identity.setWalletLink(bytes32(uint256(2)), _member(1), IdentityTypes.WalletLinkStatus.Revoked);
        identity.setWalletLink(bytes32(uint256(2)), firstOriginal, IdentityTypes.WalletLinkStatus.Active);
        vm.prank(firstOriginal);
        cabinet.voteForPrimeMinister(PM);
        vm.prank(firstMigrated);
        cabinet.voteForPrimeMinister(MINISTER);
        assertEq(cabinet.appointmentVoteCount(PM), 3);
        assertEq(cabinet.appointmentVoteCount(MINISTER), 1);
        (address retained,,) = cabinet.getAppointmentBallot(firstOriginal);
        assertEq(retained, PM);
    }

    function test_DecisionRevocationSurvivesWalletRoundTripAfterReendorsing() public {
        (DecisionApp decisions, bytes32 decisionId) = _newDecision();
        address original = _member(0);
        address migrated = address(0xC99);
        vm.prank(original);
        decisions.supportCongressDecision(decisionId);
        _moveMemberOne(original, migrated);
        vm.prank(migrated);
        decisions.supportCongressDecision(decisionId);
        vm.prank(migrated);
        decisions.revokeCongressDecisionSupport(decisionId);
        _moveMemberOne(migrated, original);
        assertFalse(decisions.hasCongressSupported(decisionId, original));
        assertEq(decisions.getDecision(decisionId).supportCount, 3);
        vm.expectRevert(abi.encodeWithSelector(IDecisionApp.CongressDecisionNotApproved.selector, decisionId, 3, 4));
        decisions.executeCongressDecision(decisionId);
        vm.prank(original);
        decisions.supportCongressDecision(decisionId);
        decisions.executeCongressDecision(decisionId);
        assertEq(uint8(decisions.getDecision(decisionId).status), uint8(DecisionTypes.DecisionStatus.Executed));
    }

    function test_DecisionRevocationFromNewWalletWithoutReendorsingRetiresOldReceipt() public {
        (DecisionApp decisions, bytes32 decisionId) = _newDecision();
        address original = _member(0);
        address migrated = address(0xC99);
        vm.prank(original);
        decisions.supportCongressDecision(decisionId);
        _moveMemberOne(original, migrated);
        vm.prank(migrated);
        decisions.revokeCongressDecisionSupport(decisionId);
        _moveMemberOne(migrated, original);
        assertFalse(decisions.hasCongressSupported(decisionId, original));
        assertEq(decisions.getDecision(decisionId).supportCount, 3);
    }

    function test_DecisionMigrationRecastDoesNotInflateStoredPersonSupportCount() public {
        (DecisionApp decisions, bytes32 decisionId) = _newDecision();
        address original = _member(0);
        address migrated = address(0xC99);
        vm.prank(original);
        decisions.supportCongressDecision(decisionId);
        _moveMemberOne(original, migrated);
        vm.prank(migrated);
        decisions.supportCongressDecision(decisionId);
        assertEq(decisions.getDecision(decisionId).supportCount, 4);
        vm.prank(migrated);
        decisions.supportCongressDecision(decisionId);
        assertEq(decisions.getDecision(decisionId).supportCount, 4);
    }

    function test_DecisionWithdrawalDoesNotEraseAnotherPersonUsingTheEarlierWallet() public {
        (DecisionApp decisions, bytes32 decisionId) = _newDecision();
        address firstOriginal = _member(0);
        address firstMigrated = address(0xC99);
        vm.prank(firstOriginal);
        decisions.supportCongressDecision(decisionId);
        _moveMemberOne(firstOriginal, firstMigrated);
        identity.setWalletLink(bytes32(uint256(2)), _member(1), IdentityTypes.WalletLinkStatus.Revoked);
        identity.setWalletLink(bytes32(uint256(2)), firstOriginal, IdentityTypes.WalletLinkStatus.Active);
        vm.prank(firstOriginal);
        decisions.supportCongressDecision(decisionId);
        vm.prank(firstMigrated);
        decisions.revokeCongressDecisionSupport(decisionId);
        assertTrue(decisions.hasCongressSupported(decisionId, firstOriginal));
        assertFalse(decisions.hasCongressSupported(decisionId, firstMigrated));
        assertEq(decisions.getDecision(decisionId).supportCount, 3);
    }

    function _newCabinet() private returns (CabinetApp) {
        return new CabinetApp(address(executive), address(congress), address(citizenPolicy), FINANCE, address(offices));
    }

    function _newDecision() private returns (DecisionApp decisions, bytes32 decisionId) {
        LiberlandMerit token = new LiberlandMerit(address(this), 1e18);
        LLMStakingVault vault = new LLMStakingVault(address(kernel), address(identity), address(stake), address(token));
        decisions = new DecisionApp(address(congress), address(identity), address(offices), address(vault));
        kernel.governanceRegisterModule(KernelModuleIds.DECISION_APP, address(decisions));
        decisionId = keccak256("predeployment.register-office");
        vm.prank(_member(1));
        decisions.createCongressRegisterOfficeDecision(
            decisionId,
            keccak256("predeployment.new-office"),
            OfficeTypes.OfficeKind.LandRegistryOffice,
            "Synthetic New Office",
            address(0xBEEF),
            keccak256("synthetic reasons"),
            ""
        );
        for (uint256 i = 2; i < 4; ++i) {
            vm.prank(_member(i));
            decisions.supportCongressDecision(decisionId);
        }
    }

    function _prepareMinisterCandidate(ExecutiveTypes.MinistryKind ministry) private {
        _voteFor(cabinet, PM);
        cabinet.appointPrimeMinister(PM);
        vm.prank(PM);
        cabinet.appointMinister(ministry, MINISTER);
        vm.prank(PM);
        cabinet.resignPrimeMinister();
        _voteFor(cabinet, MINISTER);
    }

    function _voteFor(CabinetApp target, address candidate) private {
        for (uint256 i; i < 4; ++i) {
            vm.prank(identity.activeWalletOf(bytes32(i + 1)));
            target.voteForPrimeMinister(candidate);
        }
    }

    function _moveMemberOne(address from, address to) private {
        identity.setWalletLink(bytes32(uint256(1)), from, IdentityTypes.WalletLinkStatus.Revoked);
        identity.setWalletLink(bytes32(uint256(1)), to, IdentityTypes.WalletLinkStatus.Active);
    }

    function _castRemovalAndDismissal(address member) private {
        vm.prank(member);
        cabinet.voteToRemovePrimeMinister();
        vm.prank(member);
        cabinet.voteToDismissMinister(ExecutiveTypes.MinistryKind.Finance);
    }

    function _seedPerson(bytes32 personId, address wallet) private {
        identity.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256(abi.encode("synthetic", personId)),
                metadataURI: "",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identity.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        stake.increaseStake(personId, 10_000);
    }

    function _member(uint256 index) private pure returns (address) {
        return address(uint160(0xC01 + index));
    }
}

/// @notice Demonstrates replacement continuity limits and safe user recovery with actual identity/office apps.
contract PredeploymentIdentityReviewTest is Test {
    bytes32 private constant OFFICE = keccak256("predeployment.identity");
    bytes32 private constant PERSON = bytes32(uint256(1));
    address private constant ADMIN = address(0x1DAD);
    address private constant CLERK = address(0x1C1E);
    address private constant WALLET = address(0xA11CE);
    address private constant DESTINATION = address(0xB0B);
    ConstitutionKernel private kernel;
    IdentityRegistry private identity;
    OfficeRegistry private offices;
    IdentityApp private app;
    CivicAppealReview private review;

    function setUp() public {
        vm.warp(1_900_000_000);
        kernel = new ConstitutionKernel(address(this));
        identity = new IdentityRegistry(address(kernel));
        offices = new OfficeRegistry(address(kernel));
        app = _newApp();
        review = _newReview(app);
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(app));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identity));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.CIVIC_APPEAL_AUTHORITY, address(review));
        offices.registerOffice(OFFICE, OfficeTypes.OfficeKind.IdentityOffice, "Synthetic Identity", ADMIN);
        offices.setClerkStatus(OFFICE, CLERK, true);
        kernel.disableBootstrapAuthority();
        vm.prank(ADMIN);
        app.registerIdentity(
            PERSON,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256("synthetic citizen"),
                metadataURI: "synthetic://predeployment",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.None,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        vm.prank(ADMIN);
        app.linkWallet(PERSON, WALLET, IdentityTypes.WalletLinkStatus.Active);
        vm.prank(WALLET);
        app.acceptInitialWallet(PERSON);
        vm.prank(ADMIN);
        app.setCitizenship(PERSON, IdentityTypes.CitizenshipStatus.Citizen);
    }

    function test_ApprovedMigrationIsNotImportedButUserCanCancelAndReauthorizeOnSuccessor() public {
        _approveMigration(app);
        bytes32 oldId = app.walletMigrationId(PERSON);
        IdentityApp successor = _newApp();
        kernel.governanceUpdateModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(successor));
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistry.UnauthorizedIdentityRegistryCaller.selector, address(app))
        );
        app.finalizeWalletMigration(PERSON);
        assertEq(app.walletMigrationId(PERSON), oldId);
        assertTrue(app.getWalletMigration(PERSON).approved);
        assertFalse(successor.getWalletMigration(PERSON).exists);
        assertEq(identity.activeWalletOf(PERSON), WALLET);

        vm.prank(WALLET);
        app.cancelWalletMigration(PERSON);
        _approveMigration(successor);
        assertNotEq(successor.walletMigrationId(PERSON), oldId);
        vm.warp(block.timestamp + 2 days);
        successor.finalizeWalletMigration(PERSON);
        assertEq(identity.activeWalletOf(PERSON), DESTINATION);
        assertEq(identity.activeWalletCountOf(PERSON), 1);
        assertFalse(identity.hasActiveWalletLink(WALLET));
    }

    function test_NewIdentityWriterNeedsItsOwnMatchingReviewCommitteeBeforeCivicApproval() public {
        IdentityApp successor = _newApp();
        kernel.governanceUpdateModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(successor));
        vm.prank(ADMIN);
        bytes32 request = successor.proposeCivicChange(PERSON, _suspension(), keccak256("synthetic grounds"));
        vm.prank(CLERK);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.UnauthorizedCivicReviewer.selector, address(review)));
        successor.approveCivicChange(PERSON, request);
        CivicAppealReview nextReview = _newReview(successor);
        kernel.governanceUpdateModule(KernelModuleIds.CIVIC_APPEAL_AUTHORITY, address(nextReview));
        vm.prank(CLERK);
        successor.approveCivicChange(PERSON, request);
        assertEq(successor.getCivicChange(PERSON).appealAuthority, address(nextReview));
        vm.prank(WALLET);
        successor.appealCivicChange(PERSON, request, keccak256("synthetic defence"));
        vm.warp(successor.getCivicChange(PERSON).appealDeadline);
        successor.expireCivicAppeal(PERSON, request);
        assertEq(successor.getCivicChange(PERSON).requestId, bytes32(0));
        assertEq(
            uint8(identity.getIdentityRecord(PERSON).citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.Citizen)
        );
    }

    function test_PinnedOldAppealCanStillExpireAfterWriterAndCommitteeReplacement() public {
        vm.prank(ADMIN);
        bytes32 request = app.proposeCivicChange(PERSON, _suspension(), keccak256("synthetic grounds"));
        vm.prank(CLERK);
        app.approveCivicChange(PERSON, request);
        vm.prank(WALLET);
        app.appealCivicChange(PERSON, request, keccak256("synthetic defence"));
        IdentityApp successor = _newApp();
        CivicAppealReview nextReview = _newReview(successor);
        kernel.governanceUpdateModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(successor));
        kernel.governanceUpdateModule(KernelModuleIds.CIVIC_APPEAL_AUTHORITY, address(nextReview));
        assertEq(app.getCivicChange(PERSON).appealAuthority, address(review));
        vm.warp(app.getCivicChange(PERSON).appealDeadline);
        app.expireCivicAppeal(PERSON, request);
        assertEq(app.getCivicChange(PERSON).requestId, bytes32(0));
        assertEq(
            uint8(identity.getIdentityRecord(PERSON).citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.Citizen)
        );
    }

    function _approveMigration(IdentityApp target) private {
        vm.prank(WALLET);
        target.requestWalletMigration(DESTINATION);
        bytes32 request = target.walletMigrationId(PERSON);
        vm.prank(DESTINATION);
        target.acceptWalletMigration(PERSON, request);
        vm.prank(ADMIN);
        target.approveWalletMigration(PERSON, request);
    }

    function _newApp() private returns (IdentityApp) {
        return new IdentityApp(address(identity), address(offices), OFFICE, 2 days);
    }

    function _newReview(IdentityApp target) private returns (CivicAppealReview) {
        return new CivicAppealReview(
            address(target), [address(0xA001), address(0xA002), address(0xA003), address(0xA004), address(0xA005)]
        );
    }

    function _suspension() private pure returns (IdentityTypes.CivicStatusInput memory) {
        return IdentityTypes.CivicStatusInput({
            verificationStatus: IdentityTypes.VerificationStatus.Verified,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.Suspended,
            ageClass: IdentityTypes.AgeClass.Adult,
            correctionFlag: false,
            finalSuspension: false
        });
    }
}
