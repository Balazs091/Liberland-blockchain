// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

/// @title RegistryAuthorityFallbackTest
/// @notice L7: an unregistered primary registry authority must not brick the setup-authority fallback.
/// @notice E1: exercises the narrow getCitizenshipSummary accessor added for the electorate snapshot.
contract RegistryAuthorityFallbackTest is Test {
    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    CongressCandidateRegistry internal congressCandidateRegistry;

    bytes32 internal constant PERSON_ID = bytes32(uint256(0xABCD));

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        congressCandidateRegistry = new CongressCandidateRegistry(address(kernel));

        // Register ONLY the one-time setup authority. The three primary registry authorities are left
        // unregistered so getModule reverts for them, exercising the try/catch fallback fixed in L7.
        kernel.bootstrapSetModule(KernelModuleIds.INITIAL_SETUP_AUTHORITY, address(this));
        kernel.disableBootstrapAuthority();
    }

    function test_L7_IdentityRegistryFallbackWorksWhenPrimaryUnregistered() public {
        identityRegistry.setIdentityRecord(PERSON_ID, _identityInput(false));
        assertTrue(identityRegistry.identityExists(PERSON_ID));
    }

    function test_L7_StakeRegistryFallbackWorksWhenPrimaryUnregistered() public {
        stakeRegistry.increaseStake(PERSON_ID, 5_000);
        assertEq(stakeRegistry.activeStakeOf(PERSON_ID), 5_000);
    }

    function test_L7_CongressCandidateRegistryFallbackWorksWhenPrimaryUnregistered() public {
        congressCandidateRegistry.createCycle(
            1,
            ElectionTypes.CongressCycleInput({
                nominationStart: uint64(block.timestamp + 1),
                votingStart: uint64(block.timestamp + 2 days),
                votingEnd: uint64(block.timestamp + 4 days),
                seatCount: 2,
                runnerUpCount: 2,
                maxCandidateCount: 8,
                policyReference: keccak256("policy")
            })
        );
        assertEq(congressCandidateRegistry.getCycle(1).cycleId, 1);
    }

    function test_E1_GetCitizenshipSummaryReturnsStatusFields() public {
        identityRegistry.setIdentityRecord(PERSON_ID, _identityInput(true));

        (
            IdentityTypes.VerificationStatus verificationStatus,
            IdentityTypes.CitizenshipStatus citizenshipStatus,
            IdentityTypes.AgeClass ageClass,
            bool finalSuspension
        ) = identityRegistry.getCitizenshipSummary(PERSON_ID);

        assertEq(uint256(verificationStatus), uint256(IdentityTypes.VerificationStatus.Verified));
        assertEq(uint256(citizenshipStatus), uint256(IdentityTypes.CitizenshipStatus.Citizen));
        assertEq(uint256(ageClass), uint256(IdentityTypes.AgeClass.Adult));
        assertTrue(finalSuspension);
    }

    function _identityInput(bool finalSuspension)
        internal
        pure
        returns (IdentityTypes.IdentityRecordInput memory input)
    {
        input = IdentityTypes.IdentityRecordInput({
            metadataHash: keccak256("meta"),
            metadataURI: "ipfs://citizen",
            verificationStatus: IdentityTypes.VerificationStatus.Verified,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
            ageClass: IdentityTypes.AgeClass.Adult,
            correctionFlag: false,
            finalSuspension: finalSuspension
        });
    }
}
