// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ILandRegistry} from "../../contracts/interfaces/ILandRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LandRegistry} from "../../contracts/registries/LandRegistry.sol";
import {LandTypes} from "../../contracts/types/LandTypes.sol";

/// @title LandTitleLifecycleTest
/// @notice L4: registry-authority-gated title close plus the retire guard against open accepted disputes.
contract LandTitleLifecycleTest is Test {
    ConstitutionKernel internal kernel;
    LandRegistry internal landRegistry;

    bytes32 internal constant PARCEL_ID = keccak256("parcel.one");
    bytes32 internal constant TITLE_ID = keccak256("title.one");
    bytes32 internal constant DISPUTE_ID = keccak256("dispute.one");
    bytes32 internal constant DOC_HASH = keccak256("doc");

    address internal constant HOLDER = address(0xBEEF);
    address internal constant CLAIMANT = address(0xD15C);
    address internal constant OUTSIDER = address(0xBAD);

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        landRegistry = new LandRegistry(address(kernel));

        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY, address(landRegistry));
        // This test acts as the land registry authority (the office app in production).
        kernel.bootstrapSetModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY, address(this));
        kernel.disableBootstrapAuthority();

        landRegistry.createParcel(PARCEL_ID, _parcelInput());
        landRegistry.activateParcel(PARCEL_ID, DOC_HASH);
    }

    function test_L4_RetireParcelBlockedByActiveDispute() public {
        landRegistry.fileDispute(DISPUTE_ID, PARCEL_ID, CLAIMANT, keccak256("evidence"));
        landRegistry.acceptDispute(DISPUTE_ID, bytes32(0));
        assertEq(landRegistry.activeDisputeCountOf(PARCEL_ID), 1);

        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.ParcelTransferLocked.selector, PARCEL_ID));
        landRegistry.retireParcel(PARCEL_ID, keccak256("retire-doc"));
    }

    function test_L4_CloseTitleThenRetireSucceeds() public {
        landRegistry.registerTitle(TITLE_ID, _titleInput());
        assertEq(landRegistry.activeTitleOfParcel(PARCEL_ID), TITLE_ID);

        landRegistry.closeTitle(PARCEL_ID, TITLE_ID, keccak256("close-doc"));
        assertEq(landRegistry.activeTitleOfParcel(PARCEL_ID), bytes32(0));
        assertFalse(landRegistry.getTitle(TITLE_ID).active);

        landRegistry.retireParcel(PARCEL_ID, keccak256("retire-doc"));
        assertEq(uint256(landRegistry.getParcel(PARCEL_ID).status), uint256(LandTypes.ParcelStatus.Retired));
    }

    function test_L4_CloseTitleRequiresRegistryAuthority() public {
        landRegistry.registerTitle(TITLE_ID, _titleInput());

        vm.prank(OUTSIDER);
        vm.expectRevert(abi.encodeWithSelector(ILandRegistry.UnauthorizedLandRegistryCaller.selector, OUTSIDER));
        landRegistry.closeTitle(PARCEL_ID, TITLE_ID, keccak256("close-doc"));
    }

    function _parcelInput() internal pure returns (LandTypes.ParcelInput memory input) {
        input = LandTypes.ParcelInput({
            parcelNumberHash: keccak256("parcel-number"),
            districtHash: keccak256("district"),
            metadataHash: keccak256("metadata"),
            spatialDataHash: keccak256("spatial"),
            documentHash: keccak256("doc-input"),
            spatialType: LandTypes.SpatialType.Polygon,
            areaSquareMeters: 1000
        });
    }

    function _titleInput() internal pure returns (LandTypes.TitleInput memory input) {
        input = LandTypes.TitleInput({
            parcelId: PARCEL_ID,
            holder: HOLDER,
            tenureType: LandTypes.TenureType.Freehold,
            leaseExpiresAt: 0,
            documentHash: keccak256("title-doc")
        });
    }
}
