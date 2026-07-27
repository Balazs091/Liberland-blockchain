// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {DemoCitizenGateway} from "../../contracts/mocks/DemoCitizenGateway.sol";
import {LLMStakingVault} from "../../contracts/apps/LLMStakingVault.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IStakeRegistry} from "../../contracts/interfaces/IStakeRegistry.sol";
import {ILLMStakingVault} from "../../contracts/interfaces/ILLMStakingVault.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {ElectorateRegistry} from "../../contracts/registries/ElectorateRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {UnstakingPolicy} from "../../contracts/policies/UnstakingPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {CandidateEligibilityPolicy} from "../../contracts/policies/CandidateEligibilityPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

contract DemoCitizenGatewayTest is Test {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint256 internal constant MINIMUM_CANDIDATE_STAKE = 6_000;
    uint64 internal constant WELFARE_PERIOD = 30 days;
    uint16 internal constant ANNUAL_UNSTAKE_RATE_BPS = 1_000;
    bytes32 internal constant IDENTITY_OFFICE_ID = keccak256("office.identity");

    address internal constant REGISTRAR = address(0xABCD);
    address internal constant APPLICANT = address(0x1111);

    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    OfficeRegistry internal officeRegistry;
    StakeRegistry internal stakeRegistry;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    UnstakingPolicy internal unstakingPolicy;
    VotingPowerPolicy internal votingPowerPolicy;
    CandidateEligibilityPolicy internal candidateEligibilityPolicy;
    LLMToken internal llmToken;
    LLMStakingVault internal stakingVault;
    DemoCitizenGateway internal gateway;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identityRegistry = new IdentityRegistry(address(kernel));
        officeRegistry = new OfficeRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);
        unstakingPolicy = new UnstakingPolicy(address(stakeRegistry), WELFARE_PERIOD, ANNUAL_UNSTAKE_RATE_BPS);
        ElectorateRegistry electorateRegistry =
            new ElectorateRegistry(address(kernel), address(identityRegistry), address(stakeRegistry));
        votingPowerPolicy = new VotingPowerPolicy(
            address(identityRegistry),
            address(stakeRegistry),
            address(citizenEligibilityPolicy),
            address(electorateRegistry)
        );
        candidateEligibilityPolicy = new CandidateEligibilityPolicy(
            address(identityRegistry),
            address(stakeRegistry),
            address(citizenEligibilityPolicy),
            MINIMUM_CANDIDATE_STAKE
        );
        llmToken = new LLMToken();
        stakingVault =
            new LLMStakingVault(address(kernel), address(identityRegistry), address(stakeRegistry), address(llmToken));
        gateway = new DemoCitizenGateway(
            address(identityRegistry),
            address(stakeRegistry),
            address(stakingVault),
            address(unstakingPolicy),
            address(llmToken),
            REGISTRAR,
            address(officeRegistry),
            IDENTITY_OFFICE_ID,
            2 days
        );

        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(gateway));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(gateway));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(stakeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(stakingVault));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_USER_GATEWAY_AUTHORITY, address(gateway));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(citizenEligibilityPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.UNSTAKING_POLICY, address(unstakingPolicy));
        kernel.disableBootstrapAuthority();
    }

    function test_LLMToken_UsesStandardErc20Decimals() public view {
        assertEq(llmToken.decimals(), 18);
        assertEq(llmToken.cap(), 70_000_000 * 1e18);
    }

    function test_LLMToken_EnforcesSeventyMillionHardCap() public {
        LLMToken cappedToken = new LLMToken();
        uint256 maximumSupply = cappedToken.cap();
        cappedToken.mint(APPLICANT, maximumSupply);

        vm.expectRevert(abi.encodeWithSignature("ERC20ExceededCap(uint256,uint256)", maximumSupply + 1, maximumSupply));
        cappedToken.mint(APPLICANT, 1);

        assertEq(cappedToken.totalSupply(), maximumSupply);
    }

    function test_StakingVault_RejectsUnknownPersonWithoutPullingFunds() public {
        bytes32 unknownPersonId = keccak256("unknown-person");
        llmToken.mint(APPLICANT, 100);

        vm.startPrank(APPLICANT);
        llmToken.approve(address(stakingVault), 100);
        vm.expectRevert(abi.encodeWithSelector(ILLMStakingVault.UnknownStakePerson.selector, unknownPersonId));
        stakingVault.stakeFor(unknownPersonId, 100);
        vm.stopPrank();

        assertEq(llmToken.balanceOf(APPLICANT), 100);
        assertEq(llmToken.balanceOf(address(stakingVault)), 0);
        assertEq(stakeRegistry.totalActiveStake(), 0);
    }

    function testFuzz_StakingVaultBackingEqualsAggregateStake(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, llmToken.cap());
        vm.prank(APPLICANT);
        bytes32 personId = gateway.registerSelf(keccak256("fuzz-applicant"), "ipfs://fuzz-applicant");
        vm.prank(REGISTRAR);
        gateway.confirmCitizenship(APPLICANT, true, true);

        llmToken.mint(APPLICANT, amount);
        vm.startPrank(APPLICANT);
        llmToken.approve(address(stakingVault), amount);
        stakingVault.stakeFor(personId, amount);
        vm.stopPrank();

        assertEq(llmToken.balanceOf(address(stakingVault)), amount);
        assertEq(stakeRegistry.activeStakeOf(personId), amount);
        assertEq(stakeRegistry.totalActiveStake(), amount);
        assertEq(stakingVault.backingSurplus(), 0);
    }

    function test_Register_Approve_Stake_Unstake_DrivesEligibilityAndWelfare() public {
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
        assertEq(llmToken.balanceOf(address(stakingVault)), 6_000);

        // Discrete unstake releases 10%/yr * 30/365 of 6,000 == 49 LLM immediately.
        assertEq(unstakingPolicy.unstakePortion(6_000), 49);

        vm.prank(APPLICANT);
        uint256 releasedAmount = gateway.unstake();
        assertEq(releasedAmount, 49);

        // In welfare: voting and candidacy suspended, and a second unstake reverts.
        assertTrue(stakeRegistry.isInWelfare(personId));
        assertFalse(citizenEligibilityPolicy.isCitizenInGoodStanding(APPLICANT));
        assertEq(votingPowerPolicy.votingPower(APPLICANT), 0);
        assertFalse(candidateEligibilityPolicy.isEligibleCandidate(APPLICANT));
        assertEq(stakeRegistry.activeStakeOf(personId), 5_951);
        assertEq(llmToken.balanceOf(APPLICANT), 49);
        assertEq(llmToken.balanceOf(address(stakingVault)), 5_951);

        uint64 welfareUntil = stakeRegistry.welfareUntilOf(personId);
        vm.expectRevert(abi.encodeWithSelector(IStakeRegistry.InWelfarePeriod.selector, personId, welfareUntil));
        vm.prank(APPLICANT);
        gateway.unstake();

        // After welfare elapses, good standing and voting weight return.
        vm.warp(welfareUntil);
        assertTrue(citizenEligibilityPolicy.isCitizenInGoodStanding(APPLICANT));
        assertEq(votingPowerPolicy.votingPower(APPLICANT), 5_951);
    }

    function test_CombinedDemoAuthorityPreservesStandardIdentityRenunciation() public {
        vm.prank(APPLICANT);
        bytes32 personId = gateway.registerSelf(keccak256("applicant"), "ipfs://applicant");
        vm.prank(REGISTRAR);
        gateway.confirmCitizenship(APPLICANT, true, true);

        vm.prank(APPLICANT);
        gateway.renounceCitizenship();

        assertEq(
            uint8(identityRegistry.getIdentityRecord(personId).citizenshipStatus),
            uint8(IdentityTypes.CitizenshipStatus.None)
        );
        assertTrue(identityRegistry.hasActiveWalletLink(APPLICANT));
    }
}
