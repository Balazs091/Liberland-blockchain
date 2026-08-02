// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {ERC1271WalletMock} from "@openzeppelin/contracts/mocks/ERC1271WalletMock.sol";

import {LandRegistryApp} from "../../contracts/apps/LandRegistryApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ILandRegistry} from "../../contracts/interfaces/ILandRegistry.sol";
import {ILandRegistryApp} from "../../contracts/interfaces/ILandRegistryApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LandPartyPolicy} from "../../contracts/policies/LandPartyPolicy.sol";
import {OfficePermissionPolicy} from "../../contracts/policies/OfficePermissionPolicy.sol";
import {CompanyRegistry} from "../../contracts/registries/CompanyRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LandRegistry} from "../../contracts/registries/LandRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {CompanyTypes} from "../../contracts/types/CompanyTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LandTypes} from "../../contracts/types/LandTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

/// @title LandRegistryTest
/// @notice Covers stable parties, signed transfers, version lineage, split powers, and atomic parcel operations.
contract LandRegistryTest is Test {
    bytes32 internal constant LAND_OFFICE_ID = keccak256("office.land");
    bytes32 internal constant PARCEL_ID = keccak256("parcel.one");
    bytes32 internal constant PARCEL_TWO_ID = keccak256("parcel.two");
    bytes32 internal constant TITLE_ID = keccak256("title.one");
    bytes32 internal constant TITLE_TWO_ID = keccak256("title.two");
    bytes32 internal constant SELLER_PERSON_ID = keccak256("person.seller");
    bytes32 internal constant BUYER_PERSON_ID = keccak256("person.buyer");
    bytes32 internal constant COMPANY_ID = keccak256("company.owner");
    bytes32 internal constant DISPUTE_ID = keccak256("dispute.one");
    bytes32 internal constant ENCUMBRANCE_ID = keccak256("encumbrance.one");

    uint256 internal constant SELLER_KEY = 0xA11CE;
    uint256 internal constant BUYER_KEY = 0xB0B;
    uint256 internal constant BUYER_REPLACEMENT_KEY = 0xB0B02;
    uint256 internal constant COMPANY_DIRECTOR_KEY = 0xD1EC70;

    address internal constant LAND_ADMIN = address(0x1A01);
    address internal constant LAND_CLERK = address(0x1A02);
    address internal constant OUTSIDER = address(0xBAD);

    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    CompanyRegistry internal companyRegistry;
    OfficeRegistry internal officeRegistry;
    LandRegistry internal landRegistry;
    OfficePermissionPolicy internal officePermissionPolicy;
    LandPartyPolicy internal landPartyPolicy;
    LandRegistryApp internal landRegistryApp;

    address internal seller;
    address internal buyer;
    address internal buyerReplacement;

    function setUp() public {
        seller = vm.addr(SELLER_KEY);
        buyer = vm.addr(BUYER_KEY);
        buyerReplacement = vm.addr(BUYER_REPLACEMENT_KEY);

        kernel = new ConstitutionKernel(address(this));
        identityRegistry = new IdentityRegistry(address(kernel));
        companyRegistry = new CompanyRegistry(address(kernel));
        officeRegistry = new OfficeRegistry(address(kernel));
        landRegistry = new LandRegistry(address(kernel));
        officePermissionPolicy = new OfficePermissionPolicy();
        landPartyPolicy =
            new LandPartyPolicy(address(identityRegistry), address(companyRegistry), address(officeRegistry));
        landRegistryApp = new LandRegistryApp(
            address(landRegistry),
            address(officeRegistry),
            address(officePermissionPolicy),
            address(landPartyPolicy),
            LAND_OFFICE_ID
        );

        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY, address(companyRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.COMPANY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY, address(officeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY, address(landRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY_APP, address(landRegistryApp));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY, address(landRegistryApp));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_PERMISSION_POLICY, address(officePermissionPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_PARTY_POLICY, address(landPartyPolicy));

        officeRegistry.registerOffice(
            LAND_OFFICE_ID, OfficeTypes.OfficeKind.LandRegistryOffice, "Land Registry Office", LAND_ADMIN
        );
        officeRegistry.setClerkStatus(LAND_OFFICE_ID, LAND_CLERK, true);
        _registerPerson(SELLER_PERSON_ID, seller);
        _registerPerson(BUYER_PERSON_ID, buyer);

        kernel.disableBootstrapAuthority();
    }

    function test_InterfacesExposeCleanDesignSelectors() public pure {
        assertTrue(ILandRegistry.createParcelDraft.selector != bytes4(0));
        assertTrue(ILandRegistry.subdivideParcel.selector != bytes4(0));
        assertTrue(ILandRegistry.mergeParcels.selector != bytes4(0));
        assertTrue(ILandRegistryApp.hashTitleTransferAuthorization.selector != bytes4(0));
        assertTrue(ILandRegistryApp.adjustBoundary.selector != bytes4(0));
    }

    function test_ClerkPreparesButOnlyRegistrarFinalizesAndVersionsAreChained() public {
        vm.prank(LAND_CLERK);
        landRegistryApp.submitParcelDraft(
            PARCEL_ID, _parcelInput("parcel.one", "draft.one", keccak256("survey.genesis")), keccak256("tx.draft")
        );

        LandTypes.ParcelRecord memory draft = landRegistry.getParcel(PARCEL_ID);
        assertEq(draft.revision, 1);
        assertNotEq(draft.versionHash, bytes32(0));
        assertEq(uint256(draft.status), uint256(LandTypes.ParcelStatus.Draft));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILandRegistryApp.UnauthorizedLandRegistryOfficeAction.selector,
                LAND_CLERK,
                LAND_OFFICE_ID,
                OfficeTypes.OfficeActionClass.FinalizeLandRecords
            )
        );
        vm.prank(LAND_CLERK);
        landRegistryApp.activateParcel(
            PARCEL_ID, draft.revision, _anchor("parcel.activation", draft.versionHash), keccak256("tx.activate")
        );

        vm.prank(LAND_ADMIN);
        landRegistryApp.activateParcel(
            PARCEL_ID, draft.revision, _anchor("parcel.activation", draft.versionHash), keccak256("tx.activate")
        );

        LandTypes.ParcelRecord memory active = landRegistry.getParcel(PARCEL_ID);
        assertEq(active.revision, 2);
        assertNotEq(active.versionHash, draft.versionHash);
        assertEq(active.anchor.lineageHash, draft.versionHash);
        assertEq(uint256(active.status), uint256(LandTypes.ParcelStatus.Active));

        LandTypes.PartyRef memory sellerParty = _personParty(SELLER_PERSON_ID);
        vm.prank(LAND_ADMIN);
        landRegistryApp.registerTitle(
            TITLE_ID,
            _titleInput(PARCEL_ID, sellerParty, active.versionHash, "title.register"),
            keccak256("tx.title.register")
        );

        LandTypes.TitleRecord memory title = landRegistry.getTitle(TITLE_ID);
        assertEq(title.holder.namespace, landPartyPolicy.personNamespace());
        assertEq(title.holder.id, SELLER_PERSON_ID);
        assertEq(title.revision, 1);
        assertEq(title.anchor.lineageHash, active.versionHash);
    }

    function test_TitleTransferRequiresCurrentSellerAndBuyerSignaturesAndCannotReplay() public {
        _activateParcelWithTitle(PARCEL_ID, TITLE_ID, "parcel.one", _personParty(SELLER_PERSON_ID));
        LandTypes.TitleTransferRequest memory request = _transferRequest(TITLE_ID, _personParty(BUYER_PERSON_ID));
        (bytes memory sellerSignature, bytes memory buyerSignature) = _signTransfer(request, SELLER_KEY, BUYER_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILandRegistryApp.UnauthorizedLandRegistryOfficeAction.selector,
                LAND_CLERK,
                LAND_OFFICE_ID,
                OfficeTypes.OfficeActionClass.FinalizeLandRecords
            )
        );
        vm.prank(LAND_CLERK);
        landRegistryApp.transferTitle(request, seller, sellerSignature, buyer, buyerSignature);

        vm.prank(LAND_ADMIN);
        landRegistryApp.transferTitle(request, seller, sellerSignature, buyer, buyerSignature);

        LandTypes.TitleRecord memory transferred = landRegistry.getTitle(TITLE_ID);
        assertEq(transferred.holder.id, BUYER_PERSON_ID);
        assertEq(transferred.revision, 2);
        assertEq(landRegistryApp.titleTransferNonce(TITLE_ID), 1);

        vm.expectRevert(
            abi.encodeWithSelector(ILandRegistryApp.InvalidTransferNonce.selector, TITLE_ID, uint256(0), uint256(1))
        );
        vm.prank(LAND_ADMIN);
        landRegistryApp.transferTitle(request, seller, sellerSignature, buyer, buyerSignature);
    }

    function test_TitleAuthorityFollowsPersonWalletMigration() public {
        _activateParcelWithTitle(PARCEL_ID, TITLE_ID, "parcel.one", _personParty(BUYER_PERSON_ID));

        identityRegistry.setWalletLink(BUYER_PERSON_ID, buyer, IdentityTypes.WalletLinkStatus.Revoked);
        identityRegistry.setWalletLink(BUYER_PERSON_ID, buyerReplacement, IdentityTypes.WalletLinkStatus.Active);

        LandTypes.TitleTransferRequest memory request = _transferRequest(TITLE_ID, _personParty(SELLER_PERSON_ID));
        (bytes memory oldWalletSignature, bytes memory sellerSignature) = _signTransfer(request, BUYER_KEY, SELLER_KEY);

        bytes32 buyerPartyKey = landPartyPolicy.partyKey(_personParty(BUYER_PERSON_ID));
        vm.expectRevert(abi.encodeWithSelector(ILandRegistryApp.InvalidPartySigner.selector, buyerPartyKey, buyer));
        vm.prank(LAND_ADMIN);
        landRegistryApp.transferTitle(request, buyer, oldWalletSignature, seller, sellerSignature);

        bytes32 digest = landRegistryApp.hashTitleTransferAuthorization(request);
        bytes memory replacementSignature = _signature(BUYER_REPLACEMENT_KEY, digest);
        vm.prank(LAND_ADMIN);
        landRegistryApp.transferTitle(request, buyerReplacement, replacementSignature, seller, sellerSignature);

        assertEq(landRegistry.getTitle(TITLE_ID).holder.id, SELLER_PERSON_ID);
    }

    function test_CompanyPartyUsesAnActiveDirectorAndFutureNamespacesRemainPolicyReplaceable() public {
        CompanyTypes.CompanyInput memory companyInput = CompanyTypes.CompanyInput({
            registrationNumberHash: bytes32(0),
            nameHash: keccak256("company.name"),
            jurisdictionHash: keccak256("company.jurisdiction"),
            registeredOfficeHash: keccak256("company.office"),
            metadataHash: keccak256("company.metadata"),
            articlesHash: keccak256("company.articles"),
            uboHash: keccak256("company.ubo"),
            registeredCapital: 1_000_000
        });
        companyRegistry.submitCompany(COMPANY_ID, seller, companyInput);
        companyRegistry.approveCompany(COMPANY_ID, keccak256("LLC-LAND"));

        LandTypes.PartyRef memory companyParty =
            LandTypes.PartyRef({namespace: landPartyPolicy.companyNamespace(), id: COMPANY_ID});
        assertFalse(landPartyPolicy.canAcquireLand(companyParty));

        companyRegistry.setDirector(COMPANY_ID, seller, keccak256("director"), true);
        assertTrue(landPartyPolicy.canAcquireLand(companyParty));
        assertTrue(landPartyPolicy.isAuthorizedSigner(companyParty, seller));

        LandTypes.PartyRef memory futureOwnershipGroup =
            LandTypes.PartyRef({namespace: keccak256("party.ownership-group"), id: keccak256("group.one")});
        assertFalse(landPartyPolicy.partyExists(futureOwnershipGroup));
        assertNotEq(landPartyPolicy.partyKey(futureOwnershipGroup), bytes32(0));
    }

    function test_CompanyTitleSupportsEip1271DirectorConsent() public {
        address directorOwner = vm.addr(COMPANY_DIRECTOR_KEY);
        ERC1271WalletMock directorSafe = new ERC1271WalletMock(directorOwner);
        CompanyTypes.CompanyInput memory companyInput = CompanyTypes.CompanyInput({
            registrationNumberHash: bytes32(0),
            nameHash: keccak256("safe.company.name"),
            jurisdictionHash: keccak256("safe.company.jurisdiction"),
            registeredOfficeHash: keccak256("safe.company.office"),
            metadataHash: keccak256("safe.company.metadata"),
            articlesHash: keccak256("safe.company.articles"),
            uboHash: keccak256("safe.company.ubo"),
            registeredCapital: 1_000_000
        });
        companyRegistry.submitCompany(COMPANY_ID, directorOwner, companyInput);
        companyRegistry.approveCompany(COMPANY_ID, keccak256("LLC-SAFE"));
        companyRegistry.setDirector(COMPANY_ID, address(directorSafe), keccak256("director.safe"), true);

        LandTypes.PartyRef memory companyParty =
            LandTypes.PartyRef({namespace: landPartyPolicy.companyNamespace(), id: COMPANY_ID});
        _activateParcelWithTitle(PARCEL_ID, TITLE_ID, "parcel.safe", companyParty);
        LandTypes.TitleTransferRequest memory request = _transferRequest(TITLE_ID, _personParty(BUYER_PERSON_ID));
        bytes32 digest = landRegistryApp.hashTitleTransferAuthorization(request);

        vm.prank(LAND_ADMIN);
        landRegistryApp.transferTitle(
            request,
            address(directorSafe),
            _signature(COMPANY_DIRECTOR_KEY, digest),
            buyer,
            _signature(BUYER_KEY, digest)
        );

        assertEq(landRegistry.getTitle(TITLE_ID).holder.id, BUYER_PERSON_ID);
    }

    function test_CurrentAppOnlyClosesExpiredLease() public {
        vm.prank(LAND_CLERK);
        landRegistryApp.submitParcelDraft(
            PARCEL_ID, _parcelInput("lease", "lease.draft", keccak256("lease.genesis")), keccak256("tx.lease.draft")
        );
        LandTypes.ParcelRecord memory draft = landRegistry.getParcel(PARCEL_ID);
        vm.prank(LAND_ADMIN);
        landRegistryApp.activateParcel(
            PARCEL_ID, draft.revision, _anchor("lease.activation", draft.versionHash), keccak256("tx.lease.activation")
        );
        LandTypes.ParcelRecord memory active = landRegistry.getParcel(PARCEL_ID);
        uint64 leaseExpiresAt = uint64(block.timestamp + 1 days);
        LandTypes.TitleInput memory input = LandTypes.TitleInput({
            parcelId: PARCEL_ID,
            holder: _personParty(SELLER_PERSON_ID),
            anchor: _anchor("lease.title", active.versionHash),
            tenureType: LandTypes.TenureType.Leasehold,
            leaseExpiresAt: leaseExpiresAt
        });
        vm.prank(LAND_ADMIN);
        landRegistryApp.registerTitle(TITLE_ID, input, keccak256("tx.lease.title"));
        LandTypes.TitleRecord memory title = landRegistry.getTitle(TITLE_ID);

        vm.expectRevert(abi.encodeWithSelector(ILandRegistryApp.TitleNotExpiredLease.selector, TITLE_ID));
        vm.prank(LAND_ADMIN);
        landRegistryApp.closeExpiredLease(
            PARCEL_ID,
            TITLE_ID,
            title.versionHash,
            _anchor("lease.close", title.versionHash),
            keccak256("tx.lease.close")
        );

        vm.warp(leaseExpiresAt);
        vm.prank(LAND_ADMIN);
        landRegistryApp.closeExpiredLease(
            PARCEL_ID,
            TITLE_ID,
            title.versionHash,
            _anchor("lease.close", title.versionHash),
            keccak256("tx.lease.close")
        );
        assertFalse(landRegistry.getTitle(TITLE_ID).active);
    }

    function test_RejectsPartiallySpecifiedEncumbranceBeneficiary() public {
        _activateParcelWithTitle(PARCEL_ID, TITLE_ID, "parcel.one", _personParty(SELLER_PERSON_ID));
        LandTypes.TitleRecord memory title = landRegistry.getTitle(TITLE_ID);
        LandTypes.PartyRef memory incompleteBeneficiary =
            LandTypes.PartyRef({namespace: landPartyPolicy.personNamespace(), id: bytes32(0)});
        LandTypes.EncumbranceInput memory input = LandTypes.EncumbranceInput({
            titleId: TITLE_ID,
            typeCode: keccak256("encumbrance.notice"),
            beneficiary: incompleteBeneficiary,
            anchor: _anchor("encumbrance.notice", title.versionHash),
            validUntil: 0
        });

        vm.expectRevert(abi.encodeWithSelector(ILandRegistryApp.InvalidParty.selector, incompleteBeneficiary));
        vm.prank(LAND_ADMIN);
        landRegistryApp.registerEncumbrance(ENCUMBRANCE_ID, input, keccak256("tx.encumbrance.notice"));
    }

    function test_AcceptedDisputeAndEncumbranceLockTransferUntilResolved() public {
        _activateParcelWithTitle(PARCEL_ID, TITLE_ID, "parcel.one", _personParty(SELLER_PERSON_ID));

        LandTypes.PartyRef memory claimant = _personParty(BUYER_PERSON_ID);
        vm.prank(buyer);
        landRegistryApp.fileDispute(
            DISPUTE_ID, PARCEL_ID, claimant, keccak256("dispute.evidence"), keccak256("tx.dispute.file")
        );
        assertEq(landRegistry.activeDisputeCountOf(PARCEL_ID), 0);

        vm.prank(LAND_ADMIN);
        landRegistryApp.acceptDispute(DISPUTE_ID, bytes32(0), keccak256("tx.dispute.accept"));
        assertEq(landRegistry.activeDisputeCountOf(PARCEL_ID), 1);
        assertEq(uint256(landRegistry.getParcel(PARCEL_ID).status), uint256(LandTypes.ParcelStatus.Disputed));

        vm.prank(LAND_ADMIN);
        landRegistryApp.resolveDispute(
            DISPUTE_ID, keccak256("dispute.resolution"), false, keccak256("tx.dispute.resolve")
        );
        assertEq(landRegistry.activeDisputeCountOf(PARCEL_ID), 0);

        LandTypes.TitleRecord memory title = landRegistry.getTitle(TITLE_ID);
        LandTypes.EncumbranceInput memory encumbrance = LandTypes.EncumbranceInput({
            titleId: TITLE_ID,
            typeCode: keccak256("encumbrance.mortgage"),
            beneficiary: _personParty(BUYER_PERSON_ID),
            anchor: _anchor("encumbrance", title.versionHash),
            validUntil: 0
        });
        vm.prank(LAND_ADMIN);
        landRegistryApp.registerEncumbrance(ENCUMBRANCE_ID, encumbrance, keccak256("tx.encumbrance.register"));

        LandTypes.TitleTransferRequest memory request = _transferRequest(TITLE_ID, _personParty(BUYER_PERSON_ID));
        (bytes memory sellerSignature, bytes memory buyerSignature) = _signTransfer(request, SELLER_KEY, BUYER_KEY);
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.ParcelTransferLocked.selector, PARCEL_ID));
        vm.prank(LAND_ADMIN);
        landRegistryApp.transferTitle(request, seller, sellerSignature, buyer, buyerSignature);
        assertEq(landRegistryApp.titleTransferNonce(TITLE_ID), 0);

        LandTypes.EncumbranceRecord memory stored = landRegistry.getEncumbrance(ENCUMBRANCE_ID);
        vm.prank(LAND_ADMIN);
        landRegistryApp.releaseEncumbrance(
            ENCUMBRANCE_ID,
            _anchor("encumbrance.release", stored.anchor.contentHash),
            keccak256("tx.encumbrance.release")
        );

        vm.prank(LAND_ADMIN);
        landRegistryApp.transferTitle(request, seller, sellerSignature, buyer, buyerSignature);
        assertEq(landRegistry.getTitle(TITLE_ID).holder.id, BUYER_PERSON_ID);
    }

    function test_SubdivisionAndMergeAreAtomicBoundedAndPreserveStableHolder() public {
        _activateParcelWithTitle(PARCEL_ID, TITLE_ID, "parent", _personParty(SELLER_PERSON_ID));
        LandTypes.ParcelRecord memory parent = landRegistry.getParcel(PARCEL_ID);
        LandTypes.TitleRecord memory parentTitle = landRegistry.getTitle(TITLE_ID);

        LandTypes.SubdivisionChild[] memory children = new LandTypes.SubdivisionChild[](2);
        children[0] = LandTypes.SubdivisionChild({
            parcelId: keccak256("child.one"),
            titleId: keccak256("child.title.one"),
            parcel: _parcelInput("child.one", "child.one", parent.versionHash),
            titleAnchor: _anchor("child.title.one", parentTitle.versionHash)
        });
        children[1] = LandTypes.SubdivisionChild({
            parcelId: keccak256("child.two"),
            titleId: keccak256("child.title.two"),
            parcel: _parcelInput("child.two", "child.two", parent.versionHash),
            titleAnchor: _anchor("child.title.two", parentTitle.versionHash)
        });

        vm.prank(LAND_ADMIN);
        landRegistryApp.subdivideParcel(PARCEL_ID, parent.revision, children, keccak256("tx.subdivide"));

        assertEq(uint256(landRegistry.getParcel(PARCEL_ID).status), uint256(LandTypes.ParcelStatus.Retired));
        assertFalse(landRegistry.getTitle(TITLE_ID).active);
        assertEq(landRegistry.getTitle(children[0].titleId).holder.id, SELLER_PERSON_ID);
        assertEq(landRegistry.getTitle(children[1].titleId).holder.id, SELLER_PERSON_ID);

        bytes32[] memory sourceIds = new bytes32[](2);
        sourceIds[0] = children[0].parcelId;
        sourceIds[1] = children[1].parcelId;
        uint64[] memory revisions = new uint64[](2);
        bytes32[] memory parcelVersions = new bytes32[](2);
        bytes32[] memory titleVersions = new bytes32[](2);
        for (uint256 index = 0; index < 2; ++index) {
            LandTypes.ParcelRecord memory childParcel = landRegistry.getParcel(sourceIds[index]);
            LandTypes.TitleRecord memory childTitle =
                landRegistry.getTitle(landRegistry.activeTitleOfParcel(sourceIds[index]));
            revisions[index] = childParcel.revision;
            parcelVersions[index] = childParcel.versionHash;
            titleVersions[index] = childTitle.versionHash;
        }

        bytes32 mergedParcelId = keccak256("parcel.merged");
        bytes32 mergedTitleId = keccak256("title.merged");
        LandTypes.MergeResult memory result = LandTypes.MergeResult({
            parcelId: mergedParcelId,
            titleId: mergedTitleId,
            parcel: _parcelInput("parcel.merged", "parcel.merged", keccak256(abi.encode(parcelVersions))),
            titleAnchor: _anchor("title.merged", keccak256(abi.encode(titleVersions)))
        });

        vm.prank(LAND_ADMIN);
        landRegistryApp.mergeParcels(sourceIds, revisions, result, keccak256("tx.merge"));

        assertEq(uint256(landRegistry.getParcel(mergedParcelId).status), uint256(LandTypes.ParcelStatus.Active));
        assertEq(landRegistry.getTitle(mergedTitleId).holder.id, SELLER_PERSON_ID);
        assertEq(uint256(landRegistry.getParcel(sourceIds[0]).status), uint256(LandTypes.ParcelStatus.Retired));
        assertEq(uint256(landRegistry.getParcel(sourceIds[1]).status), uint256(LandTypes.ParcelStatus.Retired));
    }

    function test_BoundaryAdjustmentUpdatesBothParcelsOrNeither() public {
        _activateParcelWithTitle(PARCEL_ID, TITLE_ID, "parcel.one", _personParty(SELLER_PERSON_ID));
        _activateParcelWithTitle(PARCEL_TWO_ID, TITLE_TWO_ID, "parcel.two", _personParty(BUYER_PERSON_ID));

        LandTypes.ParcelRecord memory firstBefore = landRegistry.getParcel(PARCEL_ID);
        LandTypes.ParcelRecord memory secondBefore = landRegistry.getParcel(PARCEL_TWO_ID);
        LandTypes.ParcelRevisionInput memory first = LandTypes.ParcelRevisionInput({
            parcelId: PARCEL_ID,
            expectedRevision: firstBefore.revision,
            parcel: _parcelInput("parcel.one", "boundary.one", firstBefore.versionHash)
        });
        LandTypes.ParcelRevisionInput memory second = LandTypes.ParcelRevisionInput({
            parcelId: PARCEL_TWO_ID,
            expectedRevision: secondBefore.revision,
            parcel: _parcelInput("parcel.two", "boundary.two", secondBefore.versionHash)
        });

        second.expectedRevision += 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILandRegistry.StaleParcelRevision.selector,
                PARCEL_TWO_ID,
                second.expectedRevision,
                secondBefore.revision
            )
        );
        vm.prank(LAND_ADMIN);
        landRegistryApp.adjustBoundary(first, second, keccak256("tx.boundary.invalid"));
        assertEq(landRegistry.getParcel(PARCEL_ID).revision, firstBefore.revision);

        second.expectedRevision = secondBefore.revision;
        vm.prank(LAND_ADMIN);
        landRegistryApp.adjustBoundary(first, second, keccak256("tx.boundary"));
        assertEq(landRegistry.getParcel(PARCEL_ID).revision, firstBefore.revision + 1);
        assertEq(landRegistry.getParcel(PARCEL_TWO_ID).revision, secondBefore.revision + 1);
    }

    function _activateParcelWithTitle(
        bytes32 parcelId,
        bytes32 titleId,
        string memory salt,
        LandTypes.PartyRef memory holder
    ) private {
        vm.prank(LAND_CLERK);
        landRegistryApp.submitParcelDraft(
            parcelId,
            _parcelInput(salt, salt, keccak256(abi.encodePacked(salt, ".genesis"))),
            keccak256(abi.encodePacked(salt, ".draft.tx"))
        );
        LandTypes.ParcelRecord memory draft = landRegistry.getParcel(parcelId);

        vm.prank(LAND_ADMIN);
        landRegistryApp.activateParcel(
            parcelId,
            draft.revision,
            _anchor(string.concat(salt, ".activation"), draft.versionHash),
            keccak256(abi.encodePacked(salt, ".activation.tx"))
        );
        LandTypes.ParcelRecord memory active = landRegistry.getParcel(parcelId);

        vm.prank(LAND_ADMIN);
        landRegistryApp.registerTitle(
            titleId,
            _titleInput(parcelId, holder, active.versionHash, string.concat(salt, ".title")),
            keccak256(abi.encodePacked(salt, ".title.tx"))
        );
    }

    function _transferRequest(bytes32 titleId, LandTypes.PartyRef memory newHolder)
        private
        view
        returns (LandTypes.TitleTransferRequest memory request)
    {
        LandTypes.TitleRecord memory title = landRegistry.getTitle(titleId);
        request = LandTypes.TitleTransferRequest({
            titleId: titleId,
            expectedVersionHash: title.versionHash,
            newHolder: newHolder,
            anchor: _anchor("title.transfer", title.versionHash),
            transactionId: keccak256(abi.encodePacked("tx.transfer", titleId, newHolder.namespace, newHolder.id)),
            nonce: landRegistryApp.titleTransferNonce(titleId),
            deadline: uint64(block.timestamp + 1 days)
        });
    }

    function _signTransfer(LandTypes.TitleTransferRequest memory request, uint256 sellerKey, uint256 buyerKey)
        private
        view
        returns (bytes memory sellerSignature, bytes memory buyerSignature)
    {
        bytes32 digest = landRegistryApp.hashTitleTransferAuthorization(request);
        return (_signature(sellerKey, digest), _signature(buyerKey, digest));
    }

    function _signature(uint256 privateKey, bytes32 digest) private pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _registerPerson(bytes32 personId, address wallet) private {
        identityRegistry.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256(abi.encodePacked("identity", personId)),
                metadataURI: "ipfs://identity",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.None,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identityRegistry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
    }

    function _personParty(bytes32 personId) private view returns (LandTypes.PartyRef memory party) {
        return LandTypes.PartyRef({namespace: landPartyPolicy.personNamespace(), id: personId});
    }

    function _parcelInput(string memory parcelSalt, string memory versionSalt, bytes32 lineageHash)
        private
        pure
        returns (LandTypes.ParcelInput memory input)
    {
        input = LandTypes.ParcelInput({
            parcelNumberHash: keccak256(abi.encodePacked(parcelSalt, ".number")),
            districtHash: keccak256(abi.encodePacked(parcelSalt, ".district")),
            anchor: _anchor(versionSalt, lineageHash),
            spatialDataHash: keccak256(abi.encodePacked(versionSalt, ".spatial")),
            coordinateReferenceSystemHash: keccak256("EPSG:4258"),
            spatialType: LandTypes.SpatialType.Polygon,
            areaSquareMeters: 10_000
        });
    }

    function _titleInput(bytes32 parcelId, LandTypes.PartyRef memory holder, bytes32 lineageHash, string memory salt)
        private
        pure
        returns (LandTypes.TitleInput memory input)
    {
        input = LandTypes.TitleInput({
            parcelId: parcelId,
            holder: holder,
            anchor: _anchor(salt, lineageHash),
            tenureType: LandTypes.TenureType.Freehold,
            leaseExpiresAt: 0
        });
    }

    function _anchor(string memory salt, bytes32 lineageHash)
        private
        pure
        returns (LandTypes.RecordAnchor memory anchor)
    {
        anchor = LandTypes.RecordAnchor({
            schemaId: keccak256("liberland.cadastre.v1"),
            contentHash: keccak256(abi.encodePacked(salt, ".content")),
            sourceDocumentHash: keccak256(abi.encodePacked(salt, ".document")),
            lineageHash: lineageHash,
            schemaVersion: 1
        });
    }
}
