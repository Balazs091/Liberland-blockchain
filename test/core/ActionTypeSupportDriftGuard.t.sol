// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {SenatePowersPolicy} from "../../contracts/policies/SenatePowersPolicy.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";

/// @title ActionTypeSupportDriftGuardTest
/// @notice Single source-of-truth guard: the set of governance action types that the router routes, the timelock
///         executes, and the Senate may cancel must stay identical. Each contract hard-codes its own disjunction of
///         `ActionType` members; this test pins all three to one canonical set across every enum value, so adding a
///         new action type (or wiring it into only some of the three sites) fails CI until every site — and this
///         canonical list — is updated in lockstep.
contract ActionTypeSupportDriftGuardTest is Test {
    ActionTimelock internal timelock;
    ConstitutionKernel internal kernel;
    GovernanceRouter internal router;
    SenatePowersPolicy internal senatePowersPolicy;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(address(kernel), _defaultDelayConfig());
        router = new GovernanceRouter(address(kernel), address(this));
        senatePowersPolicy = new SenatePowersPolicy(1, 3 days);
    }

    /// @notice Every `ActionType` must be classified identically by all three timelock-flow gates, and that shared
    ///         classification must equal the canonical supported set enumerated below.
    function test_ActionTypeSupportSets_StayIdenticalAcrossRouterTimelockAndSenate() public view {
        uint256 highestActionType = uint256(type(GovernanceTypes.ActionType).max);

        uint256 supportedSeen;
        for (uint256 raw = 0; raw <= highestActionType; ++raw) {
            GovernanceTypes.ActionType actionType = GovernanceTypes.ActionType(raw);
            bool expected = _isCanonicallySupported(actionType);

            assertEq(router.isActionTypeSupported(actionType), expected, "router support drifted");
            assertEq(timelock.isActionTypeSupported(actionType), expected, "timelock support drifted");
            assertEq(_senateCancelAllowed(actionType), expected, "senate cancellation set drifted");

            if (expected) {
                supportedSeen += 1;
            }
        }

        // Guards against the canonical helper silently accepting more/fewer members than the intended five.
        assertEq(supportedSeen, 5, "canonical supported-set cardinality changed");
        assertFalse(_isCanonicallySupported(GovernanceTypes.ActionType.Undefined), "Undefined must never be supported");
    }

    /// @dev The one intended list of timelock-flow action types. Update this — and all three contracts — together.
    function _isCanonicallySupported(GovernanceTypes.ActionType actionType) private pure returns (bool supported) {
        return actionType == GovernanceTypes.ActionType.ModulePointerUpdate
            || actionType == GovernanceTypes.ActionType.ModuleRegistration
            || actionType == GovernanceTypes.ActionType.TreasuryBudgetApproval
            || actionType == GovernanceTypes.ActionType.LegislationEnactment
            || actionType == GovernanceTypes.ActionType.TreasuryDisbursement;
    }

    /// @dev Isolates the action-type clause of Senate cancellation eligibility by supplying the minimal record that
    ///      already satisfies the `actionId != 0` and `state == Queued` preconditions.
    function _senateCancelAllowed(GovernanceTypes.ActionType actionType) private view returns (bool allowed) {
        GovernanceTypes.ActionRecord memory actionRecord;
        actionRecord.actionId = bytes32(uint256(1));
        actionRecord.state = GovernanceTypes.ActionState.Queued;
        actionRecord.actionType = actionType;
        return senatePowersPolicy.isActionCancellationAllowed(actionRecord);
    }

    function _defaultDelayConfig() internal pure returns (GovernanceTypes.TimelockDelayConfig memory config) {
        config = GovernanceTypes.TimelockDelayConfig({
            moduleGovernanceDelay: 2 days,
            treasuryBudgetApprovalDelay: 1 days,
            legislationEnactmentDelay: 1 days,
            treasuryDisbursementDelay: 2 days,
            defaultExecutionWindow: 7 days
        });
    }
}
