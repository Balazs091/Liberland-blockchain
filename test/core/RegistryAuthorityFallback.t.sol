// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../../contracts/interfaces/IStakeRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

/// @title RegistryAuthorityFallbackTest
/// @notice An unregistered primary registry authority must not brick the setup-authority fallback.
/// @notice Exercises the narrow getCitizenshipSummary accessor used for the electorate snapshot.
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
        // unregistered so getModule reverts for them, exercising the try/catch fallback. Bootstrap
        // stays active because the setup authority is a genesis-only convenience whose fallback is intentionally
        // scoped to the live bootstrap phase.
        kernel.bootstrapSetModule(KernelModuleIds.INITIAL_SETUP_AUTHORITY, address(this));
    }

    function test_IdentityRegistryFallbackWorksWhenPrimaryUnregistered() public {
        identityRegistry.setIdentityRecord(PERSON_ID, _identityInput(false));
        assertTrue(identityRegistry.identityExists(PERSON_ID));
    }

    function test_StakeIncreaseNeverUsesSetupFallbackWithoutVault() public {
        vm.expectRevert(abi.encodeWithSelector(IStakeRegistry.UnauthorizedStakeRegistryCaller.selector, address(this)));
        stakeRegistry.increaseStake(PERSON_ID, 5_000);
    }

    function test_CongressCandidateRegistryFallbackWorksWhenPrimaryUnregistered() public {
        congressCandidateRegistry.createCycle(
            1,
            ElectionTypes.CongressCycleInput({
                nominationStart: uint64(block.timestamp + 1),
                votingStart: uint64(block.timestamp + 2 days),
                votingEnd: uint64(block.timestamp + 4 days),
                votingPowerSnapshotBlock: uint48(block.number),
                seatCount: 2,
                runnerUpCount: 2,
                maxCandidateCount: 8,
                policy: address(congressCandidateRegistry),
                policyReference: keccak256("policy")
            })
        );
        assertEq(congressCandidateRegistry.getCycle(1).cycleId, 1);
    }

    /// @notice Once genesis bootstrap is disabled, the setup-authority fallback is inert, so a lingering
    ///         setup-authority module can never be a standing backdoor into high-value registry writes.
    function test_SetupAuthorityFallbackDiesAfterBootstrapDisabled() public {
        kernel.disableBootstrapAuthority();

        vm.expectRevert(abi.encodeWithSelector(IStakeRegistry.UnauthorizedStakeRegistryCaller.selector, address(this)));
        stakeRegistry.increaseStake(PERSON_ID, 5_000);

        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistry.UnauthorizedIdentityRegistryCaller.selector, address(this))
        );
        identityRegistry.setIdentityRecord(PERSON_ID, _identityInput(false));
    }

    function test_GetCitizenshipSummaryReturnsStatusFields() public {
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
