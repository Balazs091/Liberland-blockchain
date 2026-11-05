// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DeployMerit} from "../../scripts/DeployMerit.s.sol";

contract DeployMeritInputHarness is DeployMerit {
    function readInputs() external view returns (GenesisInputs memory inputs) {
        return _readGenesisInputs();
    }
}

/// @notice Checks production input rejection before any broadcast or output file write.
contract DeployMeritTest is Test {
    DeployMeritInputHarness internal script;

    function setUp() public {
        script = new DeployMeritInputHarness();
    }

    function test_GenesisInputsRequireExplicitValidAllocationAndProvenance() public {
        // Environment variables are process-global in Forge. Keep all mutations in one sequential test.
        vm.setEnv("LLM_GENESIS_RECIPIENT", vm.toString(address(0xA11CE)));
        vm.setEnv("LLM_GENESIS_SUPPLY", "70000000000000000000000000");
        vm.setEnv("LLM_GENESIS_MANIFEST_HASH", vm.toString(keccak256("reviewed-genesis-test-fixture")));
        DeployMerit.GenesisInputs memory inputs = script.readInputs();
        assertEq(inputs.recipient, address(0xA11CE));
        assertEq(inputs.supply, 70_000_000e18);
        assertEq(inputs.manifestHash, keccak256("reviewed-genesis-test-fixture"));
        vm.setEnv("LLM_GENESIS_RECIPIENT", vm.toString(address(0)));
        vm.expectRevert("LLM genesis recipient must be nonzero");
        script.readInputs();
        vm.setEnv("LLM_GENESIS_RECIPIENT", vm.toString(address(0xA11CE)));
        vm.setEnv("LLM_GENESIS_SUPPLY", "0");
        vm.expectRevert("invalid LLM genesis supply");
        script.readInputs();
        vm.setEnv("LLM_GENESIS_SUPPLY", "70000000000000000000000001");
        vm.expectRevert("invalid LLM genesis supply");
        script.readInputs();
        vm.setEnv("LLM_GENESIS_SUPPLY", "70000000000000000000000000");
        vm.setEnv("LLM_GENESIS_MANIFEST_HASH", vm.toString(bytes32(0)));
        vm.expectRevert("LLM genesis manifest hash must be nonzero");
        script.readInputs();
    }

    function test_RejectsWrongChainBeforeReadingDeploymentKey() public {
        vm.chainId(11155111);
        vm.expectRevert("merit deployment requires Ethereum mainnet");
        script.run();
    }
}
