// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {LandRegistryApp} from "../../contracts/apps/LandRegistryApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LandPartyPolicy} from "../../contracts/policies/LandPartyPolicy.sol";
import {OfficePermissionPolicy} from "../../contracts/policies/OfficePermissionPolicy.sol";
import {CompanyRegistry} from "../../contracts/registries/CompanyRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LandRegistry} from "../../contracts/registries/LandRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LandTypes} from "../../contracts/types/LandTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

contract LandRegistryInvariantHandler is Test {
    uint256 internal constant RECORD_SLOTS = 8;

    LandRegistryApp public immutable app;
    LandRegistry public immutable registry;
    LandPartyPolicy public immutable partyPolicy;
    bytes32 public immutable holderPersonId;
    mapping(uint256 slot => uint64 revisionSalt) private _revisionSalts;

    constructor(LandRegistryApp app_, LandRegistry registry_, LandPartyPolicy partyPolicy_, bytes32 holderPersonId_) {
        app = app_;
        registry = registry_;
        partyPolicy = partyPolicy_;
        holderPersonId = holderPersonId_;
    }

    /// @notice Submits a parcel draft in an unused bounded fixture slot.
    function submitDraft(uint256 seed) external {
        uint256 slot = seed % RECORD_SLOTS;
        bytes32 parcelId = parcelIdFor(slot);
        if (registry.parcelExists(parcelId)) {
            return;
        }
        try app.submitParcelDraft(
            parcelId,
            _parcelInput(slot, 0, keccak256(abi.encode("invariant.land.source", slot))),
            keccak256(abi.encode("invariant.land.draft", slot))
        ) {}
            catch {}
    }

    /// @notice Attempts to activate a prepared fixture parcel.
    function activateParcel(uint256 seed) external {
        uint256 slot = seed % RECORD_SLOTS;
        bytes32 parcelId = parcelIdFor(slot);
        if (!registry.parcelExists(parcelId)) {
            return;
        }
        LandTypes.ParcelRecord memory parcel = registry.getParcel(parcelId);
        if (parcel.status != LandTypes.ParcelStatus.Draft) {
            return;
        }
        try app.activateParcel(
            parcelId,
            parcel.revision,
            _anchor(keccak256(abi.encode("invariant.land.activation", slot)), parcel.versionHash),
            keccak256(abi.encode("invariant.land.activation.tx", slot))
        ) {}
            catch {}
    }

    /// @notice Attempts a lineage-bound revision of an active fixture parcel.
    function reviseParcel(uint256 seed) external {
        uint256 slot = seed % RECORD_SLOTS;
        bytes32 parcelId = parcelIdFor(slot);
        if (!registry.parcelExists(parcelId)) {
            return;
        }
        LandTypes.ParcelRecord memory parcel = registry.getParcel(parcelId);
        if (parcel.status != LandTypes.ParcelStatus.Active) {
            return;
        }
        uint64 revisionSalt = ++_revisionSalts[slot];
        try app.reviseParcel(
            parcelId,
            parcel.revision,
            _parcelInput(slot, revisionSalt, parcel.versionHash),
            keccak256(abi.encode("invariant.land.revision.tx", slot, revisionSalt))
        ) {}
            catch {}
    }

    /// @notice Attempts to register the sole active title for an untitled active parcel.
    function registerTitle(uint256 seed) external {
        uint256 slot = seed % RECORD_SLOTS;
        bytes32 parcelId = parcelIdFor(slot);
        bytes32 titleId = titleIdFor(slot);
        if (!registry.parcelExists(parcelId) || registry.titleExists(titleId)) {
            return;
        }
        LandTypes.ParcelRecord memory parcel = registry.getParcel(parcelId);
        if (parcel.status != LandTypes.ParcelStatus.Active || registry.activeTitleOfParcel(parcelId) != bytes32(0)) {
            return;
        }
        LandTypes.TitleInput memory input = LandTypes.TitleInput({
            parcelId: parcelId,
            holder: LandTypes.PartyRef({namespace: partyPolicy.personNamespace(), id: holderPersonId}),
            anchor: _anchor(keccak256(abi.encode("invariant.land.title", slot)), parcel.versionHash),
            tenureType: LandTypes.TenureType.Freehold,
            leaseExpiresAt: 0
        });
        try app.registerTitle(titleId, input, keccak256(abi.encode("invariant.land.title.tx", slot))) {} catch {}
    }

    /// @notice Attempts to register one active encumbrance for a fixture title.
    function registerEncumbrance(uint256 seed) external {
        uint256 slot = seed % RECORD_SLOTS;
        bytes32 titleId = titleIdFor(slot);
        bytes32 encumbranceId = encumbranceIdFor(slot);
        if (!registry.titleExists(titleId) || registry.getEncumbrance(encumbranceId).encumbranceId != bytes32(0)) {
            return;
        }
        LandTypes.TitleRecord memory title = registry.getTitle(titleId);
        if (!title.active) {
            return;
        }
        LandTypes.EncumbranceInput memory input = LandTypes.EncumbranceInput({
            titleId: titleId,
            typeCode: keccak256("invariant.encumbrance"),
            beneficiary: LandTypes.PartyRef({namespace: bytes32(0), id: bytes32(0)}),
            anchor: _anchor(keccak256(abi.encode("invariant.encumbrance", slot)), title.versionHash),
            validUntil: 0
        });
        try app.registerEncumbrance(encumbranceId, input, keccak256(abi.encode("invariant.encumbrance.tx", slot))) {}
            catch {}
    }

    /// @notice Attempts the anchored release of an active fixture encumbrance.
    function releaseEncumbrance(uint256 seed) external {
        uint256 slot = seed % RECORD_SLOTS;
        bytes32 encumbranceId = encumbranceIdFor(slot);
        LandTypes.EncumbranceRecord memory encumbrance = registry.getEncumbrance(encumbranceId);
        if (encumbrance.status != LandTypes.EncumbranceStatus.Active) {
            return;
        }
        try app.releaseEncumbrance(
            encumbranceId,
            _anchor(keccak256(abi.encode("invariant.encumbrance.release", slot)), encumbrance.anchor.contentHash),
            keccak256(abi.encode("invariant.encumbrance.release.tx", slot))
        ) {}
            catch {}
    }

    /// @notice Derives the deterministic parcel identifier for a fixture slot.
    function parcelIdFor(uint256 slot) public pure returns (bytes32 parcelId) {
        return keccak256(abi.encode("invariant.parcel", slot));
    }

    /// @notice Derives the deterministic title identifier for a fixture slot.
    function titleIdFor(uint256 slot) public pure returns (bytes32 titleId) {
        return keccak256(abi.encode("invariant.title", slot));
    }

    /// @notice Derives the deterministic encumbrance identifier for a fixture slot.
    function encumbranceIdFor(uint256 slot) public pure returns (bytes32 encumbranceId) {
        return keccak256(abi.encode("invariant.encumbrance", slot));
    }

    function _parcelInput(uint256 slot, uint64 revisionSalt, bytes32 lineageHash)
        private
        pure
        returns (LandTypes.ParcelInput memory input)
    {
        input = LandTypes.ParcelInput({
            parcelNumberHash: keccak256(abi.encode("invariant.parcel.number", slot)),
            districtHash: keccak256("invariant.district"),
            anchor: _anchor(keccak256(abi.encode("invariant.parcel.content", slot, revisionSalt)), lineageHash),
            spatialDataHash: keccak256(abi.encode("invariant.parcel.spatial", slot, revisionSalt)),
            coordinateReferenceSystemHash: keccak256("EPSG:4258"),
            spatialType: LandTypes.SpatialType.Polygon,
            areaSquareMeters: 10_000 + revisionSalt
        });
    }

    function _anchor(bytes32 contentSeed, bytes32 lineageHash)
        private
        pure
        returns (LandTypes.RecordAnchor memory anchor)
    {
        anchor = LandTypes.RecordAnchor({
            schemaId: keccak256("liberland.cadastre.invariant.v1"),
            contentHash: keccak256(abi.encode(contentSeed, "content")),
            sourceDocumentHash: keccak256(abi.encode(contentSeed, "source")),
            lineageHash: lineageHash,
            schemaVersion: 1
        });
    }
}

/// @title LandRegistryInvariantTest
/// @notice Stateful coverage for version provenance, active-title uniqueness, and encumbrance lock accounting.
contract LandRegistryInvariantTest is Test {
    uint256 internal constant RECORD_SLOTS = 8;
    bytes32 internal constant LAND_OFFICE_ID = keccak256("office.land.invariant");
    bytes32 internal constant HOLDER_PERSON_ID = keccak256("person.land.invariant-holder");

    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    LandRegistry internal landRegistry;
    LandRegistryApp internal landRegistryApp;
    LandRegistryInvariantHandler internal handler;

    /// @notice Deploys the office-authorized land registry invariant fixture.
    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identityRegistry = new IdentityRegistry(address(kernel));
        CompanyRegistry companyRegistry = new CompanyRegistry(address(kernel));
        OfficeRegistry officeRegistry = new OfficeRegistry(address(kernel));
        landRegistry = new LandRegistry(address(kernel));
        OfficePermissionPolicy officePermissionPolicy = new OfficePermissionPolicy();
        LandPartyPolicy landPartyPolicy =
            new LandPartyPolicy(address(identityRegistry), address(companyRegistry), address(officeRegistry));
        landRegistryApp = new LandRegistryApp(
            address(landRegistry),
            address(officeRegistry),
            address(officePermissionPolicy),
            address(landPartyPolicy),
            LAND_OFFICE_ID
        );
        handler = new LandRegistryInvariantHandler(landRegistryApp, landRegistry, landPartyPolicy, HOLDER_PERSON_ID);

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
            LAND_OFFICE_ID, OfficeTypes.OfficeKind.LandRegistryOffice, "Invariant Land Registry", address(handler)
        );
        identityRegistry.setIdentityRecord(
            HOLDER_PERSON_ID,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256("invariant.land.holder"),
                metadataURI: "ipfs://invariant-land-holder",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.None,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identityRegistry.setWalletLink(HOLDER_PERSON_ID, address(handler), IdentityTypes.WalletLinkStatus.Active);
        kernel.disableBootstrapAuthority();

        targetContract(address(handler));
    }

    /// @notice Proves every known parcel retains revision, version, transaction, and source-document provenance.
    function invariant_ParcelVersionsAlwaysRetainCompleteProvenance() public view {
        for (uint256 slot = 0; slot < RECORD_SLOTS; ++slot) {
            bytes32 parcelId = handler.parcelIdFor(slot);
            if (!landRegistry.parcelExists(parcelId)) {
                continue;
            }
            LandTypes.ParcelRecord memory parcel = landRegistry.getParcel(parcelId);
            assertEq(parcel.parcelId, parcelId);
            assertGt(parcel.revision, 0);
            assertNotEq(parcel.versionHash, bytes32(0));
            assertNotEq(parcel.lastTransactionId, bytes32(0));
            assertNotEq(parcel.anchor.contentHash, bytes32(0));
            assertNotEq(parcel.anchor.sourceDocumentHash, bytes32(0));
        }
    }

    /// @notice Proves each parcel has at most one active title and both lookup directions agree.
    function invariant_EachParcelHasAtMostOneConsistentActiveTitle() public view {
        for (uint256 parcelSlot = 0; parcelSlot < RECORD_SLOTS; ++parcelSlot) {
            bytes32 parcelId = handler.parcelIdFor(parcelSlot);
            bytes32 activeTitleId = landRegistry.activeTitleOfParcel(parcelId);
            uint256 activeTitleCount;
            for (uint256 titleSlot = 0; titleSlot < RECORD_SLOTS; ++titleSlot) {
                bytes32 titleId = handler.titleIdFor(titleSlot);
                if (!landRegistry.titleExists(titleId)) {
                    continue;
                }
                LandTypes.TitleRecord memory title = landRegistry.getTitle(titleId);
                if (title.active && title.parcelId == parcelId) {
                    activeTitleCount += 1;
                    assertEq(activeTitleId, titleId);
                    assertNotEq(title.versionHash, bytes32(0));
                    assertNotEq(title.lastTransactionId, bytes32(0));
                }
            }
            assertLe(activeTitleCount, 1);
            assertEq(activeTitleId == bytes32(0), activeTitleCount == 0);
        }
    }

    /// @notice Proves each parcel's active-encumbrance count matches its canonical fixture record.
    function invariant_EncumbranceCountsMatchActiveRecords() public view {
        for (uint256 slot = 0; slot < RECORD_SLOTS; ++slot) {
            bytes32 parcelId = handler.parcelIdFor(slot);
            LandTypes.EncumbranceRecord memory encumbrance = landRegistry.getEncumbrance(handler.encumbranceIdFor(slot));
            uint256 expectedCount = encumbrance.status == LandTypes.EncumbranceStatus.Active ? 1 : 0;
            assertEq(landRegistry.activeEncumbranceCountOf(parcelId), expectedCount);
        }
    }
}
