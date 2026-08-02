// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {LLMStakingVault} from "../../contracts/apps/LLMStakingVault.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {DemoCitizenGateway} from "../../contracts/mocks/DemoCitizenGateway.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {UnstakingPolicy} from "../../contracts/policies/UnstakingPolicy.sol";
import {ElectorateRegistry} from "../../contracts/registries/ElectorateRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";

contract StakeAndElectorateHandler is Test {
    DemoCitizenGateway public immutable gateway;
    LLMToken public immutable token;
    StakeRegistry public immutable stakeRegistry;
    ElectorateRegistry public immutable electorateRegistry;
    bytes32 public immutable personId;

    constructor(
        DemoCitizenGateway gateway_,
        LLMToken token_,
        StakeRegistry stakeRegistry_,
        ElectorateRegistry electorateRegistry_
    ) {
        gateway = gateway_;
        token = token_;
        stakeRegistry = stakeRegistry_;
        electorateRegistry = electorateRegistry_;
        personId = gateway_.personIdFor(address(this));
        token_.approve(address(gateway_), type(uint256).max);
    }

    /// @notice Attempts demo self-registration for the invariant actor.
    function register() external {
        try gateway.registerSelf(keccak256("invariant.identity"), "ipfs://invariant-identity") {} catch {}
    }

    /// @notice Updates the actor's demo citizenship facts when the identity exists.
    function setCitizenship(bool approved, bool adult) external {
        try gateway.confirmCitizenship(address(this), approved, adult) {} catch {}
    }

    /// @notice Stakes a bounded amount of the actor's available LLM.
    function stake(uint96 rawAmount) external {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) {
            return;
        }
        uint256 amount = bound(uint256(rawAmount), 1, balance);
        try gateway.stake(amount) {} catch {}
    }

    /// @notice Attempts the policy-bounded discrete unstake operation.
    function unstake() external {
        try gateway.unstake() {} catch {}
    }

    /// @notice Advances invariant time by a bounded amount.
    function advanceTime(uint64 rawSeconds) external {
        vm.warp(block.timestamp + bound(uint256(rawSeconds), 1, 60 days));
        vm.roll(block.number + 1);
    }

    /// @notice Permissionlessly synchronizes the actor into the electorate registry.
    function synchronize() external {
        try electorateRegistry.syncPerson(personId) {} catch {}
    }
}

/// @title StakeAndElectorateInvariantTest
/// @notice Stateful coverage for custody backing, aggregate stake, civic-roll totals, and one-active-wallet identity.
contract StakeAndElectorateInvariantTest is Test {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000 ether;
    uint256 internal constant INITIAL_TOKEN_BALANCE = 1_000_000 ether;
    bytes32 internal constant IDENTITY_OFFICE_ID = keccak256("office.identity.invariant");

    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    ElectorateRegistry internal electorateRegistry;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    LLMToken internal token;
    LLMStakingVault internal stakingVault;
    DemoCitizenGateway internal gateway;
    StakeAndElectorateHandler internal handler;

    /// @notice Deploys the identity, stake-custody, policy, and electorate invariant fixture.
    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        electorateRegistry = new ElectorateRegistry(address(kernel), address(identityRegistry), address(stakeRegistry));
        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);
        UnstakingPolicy unstakingPolicy = new UnstakingPolicy(address(stakeRegistry), 30 days, 1_064);
        token = new LLMToken();
        stakingVault =
            new LLMStakingVault(address(kernel), address(identityRegistry), address(stakeRegistry), address(token));
        OfficeRegistry officeRegistry = new OfficeRegistry(address(kernel));
        gateway = new DemoCitizenGateway(
            address(identityRegistry),
            address(stakeRegistry),
            address(stakingVault),
            address(unstakingPolicy),
            address(token),
            address(this),
            address(officeRegistry),
            IDENTITY_OFFICE_ID,
            2 days
        );
        handler = new StakeAndElectorateHandler(gateway, token, stakeRegistry, electorateRegistry);

        bytes32[] memory moduleIds = new bytes32[](9);
        address[] memory moduleAddresses = new address[](9);
        moduleIds[0] = KernelModuleIds.IDENTITY_REGISTRY;
        moduleAddresses[0] = address(identityRegistry);
        moduleIds[1] = KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY;
        moduleAddresses[1] = address(gateway);
        moduleIds[2] = KernelModuleIds.STAKE_REGISTRY;
        moduleAddresses[2] = address(stakeRegistry);
        moduleIds[3] = KernelModuleIds.STAKE_REGISTRY_AUTHORITY;
        moduleAddresses[3] = address(gateway);
        moduleIds[4] = KernelModuleIds.LLM_STAKING_VAULT;
        moduleAddresses[4] = address(stakingVault);
        moduleIds[5] = KernelModuleIds.STAKE_USER_GATEWAY_AUTHORITY;
        moduleAddresses[5] = address(gateway);
        moduleIds[6] = KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY;
        moduleAddresses[6] = address(citizenEligibilityPolicy);
        moduleIds[7] = KernelModuleIds.UNSTAKING_POLICY;
        moduleAddresses[7] = address(unstakingPolicy);
        moduleIds[8] = KernelModuleIds.ELECTORATE_REGISTRY;
        moduleAddresses[8] = address(electorateRegistry);
        kernel.bootstrapSetModules(moduleIds, moduleAddresses);

        handler.register();
        gateway.confirmCitizenship(address(handler), true, true);
        gateway.updateRegistrar(address(handler));
        token.mint(address(handler), INITIAL_TOKEN_BALANCE);
        kernel.disableBootstrapAuthority();

        targetContract(address(handler));
    }

    /// @notice Proves aggregate active stake is fully backed by vault custody.
    function invariant_StakingVaultAlwaysBacksAggregateStake() public view {
        assertGe(token.balanceOf(address(stakingVault)), stakeRegistry.totalActiveStake());
        assertEq(stakeRegistry.totalActiveStake(), stakeRegistry.activeStakeOf(handler.personId()));
        assertLe(
            stakeRegistry.requiredActiveStakeFloorOf(handler.personId()),
            stakeRegistry.activeStakeOf(handler.personId())
        );
    }

    /// @notice Proves stake-token conservation across the actor and custody vault with no gateway residue.
    function invariant_StakeTokenConservationHasNoGatewayResidue() public view {
        assertEq(token.balanceOf(address(gateway)), 0);
        assertEq(token.balanceOf(address(handler)) + token.balanceOf(address(stakingVault)), INITIAL_TOKEN_BALANCE);
    }

    /// @notice Proves electorate readiness and aggregates match current identity and stake facts.
    function invariant_ElectorateMatchesCurrentCanonicalFacts() public view {
        assertTrue(electorateRegistry.isReady());
        (uint256 citizenCount, uint256 votingPower) = electorateRegistry.snapshot();
        bool onCivicRoll = citizenEligibilityPolicy.isCitizenOnCivicRoll(handler.personId());
        assertEq(citizenCount, onCivicRoll ? 1 : 0);
        assertEq(votingPower, onCivicRoll ? stakeRegistry.activeStakeOf(handler.personId()) : 0);
    }

    /// @notice Proves the fixture person retains exactly one canonical active wallet mapping.
    function invariant_IdentityRetainsOneCanonicalActiveWallet() public view {
        assertEq(identityRegistry.activeWalletCountOf(handler.personId()), 1);
        assertEq(identityRegistry.activeWalletOf(handler.personId()), address(handler));
    }
}
