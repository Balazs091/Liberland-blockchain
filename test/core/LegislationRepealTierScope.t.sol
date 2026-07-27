// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ILegislationRegistry} from "../../contracts/interfaces/ILegislationRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LegislationRegistry} from "../../contracts/registries/LegislationRegistry.sol";
import {LegislationTypes} from "../../contracts/types/LegislationTypes.sol";

/// @title LegislationRepealTierScopeTest
/// @notice The registry enforces each bounded repeal pathway's tier scope, independent of the caller.
contract LegislationRepealTierScopeTest is Test {
    ConstitutionKernel internal kernel;
    LegislationRegistry internal legislationRegistry;

    bytes32 internal constant LAW_MEASURE_ID = keccak256("measure.law");
    bytes32 internal constant SUB_LEGAL_MEASURE_ID = keccak256("measure.sublegal");
    bytes32 internal constant REPEAL_REFERENCE = keccak256("repeal.reference");

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        legislationRegistry = new LegislationRegistry(address(kernel));

        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY, address(legislationRegistry));
        // This test acts as both the enactment authority and the bounded repeal authority.
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REPEAL_AUTHORITY, address(this));
        kernel.disableBootstrapAuthority();

        _enact(LAW_MEASURE_ID, LegislationTypes.LegislationTier.Law);
        _enact(SUB_LEGAL_MEASURE_ID, LegislationTypes.LegislationTier.SubLegalTier3);
    }

    function test_SenateCannotRepealLawTier() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILegislationRegistry.RepealTierNotPermitted.selector,
                LegislationTypes.RepealOrigin.Senate,
                LegislationTypes.LegislationTier.Law
            )
        );
        legislationRegistry.recordRepeal(LAW_MEASURE_ID, LegislationTypes.RepealOrigin.Senate, REPEAL_REFERENCE);
    }

    function test_PublicVetoCannotRepealSubLegalTier() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILegislationRegistry.RepealTierNotPermitted.selector,
                LegislationTypes.RepealOrigin.PublicVeto,
                LegislationTypes.LegislationTier.SubLegalTier3
            )
        );
        legislationRegistry.recordRepeal(
            SUB_LEGAL_MEASURE_ID, LegislationTypes.RepealOrigin.PublicVeto, REPEAL_REFERENCE
        );
    }

    function test_PermittedRepealPairsSucceed() public {
        legislationRegistry.recordRepeal(LAW_MEASURE_ID, LegislationTypes.RepealOrigin.PublicVeto, REPEAL_REFERENCE);
        assertTrue(legislationRegistry.getLegislationRecord(LAW_MEASURE_ID).repealed);

        legislationRegistry.recordRepeal(SUB_LEGAL_MEASURE_ID, LegislationTypes.RepealOrigin.Senate, REPEAL_REFERENCE);
        assertTrue(legislationRegistry.getLegislationRecord(SUB_LEGAL_MEASURE_ID).repealed);
    }

    function _enact(bytes32 measureId, LegislationTypes.LegislationTier tier) internal {
        legislationRegistry.recordEnactment(
            measureId,
            LegislationTypes.LegislationRecordInput({
                tier: tier,
                textHash: keccak256(abi.encode("text", measureId)),
                proposerReference: keccak256("proposer"),
                enactedByReferendumId: keccak256(abi.encode("referendum", measureId)),
                amendsMeasureId: bytes32(0)
            })
        );
    }
}
