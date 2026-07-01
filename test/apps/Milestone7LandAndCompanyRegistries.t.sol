// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {CompanyRegistryApp} from "../../contracts/apps/CompanyRegistryApp.sol";
import {LandRegistryApp} from "../../contracts/apps/LandRegistryApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ICompanyRegistry} from "../../contracts/interfaces/ICompanyRegistry.sol";
import {ICompanyRegistryApp} from "../../contracts/interfaces/ICompanyRegistryApp.sol";
import {ILandRegistry} from "../../contracts/interfaces/ILandRegistry.sol";
import {ILandRegistryApp} from "../../contracts/interfaces/ILandRegistryApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {OfficePermissionPolicy} from "../../contracts/policies/OfficePermissionPolicy.sol";
import {CompanyRegistry} from "../../contracts/registries/CompanyRegistry.sol";
import {LandRegistry} from "../../contracts/registries/LandRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {CompanyTypes} from "../../contracts/types/CompanyTypes.sol";
import {LandTypes} from "../../contracts/types/LandTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

/// @title Milestone7LandAndCompanyRegistriesTest
/// @notice Covers v1 office-authorized land and company registry workflows.
contract Milestone7LandAndCompanyRegistriesTest is Test {
    bytes32 internal constant LAND_OFFICE_ID = keccak256("office.land");
    bytes32 internal constant COMPANY_REGISTRY_OFFICE_ID = keccak256("office.company-registry");

    bytes32 internal constant PARCEL_ID = keccak256("parcel.one");
    bytes32 internal constant PARCEL_TWO_ID = keccak256("parcel.two");
    bytes32 internal constant TITLE_ID = keccak256("title.one");
    bytes32 internal constant DISPUTE_ID = keccak256("dispute.one");
    bytes32 internal constant ENCUMBRANCE_ONE_ID = keccak256("encumbrance.one");
    bytes32 internal constant ENCUMBRANCE_TWO_ID = keccak256("encumbrance.two");

    bytes32 internal constant COMPANY_ID = keccak256("company.one");
    bytes32 internal constant COMPANY_TWO_ID = keccak256("company.two");
    bytes32 internal constant REGISTRATION_NUMBER_HASH = keccak256("LLC-0001");
    bytes32 internal constant REGISTRATION_TWO_NUMBER_HASH = keccak256("LLC-0002");
    bytes32 internal constant SHARE_CLASS_A = keccak256("share-class.a");
    bytes32 internal constant SHARE_CLASS_B = keccak256("share-class.b");
    bytes32 internal constant FILING_ID = keccak256("filing.one");

    address internal constant LAND_ADMIN = address(0x1A01);
    address internal constant LAND_CLERK = address(0x1A02);
    address internal constant COMPANY_ADMIN = address(0xC001);
    address internal constant COMPANY_CLERK = address(0xC002);
    address internal constant OWNER_ONE = address(0xBEEF);
    address internal constant OWNER_TWO = address(0xCAFE);
    address internal constant CLAIMANT = address(0xD15C);
    address internal constant FOUNDER = address(0xF00D);
    address internal constant DIRECTOR = address(0xD1EC);
    address internal constant INVESTOR = address(0xA11CE);
    address internal constant OUTSIDER = address(0xBAD);

    ConstitutionKernel internal kernel;
    OfficeRegistry internal officeRegistry;
    OfficePermissionPolicy internal officePermissionPolicy;
    LandRegistry internal landRegistry;
    CompanyRegistry internal companyRegistry;
    LandRegistryApp internal landRegistryApp;
    CompanyRegistryApp internal companyRegistryApp;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        officeRegistry = new OfficeRegistry(address(kernel));
        officePermissionPolicy = new OfficePermissionPolicy();
        landRegistry = new LandRegistry(address(kernel));
        companyRegistry = new CompanyRegistry(address(kernel));
        landRegistryApp = new LandRegistryApp(
            address(landRegistry), address(officeRegistry), address(officePermissionPolicy), LAND_OFFICE_ID
        );
        companyRegistryApp = new CompanyRegistryApp(
            address(companyRegistry),
            address(officeRegistry),
            address(officePermissionPolicy),
            COMPANY_REGISTRY_OFFICE_ID
        );

        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY, address(officeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_PERMISSION_POLICY, address(officePermissionPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY, address(landRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY_APP, address(landRegistryApp));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY, address(landRegistryApp));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY, address(companyRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY_APP, address(companyRegistryApp));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY_AUTHORITY, address(companyRegistryApp));

        officeRegistry.registerOffice(
            LAND_OFFICE_ID, OfficeTypes.OfficeKind.LandRegistryOffice, "Land Registry Office", LAND_ADMIN
        );
        officeRegistry.setClerkStatus(LAND_OFFICE_ID, LAND_CLERK, true);
        officeRegistry.registerOffice(
            COMPANY_REGISTRY_OFFICE_ID,
            OfficeTypes.OfficeKind.CompanyRegistryOffice,
            "Company Registry Office",
            COMPANY_ADMIN
        );
        officeRegistry.setClerkStatus(COMPANY_REGISTRY_OFFICE_ID, COMPANY_CLERK, true);

        kernel.disableBootstrapAuthority();
    }

    function test_Milestone7InterfacesExposeSelectors() public pure {
        assertTrue(ILandRegistry.createParcel.selector != bytes4(0));
        assertTrue(ILandRegistry.registerTitle.selector != bytes4(0));
        assertTrue(ILandRegistryApp.fileDispute.selector != bytes4(0));
        assertTrue(ILandRegistryApp.registerEncumbrance.selector != bytes4(0));
        assertTrue(ICompanyRegistry.submitCompany.selector != bytes4(0));
        assertTrue(ICompanyRegistry.registerShareClass.selector != bytes4(0));
        assertTrue(ICompanyRegistryApp.submitIncorporation.selector != bytes4(0));
        assertTrue(ICompanyRegistryApp.recordFiling.selector != bytes4(0));
    }

    function test_LandRegistryOffice_CanCreateActivateRegisterAndTransferTitle() public {
        vm.prank(LAND_CLERK);
        landRegistryApp.submitParcelDraft(PARCEL_ID, _parcelInput("parcel.one"));

        LandTypes.ParcelRecord memory parcelRecord = landRegistry.getParcel(PARCEL_ID);
        assertEq(parcelRecord.parcelId, PARCEL_ID);
        assertEq(uint256(parcelRecord.status), uint256(LandTypes.ParcelStatus.Draft));
        assertEq(landRegistry.totalParcelCount(), 1);

        vm.prank(LAND_ADMIN);
        landRegistryApp.activateParcel(PARCEL_ID, keccak256("parcel.activation"));

        vm.prank(LAND_ADMIN);
        landRegistryApp.registerTitle(TITLE_ID, _titleInput(PARCEL_ID, OWNER_ONE));

        assertEq(landRegistry.activeTitleOfParcel(PARCEL_ID), TITLE_ID);
        LandTypes.TitleRecord memory titleRecord = landRegistry.getTitle(TITLE_ID);
        assertEq(titleRecord.holder, OWNER_ONE);
        assertTrue(titleRecord.active);

        vm.prank(LAND_CLERK);
        landRegistryApp.transferTitle(TITLE_ID, OWNER_TWO, keccak256("title.transfer"));

        titleRecord = landRegistry.getTitle(TITLE_ID);
        assertEq(titleRecord.holder, OWNER_TWO);
    }

    function test_LandRegistry_DisputesAndEncumbrancesLockTransfersOnlyWhenActive() public {
        _activateParcelWithTitle(PARCEL_ID, TITLE_ID, OWNER_ONE);

        vm.prank(CLAIMANT);
        landRegistryApp.fileDispute(DISPUTE_ID, PARCEL_ID, keccak256("dispute.evidence"));

        LandTypes.DisputeRecord memory disputeRecord = landRegistry.getDispute(DISPUTE_ID);
        assertEq(disputeRecord.claimant, CLAIMANT);
        assertEq(uint256(disputeRecord.status), uint256(LandTypes.DisputeStatus.Filed));
        assertEq(landRegistry.activeDisputeCountOf(PARCEL_ID), 0);

        vm.prank(LAND_ADMIN);
        landRegistryApp.transferTitle(TITLE_ID, OWNER_TWO, keccak256("filed.dispute.does.not.lock.transfer"));
        assertEq(landRegistry.getTitle(TITLE_ID).holder, OWNER_TWO);

        vm.prank(LAND_ADMIN);
        landRegistryApp.transferTitle(TITLE_ID, OWNER_ONE, keccak256("return.before.accepted.dispute"));
        assertEq(landRegistry.getTitle(TITLE_ID).holder, OWNER_ONE);

        vm.prank(LAND_ADMIN);
        landRegistryApp.acceptDispute(DISPUTE_ID, bytes32(0));

        assertEq(landRegistry.activeDisputeCountOf(PARCEL_ID), 1);
        assertEq(uint256(landRegistry.getParcel(PARCEL_ID).status), uint256(LandTypes.ParcelStatus.Disputed));

        vm.prank(LAND_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ILandRegistry.InvalidParcelStatus.selector, LandTypes.ParcelStatus.Disputed)
        );
        landRegistryApp.transferTitle(TITLE_ID, OWNER_TWO, keccak256("blocked.transfer"));

        vm.prank(LAND_ADMIN);
        landRegistryApp.resolveDispute(DISPUTE_ID, keccak256("dispute.resolution"), false);

        assertEq(landRegistry.activeDisputeCountOf(PARCEL_ID), 0);
        assertEq(uint256(landRegistry.getParcel(PARCEL_ID).status), uint256(LandTypes.ParcelStatus.Active));

        vm.prank(LAND_ADMIN);
        landRegistryApp.registerEncumbrance(ENCUMBRANCE_ONE_ID, TITLE_ID, keccak256("mortgage.one"));
        vm.prank(LAND_ADMIN);
        landRegistryApp.registerEncumbrance(ENCUMBRANCE_TWO_ID, TITLE_ID, keccak256("mortgage.two"));
        assertEq(landRegistry.activeEncumbranceCountOf(PARCEL_ID), 2);

        vm.prank(LAND_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.ParcelTransferLocked.selector, PARCEL_ID));
        landRegistryApp.transferTitle(TITLE_ID, OWNER_TWO, keccak256("blocked.encumbrance.transfer"));

        vm.prank(LAND_ADMIN);
        landRegistryApp.releaseEncumbrance(ENCUMBRANCE_ONE_ID, keccak256("release.one"));
        assertEq(landRegistry.activeEncumbranceCountOf(PARCEL_ID), 1);

        vm.prank(LAND_ADMIN);
        landRegistryApp.releaseEncumbrance(ENCUMBRANCE_TWO_ID, keccak256("release.two"));
        assertEq(landRegistry.activeEncumbranceCountOf(PARCEL_ID), 0);

        vm.prank(LAND_CLERK);
        landRegistryApp.transferTitle(TITLE_ID, OWNER_TWO, keccak256("final.transfer"));

        assertEq(landRegistry.getTitle(TITLE_ID).holder, OWNER_TWO);
    }

    function test_LandRegistry_CannotAcceptDisputeOnDraftParcel() public {
        vm.prank(LAND_ADMIN);
        landRegistryApp.submitParcelDraft(PARCEL_TWO_ID, _parcelInput("parcel.two"));

        vm.prank(CLAIMANT);
        landRegistryApp.fileDispute(DISPUTE_ID, PARCEL_TWO_ID, keccak256("draft.dispute.evidence"));

        vm.prank(LAND_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ILandRegistry.InvalidParcelStatus.selector, LandTypes.ParcelStatus.Draft)
        );
        landRegistryApp.acceptDispute(DISPUTE_ID, bytes32(0));
    }

    function test_CompanyRegistry_PublicSubmissionAndOfficeLifecycle() public {
        vm.prank(FOUNDER);
        companyRegistryApp.submitIncorporation(COMPANY_ID, _companyInput("company.one", bytes32(0)));

        CompanyTypes.CompanyRecord memory companyRecord = companyRegistry.getCompany(COMPANY_ID);
        assertEq(companyRecord.founder, FOUNDER);
        assertEq(uint256(companyRecord.status), uint256(CompanyTypes.CompanyStatus.Pending));
        assertEq(companyRegistry.companyByNameHash(keccak256("company.one.name")), COMPANY_ID);
        assertEq(companyRegistry.totalCompanyCount(), 1);

        vm.prank(COMPANY_CLERK);
        companyRegistryApp.approveCompany(COMPANY_ID, REGISTRATION_NUMBER_HASH);

        companyRecord = companyRegistry.getCompany(COMPANY_ID);
        assertEq(companyRecord.registrationNumberHash, REGISTRATION_NUMBER_HASH);
        assertEq(uint256(companyRecord.status), uint256(CompanyTypes.CompanyStatus.Active));

        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.setDirector(COMPANY_ID, DIRECTOR, keccak256("director.ceo"), true);

        CompanyTypes.DirectorRecord memory directorRecord = companyRegistry.getDirector(COMPANY_ID, DIRECTOR);
        assertTrue(directorRecord.active);
        assertEq(directorRecord.roleHash, keccak256("director.ceo"));

        vm.prank(COMPANY_CLERK);
        companyRegistryApp.registerShareClass(
            COMPANY_ID, SHARE_CLASS_A, keccak256("class.a.metadata"), 1_000, 10_000, false
        );

        vm.prank(COMPANY_CLERK);
        companyRegistryApp.issueShares(COMPANY_ID, SHARE_CLASS_A, FOUNDER, 700, keccak256("shares.issue"));
        assertEq(companyRegistry.shareBalanceOf(COMPANY_ID, SHARE_CLASS_A, FOUNDER), 700);

        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.transferShares(
            COMPANY_ID, SHARE_CLASS_A, FOUNDER, INVESTOR, 250, keccak256("shares.transfer")
        );
        assertEq(companyRegistry.shareBalanceOf(COMPANY_ID, SHARE_CLASS_A, FOUNDER), 450);
        assertEq(companyRegistry.shareBalanceOf(COMPANY_ID, SHARE_CLASS_A, INVESTOR), 250);

        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.burnShares(COMPANY_ID, SHARE_CLASS_A, INVESTOR, 50, keccak256("shares.burn"));

        CompanyTypes.ShareClassRecord memory shareClassRecord = companyRegistry.getShareClass(COMPANY_ID, SHARE_CLASS_A);
        assertEq(shareClassRecord.issuedShares, 650);
        assertEq(companyRegistry.shareBalanceOf(COMPANY_ID, SHARE_CLASS_A, INVESTOR), 200);

        vm.prank(COMPANY_CLERK);
        companyRegistryApp.recordFiling(
            COMPANY_ID, FILING_ID, CompanyTypes.FilingType.Compliance, keccak256("compliance.filing")
        );

        CompanyTypes.FilingRecord memory filingRecord = companyRegistry.getFiling(FILING_ID);
        assertEq(filingRecord.companyId, COMPANY_ID);
        assertEq(uint256(filingRecord.filingType), uint256(CompanyTypes.FilingType.Compliance));
        assertEq(filingRecord.filedBy, COMPANY_CLERK);
    }

    function test_CompanyRegistry_RejectsUnauthorizedOfficeAction() public {
        vm.prank(FOUNDER);
        companyRegistryApp.submitIncorporation(COMPANY_TWO_ID, _companyInput("company.two", bytes32(0)));

        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompanyRegistryApp.UnauthorizedCompanyRegistryOfficeAction.selector,
                OUTSIDER,
                COMPANY_REGISTRY_OFFICE_ID,
                OfficeTypes.OfficeActionClass.ManageCompanyRegistry
            )
        );
        companyRegistryApp.approveCompany(COMPANY_TWO_ID, keccak256("LLC-0002"));
    }

    function test_CompanyRegistry_ShareOperationsRequireActiveCompany() public {
        vm.prank(FOUNDER);
        companyRegistryApp.submitIncorporation(COMPANY_TWO_ID, _companyInput("company.two", bytes32(0)));

        vm.prank(COMPANY_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyStatus.selector, CompanyTypes.CompanyStatus.Pending)
        );
        companyRegistryApp.registerShareClass(
            COMPANY_TWO_ID, SHARE_CLASS_A, keccak256("class.metadata"), 100, 10_000, false
        );
    }

    function test_CompanyRegistry_ComplianceWarningCanOperateButSuspendedCannot() public {
        vm.prank(FOUNDER);
        companyRegistryApp.submitIncorporation(COMPANY_TWO_ID, _companyInput("company.two", bytes32(0)));

        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.approveCompany(COMPANY_TWO_ID, REGISTRATION_TWO_NUMBER_HASH);

        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.setCompanyStatus(
            COMPANY_TWO_ID, CompanyTypes.CompanyStatus.ComplianceWarning, keccak256("compliance.warning")
        );

        vm.prank(COMPANY_CLERK);
        companyRegistryApp.registerShareClass(
            COMPANY_TWO_ID, SHARE_CLASS_B, keccak256("class.b.metadata"), 500, 10_000, false
        );
        vm.prank(COMPANY_CLERK);
        companyRegistryApp.issueShares(COMPANY_TWO_ID, SHARE_CLASS_B, FOUNDER, 100, keccak256("warning.issue"));

        assertEq(companyRegistry.shareBalanceOf(COMPANY_TWO_ID, SHARE_CLASS_B, FOUNDER), 100);

        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.setCompanyStatus(
            COMPANY_TWO_ID, CompanyTypes.CompanyStatus.Suspended, keccak256("suspended")
        );

        vm.prank(COMPANY_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyStatus.selector, CompanyTypes.CompanyStatus.Suspended)
        );
        companyRegistryApp.issueShares(COMPANY_TWO_ID, SHARE_CLASS_B, FOUNDER, 1, keccak256("suspended.issue"));

        vm.prank(COMPANY_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyStatus.selector, CompanyTypes.CompanyStatus.Suspended)
        );
        companyRegistryApp.transferShares(
            COMPANY_TWO_ID, SHARE_CLASS_B, FOUNDER, INVESTOR, 1, keccak256("suspended.transfer")
        );

        vm.prank(COMPANY_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyStatus.selector, CompanyTypes.CompanyStatus.Suspended)
        );
        companyRegistryApp.burnShares(COMPANY_TWO_ID, SHARE_CLASS_B, FOUNDER, 1, keccak256("suspended.burn"));
    }

    function _activateParcelWithTitle(bytes32 parcelId, bytes32 titleId, address holder) private {
        vm.startPrank(LAND_ADMIN);
        landRegistryApp.submitParcelDraft(parcelId, _parcelInput("active.parcel"));
        landRegistryApp.activateParcel(parcelId, keccak256("active.parcel.activation"));
        landRegistryApp.registerTitle(titleId, _titleInput(parcelId, holder));
        vm.stopPrank();
    }

    function _parcelInput(string memory salt) private pure returns (LandTypes.ParcelInput memory input) {
        input = LandTypes.ParcelInput({
            parcelNumberHash: keccak256(abi.encodePacked(salt, ".number")),
            districtHash: keccak256(abi.encodePacked(salt, ".district")),
            metadataHash: keccak256(abi.encodePacked(salt, ".metadata")),
            spatialDataHash: keccak256(abi.encodePacked(salt, ".spatial")),
            documentHash: keccak256(abi.encodePacked(salt, ".document")),
            spatialType: LandTypes.SpatialType.Polygon,
            areaSquareMeters: 10_000
        });
    }

    function _titleInput(bytes32 parcelId, address holder) private pure returns (LandTypes.TitleInput memory input) {
        input = LandTypes.TitleInput({
            parcelId: parcelId,
            holder: holder,
            tenureType: LandTypes.TenureType.Freehold,
            leaseExpiresAt: 0,
            documentHash: keccak256(abi.encodePacked("title.document", parcelId, holder))
        });
    }

    function _companyInput(string memory salt, bytes32 registrationNumberHash)
        private
        pure
        returns (CompanyTypes.CompanyInput memory input)
    {
        input = CompanyTypes.CompanyInput({
            registrationNumberHash: registrationNumberHash,
            nameHash: keccak256(abi.encodePacked(salt, ".name")),
            jurisdictionHash: keccak256(abi.encodePacked(salt, ".jurisdiction")),
            registeredOfficeHash: keccak256(abi.encodePacked(salt, ".office")),
            metadataHash: keccak256(abi.encodePacked(salt, ".metadata")),
            articlesHash: keccak256(abi.encodePacked(salt, ".articles")),
            uboHash: keccak256(abi.encodePacked(salt, ".ubo")),
            registeredCapital: 1_000_000
        });
    }
}
