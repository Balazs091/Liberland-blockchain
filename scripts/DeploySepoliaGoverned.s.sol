// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployDemo} from "./DeployDemo.s.sol";
import {LiberlandMerit} from "../contracts/tokens/LiberlandMerit.sol";
import {MembershipRegistry} from "../contracts/registries/MembershipRegistry.sol";
import {ModuleUpgradePlanRegistry} from "../contracts/registries/ModuleUpgradePlanRegistry.sol";
import {SepoliaGovernedMembershipController} from "../contracts/mocks/SepoliaGovernedMembershipController.sol";
import {KernelModuleIds} from "../contracts/libraries/KernelModuleIds.sol";
import {ElectionTypes} from "../contracts/types/ElectionTypes.sol";

/// @title DeploySepoliaGoverned
/// @notice Full synthetic governance staging with the actual fixed-supply LLM and a replaceable restriction driver.
/// @dev Reuses the established demo protocol, but never installs its public-mint LLM. No production recovery power.
contract DeploySepoliaGoverned is DeployDemo {
    uint256 internal constant GOVERNED_TEST_SUPPLY = 1_000_000e18;
    uint256 internal constant TESTER_LIQUID_BALANCE = 10_000e18;
    uint256 internal constant TREASURY_LLM_RESERVE = 100_000e18;
    address[3] internal _testerWallets;
    MembershipRegistry internal _membershipRegistry;
    SepoliaGovernedMembershipController internal _membershipController;
    ModuleUpgradePlanRegistry internal _moduleUpgradePlanRegistry;

    function _deployerPrivateKey() internal view override returns (uint256) {
        return vm.envUint("SEPOLIA_GOVERNED_PRIVATE_KEY");
    }

    function _loadConfiguration(address deployer) internal override {
        address[3] memory testers;
        for (uint256 i; i < 3; ++i) {
            testers[i] = vm.envAddress(string.concat("SEPOLIA_GOVERNED_TESTER_", vm.toString(i + 1)));
        }
        _configureActors(deployer, testers);
        _readCivicReviewers();
        _validateCivicReviewers(
            deployer, [_financeOfficeAdmin, _identityOfficeAdmin, _landOfficeAdmin, _companyRegistryOfficeAdmin]
        );
    }

    function _configureActors(address deployer, address[3] memory testers) internal {
        _testerWallets = testers;
        _validateTesters(deployer);
        _financeOfficeAdmin = deployer;
        _identityOfficeAdmin = _testerWallets[0];
        _landOfficeAdmin = _testerWallets[1];
        _companyRegistryOfficeAdmin = _testerWallets[2];
        _financeClerk = _testerWallets[2];
        _treasuryPrefundUsdc = 0;
        _treasuryPrefundLlm = TREASURY_LLM_RESERVE;
    }

    function _validateTesters(address deployer) internal view {
        for (uint256 i; i < 3; ++i) {
            require(_testerWallets[i] != address(0) && _testerWallets[i] != deployer, "invalid governed tester");
            for (uint256 j; j < i; ++j) {
                require(_testerWallets[i] != _testerWallets[j], "duplicate governed tester");
            }
        }
    }

    function _deployLlmToken() internal override returns (IERC20) {
        return IERC20(address(new LiberlandMerit(_kernel.bootstrapAuthority(), GOVERNED_TEST_SUPPLY)));
    }

    function _fundLlm(address recipient, uint256 amount) internal override {
        require(_llmToken.transfer(recipient, amount), "governed LLM funding failed");
    }

    function _seededWallet(uint256 index) internal view override returns (address) {
        require(index < 3, "invalid governed tester index");
        return _testerWallets[index];
    }

    function _seedDemoState(address deployer) internal override {
        super._seedDemoState(deployer);
        // This is an explicitly synthetic genesis import, not premature finalization of a public election.
        // The input exactly matches the deterministic seeded ballot totals in the shared fixture.
        address[] memory ranking = new address[](4);
        int256[] memory votes = new int256[](4);
        ranking[0] = deployer;
        ranking[1] = _testerWallets[1];
        ranking[2] = _testerWallets[0];
        ranking[3] = _testerWallets[2];
        votes[0] = 16_000 * ONE_LLM_SIGNED;
        votes[1] = 12_000 * ONE_LLM_SIGNED;
        votes[2] = 11_500 * ONE_LLM_SIGNED;
        votes[3] = 5_500 * ONE_LLM_SIGNED;
        _demoAuthority.finalizeCongressCycle(
            DEMO_CONGRESS_CYCLE_ID,
            ElectionTypes.CongressFinalizationInput({
                rankedCandidates: ranking, rankedVoteTotals: votes, electedCount: 2, runnerUpCount: 2
            })
        );
        for (uint256 i; i < 3; ++i) {
            _fundLlm(_testerWallets[i], TESTER_LIQUID_BALANCE);
        }
    }

    function _installTestExtensions() internal override {
        _membershipRegistry = new MembershipRegistry(address(_kernel), address(_identityRegistry));
        _membershipController =
            new SepoliaGovernedMembershipController(address(_identityRegistry), address(_membershipRegistry));
        _moduleUpgradePlanRegistry = new ModuleUpgradePlanRegistry(address(_kernel));
        bytes32[] memory ids = new bytes32[](3);
        address[] memory modules = new address[](3);
        ids[0] = KernelModuleIds.MEMBERSHIP_REGISTRY;
        modules[0] = address(_membershipRegistry);
        ids[1] = KernelModuleIds.IDENTITY_WRITER;
        modules[1] = address(_membershipController);
        ids[2] = KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY;
        modules[2] = address(_moduleUpgradePlanRegistry);
        _kernel.bootstrapSetModules(ids, modules);
    }

    function _decorateDeploymentManifest(string memory key, string memory) internal override returns (string memory) {
        _assertGovernedReady();
        vm.serializeString(key, "deploymentKind", "SEPOLIA_GOVERNED_SYNTHETIC_STAGING");
        vm.serializeBool(key, "syntheticOnly", true);
        vm.serializeBool(key, "governanceInstalled", true);
        vm.serializeBool(key, "legalWorkflowsInstalled", false);
        vm.serializeBool(key, "bootstrapRetired", _kernel.bootstrapAuthority() == address(0));
        vm.serializeAddress(key, "membershipRegistry", address(_membershipRegistry));
        vm.serializeAddress(key, "membershipController", address(_membershipController));
        vm.serializeAddress(key, "moduleUpgradePlanRegistry", address(_moduleUpgradePlanRegistry));
        address proposalValidator = _referendumApp.proposalValidator();
        vm.serializeAddress(key, "referendumProposalValidator", proposalValidator);
        vm.serializeString(key, "llmTotalSupply", vm.toString(_llmToken.totalSupply()));
        // _snapshot's deployer remains the active wallet of seeded person one after bootstrap is retired.
        address deployer = _identityRegistry.activeWalletOf(DEMO_PERSON_ONE);
        vm.serializeString(key, "llmOperatorReserve", vm.toString(_llmToken.balanceOf(deployer)));
        for (uint256 i; i < 3; ++i) {
            vm.serializeAddress(key, string.concat("tester", vm.toString(i + 1)), _testerWallets[i]);
        }
        vm.serializeBytes32(key, "llmRuntimeHash", address(_llmToken).codehash);
        vm.serializeBytes32(key, "membershipRuntimeHash", address(_membershipRegistry).codehash);
        vm.serializeBytes32(key, "membershipControllerRuntimeHash", address(_membershipController).codehash);
        vm.serializeBytes32(key, "moduleUpgradePlanRegistryRuntimeHash", address(_moduleUpgradePlanRegistry).codehash);
        vm.serializeBytes32(key, "referendumProposalValidatorRuntimeHash", proposalValidator.codehash);
        return vm.serializeString(key, "broadcastProof", "CONFIRM_PUBLIC_RECEIPTS_AND_RUNTIME_SEPARATELY");
    }

    function _deploymentManifestPath() internal pure override returns (string memory) {
        return "/deployments/sepolia-governed.json";
    }

    function _assertGovernedReady() internal view {
        require(_kernel.bootstrapAuthority() == address(0), "governed kernel bootstrap active");
        require(_router.bootstrapAuthority() == address(0), "governed router bootstrap active");
        require(_officeExecutor.bootstrapAuthority() == address(0), "governed office bootstrap active");
        require(_llmToken.totalSupply() == GOVERNED_TEST_SUPPLY, "wrong governed fixed supply");
        require(_identityRegistry.totalIdentityCount() == 4, "wrong governed synthetic count");
        require(_stakeRegistry.totalActiveStake() == 45_000 * ONE_LLM, "wrong governed synthetic stake");
        require(
            _llmToken.balanceOf(address(_stakingVault)) >= _stakeRegistry.totalActiveStake(),
            "governed backing shortfall"
        );
        require(_electorateRegistry.isReady(), "governed electorate not synchronized");
        require(_congressCandidateRegistry.currentCongressMembers().length == 2, "governed Congress unavailable");
        require(
            _kernel.getModule(KernelModuleIds.IDENTITY_WRITER) == address(_membershipController),
            "wrong governed membership writer"
        );
        require(_membershipRegistry.identityRegistry() == address(_identityRegistry), "wrong governed identity ledger");
        require(
            _kernel.getModule(KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY) == address(_moduleUpgradePlanRegistry),
            "wrong governed upgrade plan registry"
        );
    }
}
