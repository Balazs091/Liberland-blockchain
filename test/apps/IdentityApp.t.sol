// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {IdentityApp} from "../../contracts/apps/IdentityApp.sol";
import {CivicAppealReview} from "../../contracts/apps/CivicAppealReview.sol";
import {ICivicAppealReview} from "../../contracts/interfaces/ICivicAppealReview.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IIdentityApp} from "../../contracts/interfaces/IIdentityApp.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

/// @title IdentityAppTest
/// @notice Covers the standing IdentityApp: office-gated lifecycle, caller-initiated renunciation, and the
///         timelocked, office-approved single-wallet migration that preserves person-keyed stake.
contract IdentityAppTest is Test {
    uint64 internal constant MIGRATION_DELAY = 2 days;
    bytes32 internal constant IDENTITY_OFFICE_ID = keccak256("office.identity");

    bytes32 internal constant PERSON_A = bytes32(uint256(1));
    bytes32 internal constant PERSON_B = bytes32(uint256(2));

    address internal constant IDENTITY_ADMIN = address(0x1DAD);
    address internal constant IDENTITY_CLERK = address(0x1C1E);
    address internal constant WALLET_A = address(0xA11CE);
    address internal constant WALLET_B = address(0xB0B);
    address internal constant WALLET_C = address(0xCACE);
    address internal constant OUTSIDER = address(0xBAD);

    event CitizenshipRenounced(bytes32 indexed personId, address indexed wallet, uint64 timestamp);
    event WalletMigrationRequested(
        bytes32 indexed personId, address indexed oldWallet, address indexed newWallet, uint64 requestedAt
    );
    event WalletMigrationFinalized(
        bytes32 indexed personId, address indexed oldWallet, address indexed newWallet, uint64 timestamp
    );

    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    OfficeRegistry internal officeRegistry;
    IdentityApp internal identityApp;
    CivicAppealReview internal civicReview;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        officeRegistry = new OfficeRegistry(address(kernel));
        identityApp =
            new IdentityApp(address(identityRegistry), address(officeRegistry), IDENTITY_OFFICE_ID, MIGRATION_DELAY);
        civicReview = new CivicAppealReview(
            address(identityApp), [address(0xA001), address(0xA002), address(0xA003), address(0xA004), address(0xA005)]
        );
        kernel.bootstrapSetModule(KernelModuleIds.CIVIC_APPEAL_AUTHORITY, address(civicReview));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));

        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(identityApp));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(stakeRegistry));
        // The test contract seeds "genesis" stake directly to prove staked LLM follows personId across migration.
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY, address(officeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(this));

        officeRegistry.registerOffice(
            IDENTITY_OFFICE_ID, OfficeTypes.OfficeKind.IdentityOffice, "Identity Office", IDENTITY_ADMIN
        );
        officeRegistry.setClerkStatus(IDENTITY_OFFICE_ID, IDENTITY_CLERK, true);

        kernel.disableBootstrapAuthority();
    }

    // --- Constructor -----------------------------------------------------------------------------------------

    function test_Constructor_StoresImmutables() public view {
        assertEq(identityApp.identityRegistry(), address(identityRegistry));
        assertEq(identityApp.officeRegistry(), address(officeRegistry));
        assertEq(identityApp.kernel(), address(kernel));
        assertEq(identityApp.identityOfficeId(), IDENTITY_OFFICE_ID);
        assertEq(identityApp.migrationDelay(), MIGRATION_DELAY);
    }

    function test_Constructor_RevertsOnInvalidConfiguration() public {
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InvalidIdentityRegistry.selector, address(0)));
        new IdentityApp(address(0), address(officeRegistry), IDENTITY_OFFICE_ID, MIGRATION_DELAY);

        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InvalidOfficeRegistry.selector, address(0)));
        new IdentityApp(address(identityRegistry), address(0), IDENTITY_OFFICE_ID, MIGRATION_DELAY);

        ConstitutionKernel otherKernel = new ConstitutionKernel(address(this));
        OfficeRegistry otherOfficeRegistry = new OfficeRegistry(address(otherKernel));
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityApp.KernelMismatch.selector, address(kernel), address(otherKernel))
        );
        new IdentityApp(address(identityRegistry), address(otherOfficeRegistry), IDENTITY_OFFICE_ID, MIGRATION_DELAY);

        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InvalidIdentityOffice.selector, bytes32(0)));
        new IdentityApp(address(identityRegistry), address(officeRegistry), bytes32(0), MIGRATION_DELAY);

        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InvalidMigrationDelay.selector, uint64(0)));
        new IdentityApp(address(identityRegistry), address(officeRegistry), IDENTITY_OFFICE_ID, 0);

        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InvalidMigrationDelay.selector, type(uint64).max));
        new IdentityApp(address(identityRegistry), address(officeRegistry), IDENTITY_OFFICE_ID, type(uint64).max);

        uint64 overMaximum = identityApp.MAX_MIGRATION_DELAY() + 1;
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InvalidMigrationDelay.selector, overMaximum));
        new IdentityApp(address(identityRegistry), address(officeRegistry), IDENTITY_OFFICE_ID, overMaximum);
    }

    // --- A. Office-gated onboarding / management -------------------------------------------------------------

    function test_OfficeAdmin_RegistersLinksAndSetsCitizenshipPostGenesis() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());

        assertTrue(identityRegistry.hasActiveWalletLink(WALLET_A));
        assertEq(identityRegistry.resolveWalletToPersonId(WALLET_A), PERSON_A);
        assertEq(
            uint256(identityRegistry.getIdentityRecord(PERSON_A).citizenshipStatus),
            uint256(IdentityTypes.CitizenshipStatus.Citizen)
        );

        // Direct adverse edits are no longer an admin power.
        vm.prank(IDENTITY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.UseCivicChangeProcedure.selector, PERSON_A));
        identityApp.setCitizenship(PERSON_A, IdentityTypes.CitizenshipStatus.Suspended);
        bytes32 requestId = _proposeSuspension(false);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveCivicChange(PERSON_A, requestId);
        vm.warp(block.timestamp + 7 days);
        identityApp.finalizeCivicChange(PERSON_A, requestId);

        IdentityTypes.IdentityRecord memory record = identityRegistry.getIdentityRecord(PERSON_A);
        assertEq(uint256(record.citizenshipStatus), uint256(IdentityTypes.CitizenshipStatus.Suspended));
        assertEq(record.metadataHash, keccak256("citizen-A"));
        assertEq(record.metadataURI, "ipfs://citizen-A");
        assertEq(uint256(record.verificationStatus), uint256(IdentityTypes.VerificationStatus.Verified));
        assertEq(uint256(record.ageClass), uint256(IdentityTypes.AgeClass.Adult));
    }

    function test_Management_RejectsNonAdminCallers() public {
        // Clerk cannot perform admin-only management actions.
        vm.prank(IDENTITY_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(
                IIdentityApp.UnauthorizedIdentityOfficer.selector, IDENTITY_CLERK, IDENTITY_OFFICE_ID
            )
        );
        identityApp.registerIdentity(PERSON_A, _citizenInput());

        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityApp.UnauthorizedIdentityOfficer.selector, OUTSIDER, IDENTITY_OFFICE_ID)
        );
        identityApp.setCitizenship(PERSON_A, IdentityTypes.CitizenshipStatus.Citizen);
    }

    // --- B. Citizen self-renunciation ------------------------------------------------------------------------

    function test_RenounceCitizenship_SetsNonePreservesFieldsAndKeepsWalletLink() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());

        vm.expectEmit(true, true, false, true, address(identityApp));
        emit CitizenshipRenounced(PERSON_A, WALLET_A, uint64(block.timestamp));
        vm.prank(WALLET_A);
        identityApp.renounceCitizenship();

        IdentityTypes.IdentityRecord memory record = identityRegistry.getIdentityRecord(PERSON_A);
        assertEq(uint256(record.citizenshipStatus), uint256(IdentityTypes.CitizenshipStatus.None));
        // Every other field preserved.
        assertEq(record.metadataHash, keccak256("citizen-A"));
        assertEq(record.metadataURI, "ipfs://citizen-A");
        assertEq(uint256(record.verificationStatus), uint256(IdentityTypes.VerificationStatus.Verified));
        assertEq(uint256(record.ageClass), uint256(IdentityTypes.AgeClass.Adult));
        assertFalse(record.correctionFlag);
        assertFalse(record.finalSuspension);
        // Wallet link intact so the person can still unstake their LLM.
        assertTrue(identityRegistry.hasActiveWalletLink(WALLET_A));
        assertEq(identityRegistry.resolveWalletToPersonId(WALLET_A), PERSON_A);
    }

    function test_RenounceCitizenship_RevertsForNonCitizenAndUnlinkedWallet() public {
        IdentityTypes.IdentityRecordInput memory eresident = _citizenInput();
        eresident.citizenshipStatus = IdentityTypes.CitizenshipStatus.EResident;
        _registerCitizen(PERSON_B, WALLET_B, eresident);

        vm.prank(WALLET_B);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.NotRenounceableCitizen.selector, WALLET_B, PERSON_B));
        identityApp.renounceCitizenship();

        // Unlinked wallet resolves to the zero person id.
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.NotRenounceableCitizen.selector, OUTSIDER, bytes32(0)));
        identityApp.renounceCitizenship();
    }

    function test_RenounceCitizenship_IsCallerControlledAndOfficeCannotForceIt() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());

        // The office cannot force a citizen to renounce: renounce always acts on the caller's own wallet.
        vm.prank(IDENTITY_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityApp.NotRenounceableCitizen.selector, IDENTITY_ADMIN, bytes32(0))
        );
        identityApp.renounceCitizenship();

        vm.prank(WALLET_A);
        identityApp.renounceCitizenship();
        assertEq(
            uint256(identityRegistry.getIdentityRecord(PERSON_A).citizenshipStatus),
            uint256(IdentityTypes.CitizenshipStatus.None)
        );

        // Reinstatement requires the two-officer civic process; the onboarding shortcut cannot be reused.
        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityApp.UnauthorizedIdentityOfficer.selector, OUTSIDER, IDENTITY_OFFICE_ID)
        );
        identityApp.setCitizenship(PERSON_A, IdentityTypes.CitizenshipStatus.Citizen);

        vm.prank(IDENTITY_ADMIN);
        bytes32 reinstatement = identityApp.proposeCivicChange(
            PERSON_A,
            IdentityTypes.CivicStatusInput({
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            }),
            keccak256("reinstatement evidence")
        );
        vm.prank(IDENTITY_CLERK);
        identityApp.approveCivicChange(PERSON_A, reinstatement);
        skip(7 days);
        identityApp.finalizeCivicChange(PERSON_A, reinstatement);
        assertEq(
            uint256(identityRegistry.getIdentityRecord(PERSON_A).citizenshipStatus),
            uint256(IdentityTypes.CitizenshipStatus.Citizen)
        );
    }

    // --- C. Timelocked, office-approved wallet migration -----------------------------------------------------

    function test_WalletMigration_HappyPathPreservesStakeAndOneActiveWallet() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        stakeRegistry.increaseStake(PERSON_A, 10_000);
        assertEq(stakeRegistry.activeStakeOf(PERSON_A), 10_000);

        vm.expectEmit(true, true, true, true, address(identityApp));
        emit WalletMigrationRequested(PERSON_A, WALLET_A, WALLET_B, uint64(block.timestamp));
        vm.prank(WALLET_A);
        identityApp.requestWalletMigration(WALLET_B);

        // Finalize before office approval reverts.
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.MigrationNotApproved.selector, PERSON_A));
        identityApp.finalizeWalletMigration(PERSON_A);

        // Approval by a clerk (admin-or-clerk gate) starts the timelock.
        bytes32 requestId = _acceptMigration(PERSON_A, WALLET_B);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveWalletMigration(PERSON_A, requestId);

        uint64 readyAt = uint64(block.timestamp) + MIGRATION_DELAY;

        // Finalize before the post-approval delay elapses reverts.
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.MigrationDelayNotElapsed.selector, PERSON_A, readyAt));
        identityApp.finalizeWalletMigration(PERSON_A);

        // Finalize after the delay is callable by anyone and swaps the active wallet A -> B.
        vm.warp(readyAt);
        vm.expectEmit(true, true, true, true, address(identityApp));
        emit WalletMigrationFinalized(PERSON_A, WALLET_A, WALLET_B, uint64(block.timestamp));
        vm.prank(OUTSIDER);
        identityApp.finalizeWalletMigration(PERSON_A);

        assertEq(identityRegistry.resolveWalletToPersonId(WALLET_B), PERSON_A);
        assertTrue(identityRegistry.hasActiveWalletLink(WALLET_B));
        assertFalse(identityRegistry.hasActiveWalletLink(WALLET_A));
        assertEq(
            uint256(identityRegistry.getWalletLink(WALLET_A).status), uint256(IdentityTypes.WalletLinkStatus.Revoked)
        );
        assertEq(identityRegistry.activeWalletCountOf(PERSON_A), 1);
        // Staked LLM followed the personId, untouched by the wallet swap.
        assertEq(stakeRegistry.activeStakeOf(PERSON_A), 10_000);
        assertFalse(identityApp.getWalletMigration(PERSON_A).exists);
    }

    function test_WalletMigration_RevertsToAlreadyLinkedNewWallet() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        _registerCitizen(PERSON_B, WALLET_B, _citizenInput());

        vm.prank(WALLET_A);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.NewWalletAlreadyLinked.selector, WALLET_B, PERSON_B));
        identityApp.requestWalletMigration(WALLET_B);
    }

    function test_WalletMigration_RejectsSecondPendingAndBadNewWallet() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());

        // Cannot migrate to the zero wallet or to the caller's own wallet.
        vm.prank(WALLET_A);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InvalidNewWallet.selector, address(0)));
        identityApp.requestWalletMigration(address(0));
        vm.prank(WALLET_A);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InvalidNewWallet.selector, WALLET_A));
        identityApp.requestWalletMigration(WALLET_A);

        // An unlinked caller cannot request a migration.
        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.WalletNotLinked.selector, OUTSIDER));
        identityApp.requestWalletMigration(WALLET_B);

        // First request succeeds; a second pending request for the same person reverts.
        vm.prank(WALLET_A);
        identityApp.requestWalletMigration(WALLET_B);
        vm.prank(WALLET_A);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.MigrationAlreadyPending.selector, PERSON_A));
        identityApp.requestWalletMigration(WALLET_C);
    }

    function test_WalletMigration_ApproveRequiresOfficer() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        vm.prank(WALLET_A);
        identityApp.requestWalletMigration(WALLET_B);
        bytes32 requestId = _acceptMigration(PERSON_A, WALLET_B);

        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityApp.UnauthorizedIdentityOfficer.selector, OUTSIDER, IDENTITY_OFFICE_ID)
        );
        identityApp.approveWalletMigration(PERSON_A, requestId);

        // A double approval reverts as well.
        vm.prank(IDENTITY_ADMIN);
        identityApp.approveWalletMigration(PERSON_A, requestId);
        vm.prank(IDENTITY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.MigrationAlreadyApproved.selector, PERSON_A));
        identityApp.approveWalletMigration(PERSON_A, requestId);
    }

    function test_WalletMigration_CancelByOldWalletAndByOffice() public {
        // Cancel by the recorded old wallet.
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        vm.prank(WALLET_A);
        identityApp.requestWalletMigration(WALLET_B);

        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityApp.UnauthorizedMigrationCanceller.selector, OUTSIDER, PERSON_A)
        );
        identityApp.cancelWalletMigration(PERSON_A);

        vm.prank(WALLET_A);
        identityApp.cancelWalletMigration(PERSON_A);
        assertFalse(identityApp.getWalletMigration(PERSON_A).exists);

        // Cancel by an identity officer (clerk) during the window.
        vm.prank(WALLET_A);
        identityApp.requestWalletMigration(WALLET_B);
        vm.prank(IDENTITY_CLERK);
        identityApp.cancelWalletMigration(PERSON_A);
        assertFalse(identityApp.getWalletMigration(PERSON_A).exists);
    }

    function test_WalletMigration_OneActiveWalletInvariantHoldsAfterFinalize() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        vm.prank(WALLET_A);
        identityApp.requestWalletMigration(WALLET_B);
        bytes32 requestId = _acceptMigration(PERSON_A, WALLET_B);
        vm.prank(IDENTITY_ADMIN);
        identityApp.approveWalletMigration(PERSON_A, requestId);
        vm.warp(block.timestamp + MIGRATION_DELAY);
        identityApp.finalizeWalletMigration(PERSON_A);

        assertEq(identityRegistry.activeWalletCountOf(PERSON_A), 1);
        // Re-activating the revoked old wallet while the new wallet is active must revert (no 2 active wallets).
        vm.prank(IDENTITY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InitialWalletOnly.selector, PERSON_A));
        identityApp.linkWallet(PERSON_A, WALLET_A, IdentityTypes.WalletLinkStatus.Active);
    }

    function test_Governance_NoRecordOverwriteOrDirectRebinding() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        vm.startPrank(IDENTITY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.IdentityAlreadyRegistered.selector, PERSON_A));
        identityApp.registerIdentity(PERSON_A, _citizenInput());
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InitialWalletOnly.selector, PERSON_A));
        identityApp.linkWallet(PERSON_A, WALLET_A, IdentityTypes.WalletLinkStatus.Revoked);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.InitialWalletOnly.selector, PERSON_A));
        identityApp.linkWallet(PERSON_A, WALLET_B, IdentityTypes.WalletLinkStatus.Active);
        vm.stopPrank();
        assertEq(identityRegistry.activeWalletOf(PERSON_A), WALLET_A);
    }

    function test_Governance_InitialWalletRequiresConsent() public {
        IdentityTypes.IdentityRecordInput memory input = _citizenInput();
        input.citizenshipStatus = IdentityTypes.CitizenshipStatus.None;
        vm.startPrank(IDENTITY_ADMIN);
        identityApp.registerIdentity(PERSON_A, input);
        identityApp.linkWallet(PERSON_A, WALLET_A, IdentityTypes.WalletLinkStatus.Active);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.DestinationConsentRequired.selector, PERSON_A));
        identityApp.acceptInitialWallet(PERSON_A);
        vm.stopPrank();
        assertEq(identityRegistry.activeWalletOf(PERSON_A), address(0));
        vm.prank(WALLET_A);
        identityApp.acceptInitialWallet(PERSON_A);
        assertEq(identityRegistry.activeWalletOf(PERSON_A), WALLET_A);
    }

    function test_Governance_MigrationConsentAndNoncePreventStaleApproval() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        vm.prank(WALLET_A);
        identityApp.requestWalletMigration(WALLET_B);
        bytes32 firstId = identityApp.walletMigrationId(PERSON_A);
        vm.prank(IDENTITY_CLERK);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.DestinationConsentRequired.selector, PERSON_A));
        identityApp.approveWalletMigration(PERSON_A, firstId);
        vm.prank(WALLET_A);
        identityApp.cancelWalletMigration(PERSON_A);
        vm.prank(WALLET_A);
        identityApp.requestWalletMigration(WALLET_B);
        bytes32 secondId = _acceptMigration(PERSON_A, WALLET_B);
        assertNotEq(firstId, secondId);
        vm.prank(IDENTITY_CLERK);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.StaleRequest.selector, secondId, firstId));
        identityApp.approveWalletMigration(PERSON_A, firstId);
        assertFalse(identityApp.getWalletMigration(PERSON_A).approved);
    }

    function test_Governance_RecoveryNeedsEvidenceSecondOfficerConsentAndSevenDays() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        stakeRegistry.increaseStake(PERSON_A, 10_000);
        vm.startPrank(IDENTITY_ADMIN);
        vm.expectRevert(IIdentityApp.InvalidEvidenceHash.selector);
        identityApp.proposeWalletRecovery(PERSON_A, WALLET_B, bytes32(0));
        identityApp.proposeWalletRecovery(PERSON_A, WALLET_B, keccak256("lost key evidence"));
        vm.stopPrank();
        bytes32 requestId = _acceptMigration(PERSON_A, WALLET_B);
        vm.prank(IDENTITY_ADMIN);
        vm.expectRevert(IIdentityApp.DistinctOfficerRequired.selector);
        identityApp.approveWalletMigration(PERSON_A, requestId);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveWalletMigration(PERSON_A, requestId);
        uint64 ready = uint64(block.timestamp + 7 days);
        vm.warp(ready - 1);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.MigrationDelayNotElapsed.selector, PERSON_A, ready));
        identityApp.finalizeWalletMigration(PERSON_A);
        vm.warp(ready);
        vm.prank(OUTSIDER); // No old-wallet signature is needed to recover a genuinely lost key.
        identityApp.finalizeWalletMigration(PERSON_A);
        assertEq(identityRegistry.activeWalletOf(PERSON_A), WALLET_B);
        assertEq(identityRegistry.activeWalletCountOf(PERSON_A), 1);
        assertEq(stakeRegistry.activeStakeOf(PERSON_A), 10_000);
    }

    function test_Governance_OldWalletCanChallengeRecovery() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        vm.prank(IDENTITY_ADMIN);
        identityApp.proposeWalletRecovery(PERSON_A, WALLET_B, keccak256("contested claim"));
        bytes32 requestId = _acceptMigration(PERSON_A, WALLET_B);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveWalletMigration(PERSON_A, requestId);
        vm.prank(WALLET_A);
        identityApp.cancelWalletMigration(PERSON_A);
        vm.warp(block.timestamp + 7 days);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.MigrationNotFound.selector, PERSON_A));
        identityApp.finalizeWalletMigration(PERSON_A);
        assertEq(identityRegistry.activeWalletOf(PERSON_A), WALLET_A);
    }

    function test_Governance_RevokedOfficerCannotLeaveExecutableRecoveryApproval() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        vm.prank(IDENTITY_ADMIN);
        identityApp.proposeWalletRecovery(PERSON_A, WALLET_B, keccak256("lost key"));
        bytes32 requestId = _acceptMigration(PERSON_A, WALLET_B);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveWalletMigration(PERSON_A, requestId);
        officeRegistry.setClerkStatus(IDENTITY_OFFICE_ID, IDENTITY_CLERK, false);
        vm.warp(block.timestamp + 7 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                IIdentityApp.UnauthorizedIdentityOfficer.selector, IDENTITY_CLERK, IDENTITY_OFFICE_ID
            )
        );
        identityApp.finalizeWalletMigration(PERSON_A);
    }

    function test_Governance_CivicNoticeMetadataIsolationAndFinalSuspensionReversal() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        bytes32 requestId = _proposeSuspension(true);
        vm.prank(IDENTITY_ADMIN);
        vm.expectRevert(IIdentityApp.DistinctOfficerRequired.selector);
        identityApp.approveCivicChange(PERSON_A, requestId);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveCivicChange(PERSON_A, requestId);
        vm.prank(IDENTITY_ADMIN);
        identityApp.correctMetadata(PERSON_A, keccak256("corrected metadata"), "ipfs://correction");
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.CivicChangeNotReady.selector, PERSON_A));
        identityApp.finalizeCivicChange(PERSON_A, requestId);
        vm.warp(block.timestamp + 7 days);
        identityApp.finalizeCivicChange(PERSON_A, requestId);
        assertTrue(identityRegistry.getIdentityRecord(PERSON_A).finalSuspension);
        assertEq(identityRegistry.getIdentityRecord(PERSON_A).metadataURI, "ipfs://correction");
        vm.startPrank(IDENTITY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.UseCivicChangeProcedure.selector, PERSON_A));
        identityApp.setCitizenship(PERSON_A, IdentityTypes.CitizenshipStatus.Citizen);
        bytes32 reversal = identityApp.proposeCivicChange(
            PERSON_A,
            IdentityTypes.CivicStatusInput({
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            }),
            keccak256("reversal judgment")
        );
        vm.stopPrank();
        vm.prank(IDENTITY_CLERK);
        identityApp.approveCivicChange(PERSON_A, reversal);
        vm.warp(block.timestamp + 7 days);
        identityApp.finalizeCivicChange(PERSON_A, reversal);
        assertFalse(identityRegistry.getIdentityRecord(PERSON_A).finalSuspension);
    }

    function test_CivicSubjectCannotDeleteOrReappealAnUpheldChange() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        bytes32 requestId = _proposeSuspension(true);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveCivicChange(PERSON_A, requestId);
        skip(7 days - 1);
        vm.prank(WALLET_A);
        vm.expectPartialRevert(IIdentityApp.UnauthorizedIdentityOfficer.selector);
        identityApp.cancelCivicChange(PERSON_A, requestId);
        vm.prank(WALLET_A);
        identityApp.appealCivicChange(PERSON_A, requestId, keccak256("appeal evidence"));
        for (uint256 i; i < 3; ++i) {
            vm.prank(civicReview.reviewerAt(i));
            civicReview.castRulingVote(PERSON_A, requestId, true, keccak256("reasoned ruling"), true);
        }
        civicReview.executeRuling(PERSON_A, requestId, true, keccak256("reasoned ruling"));
        vm.prank(WALLET_A);
        vm.expectPartialRevert(IIdentityApp.CivicAppealNotOpen.selector);
        identityApp.appealCivicChange(PERSON_A, requestId, keccak256("repeat"));
        skip(2 days);
        identityApp.finalizeCivicChange(PERSON_A, requestId);
        assertTrue(identityRegistry.getIdentityRecord(PERSON_A).finalSuspension);
    }

    function test_Governance_OfficerWithdrawalAndRenunciationInvalidateStaleRequests() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        bytes32 firstId = _proposeSuspension(true);
        vm.prank(IDENTITY_CLERK);
        identityApp.cancelCivicChange(PERSON_A, firstId);
        bytes32 secondId = _proposeSuspension(true);
        assertNotEq(firstId, secondId);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveCivicChange(PERSON_A, secondId);
        vm.prank(WALLET_A);
        identityApp.renounceCitizenship();
        vm.warp(block.timestamp + 7 days);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.StaleRequest.selector, bytes32(0), secondId));
        identityApp.finalizeCivicChange(PERSON_A, secondId);
        assertEq(
            uint8(identityRegistry.getIdentityRecord(PERSON_A).citizenshipStatus),
            uint8(IdentityTypes.CitizenshipStatus.None)
        );
    }

    function test_CivicAppealNeedsThreeMatchingDistinctApprovals() public {
        bytes32 id = _openAppeal();
        bytes32 evidence = keccak256("ruling reasons");
        for (uint256 i; i < 2; ++i) {
            vm.prank(civicReview.reviewerAt(i));
            civicReview.castRulingVote(PERSON_A, id, true, evidence, true);
        }
        vm.prank(civicReview.reviewerAt(0));
        civicReview.castRulingVote(PERSON_A, id, true, evidence, true);
        assertEq(civicReview.rulingSupport(PERSON_A, id, true, evidence), 2);
        vm.expectRevert(abi.encodeWithSelector(ICivicAppealReview.InsufficientRulingSupport.selector, 2));
        civicReview.executeRuling(PERSON_A, id, true, evidence);
        vm.prank(civicReview.reviewerAt(2));
        civicReview.castRulingVote(PERSON_A, id, false, evidence, true);
        assertEq(civicReview.rulingSupport(PERSON_A, id, true, evidence), 2);
        assertEq(civicReview.rulingSupport(PERSON_A, id, false, evidence), 1);
        assertEq(civicReview.rulingSupport(PERSON_A, id, true, keccak256("different reasons")), 0);
        vm.prank(civicReview.reviewerAt(2));
        civicReview.castRulingVote(PERSON_A, id, true, evidence, true);
        civicReview.executeRuling(PERSON_A, id, true, evidence);
        vm.expectPartialRevert(ICivicAppealReview.InvalidAppeal.selector);
        civicReview.executeRuling(PERSON_A, id, true, evidence);
    }

    function test_CivicAppealUpholdingNeverShortensOriginalNotice() public {
        bytes32 id = _openAppeal();
        uint64 originalReady = identityApp.getCivicChange(PERSON_A).readyAt;
        _castRuling(id, true);
        assertEq(identityApp.getCivicChange(PERSON_A).readyAt, originalReady);
        vm.warp(originalReady - 1);
        vm.expectPartialRevert(IIdentityApp.CivicChangeNotReady.selector);
        identityApp.finalizeCivicChange(PERSON_A, id);
        vm.warp(originalReady);
        identityApp.finalizeCivicChange(PERSON_A, id);
        assertTrue(identityRegistry.getIdentityRecord(PERSON_A).finalSuspension);
    }

    function test_CivicAppealTimeoutDismissesAndRejectsLateRulings() public {
        bytes32 id = _openAppeal();
        uint64 deadline = identityApp.getCivicChange(PERSON_A).appealDeadline;
        vm.warp(deadline - 1);
        vm.expectPartialRevert(IIdentityApp.CivicAppealNotOpen.selector);
        identityApp.expireCivicAppeal(PERSON_A, id);
        vm.warp(deadline);
        vm.expectPartialRevert(IIdentityApp.CivicChangeNotReady.selector);
        identityApp.finalizeCivicChange(PERSON_A, id);
        vm.prank(civicReview.reviewerAt(0));
        vm.expectPartialRevert(ICivicAppealReview.InvalidAppeal.selector);
        civicReview.castRulingVote(PERSON_A, id, true, keccak256("late"), true);
        vm.prank(OUTSIDER);
        identityApp.expireCivicAppeal(PERSON_A, id);
        assertEq(identityApp.getCivicChange(PERSON_A).requestId, bytes32(0));
        assertFalse(identityRegistry.getIdentityRecord(PERSON_A).finalSuspension);
    }

    function test_CivicDismissalCannotBeReusedOnAReproposedCase() public {
        bytes32 oldId = _openAppeal();
        _castRuling(oldId, false);
        assertFalse(identityRegistry.getIdentityRecord(PERSON_A).finalSuspension);
        bytes32 newId = _proposeSuspension(true);
        assertNotEq(oldId, newId);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveCivicChange(PERSON_A, newId);
        vm.prank(WALLET_A);
        identityApp.appealCivicChange(PERSON_A, newId, keccak256("new appeal"));
        assertEq(civicReview.rulingSupport(PERSON_A, newId, false, keccak256("ruling")), 0);
        vm.expectPartialRevert(ICivicAppealReview.InvalidAppeal.selector);
        civicReview.executeRuling(PERSON_A, oldId, false, keccak256("ruling"));
    }

    function test_CivicCommitteeReplacementCannotTakeOverAnExistingNotice() public {
        bytes32 id = _openAppeal();
        CivicAppealReview replacement = new CivicAppealReview(
            address(identityApp), [address(0xB001), address(0xB002), address(0xB003), address(0xB004), address(0xB005)]
        );
        kernel.governanceUpdateModule(KernelModuleIds.CIVIC_APPEAL_AUTHORITY, address(replacement));
        assertEq(identityApp.getCivicChange(PERSON_A).appealAuthority, address(civicReview));
        vm.prank(replacement.reviewerAt(0));
        vm.expectPartialRevert(ICivicAppealReview.InvalidAppeal.selector);
        replacement.castRulingVote(PERSON_A, id, true, keccak256("ruling"), true);
        _castRuling(id, false);
    }

    function test_CivicReviewerIndependenceIsRecheckedAtExecution() public {
        bytes32 id = _openAppeal();
        for (uint256 i; i < 3; ++i) {
            vm.prank(civicReview.reviewerAt(i));
            civicReview.castRulingVote(PERSON_A, id, true, keccak256("ruling"), true);
        }
        officeRegistry.setClerkStatus(IDENTITY_OFFICE_ID, civicReview.reviewerAt(0), true);
        assertEq(civicReview.rulingSupport(PERSON_A, id, true, keccak256("ruling")), 2);
        vm.expectRevert(abi.encodeWithSelector(ICivicAppealReview.InsufficientRulingSupport.selector, 2));
        civicReview.executeRuling(PERSON_A, id, true, keccak256("ruling"));
        vm.prank(civicReview.reviewerAt(3));
        civicReview.castRulingVote(PERSON_A, id, true, keccak256("ruling"), true);
        civicReview.executeRuling(PERSON_A, id, true, keccak256("ruling"));
    }

    function test_CivicReviewerCanWithdrawApproval() public {
        bytes32 id = _openAppeal();
        vm.startPrank(civicReview.reviewerAt(0));
        civicReview.castRulingVote(PERSON_A, id, true, keccak256("ruling"), true);
        civicReview.castRulingVote(PERSON_A, id, true, keccak256("ruling"), false);
        vm.stopPrank();
        assertEq(civicReview.rulingSupport(PERSON_A, id, true, keccak256("ruling")), 0);
    }

    function test_CivicAppealCannotBeFiledWithoutApprovalOrAtNoticeDeadline() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        bytes32 id = _proposeSuspension(true);
        vm.prank(WALLET_A);
        vm.expectPartialRevert(IIdentityApp.CivicAppealNotOpen.selector);
        identityApp.appealCivicChange(PERSON_A, id, keccak256("appeal"));
        vm.prank(IDENTITY_CLERK);
        identityApp.approveCivicChange(PERSON_A, id);
        vm.prank(WALLET_A);
        vm.expectRevert(IIdentityApp.InvalidEvidenceHash.selector);
        identityApp.appealCivicChange(PERSON_A, id, bytes32(0));
        vm.warp(identityApp.getCivicChange(PERSON_A).readyAt);
        vm.prank(WALLET_A);
        vm.expectPartialRevert(IIdentityApp.CivicAppealNotOpen.selector);
        identityApp.appealCivicChange(PERSON_A, id, keccak256("late"));
        identityApp.finalizeCivicChange(PERSON_A, id);
    }

    function test_CivicRulingCannotComeDirectlyFromAnOfficerOrReviewer() public {
        bytes32 id = _openAppeal();
        vm.prank(IDENTITY_ADMIN);
        vm.expectPartialRevert(IIdentityApp.UnauthorizedCivicReviewer.selector);
        identityApp.resolveCivicAppeal(PERSON_A, id, true, keccak256("ruling"));
        vm.prank(civicReview.reviewerAt(0));
        vm.expectPartialRevert(IIdentityApp.UnauthorizedCivicReviewer.selector);
        identityApp.resolveCivicAppeal(PERSON_A, id, true, keccak256("ruling"));
    }

    function test_RecoveryApprovalCannotSurviveSameBlockReappointment() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        vm.prank(IDENTITY_ADMIN);
        identityApp.proposeWalletRecovery(PERSON_A, WALLET_B, keccak256("recovery"));
        bytes32 id = _acceptMigration(PERSON_A, WALLET_B);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveWalletMigration(PERSON_A, id);
        officeRegistry.setClerkStatus(IDENTITY_OFFICE_ID, IDENTITY_CLERK, false);
        officeRegistry.setClerkStatus(IDENTITY_OFFICE_ID, IDENTITY_CLERK, true);
        skip(7 days);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.StaleOfficerAuthorization.selector, IDENTITY_CLERK));
        identityApp.finalizeWalletMigration(PERSON_A);
    }

    function test_CivicApprovalCannotSurviveSameBlockReappointment() public {
        bytes32 id = _openAppeal();
        _castRuling(id, true);
        officeRegistry.setClerkStatus(IDENTITY_OFFICE_ID, IDENTITY_CLERK, false);
        officeRegistry.setClerkStatus(IDENTITY_OFFICE_ID, IDENTITY_CLERK, true);
        skip(7 days);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.StaleOfficerAuthorization.selector, IDENTITY_CLERK));
        identityApp.finalizeCivicChange(PERSON_A, id);
    }

    function test_CivicSubjectCannotWithdrawOwnCaseUsingAnOfficerAppointment() public {
        bytes32 id = _openAppeal();
        officeRegistry.setClerkStatus(IDENTITY_OFFICE_ID, WALLET_A, true);
        vm.prank(WALLET_A);
        vm.expectPartialRevert(IIdentityApp.CivicAppealNotOpen.selector);
        identityApp.cancelCivicChange(PERSON_A, id);
        assertEq(identityApp.getCivicChange(PERSON_A).requestId, id);
    }

    function test_RenunciationCannotReopenTheOneOfficerOnboardingGrant() public {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        vm.prank(WALLET_A);
        identityApp.renounceCitizenship();
        vm.prank(IDENTITY_ADMIN);
        vm.expectPartialRevert(IIdentityApp.UseCivicChangeProcedure.selector);
        identityApp.setCitizenship(PERSON_A, IdentityTypes.CitizenshipStatus.Citizen);
    }

    function _openAppeal() internal returns (bytes32 id) {
        _registerCitizen(PERSON_A, WALLET_A, _citizenInput());
        id = _proposeSuspension(true);
        vm.prank(IDENTITY_CLERK);
        identityApp.approveCivicChange(PERSON_A, id);
        vm.prank(WALLET_A);
        identityApp.appealCivicChange(PERSON_A, id, keccak256("appeal"));
    }

    function _castRuling(bytes32 id, bool uphold) internal {
        for (uint256 i; i < 3; ++i) {
            vm.prank(civicReview.reviewerAt(i));
            civicReview.castRulingVote(PERSON_A, id, uphold, keccak256("ruling"), true);
        }
        civicReview.executeRuling(PERSON_A, id, uphold, keccak256("ruling"));
    }

    // --- helpers ---------------------------------------------------------------------------------------------

    function _registerCitizen(bytes32 personId, address wallet, IdentityTypes.IdentityRecordInput memory input)
        internal
    {
        bool grant = input.citizenshipStatus == IdentityTypes.CitizenshipStatus.Citizen;
        if (grant) input.citizenshipStatus = IdentityTypes.CitizenshipStatus.None;
        vm.prank(IDENTITY_ADMIN);
        identityApp.registerIdentity(personId, input);
        vm.prank(IDENTITY_ADMIN);
        identityApp.linkWallet(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        vm.prank(wallet);
        identityApp.acceptInitialWallet(personId);
        if (grant) {
            vm.prank(IDENTITY_ADMIN);
            identityApp.setCitizenship(personId, IdentityTypes.CitizenshipStatus.Citizen);
        }
    }

    function _acceptMigration(bytes32 personId, address destination) internal returns (bytes32 requestId) {
        requestId = identityApp.walletMigrationId(personId);
        vm.prank(destination);
        identityApp.acceptWalletMigration(personId, requestId);
    }

    function _proposeSuspension(bool finalSuspension) internal returns (bytes32 requestId) {
        vm.prank(IDENTITY_ADMIN);
        return identityApp.proposeCivicChange(
            PERSON_A,
            IdentityTypes.CivicStatusInput({
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Suspended,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: finalSuspension
            }),
            keccak256("documented grounds")
        );
    }

    function _citizenInput() internal pure returns (IdentityTypes.IdentityRecordInput memory input) {
        input = IdentityTypes.IdentityRecordInput({
            metadataHash: keccak256("citizen-A"),
            metadataURI: "ipfs://citizen-A",
            verificationStatus: IdentityTypes.VerificationStatus.Verified,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
            ageClass: IdentityTypes.AgeClass.Adult,
            correctionFlag: false,
            finalSuspension: false
        });
    }
}
