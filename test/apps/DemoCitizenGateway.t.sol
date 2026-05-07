// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {DemoCitizenGateway} from "../../contracts/mocks/DemoCitizenGateway.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {UnstakingPolicy} from "../../contracts/policies/UnstakingPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {CandidateEligibilityPolicy} from "../../contracts/policies/CandidateEligibilityPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";

contract DemoCitizenGatewayTest is Test {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint256 internal constant MINIMUM_CANDIDATE_STAKE = 6_000;
    uint64 internal constant UNSTAKE_COOLDOWN = 1 days;

    address internal constant REGISTRAR = address(0xABCD);
    address internal constant APPLICANT = address(0x1111);

    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    UnstakingPolicy internal unstakingPolicy;
    VotingPowerPolicy internal votingPowerPolicy;
    CandidateEligibilityPolicy internal candidateEligibilityPolicy;
    LLMToken internal llmToken;
    DemoCitizenGateway internal gateway;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);
        unstakingPolicy = new UnstakingPolicy(address(stakeRegistry), UNSTAKE_COOLDOWN);
        votingPowerPolicy =
            new VotingPowerPolicy(address(identityRegistry), address(stakeRegistry), address(citizenEligibilityPolicy));
        candidateEligibilityPolicy = new CandidateEligibilityPolicy(
            address(identityRegistry),
            address(stakeRegistry),
            address(citizenEligibilityPolicy),
            MINIMUM_CANDIDATE_STAKE
        );
        llmToken = new LLMToken();
        gateway = new DemoCitizenGateway(
            address(identityRegistry), address(stakeRegistry), address(unstakingPolicy), address(llmToken), REGISTRAR
        );

        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(gateway));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(gateway));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(stakeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(citizenEligibilityPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.UNSTAKING_POLICY, address(unstakingPolicy));
        kernel.disableBootstrapAuthority();
    }

    function test_Register_Approve_Stake_Unstake_AndClaim_DrivesEligibility() public {
        vm.prank(APPLICANT);
        bytes32 personId = gateway.registerSelf(keccak256("applicant"), "ipfs://applicant");

        assertFalse(citizenEligibilityPolicy.isCitizenInGoodStanding(APPLICANT));
        assertEq(votingPowerPolicy.votingPower(APPLICANT), 0);
        assertFalse(candidateEligibilityPolicy.isEligibleCandidate(APPLICANT));

        vm.prank(REGISTRAR);
        gateway.confirmCitizenship(APPLICANT, true, true);

        assertFalse(citizenEligibilityPolicy.isCitizenInGoodStanding(APPLICANT));

        llmToken.mint(APPLICANT, 6_000);
        vm.startPrank(APPLICANT);
        llmToken.approve(address(gateway), 6_000);
        gateway.stake(6_000);
        vm.stopPrank();

        assertTrue(citizenEligibilityPolicy.isCitizenInGoodStanding(APPLICANT));
        assertEq(votingPowerPolicy.votingPower(APPLICANT), 6_000);
        assertTrue(candidateEligibilityPolicy.isEligibleCandidate(APPLICANT));
        assertEq(stakeRegistry.activeStakeOf(personId), 6_000);
        assertEq(llmToken.balanceOf(address(gateway)), 6_000);

        vm.prank(APPLICANT);
        gateway.requestUnstake(1_000);

        assertFalse(citizenEligibilityPolicy.isCitizenInGoodStanding(APPLICANT));
        assertEq(votingPowerPolicy.votingPower(APPLICANT), 0);
        assertFalse(candidateEligibilityPolicy.isEligibleCandidate(APPLICANT));
        assertEq(stakeRegistry.activeStakeOf(personId), 5_000);
        assertEq(stakeRegistry.pendingUnstakeOf(personId), 1_000);

        vm.warp(block.timestamp + UNSTAKE_COOLDOWN);

        vm.prank(APPLICANT);
        uint256 claimedAmount = gateway.claimUnstake();

        assertEq(claimedAmount, 1_000);
        assertTrue(citizenEligibilityPolicy.isCitizenInGoodStanding(APPLICANT));
        assertEq(votingPowerPolicy.votingPower(APPLICANT), 5_000);
        assertFalse(candidateEligibilityPolicy.isEligibleCandidate(APPLICANT));
        assertEq(llmToken.balanceOf(APPLICANT), 1_000);
        assertEq(llmToken.balanceOf(address(gateway)), 5_000);
    }
}
