// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {DeployDemo} from "../../scripts/DeployDemo.s.sol";
import {CongressElectionApp} from "../../contracts/apps/CongressElectionApp.sol";
import {DemoCitizenGateway} from "../../contracts/mocks/DemoCitizenGateway.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {ReferendumApp} from "../../contracts/apps/ReferendumApp.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {ReferendumRegistry} from "../../contracts/registries/ReferendumRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {ReferendumTypes} from "../../contracts/types/ReferendumTypes.sol";

contract DeployDemoIntegrationHarness is DeployDemo {
    function deployForTest(address registrar) external {
        address deployer = address(this);

        _financeOfficeAdmin = deployer;
        _identityOfficeAdmin = registrar;
        _landOfficeAdmin = address(0x1A2D);
        _companyRegistryOfficeAdmin = deployer;
        _financeClerk = address(0xC1E2);
        _treasuryPrefundUsdc = 0;
        _treasuryPrefundLlm = 0;

        _deployCore(deployer);
        _deployRegistries();
        _deployDemoAuthority(deployer);
        _deployPoliciesAndApps(deployer);
        _registerBootstrapModules();
        _seedDemoState(deployer);
        _switchToFinalDemoWiring();
        _prefundTreasury();
        _officeExecutor.disableBootstrapAuthority();
        _router.disableBootstrapAuthority();
        _kernel.disableBootstrapAuthority();
    }

    function kernelForTest() external view returns (ConstitutionKernel) {
        return _kernel;
    }

    function gatewayForTest() external view returns (DemoCitizenGateway) {
        return _demoCitizenGateway;
    }

    function identityAppForTest() external view returns (address app) {
        return address(_identityApp);
    }

    function identityAuthorityForTest() external view returns (address authority) {
        return _kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY);
    }

    function congressAuthorityForTest() external view returns (address authority) {
        return _kernel.getModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY);
    }

    function landTopologyForTest() external view returns (address policy, address app, address authority) {
        return (
            _kernel.getModule(KernelModuleIds.LAND_PARTY_POLICY),
            address(_landRegistryApp),
            _kernel.getModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY)
        );
    }

    function routerBootstrapAuthorityForTest() external view returns (address authority) {
        return _router.bootstrapAuthority();
    }

    function officeExecutorBootstrapAuthorityForTest() external view returns (address authority) {
        return _officeExecutor.bootstrapAuthority();
    }

    function llmForTest() external view returns (LLMToken) {
        return _llmToken;
    }

    function stakeRegistryForTest() external view returns (StakeRegistry) {
        return _stakeRegistry;
    }

    function congressRegistryForTest() external view returns (CongressCandidateRegistry) {
        return _congressCandidateRegistry;
    }

    function congressAppForTest() external view returns (CongressElectionApp) {
        return _congressElectionApp;
    }

    function referendumRegistryForTest() external view returns (ReferendumRegistry) {
        return _referendumRegistry;
    }

    function referendumAppForTest() external view returns (ReferendumApp) {
        return _referendumApp;
    }

    function activeReferendumIdForTest() external pure returns (bytes32) {
        return ACTIVE_REFERENDUM_ID;
    }
}

contract DeployDemoIntegrationTest is Test {
    uint256 internal constant ONE_LLM = 1e18;
    int256 internal constant ONE_LLM_SIGNED = 1e18;
    address internal constant REGISTRAR = address(0x1D);
    address internal constant NEW_USER = address(0xA55);
    address internal constant SEEDED_VOTER = address(0xB0B);

    DeployDemoIntegrationHarness internal deployment;

    function setUp() public {
        vm.warp(100 days);
        vm.roll(1_000);
        deployment = new DeployDemoIntegrationHarness();
        deployment.deployForTest(REGISTRAR);
    }

    function test_FinalizedTopologySupportsOnboardingAndStandardIdentityLifecycle() public {
        ConstitutionKernel kernel = deployment.kernelForTest();
        DemoCitizenGateway gateway = deployment.gatewayForTest();
        LLMToken llm = deployment.llmForTest();

        assertEq(kernel.bootstrapAuthority(), address(0));
        assertEq(deployment.routerBootstrapAuthorityForTest(), address(0));
        assertEq(deployment.officeExecutorBootstrapAuthorityForTest(), address(0));
        assertEq(deployment.identityAppForTest(), address(gateway));
        assertEq(deployment.identityAuthorityForTest(), address(gateway));
        assertEq(deployment.congressAuthorityForTest(), address(deployment.congressAppForTest()));
        (address landPartyPolicy, address landApp, address landAuthority) = deployment.landTopologyForTest();
        assertTrue(landPartyPolicy.code.length != 0);
        assertEq(landAuthority, landApp);

        vm.prank(NEW_USER);
        bytes32 personId = gateway.registerSelf(keccak256("new-user"), "ipfs://demo/new-user");
        vm.prank(REGISTRAR);
        gateway.confirmCitizenship(NEW_USER, true, true);

        llm.mint(NEW_USER, 6_000 * ONE_LLM);
        vm.startPrank(NEW_USER);
        llm.approve(address(gateway), 6_000 * ONE_LLM);
        gateway.stake(6_000 * ONE_LLM);
        gateway.renounceCitizenship();
        uint256 released = gateway.unstake();
        vm.stopPrank();

        assertGt(released, 0);
        assertGt(deployment.stakeRegistryForTest().activeStakeOf(personId), 0);
    }

    function test_SeededSnapshotBlocksContainStakeAndAllowLiveRecast() public {
        CongressCandidateRegistry congressRegistry = deployment.congressRegistryForTest();
        CongressElectionApp congressApp = deployment.congressAppForTest();
        ElectionTypes.CongressCycleRecord memory cycle = congressRegistry.getCycle(1);
        assertEq(cycle.votingPowerSnapshotBlock, block.number);
        assertGt(
            deployment.stakeRegistryForTest().activeStakeAt(bytes32(uint256(2)), cycle.votingPowerSnapshotBlock), 0
        );

        vm.prank(SEEDED_VOTER);
        congressApp.castBallot(1, _asAddressArray(SEEDED_VOTER), _asIntArray(7_500 * ONE_LLM_SIGNED));

        bytes32 referendumId = deployment.activeReferendumIdForTest();
        ReferendumApp referendumApp = deployment.referendumAppForTest();
        ReferendumTypes.ReferendumRecord memory referendum =
            deployment.referendumRegistryForTest().getReferendum(referendumId);
        assertEq(referendum.votingPowerSnapshotBlock, block.number);
        assertGt(
            deployment.stakeRegistryForTest().activeStakeAt(bytes32(uint256(2)), referendum.votingPowerSnapshotBlock), 0
        );

        vm.prank(SEEDED_VOTER);
        referendumApp.castVote(referendumId, ReferendumTypes.VoteOption.For);
    }

    function _asAddressArray(address first) private pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = first;
    }

    function _asIntArray(int256 first) private pure returns (int256[] memory values) {
        values = new int256[](1);
        values[0] = first;
    }
}
