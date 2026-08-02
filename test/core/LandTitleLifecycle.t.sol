// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ILandRegistry} from "../../contracts/interfaces/ILandRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LandRegistry} from "../../contracts/registries/LandRegistry.sol";
import {LandTypes} from "../../contracts/types/LandTypes.sol";

/// @title LandTitleLifecycleTest
/// @notice Covers registry-authority gating, title closure, and retirement locks in the stable fact layer.
contract LandTitleLifecycleTest is Test {
    ConstitutionKernel internal kernel;
    LandRegistry internal landRegistry;

    bytes32 internal constant PARCEL_ID = keccak256("parcel.one");
    bytes32 internal constant TITLE_ID = keccak256("title.one");
    bytes32 internal constant DISPUTE_ID = keccak256("dispute.one");
    bytes32 internal constant PERSON_NAMESPACE = keccak256("party.person");
    bytes32 internal constant HOLDER_ID = keccak256("person.holder");
    bytes32 internal constant CLAIMANT_ID = keccak256("person.claimant");

    address internal constant OUTSIDER = address(0xBAD);

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        landRegistry = new LandRegistry(address(kernel));

        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY, address(landRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY, address(this));
        kernel.disableBootstrapAuthority();

        landRegistry.createParcelDraft(PARCEL_ID, _parcelInput(keccak256("survey.genesis")), keccak256("tx.draft"));
        LandTypes.ParcelRecord memory draft = landRegistry.getParcel(PARCEL_ID);
        landRegistry.activateParcel(
            PARCEL_ID, draft.revision, _anchor("activate", draft.versionHash), keccak256("tx.activate")
        );
    }

    function test_RetireParcelBlockedByActiveDispute() public {
        landRegistry.fileDispute(
            DISPUTE_ID,
            PARCEL_ID,
            LandTypes.PartyRef({namespace: PERSON_NAMESPACE, id: CLAIMANT_ID}),
            keccak256("evidence"),
            keccak256("tx.dispute.file")
        );
        landRegistry.acceptDispute(DISPUTE_ID, bytes32(0), keccak256("tx.dispute.accept"));
        assertEq(landRegistry.activeDisputeCountOf(PARCEL_ID), 1);

        LandTypes.ParcelRecord memory parcel = landRegistry.getParcel(PARCEL_ID);
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.ParcelTransferLocked.selector, PARCEL_ID));
        landRegistry.retireParcel(
            PARCEL_ID, parcel.revision, _anchor("retire", parcel.versionHash), keccak256("tx.retire")
        );
    }

    function test_CloseTitleThenRetireSucceeds() public {
        _registerTitle();
        LandTypes.TitleRecord memory title = landRegistry.getTitle(TITLE_ID);
        assertEq(landRegistry.activeTitleOfParcel(PARCEL_ID), TITLE_ID);

        landRegistry.closeTitle(
            PARCEL_ID, TITLE_ID, title.versionHash, _anchor("close", title.versionHash), keccak256("tx.close")
        );
        assertEq(landRegistry.activeTitleOfParcel(PARCEL_ID), bytes32(0));
        assertFalse(landRegistry.getTitle(TITLE_ID).active);

        LandTypes.ParcelRecord memory parcel = landRegistry.getParcel(PARCEL_ID);
        landRegistry.retireParcel(
            PARCEL_ID, parcel.revision, _anchor("retire", parcel.versionHash), keccak256("tx.retire")
        );
        assertEq(uint256(landRegistry.getParcel(PARCEL_ID).status), uint256(LandTypes.ParcelStatus.Retired));
    }

    function test_CloseTitleRequiresRegistryAuthority() public {
        _registerTitle();
        LandTypes.TitleRecord memory title = landRegistry.getTitle(TITLE_ID);

        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.UnauthorizedLandRegistryCaller.selector, OUTSIDER));
        landRegistry.closeTitle(
            PARCEL_ID, TITLE_ID, title.versionHash, _anchor("close", title.versionHash), keccak256("tx.close")
        );
    }

    function _registerTitle() private {
        LandTypes.ParcelRecord memory parcel = landRegistry.getParcel(PARCEL_ID);
        landRegistry.registerTitle(
            TITLE_ID,
            LandTypes.TitleInput({
                parcelId: PARCEL_ID,
                holder: LandTypes.PartyRef({namespace: PERSON_NAMESPACE, id: HOLDER_ID}),
                anchor: _anchor("title", parcel.versionHash),
                tenureType: LandTypes.TenureType.Freehold,
                leaseExpiresAt: 0
            }),
            keccak256("tx.title")
        );
    }

    function _parcelInput(bytes32 lineageHash) private pure returns (LandTypes.ParcelInput memory input) {
        input = LandTypes.ParcelInput({
            parcelNumberHash: keccak256("parcel-number"),
            districtHash: keccak256("district"),
            anchor: _anchor("parcel", lineageHash),
            spatialDataHash: keccak256("spatial"),
            coordinateReferenceSystemHash: keccak256("EPSG:4258"),
            spatialType: LandTypes.SpatialType.Polygon,
            areaSquareMeters: 1_000
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
