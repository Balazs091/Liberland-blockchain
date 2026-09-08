// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IdentityStakePoliciesTest} from "../policies/IdentityStakePolicies.t.sol";
import {LLMStakingVault} from "../../contracts/apps/LLMStakingVault.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";

contract FailingElectorateCallback {
    fallback() external {
        revert("deliberately incompatible callback");
    }
}

contract HighSeverityElectorateTest is IdentityStakePoliciesTest {
    function test_Security_UnderfundedStakeCannotCommitUnsynchronizedMutation() public {
        _registerCitizen(PERSON_ID, WALLET, MINIMUM_CITIZEN_STAKE);
        LLMToken token = new LLMToken();
        LLMStakingVault vault =
            new LLMStakingVault(address(kernel), address(identityRegistry), address(stakeRegistry), address(token));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(vault));
        kernel.disableBootstrapAuthority();
        token.mint(address(vault), MINIMUM_CITIZEN_STAKE);
        token.mint(address(this), 10);
        token.approve(address(vault), 10);
        vm.roll(block.number + 1);
        uint256 successes;
        uint256 reverts;
        for (uint256 budget = 20_000; budget <= 1_000_000; budget += 10_000) {
            uint256 snap = vm.snapshotState();
            vm.cool(address(stakeRegistry));
            vm.cool(address(electorateRegistry));
            (bool ok,) = address(vault).call{gas: budget}(abi.encodeCall(vault.stakeFor, (PERSON_ID, 1)));
            assertTrue(electorateRegistry.isReady(), "underfunding cannot poison readiness");
            assertEq(stakeRegistry.activeStakeOf(PERSON_ID), MINIMUM_CITIZEN_STAKE + (ok ? 1 : 0));
            if (ok) successes++;
            else reverts++;
            vm.revertToStateAndDelete(snap);
        }
        assertGt(successes, 0);
        assertGt(reverts, 0);
    }

    function test_Security_GenuinelyBrokenCallbackStillAllowsCanonicalStakeWrite() public {
        _registerCitizen(PERSON_ID, WALLET, MINIMUM_CITIZEN_STAKE);
        kernel.bootstrapSetModule(KernelModuleIds.ELECTORATE_REGISTRY, address(new FailingElectorateCallback()));
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(PERSON_ID, 1);
        assertEq(stakeRegistry.activeStakeOf(PERSON_ID), MINIMUM_CITIZEN_STAKE + 1);
    }
}
