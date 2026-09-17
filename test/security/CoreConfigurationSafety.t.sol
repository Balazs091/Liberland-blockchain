// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ActionLifecycleTest} from "../core/ActionLifecycle.t.sol";
import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";

/// @notice Constructor bounds must protect every immutable delay, not only the execution window.
contract CoreConfigurationSafetyTest is ActionLifecycleTest {
    function test_CoreRejectsZeroOrUnrepresentableConfiguredDurations() public {
        ConstitutionKernel freshKernel = new ConstitutionKernel(address(this));
        for (uint256 field; field < 5; ++field) {
            for (uint256 valueIndex; valueIndex < 3; ++valueIndex) {
                uint64 invalidDuration =
                    valueIndex == 0 ? 0 : valueIndex == 1 ? uint64(type(uint32).max) + 1 : type(uint64).max;
                GovernanceTypes.TimelockDelayConfig memory config = _defaultDelayConfig();
                if (field == 0) config.moduleGovernanceDelay = invalidDuration;
                else if (field == 1) config.treasuryBudgetApprovalDelay = invalidDuration;
                else if (field == 2) config.legislationEnactmentDelay = invalidDuration;
                else if (field == 3) config.treasuryDisbursementDelay = invalidDuration;
                else config.defaultExecutionWindow = invalidDuration;
                vm.expectRevert(abi.encodeWithSelector(IActionTimelock.InvalidDelayConfig.selector, config));
                new ActionTimelock(address(freshKernel), config);
            }
        }
    }

    function testFuzz_CoreAcceptsRepresentableNonzeroDurations(uint32 rawDuration) public {
        uint64 duration = uint64(bound(rawDuration, 1, type(uint32).max));
        GovernanceTypes.TimelockDelayConfig memory config = GovernanceTypes.TimelockDelayConfig({
            moduleGovernanceDelay: duration,
            treasuryBudgetApprovalDelay: duration,
            legislationEnactmentDelay: duration,
            treasuryDisbursementDelay: duration,
            defaultExecutionWindow: duration
        });
        ActionTimelock configured = new ActionTimelock(address(kernel), config);
        assertEq(configured.minimumDelay(GovernanceTypes.ActionType.ModulePointerUpdate), duration);
        assertEq(configured.minimumDelay(GovernanceTypes.ActionType.TreasuryDisbursement), duration);
    }

    function test_CoreRejectsOverflowingRequestedScheduleWithoutPoisoningQueue() public {
        GovernanceTypes.ActionRequest memory request = _buildModuleUpdateRequest(address(replacementModule));
        request.requestedExecutionTime = type(uint64).max;
        request.expiresAt = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                IActionTimelock.InvalidActionSchedule.selector,
                uint256(type(uint64).max),
                uint256(type(uint64).max) + 7 days
            )
        );
        vm.prank(referendumAuthority);
        router.routeAction(request);

        request.requestedExecutionTime = 0;
        vm.prank(referendumAuthority);
        bytes32 actionId = router.routeAction(request);
        GovernanceTypes.ActionRecord memory queued = timelock.getAction(actionId);
        vm.warp(queued.earliestExecutionTime);
        timelock.executeAction(actionId);
        assertEq(kernel.getModule(TARGET_MODULE_ID), address(replacementModule));
    }
}
