// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Script} from "forge-std/Script.sol";

import {LLMTokenConstants} from "../contracts/libraries/LLMTokenConstants.sol";
import {LiberlandMerit} from "../contracts/tokens/LiberlandMerit.sol";
import {EthereumMainnetParameters} from "./parameters/EthereumMainnetParameters.sol";

/// @title DeployMerit
/// @notice Deploys the fixed-supply production asset separately from the governance system.
/// @dev Genesis allocation inputs must be supplied and reviewed before broadcast. This script is not a minter.
contract DeployMerit is Script {
    struct GenesisInputs {
        address recipient;
        uint256 supply;
        bytes32 manifestHash;
    }

    /// @notice Deploys Liberland Merit from the configured genesis inputs and records its constructor provenance.
    /// @return token The deployed token. Simulation alone does not establish an on-chain deployment.
    function run() external returns (LiberlandMerit token) {
        require(block.chainid == EthereumMainnetParameters.CHAIN_ID, "merit deployment requires Ethereum mainnet");
        GenesisInputs memory inputs = _readGenesisInputs();
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        token = new LiberlandMerit(inputs.recipient, inputs.supply);
        vm.stopBroadcast();

        string memory key = "production-merit";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeAddress(key, "llmToken", address(token));
        vm.serializeAddress(key, "genesisRecipient", inputs.recipient);
        vm.serializeUint(key, "genesisSupply", inputs.supply);
        vm.serializeUint(key, "decimals", token.decimals());
        vm.serializeUint(key, "cap", token.cap());
        vm.serializeBytes32(key, "genesisManifestHash", inputs.manifestHash);
        vm.serializeBytes(key, "constructorArguments", abi.encode(inputs.recipient, inputs.supply));
        string memory json = vm.serializeBytes32(key, "runtimeCodeHash", address(token).codehash);
        vm.createDir(string.concat(vm.projectRoot(), "/deployments"), true);
        vm.writeJson(json, string.concat(vm.projectRoot(), "/deployments/ethereum-mainnet-merit.json"));
    }

    /// @dev A manifest hash is an operator-supplied provenance reference, not proof of legal approval.
    function _readGenesisInputs() internal view returns (GenesisInputs memory inputs) {
        inputs.recipient = vm.envAddress("LLM_GENESIS_RECIPIENT");
        inputs.supply = vm.envUint("LLM_GENESIS_SUPPLY");
        inputs.manifestHash = vm.envBytes32("LLM_GENESIS_MANIFEST_HASH");
        require(inputs.recipient != address(0), "LLM genesis recipient must be nonzero");
        require(inputs.supply != 0 && inputs.supply <= LLMTokenConstants.MAX_SUPPLY, "invalid LLM genesis supply");
        require(inputs.manifestHash != bytes32(0), "LLM genesis manifest hash must be nonzero");
    }
}
