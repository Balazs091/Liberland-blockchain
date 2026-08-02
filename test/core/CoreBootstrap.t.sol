// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IActionTimelock} from "../../contracts/interfaces/IActionTimelock.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IGovernanceRouter} from "../../contracts/interfaces/IGovernanceRouter.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";

/// @title CoreBootstrapTest
/// @notice Covers kernel bootstrap registration and the shared domain types.
contract CoreBootstrapTest is Test {
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
            targetModuleAddress: address(0x1234),
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
        assertTrue(IConstitutionKernel.bootstrapSetModules.selector != bytes4(0));
        assertTrue(IConstitutionKernel.governanceUpdateModule.selector != bytes4(0));
        assertTrue(IConstitutionKernel.governanceRegisterModule.selector != bytes4(0));

        assertTrue(IGovernanceRouter.kernel.selector != bytes4(0));
        assertTrue(IGovernanceRouter.routeAction.selector != bytes4(0));
        assertTrue(IGovernanceRouter.cancelAction.selector != bytes4(0));
        assertTrue(IGovernanceRouter.originAuthority.selector != bytes4(0));
        assertTrue(IGovernanceRouter.isActionTypeSupported.selector != bytes4(0));

        assertTrue(IActionTimelock.queueAction.selector != bytes4(0));
        assertTrue(IActionTimelock.cancelAction.selector != bytes4(0));
        assertTrue(IActionTimelock.executeAction.selector != bytes4(0));
        assertTrue(IActionTimelock.executeActions.selector != bytes4(0));
        assertTrue(IActionTimelock.expireAction.selector != bytes4(0));
    }

    function test_BootstrapSetModulesRegistersBatch() public {
        ConstitutionKernel kernel = new ConstitutionKernel(address(this));
        MockModule router = new MockModule(keccak256("router"));
        MockModule timelock = new MockModule(keccak256("timelock"));

        bytes32[] memory moduleIds = new bytes32[](2);
        address[] memory moduleAddresses = new address[](2);
        moduleIds[0] = KernelModuleIds.GOVERNANCE_ROUTER;
        moduleIds[1] = KernelModuleIds.ACTION_TIMELOCK;
        moduleAddresses[0] = address(router);
        moduleAddresses[1] = address(timelock);

        kernel.bootstrapSetModules(moduleIds, moduleAddresses);

        assertEq(kernel.getModule(KernelModuleIds.GOVERNANCE_ROUTER), address(router));
        assertEq(kernel.getModule(KernelModuleIds.ACTION_TIMELOCK), address(timelock));
        assertTrue(kernel.isAuthorizedModule(address(router)));
        assertTrue(kernel.isAuthorizedModule(address(timelock)));
    }

    function test_LandPartyPolicyUsesConstitutionalPolicyClass() public {
        ConstitutionKernel kernel = new ConstitutionKernel(address(this));
        assertEq(
            uint256(kernel.moduleClass(KernelModuleIds.LAND_PARTY_POLICY)), uint256(GovernanceTypes.ModuleClass.Policy)
        );
    }

    function test_BootstrapSetModulesReplacesExistingModuleAndAuthorization() public {
        ConstitutionKernel kernel = new ConstitutionKernel(address(this));
        MockModule initialModule = new MockModule(keccak256("initial"));
        MockModule replacementModule = new MockModule(keccak256("replacement"));

        bytes32[] memory moduleIds = new bytes32[](1);
        address[] memory moduleAddresses = new address[](1);
        moduleIds[0] = KernelModuleIds.GOVERNANCE_ROUTER;
        moduleAddresses[0] = address(initialModule);
        kernel.bootstrapSetModules(moduleIds, moduleAddresses);

        moduleAddresses[0] = address(replacementModule);
        kernel.bootstrapSetModules(moduleIds, moduleAddresses);

        assertEq(kernel.getModule(KernelModuleIds.GOVERNANCE_ROUTER), address(replacementModule));
        assertFalse(kernel.isAuthorizedModule(address(initialModule)));
        assertTrue(kernel.isAuthorizedModule(address(replacementModule)));
    }

    function test_BootstrapSetModulesRevertsForInvalidBatchLengths() public {
        ConstitutionKernel kernel = new ConstitutionKernel(address(this));

        bytes32[] memory emptyModuleIds = new bytes32[](0);
        address[] memory emptyModuleAddresses = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(ConstitutionKernel.InvalidModuleBatchLength.selector, 0, 0));
        kernel.bootstrapSetModules(emptyModuleIds, emptyModuleAddresses);

        bytes32[] memory moduleIds = new bytes32[](1);
        moduleIds[0] = KernelModuleIds.GOVERNANCE_ROUTER;
        vm.expectRevert(abi.encodeWithSelector(ConstitutionKernel.InvalidModuleBatchLength.selector, 1, 0));
        kernel.bootstrapSetModules(moduleIds, emptyModuleAddresses);
    }

    function test_BootstrapSetModulesRevertsAfterBootstrapAuthorityDisabled() public {
        ConstitutionKernel kernel = new ConstitutionKernel(address(this));
        MockModule router = new MockModule(keccak256("router"));

        bytes32[] memory moduleIds = new bytes32[](1);
        address[] memory moduleAddresses = new address[](1);
        moduleIds[0] = KernelModuleIds.GOVERNANCE_ROUTER;
        moduleAddresses[0] = address(router);

        kernel.disableBootstrapAuthority();
        vm.expectRevert(ConstitutionKernel.BootstrapAlreadyDisabled.selector);
        kernel.bootstrapSetModules(moduleIds, moduleAddresses);
    }
}
