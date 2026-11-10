// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {CabinetAppTest} from "../apps/CabinetApp.t.sol";
import {ICabinetApp} from "../../contracts/interfaces/ICabinetApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {JusticeCitizenEligibilityPolicy} from "../../contracts/policies/JusticeCitizenEligibilityPolicy.sol";
import {MembershipRegistry} from "../../contracts/registries/MembershipRegistry.sol";
import {ExecutiveTypes} from "../../contracts/types/ExecutiveTypes.sol";
import {MembershipTypes} from "../../contracts/types/MembershipTypes.sol";

contract JusticeLegacyCabinetPolicy {
    function isCitizenInGoodStanding(address) external pure returns (bool) {
        return true;
    }
}

/// @dev Reuses the existing Cabinet fixture and keeps its legacy regression tests unchanged.
contract JusticeCabinetEligibilityTest is CabinetAppTest {
    function testJusticeAppointmentRestrictionRechecksVotesAndExecution() public {
        MembershipRegistry membership = _enableJusticePolicy();
        _voteForPm(CM1, PM_CANDIDATE);
        _voteForPm(CM2, PM_CANDIDATE);
        _voteForPm(CM3, PM_CANDIDATE);
        _voteForPm(CM4, PM_CANDIDATE);
        assertTrue(cabinetApp.canAppointPrimeMinister(PM_CANDIDATE));
        _restrictAppointment(membership, PID_PM);
        assertFalse(cabinetApp.canAppointPrimeMinister(PM_CANDIDATE));
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.CandidateNotInGoodStanding.selector, PM_CANDIDATE));
        vm.prank(CM5);
        cabinetApp.voteForPrimeMinister(PM_CANDIDATE);
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.CandidateNotInGoodStanding.selector, PM_CANDIDATE));
        cabinetApp.appointPrimeMinister(PM_CANDIDATE);
        vm.warp(block.timestamp + 100);
        cabinetApp.appointPrimeMinister(PM_CANDIDATE);
        assertEq(executiveRegistry.primeMinister(), PM_CANDIDATE);
    }

    function testJusticeMinisterAdmissionChecksAppointmentRestriction() public {
        MembershipRegistry membership = _enableJusticePolicy();
        _appointPmWithVotes(PM_CANDIDATE, 4);
        _restrictAppointment(membership, bytes32(uint256(111)));
        vm.expectRevert(abi.encodeWithSelector(ICabinetApp.CandidateNotInGoodStanding.selector, MIN_A));
        vm.prank(PM_CANDIDATE);
        cabinetApp.appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        vm.warp(block.timestamp + 100);
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Finance).minister, MIN_A);
    }

    function testJusticeAdmissionRuleDoesNotRevokeIncumbentAuthority() public {
        MembershipRegistry membership = _enableJusticePolicy();
        _appointPmWithVotes(PM_CANDIDATE, 4);
        // Direct fact-source fixture: actual JusticeApp protects sitting office holders from this order.
        _restrictAppointment(membership, PID_PM);
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        assertEq(executiveRegistry.primeMinister(), PM_CANDIDATE);
        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Finance).minister, MIN_A);
    }

    function testJusticeLegacyPolicyWithoutAppointmentMethodStillWorks() public {
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(new JusticeLegacyCabinetPolicy()));
        _appointPmWithVotes(PM_CANDIDATE, 4);
        _appointMinister(ExecutiveTypes.MinistryKind.Finance, MIN_A);
        assertEq(executiveRegistry.primeMinister(), PM_CANDIDATE);
        assertEq(executiveRegistry.getMinister(ExecutiveTypes.MinistryKind.Finance).minister, MIN_A);
    }

    function _enableJusticePolicy() private returns (MembershipRegistry membership) {
        membership = new MembershipRegistry(address(kernel), address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.MEMBERSHIP_REGISTRY, address(membership));
        kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_APP, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_WRITER, address(this));
        JusticeCitizenEligibilityPolicy policy = new JusticeCitizenEligibilityPolicy(
            address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE, address(membership)
        );
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(policy));
    }

    function _restrictAppointment(MembershipRegistry membership, bytes32 personId) private {
        membership.recordOrder(
            MembershipTypes.OrderInput(
                personId,
                keccak256("appointment order"),
                16,
                uint64(block.timestamp),
                uint64(block.timestamp + 100),
                false
            ),
            keccak256("decision receipt")
        );
    }
}
