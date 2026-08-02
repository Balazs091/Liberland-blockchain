// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {CompanyRegistryApp} from "../../contracts/apps/CompanyRegistryApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ICompanyRegistry} from "../../contracts/interfaces/ICompanyRegistry.sol";
import {ICompanyRegistryApp} from "../../contracts/interfaces/ICompanyRegistryApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {OfficePermissionPolicy} from "../../contracts/policies/OfficePermissionPolicy.sol";
import {CompanyRegistry} from "../../contracts/registries/CompanyRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {CompanyTypes} from "../../contracts/types/CompanyTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

/// @title CompanyRegistryTest
/// @notice Covers public incorporation and office-authorized company lifecycle operations.
contract CompanyRegistryTest is Test {
    bytes32 internal constant COMPANY_REGISTRY_OFFICE_ID = keccak256("office.company-registry");
    bytes32 internal constant COMPANY_ID = keccak256("company.one");
    bytes32 internal constant COMPANY_TWO_ID = keccak256("company.two");
    bytes32 internal constant REGISTRATION_NUMBER_HASH = keccak256("LLC-0001");
    bytes32 internal constant REGISTRATION_TWO_NUMBER_HASH = keccak256("LLC-0002");
    bytes32 internal constant SHARE_CLASS_A = keccak256("share-class.a");
    bytes32 internal constant SHARE_CLASS_B = keccak256("share-class.b");
    bytes32 internal constant FILING_ID = keccak256("filing.one");

    address internal constant COMPANY_ADMIN = address(0xC001);
    address internal constant COMPANY_CLERK = address(0xC002);
    address internal constant FOUNDER = address(0xF00D);
    address internal constant DIRECTOR = address(0xD1EC);
    address internal constant INVESTOR = address(0xA11CE);
    address internal constant OUTSIDER = address(0xBAD);

    ConstitutionKernel internal kernel;
    OfficeRegistry internal officeRegistry;
    OfficePermissionPolicy internal officePermissionPolicy;
    CompanyRegistry internal companyRegistry;
    CompanyRegistryApp internal companyRegistryApp;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        officeRegistry = new OfficeRegistry(address(kernel));
        officePermissionPolicy = new OfficePermissionPolicy();
        companyRegistry = new CompanyRegistry(address(kernel));
        companyRegistryApp = new CompanyRegistryApp(
            address(companyRegistry),
            address(officeRegistry),
            address(officePermissionPolicy),
            COMPANY_REGISTRY_OFFICE_ID
        );

        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_PERMISSION_POLICY, address(officePermissionPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY, address(companyRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY_APP, address(companyRegistryApp));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY_AUTHORITY, address(companyRegistryApp));

        officeRegistry.registerOffice(
            COMPANY_REGISTRY_OFFICE_ID,
            OfficeTypes.OfficeKind.CompanyRegistryOffice,
            "Company Registry Office",
            COMPANY_ADMIN
        );
        officeRegistry.setClerkStatus(COMPANY_REGISTRY_OFFICE_ID, COMPANY_CLERK, true);
        kernel.disableBootstrapAuthority();
    }

    function test_InterfacesExposeSelectors() public pure {
        assertTrue(ICompanyRegistry.submitCompany.selector != bytes4(0));
        assertTrue(ICompanyRegistry.registerShareClass.selector != bytes4(0));
        assertTrue(ICompanyRegistryApp.submitIncorporation.selector != bytes4(0));
        assertTrue(ICompanyRegistryApp.recordFiling.selector != bytes4(0));
    }

    function test_PublicSubmissionAndOfficeLifecycle() public {
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

    function test_RejectsUnauthorizedOfficeAction() public {
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

    function test_ShareOperationsRequireActiveCompany() public {
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

    function test_PendingCompanyCannotAccumulateDirectorStateBeforeResubmission() public {
        vm.prank(FOUNDER);
        companyRegistryApp.submitIncorporation(COMPANY_TWO_ID, _companyInput("company.two", bytes32(0)));

        vm.prank(COMPANY_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyStatus.selector, CompanyTypes.CompanyStatus.Pending)
        );
        companyRegistryApp.setDirector(COMPANY_TWO_ID, DIRECTOR, keccak256("director.ceo"), true);

        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.rejectCompany(COMPANY_TWO_ID, keccak256("incomplete"));

        vm.prank(FOUNDER);
        companyRegistryApp.submitIncorporation(COMPANY_TWO_ID, _companyInput("company.two.revised", bytes32(0)));
        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.approveCompany(COMPANY_TWO_ID, REGISTRATION_TWO_NUMBER_HASH);

        vm.startPrank(COMPANY_ADMIN);
        companyRegistryApp.setDirector(COMPANY_TWO_ID, DIRECTOR, keccak256("director.ceo"), true);
        companyRegistryApp.setDirector(COMPANY_TWO_ID, DIRECTOR, bytes32(0), false);
        vm.stopPrank();

        assertEq(companyRegistry.getCompany(COMPANY_TWO_ID).activeDirectorCount, 0);
        assertFalse(companyRegistry.getDirector(COMPANY_TWO_ID, DIRECTOR).active);
    }

    function test_ComplianceWarningCanOperateButSuspendedCannot() public {
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

        vm.startPrank(COMPANY_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyStatus.selector, CompanyTypes.CompanyStatus.Suspended)
        );
        companyRegistryApp.issueShares(COMPANY_TWO_ID, SHARE_CLASS_B, FOUNDER, 1, keccak256("suspended.issue"));
        vm.expectRevert(
            abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyStatus.selector, CompanyTypes.CompanyStatus.Suspended)
        );
        companyRegistryApp.transferShares(
            COMPANY_TWO_ID, SHARE_CLASS_B, FOUNDER, INVESTOR, 1, keccak256("suspended.transfer")
        );
        vm.expectRevert(
            abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyStatus.selector, CompanyTypes.CompanyStatus.Suspended)
        );
        companyRegistryApp.burnShares(COMPANY_TWO_ID, SHARE_CLASS_B, FOUNDER, 1, keccak256("suspended.burn"));
        vm.stopPrank();
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
