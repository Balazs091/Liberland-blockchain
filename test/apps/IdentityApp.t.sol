// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {IdentityApp} from "../../contracts/apps/IdentityApp.sol";
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

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        officeRegistry = new OfficeRegistry(address(kernel));
        identityApp =
            new IdentityApp(address(identityRegistry), address(officeRegistry), IDENTITY_OFFICE_ID, MIGRATION_DELAY);

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
    }

    // --- A. Office-gated onboarding / management -------------------------------------------------------------

    function test_OfficeAdmin_RegistersLinksAndSetsCitizenshipPostGenesis() public {
        vm.prank(IDENTITY_ADMIN);
        identityApp.registerIdentity(PERSON_A, _citizenInput());
        vm.prank(IDENTITY_ADMIN);
        identityApp.linkWallet(PERSON_A, WALLET_A, IdentityTypes.WalletLinkStatus.Active);

        assertTrue(identityRegistry.hasActiveWalletLink(WALLET_A));
        assertEq(identityRegistry.resolveWalletToPersonId(WALLET_A), PERSON_A);
        assertEq(
            uint256(identityRegistry.getIdentityRecord(PERSON_A).citizenshipStatus),
            uint256(IdentityTypes.CitizenshipStatus.Citizen)
        );

        // setCitizenship rewrites only citizenship, preserving every other field.
        vm.prank(IDENTITY_ADMIN);
        identityApp.setCitizenship(PERSON_A, IdentityTypes.CitizenshipStatus.Suspended);

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

        // Re-granting citizenship requires an explicit office action; non-admins cannot flip it back.
        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityApp.UnauthorizedIdentityOfficer.selector, OUTSIDER, IDENTITY_OFFICE_ID)
        );
        identityApp.setCitizenship(PERSON_A, IdentityTypes.CitizenshipStatus.Citizen);

        vm.prank(IDENTITY_ADMIN);
        identityApp.setCitizenship(PERSON_A, IdentityTypes.CitizenshipStatus.Citizen);
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
        vm.prank(IDENTITY_CLERK);
        identityApp.approveWalletMigration(PERSON_A);

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

        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityApp.UnauthorizedIdentityOfficer.selector, OUTSIDER, IDENTITY_OFFICE_ID)
        );
        identityApp.approveWalletMigration(PERSON_A);

        // A double approval reverts as well.
        vm.prank(IDENTITY_ADMIN);
        identityApp.approveWalletMigration(PERSON_A);
        vm.prank(IDENTITY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IIdentityApp.MigrationAlreadyApproved.selector, PERSON_A));
        identityApp.approveWalletMigration(PERSON_A);
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
        vm.prank(IDENTITY_ADMIN);
        identityApp.approveWalletMigration(PERSON_A);
        vm.warp(block.timestamp + MIGRATION_DELAY);
        identityApp.finalizeWalletMigration(PERSON_A);

        assertEq(identityRegistry.activeWalletCountOf(PERSON_A), 1);
        // Re-activating the revoked old wallet while the new wallet is active must revert (no 2 active wallets).
        vm.prank(IDENTITY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistry.PersonAlreadyHasActiveWallet.selector, PERSON_A));
        identityApp.linkWallet(PERSON_A, WALLET_A, IdentityTypes.WalletLinkStatus.Active);
    }

    // --- helpers ---------------------------------------------------------------------------------------------

    function _registerCitizen(bytes32 personId, address wallet, IdentityTypes.IdentityRecordInput memory input)
        internal
    {
        vm.prank(IDENTITY_ADMIN);
        identityApp.registerIdentity(personId, input);
        vm.prank(IDENTITY_ADMIN);
        identityApp.linkWallet(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
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
