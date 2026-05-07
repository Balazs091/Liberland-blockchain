// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IGovernanceRouter} from "../../contracts/interfaces/IGovernanceRouter.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";

/// @title Milestone1BootstrapTest
/// @notice Placeholder tests that keep the Milestone 1 scaffold compile-checked.
contract Milestone1BootstrapTest is Test {
    function test_GovernanceTypesCanBeInstantiated() public pure {
        GovernanceTypes.ActionRequest memory request = GovernanceTypes.ActionRequest({
            actionType: GovernanceTypes.ActionType.ModulePointerUpdate,
            origin: GovernanceTypes.ActionOrigin.Referendum,
            originReference: bytes32(uint256(1)),
            policyReference: bytes32(uint256(2)),
            targetModule: keccak256("ActionTimelock"),
            payload: hex"01020304",
            requestedExecutionTime: 100,
            expiresAt: 200
        });

        GovernanceTypes.ActionRecord memory record = GovernanceTypes.ActionRecord({
            actionId: keccak256("action-1"),
            actionType: request.actionType,
            origin: request.origin,
            originReference: request.originReference,
            policyReference: request.policyReference,
            targetModule: request.targetModule,
            payload: request.payload,
            createdAt: 90,
            earliestExecutionTime: 100,
            expiresAt: 200,
            state: GovernanceTypes.ActionState.Queued
        });

        assertEq(uint256(request.actionType), uint256(GovernanceTypes.ActionType.ModulePointerUpdate));
        assertEq(record.actionId, keccak256("action-1"));
        assertEq(uint256(record.state), uint256(GovernanceTypes.ActionState.Queued));
    }

    function test_DomainTypesCanBeInstantiated() public pure {
        IdentityTypes.IdentityRecord memory identity = IdentityTypes.IdentityRecord({
            personId: bytes32(uint256(11)),
            metadataHash: keccak256("identity"),
            metadataURI: "ipfs://identity",
            verificationStatus: IdentityTypes.VerificationStatus.Verified,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
            ageClass: IdentityTypes.AgeClass.Adult,
            correctionFlag: false,
            finalSuspension: false,
            updatedAt: 1
        });

        ElectionTypes.ElectionCycle memory cycle = ElectionTypes.ElectionCycle({
            cycleId: 1,
            electionType: ElectionTypes.ElectionType.CongressGeneral,
            status: ElectionTypes.ElectionStatus.Scheduled,
            ballotType: ElectionTypes.BallotType.SingleChoice,
            nominationStart: 10,
            votingStart: 20,
            votingEnd: 30,
            seats: 25,
            policyReference: bytes32(uint256(12))
        });

        TreasuryTypes.DisbursementRequest memory request = TreasuryTypes.DisbursementRequest({
            requestId: bytes32(uint256(21)),
            budgetId: bytes32(uint256(22)),
            officeId: bytes32(uint256(24)),
            disbursementType: TreasuryTypes.DisbursementType.Operations,
            asset: address(0xBEEF),
            recipient: address(0xCAFE),
            amount: 100 ether,
            policyReference: bytes32(uint256(23)),
            noteHash: keccak256("note"),
            noteURI: "ipfs://note",
            state: TreasuryTypes.DisbursementState.Proposed,
            createdAt: 1,
            routeAfter: 2,
            actionId: bytes32(uint256(25))
        });

        assertEq(identity.personId, bytes32(uint256(11)));
        assertEq(cycle.cycleId, 1);
        assertEq(request.recipient, address(0xCAFE));
    }

    function test_CoreInterfacesExposeSelectors() public pure {
        assertTrue(IConstitutionKernel.getModule.selector != bytes4(0));
        assertTrue(IConstitutionKernel.getModuleRecord.selector != bytes4(0));
        assertTrue(IConstitutionKernel.isAuthorizedModule.selector != bytes4(0));
        assertTrue(IConstitutionKernel.governanceUpdateModule.selector != bytes4(0));

        assertTrue(IGovernanceRouter.kernel.selector != bytes4(0));
        assertTrue(IGovernanceRouter.routeAction.selector != bytes4(0));
        assertTrue(IGovernanceRouter.cancelAction.selector != bytes4(0));
        assertTrue(IGovernanceRouter.originAuthority.selector != bytes4(0));
        assertTrue(IGovernanceRouter.isActionTypeSupported.selector != bytes4(0));

        assertTrue(IActionTimelock.queueAction.selector != bytes4(0));
        assertTrue(IActionTimelock.cancelAction.selector != bytes4(0));
        assertTrue(IActionTimelock.executeAction.selector != bytes4(0));
        assertTrue(IActionTimelock.expireAction.selector != bytes4(0));
    }
}
