// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {LlmBackedUSDCFixture} from "../apps/LlmBackedUSDC.t.sol";
import {USDCLendingPoolApp} from "../../contracts/apps/USDCLendingPoolApp.sol";
import {LandRegistryApp} from "../../contracts/apps/LandRegistryApp.sol";
import {CompanyRegistryApp} from "../../contracts/apps/CompanyRegistryApp.sol";
import {MinistryTreasury} from "../../contracts/apps/MinistryTreasury.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IInterestRatePolicy} from "../../contracts/interfaces/IInterestRatePolicy.sol";
import {IUSDCLendingPoolApp} from "../../contracts/interfaces/IUSDCLendingPoolApp.sol";
import {ILandRegistry} from "../../contracts/interfaces/ILandRegistry.sol";
import {ILandRegistryApp} from "../../contracts/interfaces/ILandRegistryApp.sol";
import {ICompanyRegistry} from "../../contracts/interfaces/ICompanyRegistry.sol";
import {ICompanyRegistryApp} from "../../contracts/interfaces/ICompanyRegistryApp.sol";
import {IMinistryTreasury} from "../../contracts/interfaces/IMinistryTreasury.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {OfficePermissionPolicy} from "../../contracts/policies/OfficePermissionPolicy.sol";
import {LandPartyPolicy} from "../../contracts/policies/LandPartyPolicy.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {LandRegistry} from "../../contracts/registries/LandRegistry.sol";
import {CompanyRegistry} from "../../contracts/registries/CompanyRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";
import {LandTypes} from "../../contracts/types/LandTypes.sol";
import {CompanyTypes} from "../../contracts/types/CompanyTypes.sol";

contract UnusablePredeploymentRatePolicy is IInterestRatePolicy {
    error RateUnavailable();

    function ray() external pure returns (uint256) {
        return 1e27;
    }

    function borrowRatePerSecond(uint256) external pure returns (uint256) {
        revert RateUnavailable();
    }

    function supplyRatePerSecond(uint256, uint16) external pure returns (uint256) {
        revert RateUnavailable();
    }
}

/// @notice User settlement across real pool instances; kernel caller is a test timelock, not a referendum harness.
contract PredeploymentLendingReviewTest is LlmBackedUSDCFixture {
    function _sealGovernanceHarness() private {
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));
        kernel.disableBootstrapAuthority();
    }

    function _successor() private returns (USDCLendingPoolApp) {
        return new USDCLendingPoolApp(
            address(kernel),
            address(usdc),
            address(identityRegistry),
            address(stakeRegistry),
            address(stakeLienRegistry),
            BORROW_CAP
        );
    }

    function _replaceAll(USDCLendingPoolApp successor) private {
        kernel.governanceUpdateModule(KernelModuleIds.USDC_LENDING_POOL_APP, address(successor));
        kernel.governanceUpdateModule(KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY, address(successor));
        kernel.governanceUpdateModule(KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY, address(successor));
    }

    function test_RetiredBorrowerCanSettleAfterRevocationAndLpCanExitOldPool() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);
        USDCLendingPoolApp successor = _successor();
        _sealGovernanceHarness();
        _replaceAll(successor);
        IdentityTypes.IdentityRecordInput memory revoked = _defaultIdentityInput();
        revoked.citizenshipStatus = IdentityTypes.CitizenshipStatus.Revoked;
        vm.prank(address(identityAuthority));
        identityRegistry.setIdentityRecord(BORROWER_PERSON_ID, revoked);

        usdc.mint(LIQUIDATOR, 1_000 * USDC_UNIT);
        vm.startPrank(LIQUIDATOR);
        usdc.approve(address(lendingPool), type(uint256).max);
        lendingPool.repayFor(BORROWER_PERSON_ID, type(uint256).max);
        vm.stopPrank();
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        assertEq(stakeLienRegistry.lienedStakeOf(BORROWER_PERSON_ID), 0);
        assertEq(successor.totalBorrows(), 0);
        vm.prank(LP);
        lendingPool.withdraw(10_000 * USDC_UNIT, LP);
        assertEq(lendingPool.balanceOf(LP), 0);
        assertEq(usdc.balanceOf(LP), 10_000 * USDC_UNIT);
    }

    function test_AllSixPointerActivationOrdersPreserveOldRepaymentAndBlockDoubleLoans() public {
        for (uint256 selected; selected < 6; ++selected) {
            uint256 snapshot = vm.snapshotState();
            _exerciseActivationOrder(selected);
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function _exerciseActivationOrder(uint256 selected) private {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);
        USDCLendingPoolApp successor = _successor();
        _sealGovernanceHarness();
        bytes32[3] memory ids = [
            KernelModuleIds.USDC_LENDING_POOL_APP,
            KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY,
            KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY
        ];
        uint8[3][6] memory orders = [
            [uint8(0), 1, 2], [uint8(0), 2, 1], [uint8(1), 0, 2], [uint8(1), 2, 0], [uint8(2), 0, 1], [uint8(2), 1, 0]
        ];
        usdc.mint(LIQUIDATOR, 1_000 * USDC_UNIT);
        vm.prank(LIQUIDATOR);
        usdc.approve(address(lendingPool), type(uint256).max);
        for (uint256 i; i < 3; ++i) {
            kernel.governanceUpdateModule(ids[orders[selected][i]], address(successor));
            assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 0);
            vm.prank(BORROWER);
            vm.expectRevert(IUSDCLendingPoolApp.RetiredLendingPool.selector);
            lendingPool.borrow(1);
            vm.prank(BORROWER);
            vm.expectRevert(); // Partial activation or a still-owned old book; neither permits a second loan.
            successor.borrow(1);
            vm.prank(LIQUIDATOR);
            lendingPool.repayFor(BORROWER_PERSON_ID, 100 * USDC_UNIT);
            assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), (900 - i * 100) * USDC_UNIT);
        }
        vm.prank(LIQUIDATOR);
        lendingPool.repayFor(BORROWER_PERSON_ID, type(uint256).max);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        usdc.mint(LP, 2_000 * USDC_UNIT);
        vm.startPrank(LP);
        usdc.approve(address(successor), 2_000 * USDC_UNIT);
        successor.deposit(2_000 * USDC_UNIT, LP);
        vm.stopPrank();
        vm.prank(BORROWER);
        successor.borrow(1_000 * USDC_UNIT);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(successor));
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
        assertEq(successor.currentDebtOf(BORROWER_PERSON_ID), 1_000 * USDC_UNIT);
    }

    function test_BadLiveRateBlocksOngoingDebtButNotLastRepaymentAndDebtFreeExit() public {
        vm.prank(BORROWER);
        lendingPool.borrow(1_000 * USDC_UNIT);
        _sealGovernanceHarness();
        UnusablePredeploymentRatePolicy unusable = new UnusablePredeploymentRatePolicy();
        kernel.governanceUpdateModule(KernelModuleIds.USDC_INTEREST_RATE_POLICY, address(unusable));
        vm.prank(BORROWER);
        usdc.approve(address(lendingPool), type(uint256).max);
        uint256 oldShares = lendingPool.balanceOf(LP);
        uint256 oldDebt = lendingPool.currentDebtOf(BORROWER_PERSON_ID);
        uint256 cash = usdc.balanceOf(address(lendingPool));
        vm.prank(BORROWER);
        vm.expectRevert(UnusablePredeploymentRatePolicy.RateUnavailable.selector);
        lendingPool.repayFor(BORROWER_PERSON_ID, 100 * USDC_UNIT);
        vm.prank(LP);
        vm.expectRevert(UnusablePredeploymentRatePolicy.RateUnavailable.selector);
        lendingPool.withdraw(100 * USDC_UNIT, LP);
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), oldDebt);
        assertEq(lendingPool.balanceOf(LP), oldShares);
        assertEq(usdc.balanceOf(address(lendingPool)), cash);
        vm.prank(BORROWER);
        lendingPool.repayFor(BORROWER_PERSON_ID, type(uint256).max);
        vm.prank(LP);
        lendingPool.withdraw(10_000 * USDC_UNIT, LP);
        assertEq(lendingPool.balanceOf(LP), 0);
        assertEq(stakeLienRegistry.loanBookOf(BORROWER_PERSON_ID), address(0));
        vm.prank(BORROWER);
        vm.expectRevert(UnusablePredeploymentRatePolicy.RateUnavailable.selector);
        lendingPool.borrow(1);
    }

    function test_RetiredMinistryTreasuryOldPoolExitUsesCurrentOfficeRecords() public {
        bytes32 officeId = keccak256("predeployment.finance");
        OfficeRegistry originalOffices = new OfficeRegistry(address(kernel));
        MinistryTreasury ministry = new MinistryTreasury(address(kernel));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY, address(originalOffices));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.MINISTRY_TREASURY_FUNDING_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.MINISTRY_TREASURY, address(ministry));
        originalOffices.registerOffice(
            officeId, OfficeTypes.OfficeKind.MinistryOfFinance, "Synthetic Finance", BORROWER
        );
        usdc.mint(address(this), 500 * USDC_UNIT);
        usdc.approve(address(ministry), 500 * USDC_UNIT);
        ministry.fund(officeId, address(usdc), address(this), 500 * USDC_UNIT);
        vm.prank(BORROWER);
        ministry.supplyToPool(officeId, 400 * USDC_UNIT);
        uint256 shares = ministry.poolSharesAt(officeId, address(lendingPool));
        _sealGovernanceHarness();
        MinistryTreasury successor = new MinistryTreasury(address(kernel));
        OfficeRegistry nextOffices = new OfficeRegistry(address(kernel));
        kernel.governanceUpdateModule(KernelModuleIds.MINISTRY_TREASURY, address(successor));
        kernel.governanceUpdateModule(KernelModuleIds.OFFICE_REGISTRY, address(nextOffices));
        // The old treasury keeps its balances/shares, but it resolves role facts from the CURRENT office ledger.
        vm.prank(BORROWER);
        vm.expectRevert(abi.encodeWithSelector(IMinistryTreasury.InvalidMinistryOffice.selector, officeId));
        ministry.withdrawFromPoolAt(officeId, address(lendingPool), 400 * USDC_UNIT);
        assertEq(ministry.poolSharesAt(officeId, address(lendingPool)), shares);
        assertEq(ministry.balanceOf(officeId, address(usdc)), 100 * USDC_UNIT);
        nextOffices.registerOffice(officeId, OfficeTypes.OfficeKind.MinistryOfFinance, "Synthetic Finance", BORROWER);
        vm.prank(BORROWER);
        ministry.withdrawFromPoolAt(officeId, address(lendingPool), 400 * USDC_UNIT);
        assertEq(ministry.poolSharesAt(officeId, address(lendingPool)), 0);
        assertEq(ministry.balanceOf(officeId, address(usdc)), 500 * USDC_UNIT);
        assertEq(successor.balanceOf(officeId, address(usdc)), 0);
        uint256 before = usdc.balanceOf(BORROWER);
        vm.prank(BORROWER);
        ministry.spend(officeId, address(usdc), BORROWER, 500 * USDC_UNIT);
        assertEq(usdc.balanceOf(BORROWER), before + 500 * USDC_UNIT);
        assertEq(ministry.balanceOf(officeId, address(usdc)), 0);
    }
}

/// @notice Owner, applicant and registrar journeys across canonical land/company app replacement.
contract PredeploymentPropertyReviewTest is Test {
    bytes32 private constant LAND_OFFICE = keccak256("predeployment.land.office");
    bytes32 private constant COMPANY_OFFICE = keccak256("predeployment.company.office");
    bytes32 private constant PARCEL = keccak256("predeployment.parcel");
    bytes32 private constant TITLE = keccak256("predeployment.title");
    bytes32 private constant SELLER_PERSON = keccak256("predeployment.seller");
    bytes32 private constant BUYER_PERSON = keccak256("predeployment.buyer");
    uint256 private constant SELLER_KEY = 0xA11CE;
    uint256 private constant BUYER_KEY = 0xB0B;
    address private constant ADMIN = address(0xA001);

    ConstitutionKernel private kernel;
    IdentityRegistry private identity;
    OfficeRegistry private offices;
    LandRegistry private land;
    CompanyRegistry private companies;
    OfficePermissionPolicy private permission;
    LandPartyPolicy private partyPolicy;
    LandRegistryApp private landApp;
    CompanyRegistryApp private companyApp;
    address private seller;
    address private buyer;

    function setUp() public {
        seller = vm.addr(SELLER_KEY);
        buyer = vm.addr(BUYER_KEY);
        kernel = new ConstitutionKernel(address(this));
        identity = new IdentityRegistry(address(kernel));
        offices = new OfficeRegistry(address(kernel));
        land = new LandRegistry(address(kernel));
        companies = new CompanyRegistry(address(kernel));
        permission = new OfficePermissionPolicy();
        partyPolicy = new LandPartyPolicy(address(identity), address(companies), address(offices));
        landApp = _newLandApp();
        companyApp = new CompanyRegistryApp(address(companies), address(offices), address(permission), COMPANY_OFFICE);
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY, address(land));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY_APP, address(landApp));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY, address(landApp));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY, address(companies));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY_APP, address(companyApp));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY_AUTHORITY, address(companyApp));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_PERMISSION_POLICY, address(permission));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_PARTY_POLICY, address(partyPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));
        offices.registerOffice(LAND_OFFICE, OfficeTypes.OfficeKind.LandRegistryOffice, "Synthetic land", ADMIN);
        offices.registerOffice(COMPANY_OFFICE, OfficeTypes.OfficeKind.CompanyRegistryOffice, "Synthetic company", ADMIN);
        _register(SELLER_PERSON, seller);
        _register(BUYER_PERSON, buyer);
        kernel.disableBootstrapAuthority();
        vm.startPrank(ADMIN);
        landApp.submitParcelDraft(PARCEL, _parcelInput(keccak256("genesis")), keccak256("tx.draft"));
        LandTypes.ParcelRecord memory draft = land.getParcel(PARCEL);
        landApp.activateParcel(
            PARCEL, draft.revision, _anchor(keccak256("activate"), draft.versionHash), keccak256("tx.activate")
        );
        landApp.registerTitle(
            TITLE,
            LandTypes.TitleInput({
                parcelId: PARCEL,
                holder: _party(SELLER_PERSON),
                anchor: _anchor(keccak256("title"), land.getParcel(PARCEL).versionHash),
                tenureType: LandTypes.TenureType.Freehold,
                leaseExpiresAt: 0
            }),
            keccak256("tx.title")
        );
        vm.stopPrank();
    }

    function test_LandAppReplacementPreservesOwnerButRequiresFreshConsent() public {
        LandTypes.TitleTransferRequest memory request = _request();
        bytes32 oldDigest = landApp.hashTitleTransferAuthorization(request);
        bytes memory sellerConsent = _signature(SELLER_KEY, oldDigest);
        bytes memory buyerConsent = _signature(BUYER_KEY, oldDigest);
        LandRegistryApp original = landApp;
        landApp = _newLandApp();
        kernel.governanceUpdateModule(KernelModuleIds.LAND_REGISTRY_APP, address(landApp));
        kernel.governanceUpdateModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY, address(landApp));
        assertEq(land.getTitle(TITLE).holder.id, SELLER_PERSON);
        vm.prank(ADMIN);
        vm.expectPartialRevert(ILandRegistry.UnauthorizedLandRegistryCaller.selector);
        original.transferTitle(request, seller, sellerConsent, buyer, buyerConsent);
        assertEq(original.titleTransferNonce(TITLE), 0);
        vm.prank(ADMIN);
        vm.expectPartialRevert(ILandRegistryApp.InvalidSignature.selector);
        landApp.transferTitle(request, seller, sellerConsent, buyer, buyerConsent);
        assertEq(landApp.titleTransferNonce(TITLE), 0);
        bytes32 newDigest = landApp.hashTitleTransferAuthorization(request);
        assertTrue(oldDigest != newDigest);
        sellerConsent = _signature(SELLER_KEY, newDigest);
        buyerConsent = _signature(BUYER_KEY, newDigest);
        vm.prank(ADMIN);
        landApp.transferTitle(request, seller, sellerConsent, buyer, buyerConsent);
        assertEq(land.getTitle(TITLE).holder.id, BUYER_PERSON);
        assertEq(landApp.titleTransferNonce(TITLE), 1);
    }

    function test_MultipleAcceptedDisputesSurviveReplacementAndReleaseIndependently() public {
        bytes32 first = keccak256("dispute.first");
        bytes32 second = keccak256("dispute.second");
        _fileAndAccept(first);
        _fileAndAccept(second);
        assertEq(land.activeDisputeCountOf(PARCEL), 2);
        landApp = _newLandApp();
        kernel.governanceUpdateModule(KernelModuleIds.LAND_REGISTRY_APP, address(landApp));
        kernel.governanceUpdateModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY, address(landApp));
        vm.startPrank(ADMIN);
        landApp.resolveDispute(first, keccak256("first.reason"), false, keccak256("first.resolve"));
        assertEq(land.activeDisputeCountOf(PARCEL), 1);
        assertEq(uint8(land.getParcel(PARCEL).status), uint8(LandTypes.ParcelStatus.Disputed));
        landApp.resolveDispute(second, keccak256("second.reason"), false, keccak256("second.resolve"));
        vm.stopPrank();
        assertEq(land.activeDisputeCountOf(PARCEL), 0);
        assertEq(uint8(land.getParcel(PARCEL).status), uint8(LandTypes.ParcelStatus.Active));
        assertEq(land.getTitle(TITLE).holder.id, SELLER_PERSON);
        _transferWithFreshConsent();
        assertEq(land.getTitle(TITLE).holder.id, BUYER_PERSON);
    }

    function test_AcceptedDisputeHasNoAutomaticTimeoutEvenAfterLongInactivity() public {
        _fileAndAccept(keccak256("dispute.no-timeout"));
        skip(100 * 365 days);
        assertEq(land.activeDisputeCountOf(PARCEL), 1);
        LandTypes.TitleTransferRequest memory request = _request();
        bytes32 digest = landApp.hashTitleTransferAuthorization(request);
        bytes memory sellerConsent = _signature(SELLER_KEY, digest);
        bytes memory buyerConsent = _signature(BUYER_KEY, digest);
        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ILandRegistry.InvalidParcelStatus.selector, LandTypes.ParcelStatus.Disputed)
        );
        landApp.transferTitle(request, seller, sellerConsent, buyer, buyerConsent);
        assertEq(landApp.titleTransferNonce(TITLE), 0);
        assertEq(land.getTitle(TITLE).holder.id, SELLER_PERSON);
    }

    function test_PendingCompanyApplicantCanCompleteAfterOfficeAppReplacement() public {
        bytes32 companyId = keccak256("pending.company");
        CompanyTypes.CompanyInput memory input = CompanyTypes.CompanyInput({
            registrationNumberHash: 0,
            nameHash: keccak256("company.name"),
            jurisdictionHash: keccak256("jurisdiction"),
            registeredOfficeHash: keccak256("registered-office"),
            metadataHash: keccak256("metadata"),
            articlesHash: keccak256("articles"),
            uboHash: keccak256("ubo"),
            registeredCapital: 1_000
        });
        vm.prank(seller);
        companyApp.submitIncorporation(companyId, input);
        CompanyRegistryApp original = companyApp;
        companyApp = new CompanyRegistryApp(address(companies), address(offices), address(permission), COMPANY_OFFICE);
        kernel.governanceUpdateModule(KernelModuleIds.COMPANY_REGISTRY_APP, address(companyApp));
        kernel.governanceUpdateModule(KernelModuleIds.COMPANY_REGISTRY_AUTHORITY, address(companyApp));
        vm.prank(ADMIN);
        vm.expectPartialRevert(ICompanyRegistry.UnauthorizedCompanyRegistryCaller.selector);
        original.approveCompany(companyId, keccak256("registration.number"));
        assertEq(uint8(companies.getCompany(companyId).status), uint8(CompanyTypes.CompanyStatus.Pending));
        vm.prank(ADMIN);
        companyApp.approveCompany(companyId, keccak256("registration.number"));
        assertEq(uint8(companies.getCompany(companyId).status), uint8(CompanyTypes.CompanyStatus.Active));
        assertEq(companies.getCompany(companyId).founder, seller);
    }

    function test_PredeploymentApiCompanyMetadataMaintenanceAndShareClassPause() public {
        // These are the actual bindings a company-management screen needs before it submits a transaction.
        assertEq(companyApp.companyRegistry(), address(companies));
        assertEq(companyApp.officeRegistry(), address(offices));
        assertEq(companyApp.officePermissionPolicy(), address(permission));
        assertEq(companyApp.companyRegistryOfficeId(), COMPANY_OFFICE);
        bytes32 companyId = keccak256("api.company");
        bytes32 classId = keccak256("api.company.class");
        CompanyTypes.CompanyInput memory input = CompanyTypes.CompanyInput({
            registrationNumberHash: 0,
            nameHash: keccak256("api.company.name"),
            jurisdictionHash: keccak256("api.jurisdiction"),
            registeredOfficeHash: keccak256("api.registered-office"),
            metadataHash: keccak256("api.original.metadata"),
            articlesHash: keccak256("api.original.articles"),
            uboHash: keccak256("api.ubo"),
            registeredCapital: 1_000
        });
        vm.prank(seller);
        companyApp.submitIncorporation(companyId, input);
        vm.prank(ADMIN);
        companyApp.approveCompany(companyId, keccak256("api.registration"));
        bytes32 updatedMetadata = keccak256("api.corrected.metadata");
        bytes32 updatedArticles = keccak256("api.corrected.articles");
        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompanyRegistryApp.UnauthorizedCompanyRegistryOfficeAction.selector,
                seller,
                COMPANY_OFFICE,
                OfficeTypes.OfficeActionClass.ManageCompanyRegistry
            )
        );
        companyApp.updateCompanyMetadata(companyId, updatedMetadata, updatedArticles);
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyPayload.selector, companyId));
        companyApp.updateCompanyMetadata(companyId, 0, updatedArticles);
        assertEq(companies.getCompany(companyId).metadataHash, input.metadataHash);
        vm.prank(ADMIN);
        companyApp.updateCompanyMetadata(companyId, updatedMetadata, updatedArticles);
        assertEq(companies.getCompany(companyId).metadataHash, updatedMetadata);
        assertEq(companies.getCompany(companyId).articlesHash, updatedArticles);
        assertEq(companies.getCompany(companyId).founder, seller);

        vm.startPrank(ADMIN);
        companyApp.registerShareClass(companyId, classId, keccak256("api.class.metadata"), 1_000, 10_000, false);
        companyApp.issueShares(companyId, classId, seller, 100, keccak256("api.issue.initial"));
        vm.stopPrank();
        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompanyRegistryApp.UnauthorizedCompanyRegistryOfficeAction.selector,
                seller,
                COMPANY_OFFICE,
                OfficeTypes.OfficeActionClass.ManageCompanyRegistry
            )
        );
        companyApp.setShareClassStatus(companyId, classId, false);
        vm.prank(ADMIN);
        companyApp.setShareClassStatus(companyId, classId, false);
        assertFalse(companies.getShareClass(companyId, classId).active);
        assertEq(companies.shareBalanceOf(companyId, classId, seller), 100);
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ICompanyRegistry.InvalidShareClass.selector, classId));
        companyApp.issueShares(companyId, classId, seller, 1, keccak256("api.issue.paused"));
        vm.startPrank(ADMIN);
        companyApp.setShareClassStatus(companyId, classId, true);
        companyApp.issueShares(companyId, classId, seller, 25, keccak256("api.issue.resumed"));
        vm.stopPrank();
        assertTrue(companies.getShareClass(companyId, classId).active);
        assertEq(companies.getShareClass(companyId, classId).issuedShares, 125);
        assertEq(companies.shareBalanceOf(companyId, classId, seller), 125);
        vm.prank(ADMIN);
        companyApp.setCompanyStatus(companyId, CompanyTypes.CompanyStatus.Dissolved, keccak256("api.dissolution"));
        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyStatus.selector, CompanyTypes.CompanyStatus.Dissolved)
        );
        companyApp.updateCompanyMetadata(companyId, keccak256("after.dissolution"), updatedArticles);
        assertEq(companies.getCompany(companyId).metadataHash, updatedMetadata);
    }

    function test_PredeploymentApiCorrectDraftThenActivateWithoutChangingAnActiveParcel() public {
        assertEq(landApp.landRegistry(), address(land));
        assertEq(landApp.officeRegistry(), address(offices));
        assertEq(landApp.officePermissionPolicy(), address(permission));
        assertEq(landApp.landPartyPolicy(), address(partyPolicy));
        assertEq(landApp.landOfficeId(), LAND_OFFICE);
        bytes32 parcelId = keccak256("api.draft");
        LandTypes.ParcelInput memory input = _parcelInput(keccak256("api.draft.genesis"));
        input.parcelNumberHash = keccak256("api.draft.number");
        vm.prank(ADMIN);
        landApp.submitParcelDraft(parcelId, input, keccak256("api.draft.submit"));
        LandTypes.ParcelRecord memory before = land.getParcel(parcelId);
        input.areaSquareMeters = 12_000;
        input.spatialDataHash = keccak256("api.corrected.geometry");
        input.anchor = _anchor(keccak256("api.corrected.parcel"), before.versionHash);
        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILandRegistryApp.UnauthorizedLandRegistryOfficeAction.selector,
                seller,
                LAND_OFFICE,
                OfficeTypes.OfficeActionClass.PrepareLandRecords
            )
        );
        landApp.updateParcelDraft(parcelId, before.revision, input, keccak256("api.draft.correct"));
        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILandRegistry.StaleParcelRevision.selector, parcelId, before.revision + 1, before.revision
            )
        );
        landApp.updateParcelDraft(parcelId, before.revision + 1, input, keccak256("api.draft.correct"));
        vm.prank(ADMIN);
        landApp.updateParcelDraft(parcelId, before.revision, input, keccak256("api.draft.correct"));
        LandTypes.ParcelRecord memory corrected = land.getParcel(parcelId);
        assertEq(corrected.areaSquareMeters, 12_000);
        assertEq(corrected.spatialDataHash, input.spatialDataHash);
        assertEq(corrected.anchor.lineageHash, before.versionHash);
        assertEq(corrected.revision, before.revision + 1);
        assertEq(uint8(corrected.status), uint8(LandTypes.ParcelStatus.Draft));
        LandTypes.RecordAnchor memory activation = _anchor(keccak256("api.draft.activation"), corrected.versionHash);
        vm.prank(ADMIN);
        landApp.activateParcel(parcelId, corrected.revision, activation, keccak256("api.draft.activate"));
        LandTypes.ParcelRecord memory active = land.getParcel(parcelId);
        input.anchor.lineageHash = active.versionHash;
        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ILandRegistry.InvalidParcelStatus.selector, LandTypes.ParcelStatus.Active)
        );
        landApp.updateParcelDraft(parcelId, active.revision, input, keccak256("api.active.draft-edit"));
        assertEq(land.getParcel(parcelId).versionHash, active.versionHash);
    }

    function test_PredeploymentApiRetireUntitledParcelAfterResolvingItsLock() public {
        LandTypes.ParcelRecord memory titled = land.getParcel(PARCEL);
        LandTypes.RecordAnchor memory invalidRetirement = _anchor(keccak256("api.titled.retire"), titled.versionHash);
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.InvalidParcelPayload.selector, PARCEL));
        landApp.retireParcel(PARCEL, titled.revision, invalidRetirement, keccak256("api.titled.retirement"));
        assertEq(land.getTitle(TITLE).holder.id, SELLER_PERSON);

        bytes32 parcelId = keccak256("api.retirement.parcel");
        bytes32 disputeId = keccak256("api.retirement.dispute");
        LandTypes.ParcelInput memory input = _parcelInput(keccak256("api.retirement.genesis"));
        input.parcelNumberHash = keccak256("api.retirement.number");
        vm.prank(ADMIN);
        landApp.submitParcelDraft(parcelId, input, keccak256("api.retirement.draft"));
        LandTypes.ParcelRecord memory draft = land.getParcel(parcelId);
        LandTypes.RecordAnchor memory activation = _anchor(keccak256("api.retirement.activation"), draft.versionHash);
        vm.prank(ADMIN);
        landApp.activateParcel(parcelId, draft.revision, activation, keccak256("api.retirement.activate"));
        LandTypes.PartyRef memory claimant = _party(BUYER_PERSON);
        vm.prank(buyer);
        landApp.fileDispute(disputeId, parcelId, claimant, keccak256("api.evidence"), keccak256("api.dispute.file"));
        vm.prank(ADMIN);
        landApp.acceptDispute(disputeId, 0, keccak256("api.dispute.accept"));
        LandTypes.ParcelRecord memory locked = land.getParcel(parcelId);
        LandTypes.RecordAnchor memory retirement = _anchor(keccak256("api.retirement"), locked.versionHash);
        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILandRegistryApp.UnauthorizedLandRegistryOfficeAction.selector,
                seller,
                LAND_OFFICE,
                OfficeTypes.OfficeActionClass.FinalizeLandRecords
            )
        );
        landApp.retireParcel(parcelId, locked.revision, retirement, keccak256("api.retirement.tx"));
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.ParcelTransferLocked.selector, parcelId));
        landApp.retireParcel(parcelId, locked.revision, retirement, keccak256("api.retirement.tx"));
        assertEq(land.getParcel(parcelId).versionHash, locked.versionHash);
        vm.prank(ADMIN);
        landApp.resolveDispute(disputeId, keccak256("api.resolution"), false, keccak256("api.dispute.resolve"));
        LandTypes.ParcelRecord memory unlocked = land.getParcel(parcelId);
        retirement.lineageHash = unlocked.versionHash;
        vm.prank(ADMIN);
        landApp.retireParcel(parcelId, unlocked.revision, retirement, keccak256("api.retirement.tx"));
        LandTypes.ParcelRecord memory retired = land.getParcel(parcelId);
        assertEq(uint8(retired.status), uint8(LandTypes.ParcelStatus.Retired));
        assertEq(retired.revision, unlocked.revision + 1);
        assertEq(retired.anchor.lineageHash, unlocked.versionHash);
        assertEq(retired.lastTransactionId, keccak256("api.retirement.tx"));
        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ILandRegistry.InvalidParcelStatus.selector, LandTypes.ParcelStatus.Retired)
        );
        landApp.retireParcel(parcelId, retired.revision, retirement, keccak256("api.retirement.duplicate"));
    }

    function _newLandApp() private returns (LandRegistryApp) {
        return
            new LandRegistryApp(address(land), address(offices), address(permission), address(partyPolicy), LAND_OFFICE);
    }

    function _register(bytes32 personId, address wallet) private {
        identity.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256(abi.encode(personId)),
                metadataURI: "synthetic://predeployment-review",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identity.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
    }

    function _fileAndAccept(bytes32 disputeId) private {
        LandTypes.PartyRef memory claimant = _party(BUYER_PERSON);
        vm.prank(buyer);
        landApp.fileDispute(
            disputeId, PARCEL, claimant, keccak256("evidence"), keccak256(abi.encode(disputeId, "file"))
        );
        vm.prank(ADMIN);
        landApp.acceptDispute(disputeId, 0, keccak256(abi.encode(disputeId, "accept")));
    }

    function _transferWithFreshConsent() private {
        LandTypes.TitleTransferRequest memory request = _request();
        bytes32 digest = landApp.hashTitleTransferAuthorization(request);
        bytes memory sellerConsent = _signature(SELLER_KEY, digest);
        bytes memory buyerConsent = _signature(BUYER_KEY, digest);
        vm.prank(ADMIN);
        landApp.transferTitle(request, seller, sellerConsent, buyer, buyerConsent);
    }

    function _request() private view returns (LandTypes.TitleTransferRequest memory) {
        LandTypes.TitleRecord memory title = land.getTitle(TITLE);
        return LandTypes.TitleTransferRequest({
            titleId: TITLE,
            expectedVersionHash: title.versionHash,
            expectedParcelVersionHash: land.getParcel(PARCEL).versionHash,
            newHolder: _party(BUYER_PERSON),
            anchor: _anchor(keccak256("transfer"), title.versionHash),
            transactionId: keccak256("tx.transfer"),
            nonce: landApp.titleTransferNonce(TITLE),
            deadline: uint64(block.timestamp + 1 days)
        });
    }

    function _party(bytes32 personId) private view returns (LandTypes.PartyRef memory) {
        return LandTypes.PartyRef({namespace: partyPolicy.personNamespace(), id: personId});
    }

    function _signature(uint256 key, bytes32 digest) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _parcelInput(bytes32 lineage) private pure returns (LandTypes.ParcelInput memory) {
        return LandTypes.ParcelInput({
            parcelNumberHash: keccak256("number"),
            districtHash: keccak256("district"),
            anchor: _anchor(keccak256("parcel"), lineage),
            spatialDataHash: keccak256("geometry"),
            coordinateReferenceSystemHash: keccak256("crs"),
            spatialType: LandTypes.SpatialType.Polygon,
            areaSquareMeters: 10_000
        });
    }

    function _anchor(bytes32 content, bytes32 lineage) private pure returns (LandTypes.RecordAnchor memory) {
        return LandTypes.RecordAnchor({
            schemaId: keccak256("schema"),
            contentHash: content,
            sourceDocumentHash: keccak256("document"),
            lineageHash: lineage,
            schemaVersion: 1
        });
    }
}
