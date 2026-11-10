// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";

import {CompanyRegistryApp} from "../../contracts/apps/CompanyRegistryApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ICompanyRegistry} from "../../contracts/interfaces/ICompanyRegistry.sol";
import {ICompanyRegistryApp} from "../../contracts/interfaces/ICompanyRegistryApp.sol";
import {ILandPartyPolicy} from "../../contracts/interfaces/ILandPartyPolicy.sol";
import {ILandRegistry} from "../../contracts/interfaces/ILandRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LandPartyPolicy} from "../../contracts/policies/LandPartyPolicy.sol";
import {OfficePermissionPolicy} from "../../contracts/policies/OfficePermissionPolicy.sol";
import {CompanyRegistry} from "../../contracts/registries/CompanyRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LandRegistry} from "../../contracts/registries/LandRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {CompanyTypes} from "../../contracts/types/CompanyTypes.sol";
import {LandTypes} from "../../contracts/types/LandTypes.sol";
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
    bytes32 internal constant PARCEL_ID = keccak256("company.parcel");
    bytes32 internal constant TITLE_ID = keccak256("company.title");

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
    // This fixture writes directly to the land ledger. Expose the same binding as LandRegistryApp.
    LandRegistry public landRegistry;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        officeRegistry = new OfficeRegistry(address(kernel));
        officePermissionPolicy = new OfficePermissionPolicy();
        companyRegistry = new CompanyRegistry(address(kernel));
        landRegistry = new LandRegistry(address(kernel));
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
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY, address(landRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));

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

    function test_PendingCompanyCannotLeaveFilingsBehindAfterRejection() public {
        vm.prank(FOUNDER);
        companyRegistryApp.submitIncorporation(COMPANY_ID, _companyInput("company.one", bytes32(0)));
        vm.prank(COMPANY_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(ICompanyRegistry.InvalidCompanyStatus.selector, CompanyTypes.CompanyStatus.Pending)
        );
        companyRegistryApp.recordFiling(COMPANY_ID, FILING_ID, CompanyTypes.FilingType.Compliance, keccak256("filing"));
        assertEq(companyRegistry.getFiling(FILING_ID).filingId, bytes32(0));

        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.rejectCompany(COMPANY_ID, keccak256("incomplete"));
        vm.prank(OUTSIDER);
        companyRegistryApp.submitIncorporation(COMPANY_ID, _companyInput("company.revised", bytes32(0)));
        assertEq(companyRegistry.getFiling(FILING_ID).filingId, bytes32(0));
    }

    function test_SuspendedCompanyCanStillRecordComplianceFiling() public {
        vm.prank(FOUNDER);
        companyRegistryApp.submitIncorporation(COMPANY_ID, _companyInput("company.one", bytes32(0)));
        vm.startPrank(COMPANY_ADMIN);
        companyRegistryApp.approveCompany(COMPANY_ID, REGISTRATION_NUMBER_HASH);
        companyRegistryApp.setCompanyStatus(COMPANY_ID, CompanyTypes.CompanyStatus.Suspended, keccak256("suspended"));
        companyRegistryApp.recordFiling(COMPANY_ID, FILING_ID, CompanyTypes.FilingType.Compliance, keccak256("filing"));
        vm.stopPrank();
        assertEq(companyRegistry.getFiling(FILING_ID).companyId, COMPANY_ID);
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

    function test_CompanyWithLandCanReplaceDirectorAndWindDownAfterTransfer() public {
        _approveLandCompany();
        _setDirector(DIRECTOR, true);
        _setDirector(INVESTOR, true);
        _activateParcel();
        _registerTitle(_companyParty(), 0);
        assertEq(landRegistry.activeCompanyTitleCount(COMPANY_ID), 1);

        _setDirector(DIRECTOR, false);
        vm.expectRevert(abi.encodeWithSelector(ICompanyRegistry.CompanyHasActiveLandTitles.selector, COMPANY_ID));
        _setDirector(INVESTOR, false);
        assertTrue(companyRegistry.getDirector(COMPANY_ID, INVESTOR).active);

        _setCompanyStatus(CompanyTypes.CompanyStatus.Dissolving);
        vm.expectRevert(abi.encodeWithSelector(ICompanyRegistry.CompanyHasActiveLandTitles.selector, COMPANY_ID));
        _setCompanyStatus(CompanyTypes.CompanyStatus.Dissolved);

        _transferTitle(_personParty());
        assertEq(landRegistry.activeCompanyTitleCount(COMPANY_ID), 0);
        _setCompanyStatus(CompanyTypes.CompanyStatus.Dissolved);

        bytes32 titleVersion = landRegistry.getTitle(TITLE_ID).versionHash;
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.InvalidParty.selector, _companyParty()));
        _transferTitle(_companyParty(), titleVersion);
    }

    function test_LandRegistryCutoverPausesCompanyLifecycleAndObsoleteLandWrites() public {
        _approveLandCompany();
        _setDirector(DIRECTOR, true);
        _activateParcel();
        _registerTitle(_companyParty(), 0);
        bytes32 titleVersion = landRegistry.getTitle(TITLE_ID).versionHash;

        LandRegistry successor = new LandRegistry(address(kernel));
        kernel.governanceUpdateModule(KernelModuleIds.LAND_REGISTRY, address(successor));
        bytes memory mismatch = abi.encodeWithSelector(
            ICompanyRegistry.LandRegistryWriterMismatch.selector, address(successor), address(this)
        );
        vm.expectRevert(mismatch);
        _setDirector(DIRECTOR, false);
        vm.expectRevert(mismatch);
        _setCompanyStatus(CompanyTypes.CompanyStatus.Dissolved);
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.UnauthorizedLandRegistryCaller.selector, address(this)));
        _transferTitle(_personParty(), titleVersion);

        kernel.governanceUpdateModule(KernelModuleIds.LAND_REGISTRY, address(landRegistry));
        assertTrue(companyRegistry.getDirector(COMPANY_ID, DIRECTOR).active);
        assertEq(landRegistry.activeCompanyTitleCount(COMPANY_ID), 1);
        vm.expectRevert(abi.encodeWithSelector(ICompanyRegistry.CompanyHasActiveLandTitles.selector, COMPANY_ID));
        _setCompanyStatus(CompanyTypes.CompanyStatus.Dissolved);
        _transferTitle(_personParty(), titleVersion);
        _setCompanyStatus(CompanyTypes.CompanyStatus.Dissolved);
    }

    function test_DirectLandAuthorityCannotAssignTitleToCompanyWithoutDirector() public {
        _approveLandCompany();
        _activateParcel();

        LandTypes.TitleInput memory unrepresentedTitle = _titleInput(_companyParty(), 0);
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.InvalidParty.selector, _companyParty()));
        landRegistry.registerTitle(TITLE_ID, unrepresentedTitle, keccak256("title.invalid"));
        _registerTitle(_personParty(), 0);

        bytes32 titleVersion = landRegistry.getTitle(TITLE_ID).versionHash;
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.InvalidParty.selector, _companyParty()));
        _transferTitle(_companyParty(), titleVersion);
        assertEq(landRegistry.activeCompanyTitleCount(COMPANY_ID), 0);

        _setDirector(DIRECTOR, true);
        _transferTitle(_companyParty());
        _transferTitle(_companyParty());
        assertEq(landRegistry.activeCompanyTitleCount(COMPANY_ID), 1);

        _transferTitle(_personParty());
        _setDirector(DIRECTOR, false);
        assertEq(companyRegistry.getCompany(COMPANY_ID).activeDirectorCount, 0);
    }

    function test_ExpiredLeaseCountsUntilClosed() public {
        _approveLandCompany();
        _setDirector(DIRECTOR, true);
        _activateParcel();
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        _registerTitle(_companyParty(), expiresAt);

        vm.warp(expiresAt);
        assertEq(landRegistry.activeCompanyTitleCount(COMPANY_ID), 1);
        vm.expectRevert(abi.encodeWithSelector(ICompanyRegistry.CompanyHasActiveLandTitles.selector, COMPANY_ID));
        _setCompanyStatus(CompanyTypes.CompanyStatus.Dissolved);

        LandTypes.TitleRecord memory title = landRegistry.getTitle(TITLE_ID);
        landRegistry.closeTitle(PARCEL_ID, TITLE_ID, title.versionHash, _anchor(title.versionHash), keccak256("close"));
        assertEq(landRegistry.activeCompanyTitleCount(COMPANY_ID), 0);
        _setCompanyStatus(CompanyTypes.CompanyStatus.Dissolved);
    }

    function test_ObsoleteCompanyRegistryRejectsWritesAndCannotAuthorizeLandSigners() public {
        _approveLandCompany();
        _setDirector(DIRECTOR, true);
        IdentityRegistry identityRegistry = new IdentityRegistry(address(kernel));
        LandPartyPolicy policy =
            new LandPartyPolicy(address(identityRegistry), address(companyRegistry), address(officeRegistry));
        LandTypes.PartyRef memory company = _companyParty();
        assertTrue(policy.isAuthorizedSigner(company, DIRECTOR));

        CompanyRegistry successor = new CompanyRegistry(address(kernel));
        kernel.governanceUpdateModule(KernelModuleIds.COMPANY_REGISTRY, address(successor));
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompanyRegistry.UnauthorizedCompanyRegistryCaller.selector, address(companyRegistryApp)
            )
        );
        _setDirector(DIRECTOR, false);
        assertTrue(companyRegistry.getDirector(COMPANY_ID, DIRECTOR).active);
        vm.expectRevert(
            abi.encodeWithSelector(ILandPartyPolicy.InvalidCompanyRegistry.selector, address(companyRegistry))
        );
        policy.isAuthorizedSigner(company, DIRECTOR);
    }

    function _approveLandCompany() private {
        vm.prank(FOUNDER);
        companyRegistryApp.submitIncorporation(COMPANY_ID, _companyInput("company.land", bytes32(0)));
        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.approveCompany(COMPANY_ID, REGISTRATION_NUMBER_HASH);
    }

    function _setDirector(address director, bool active) private {
        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.setDirector(COMPANY_ID, director, keccak256("director"), active);
    }

    function _setCompanyStatus(CompanyTypes.CompanyStatus status) private {
        vm.prank(COMPANY_ADMIN);
        companyRegistryApp.setCompanyStatus(COMPANY_ID, status, keccak256("status.reason"));
    }

    function _activateParcel() private {
        LandTypes.ParcelInput memory input = LandTypes.ParcelInput({
            parcelNumberHash: keccak256("parcel.number"),
            districtHash: keccak256("parcel.district"),
            anchor: _anchor(keccak256("parcel.origin")),
            spatialDataHash: keccak256("parcel.geometry"),
            coordinateReferenceSystemHash: keccak256("EPSG:4258"),
            spatialType: LandTypes.SpatialType.Polygon,
            areaSquareMeters: 1_000
        });
        landRegistry.createParcelDraft(PARCEL_ID, input, keccak256("draft"));
        LandTypes.ParcelRecord memory parcel = landRegistry.getParcel(PARCEL_ID);
        landRegistry.activateParcel(PARCEL_ID, parcel.revision, _anchor(parcel.versionHash), keccak256("activate"));
    }

    function _registerTitle(LandTypes.PartyRef memory holder, uint64 leaseExpiresAt) private {
        landRegistry.registerTitle(TITLE_ID, _titleInput(holder, leaseExpiresAt), keccak256("title.register"));
    }

    function _titleInput(LandTypes.PartyRef memory holder, uint64 leaseExpiresAt)
        private
        view
        returns (LandTypes.TitleInput memory input)
    {
        bytes32 parcelVersion = landRegistry.getParcel(PARCEL_ID).versionHash;
        input = LandTypes.TitleInput({
            parcelId: PARCEL_ID,
            holder: holder,
            anchor: _anchor(parcelVersion),
            tenureType: leaseExpiresAt == 0 ? LandTypes.TenureType.Freehold : LandTypes.TenureType.Leasehold,
            leaseExpiresAt: leaseExpiresAt
        });
    }

    function _transferTitle(LandTypes.PartyRef memory holder) private {
        _transferTitle(holder, landRegistry.getTitle(TITLE_ID).versionHash);
    }

    function _transferTitle(LandTypes.PartyRef memory holder, bytes32 titleVersion) private {
        landRegistry.transferTitle(TITLE_ID, titleVersion, holder, _anchor(titleVersion), keccak256("title.transfer"));
    }

    function _companyParty() private pure returns (LandTypes.PartyRef memory) {
        return LandTypes.PartyRef({namespace: LandTypes.COMPANY_NAMESPACE, id: COMPANY_ID});
    }

    function _personParty() private pure returns (LandTypes.PartyRef memory) {
        return LandTypes.PartyRef({namespace: keccak256("party.person"), id: keccak256("person.new.holder")});
    }

    function _anchor(bytes32 lineageHash) private pure returns (LandTypes.RecordAnchor memory) {
        return LandTypes.RecordAnchor({
            schemaId: keccak256("schema"),
            contentHash: keccak256("content"),
            sourceDocumentHash: keccak256("document"),
            lineageHash: lineageHash,
            schemaVersion: 1
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
