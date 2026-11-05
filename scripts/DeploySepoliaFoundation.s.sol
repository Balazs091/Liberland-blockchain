// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ConstitutionKernel} from "../contracts/core/ConstitutionKernel.sol";
import {KernelModuleIds} from "../contracts/libraries/KernelModuleIds.sol";
import {LLMTokenConstants} from "../contracts/libraries/LLMTokenConstants.sol";
import {SepoliaFoundationFixtures} from "../contracts/mocks/SepoliaFoundationFixtures.sol";
import {SepoliaMembershipController} from "../contracts/mocks/SepoliaMembershipController.sol";
import {IdentityRegistry} from "../contracts/registries/IdentityRegistry.sol";
import {MembershipRegistry} from "../contracts/registries/MembershipRegistry.sol";
import {LiberlandMerit} from "../contracts/tokens/LiberlandMerit.sol";
import {GovernanceTypes} from "../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../contracts/types/IdentityTypes.sol";

/// @title DeploySepoliaFoundation
/// @notice Prepares an isolated, synthetic Sepolia token and membership-restriction test environment.
/// @dev Does not install production legal workflows, governance, staking or USDC. Simulation is not broadcast proof.
contract DeploySepoliaFoundation is Script {
    struct Deployment {
        address constitutionKernel;
        address llmToken;
        address identityRegistry;
        address membershipRegistry;
        address membershipController;
        address operator;
    }

    /// @notice Deploys and seeds the fixed test environment using the dedicated Sepolia operator key.
    /// @return deployment Exact addresses for the isolated test environment.
    function run() external returns (Deployment memory deployment) {
        _requireSepolia();
        uint256 operatorKey = vm.envUint("SEPOLIA_FOUNDATION_PRIVATE_KEY");
        address operator = vm.addr(operatorKey);

        vm.startBroadcast(operatorKey);
        deployment = _deployAndSeed(operator);
        vm.stopBroadcast();

        _assertDeployment(deployment);
        _writeManifest(deployment);
        console2.log("SYNTHETIC SEPOLIA FOUNDATION ONLY; simulation output is not deployment proof.");
        console2.log("Operator:", operator);
        console2.log("Kernel:", deployment.constitutionKernel);
        console2.log("LiberlandMerit:", deployment.llmToken);
        console2.log("IdentityRegistry:", deployment.identityRegistry);
        console2.log("MembershipRegistry:", deployment.membershipRegistry);
        console2.log("TEST-ONLY membership controller:", deployment.membershipController);
    }

    /// @notice Checks topology, sealed setup and the initial allocation of a fresh deployment without a signer.
    /// @dev Run before intentional token transfers; later changes to initial balances cause this check to fail.
    ///      This is a structural/read-back check, not authentication of arbitrary supplied runtime bytecode.
    /// @param kernelAddress Kernel from this deployment's reviewed manifest and successful broadcast receipts.
    /// @param tokenAddress Token from the same deployment's reviewed manifest and successful broadcast receipts.
    /// @return deployment Reconstructed deployment whose fresh-state checks passed.
    function verify(address kernelAddress, address tokenAddress) external view returns (Deployment memory deployment) {
        _requireSepolia();
        ConstitutionKernel kernel = ConstitutionKernel(kernelAddress);
        address controllerAddress = kernel.getModule(KernelModuleIds.IDENTITY_WRITER);
        deployment = Deployment({
            constitutionKernel: kernelAddress,
            llmToken: tokenAddress,
            identityRegistry: kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY),
            membershipRegistry: kernel.getModule(KernelModuleIds.MEMBERSHIP_REGISTRY),
            membershipController: controllerAddress,
            operator: SepoliaMembershipController(controllerAddress).operator()
        });
        _assertDeployment(deployment);
    }

    function _requireSepolia() internal view {
        require(block.chainid == SepoliaFoundationFixtures.CHAIN_ID, "foundation deployment requires Sepolia");
    }

    function _deployAndSeed(address operator) internal returns (Deployment memory deployment) {
        ConstitutionKernel kernel = new ConstitutionKernel(operator);
        IdentityRegistry identity = new IdentityRegistry(address(kernel));
        MembershipRegistry membership = new MembershipRegistry(address(kernel), address(identity));
        LiberlandMerit token = new LiberlandMerit(operator, SepoliaFoundationFixtures.GENESIS_SUPPLY);
        SepoliaMembershipController controller =
            new SepoliaMembershipController(operator, address(identity), address(membership));

        bytes32[] memory moduleIds = new bytes32[](4);
        address[] memory modules = new address[](4);
        moduleIds[0] = KernelModuleIds.IDENTITY_REGISTRY;
        modules[0] = address(identity);
        moduleIds[1] = KernelModuleIds.MEMBERSHIP_REGISTRY;
        modules[1] = address(membership);
        // This authority exposes only fixed, one-time synthetic seeding; it becomes inert at bootstrap retirement.
        moduleIds[2] = KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY;
        modules[2] = address(controller);
        moduleIds[3] = KernelModuleIds.IDENTITY_WRITER;
        modules[3] = address(controller);
        kernel.bootstrapSetModules(moduleIds, modules);
        controller.seedSyntheticIdentities();

        for (uint256 i; i < SepoliaFoundationFixtures.PERSON_COUNT; ++i) {
            address wallet = SepoliaFoundationFixtures.walletAt(i);
            require(operator != wallet, "operator must differ from synthetic wallets");
            require(token.transfer(wallet, SepoliaFoundationFixtures.BALANCE_PER_PERSON), "fixture transfer failed");
        }
        kernel.disableBootstrapAuthority();

        deployment = Deployment({
            constitutionKernel: address(kernel),
            llmToken: address(token),
            identityRegistry: address(identity),
            membershipRegistry: address(membership),
            membershipController: address(controller),
            operator: operator
        });
    }

    function _assertDeployment(Deployment memory deployment) internal view {
        _requireSepolia();
        require(
            deployment.constitutionKernel.code.length != 0 && deployment.llmToken.code.length != 0
                && deployment.identityRegistry.code.length != 0 && deployment.membershipRegistry.code.length != 0
                && deployment.membershipController.code.length != 0,
            "foundation component missing code"
        );
        ConstitutionKernel kernel = ConstitutionKernel(deployment.constitutionKernel);
        IdentityRegistry identity = IdentityRegistry(deployment.identityRegistry);
        MembershipRegistry membership = MembershipRegistry(deployment.membershipRegistry);
        SepoliaMembershipController controller = SepoliaMembershipController(deployment.membershipController);
        LiberlandMerit token = LiberlandMerit(deployment.llmToken);

        require(kernel.bootstrapAuthority() == address(0), "foundation bootstrap still active");
        require(kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY) == address(identity), "wrong identity pointer");
        require(
            kernel.getModule(KernelModuleIds.MEMBERSHIP_REGISTRY) == address(membership), "wrong membership pointer"
        );
        require(kernel.getModule(KernelModuleIds.IDENTITY_WRITER) == address(controller), "wrong restriction writer");
        require(
            kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY) == address(controller),
            "wrong synthetic identity authority"
        );
        require(
            kernel.moduleClass(KernelModuleIds.MEMBERSHIP_REGISTRY) == GovernanceTypes.ModuleClass.State
                && kernel.moduleClass(KernelModuleIds.IDENTITY_WRITER) == GovernanceTypes.ModuleClass.Authority,
            "wrong foundation module classes"
        );
        require(
            identity.kernel() == address(kernel) && membership.kernel() == address(kernel), "registry kernel mismatch"
        );
        require(membership.identityRegistry() == address(identity), "membership identity mismatch");
        require(
            controller.kernel() == address(kernel) && controller.operator() == deployment.operator, "wrong controller"
        );
        require(
            controller.identityRegistry() == address(identity)
                && controller.membershipRegistry() == address(membership),
            "controller registry mismatch"
        );
        require(controller.fixturesSeeded(), "synthetic identities not seeded");
        require(
            identity.totalIdentityCount() == SepoliaFoundationFixtures.PERSON_COUNT, "wrong synthetic identity count"
        );
        require(
            token.decimals() == LLMTokenConstants.DECIMALS && token.cap() == LLMTokenConstants.MAX_SUPPLY,
            "wrong token units/cap"
        );
        require(
            keccak256(bytes(token.name())) == keccak256("Liberland Merit")
                && keccak256(bytes(token.symbol())) == keccak256("LLM"),
            "wrong token metadata"
        );
        require(token.totalSupply() == SepoliaFoundationFixtures.GENESIS_SUPPLY, "wrong fixed test supply");
        require(
            token.balanceOf(deployment.operator)
                == SepoliaFoundationFixtures.GENESIS_SUPPLY - SepoliaFoundationFixtures.PERSON_COUNT
                    * SepoliaFoundationFixtures.BALANCE_PER_PERSON,
            "operator initial allocation changed"
        );
        for (uint256 i; i < SepoliaFoundationFixtures.PERSON_COUNT; ++i) {
            bytes32 personId = SepoliaFoundationFixtures.personIdAt(i);
            address wallet = SepoliaFoundationFixtures.walletAt(i);
            IdentityTypes.IdentityRecord memory person = identity.getIdentityRecord(personId);
            require(
                person.personId == personId && person.metadataHash == SepoliaFoundationFixtures.metadataHashAt(i)
                    && person.verificationStatus == IdentityTypes.VerificationStatus.Verified
                    && person.citizenshipStatus == IdentityTypes.CitizenshipStatus.Citizen
                    && person.ageClass == IdentityTypes.AgeClass.Adult,
                "wrong synthetic identity facts"
            );
            require(
                identity.activeWalletOf(personId) == wallet && identity.activeWalletCountOf(personId) == 1,
                "wrong fixture wallet"
            );
            require(
                token.balanceOf(wallet) == SepoliaFoundationFixtures.BALANCE_PER_PERSON,
                "fixture initial allocation changed"
            );
        }
    }

    function _writeManifest(Deployment memory deployment) private {
        string memory key = "sepolia-foundation";
        vm.serializeUint(key, "manifestVersion", 1);
        vm.serializeString(key, "deploymentKind", "SEPOLIA_FOUNDATION_TEST_ONLY");
        vm.serializeBool(key, "syntheticOnly", true);
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeAddress(key, "operator", deployment.operator);
        vm.serializeAddress(key, "constitutionKernel", deployment.constitutionKernel);
        vm.serializeAddress(key, "llmToken", deployment.llmToken);
        vm.serializeAddress(key, "identityRegistry", deployment.identityRegistry);
        vm.serializeAddress(key, "membershipRegistry", deployment.membershipRegistry);
        vm.serializeAddress(key, "membershipController", deployment.membershipController);
        vm.serializeBytes32(key, "fixtureVersion", SepoliaFoundationFixtures.FIXTURE_VERSION);
        vm.serializeUint(key, "genesisSupply", SepoliaFoundationFixtures.GENESIS_SUPPLY);
        vm.serializeUint(key, "decimals", LLMTokenConstants.DECIMALS);
        vm.serializeUint(key, "cap", LLMTokenConstants.MAX_SUPPLY);
        vm.serializeUint(key, "personCount", SepoliaFoundationFixtures.PERSON_COUNT);
        vm.serializeUint(key, "balancePerPerson", SepoliaFoundationFixtures.BALANCE_PER_PERSON);
        vm.serializeBool(key, "bootstrapRetired", true);
        vm.serializeBool(key, "legalWorkflowsInstalled", false);
        vm.serializeBool(key, "governanceInstalled", false);
        for (uint256 i; i < SepoliaFoundationFixtures.PERSON_COUNT; ++i) {
            string memory suffix = vm.toString(i);
            vm.serializeBytes32(key, string.concat("personId", suffix), SepoliaFoundationFixtures.personIdAt(i));
            vm.serializeAddress(key, string.concat("wallet", suffix), SepoliaFoundationFixtures.walletAt(i));
        }
        vm.serializeBytes32(key, "kernelRuntimeHash", deployment.constitutionKernel.codehash);
        vm.serializeBytes32(key, "llmRuntimeHash", deployment.llmToken.codehash);
        vm.serializeBytes32(key, "identityRuntimeHash", deployment.identityRegistry.codehash);
        vm.serializeBytes32(key, "membershipRuntimeHash", deployment.membershipRegistry.codehash);
        vm.serializeBytes32(key, "controllerRuntimeHash", deployment.membershipController.codehash);
        string memory json = vm.serializeString(key, "broadcastProof", "VERIFY_SUCCESSFUL_PUBLIC_RECEIPTS_SEPARATELY");
        vm.createDir(string.concat(vm.projectRoot(), "/deployments"), true);
        vm.writeJson(json, string.concat(vm.projectRoot(), "/deployments/sepolia-foundation.json"));
    }
}
