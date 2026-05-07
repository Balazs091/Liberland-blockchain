// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {BudgetEnvelopeRegistry} from "../../contracts/registries/BudgetEnvelopeRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {SenateSeatRegistry} from "../../contracts/registries/SenateSeatRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {OfficeExecutor} from "../../contracts/apps/OfficeExecutor.sol";
import {PayoutQueue} from "../../contracts/apps/PayoutQueue.sol";
import {SenateApp} from "../../contracts/apps/SenateApp.sol";
import {TreasuryVault} from "../../contracts/apps/TreasuryVault.sol";
import {ActionTimelock} from "../../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../../contracts/core/GovernanceRouter.sol";
import {IBudgetEnvelopeRegistry} from "../../contracts/interfaces/IBudgetEnvelopeRegistry.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IOfficeExecutor} from "../../contracts/interfaces/IOfficeExecutor.sol";
import {IOfficePermissionPolicy} from "../../contracts/interfaces/IOfficePermissionPolicy.sol";
import {IOfficeRegistry} from "../../contracts/interfaces/IOfficeRegistry.sol";
import {IPayoutQueue} from "../../contracts/interfaces/IPayoutQueue.sol";
import {ISenateApp} from "../../contracts/interfaces/ISenateApp.sol";
import {ITreasurySpendingPolicy} from "../../contracts/interfaces/ITreasurySpendingPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {OfficePermissionPolicy} from "../../contracts/policies/OfficePermissionPolicy.sol";
import {SenatePowersPolicy} from "../../contracts/policies/SenatePowersPolicy.sol";
import {TreasurySpendingPolicy} from "../../contracts/policies/TreasurySpendingPolicy.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";

/// @title Milestone6TreasuryAndOfficesTest
/// @notice Covers v1 office administration, budget approval, delayed payouts, and Senate-vetoable treasury execution.
contract Milestone6TreasuryAndOfficesTest is Test {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint32 internal constant SENATE_CANCELLATION_THRESHOLD = 2;
    uint256 internal constant FINANCE_CLERK_OPERATIONS_LIMIT = 3 ether;
    uint256 internal constant FINANCE_CLERK_SALARY_LIMIT = 2 ether;

    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    bytes32 internal constant IDENTITY_OFFICE_ID = keccak256("office.identity");
    bytes32 internal constant LAND_OFFICE_ID = keccak256("office.land");
    bytes32 internal constant OPERATIONS_BUDGET_ID = keccak256("budget.operations");
    bytes32 internal constant VETO_BUDGET_ID = keccak256("budget.veto");
    bytes32 internal constant PAYOUT_REQUEST_ID = keccak256("payout.operations");
    bytes32 internal constant VETO_PAYOUT_REQUEST_ID = keccak256("payout.veto");

    bytes32 internal constant SENATOR_ONE_PERSON_ID = bytes32(uint256(1));
    bytes32 internal constant SENATOR_TWO_PERSON_ID = bytes32(uint256(2));

    address internal constant MINISTER_OF_FINANCE = address(0xF1A0);
    address internal constant FINANCE_CLERK = address(0xF1A1);
    address internal constant IDENTITY_ADMIN = address(0x1D01);
    address internal constant IDENTITY_CLERK = address(0x1D02);
    address internal constant LAND_ADMIN = address(0x1A01);
    address internal constant TREASURY_RECIPIENT = address(0xBEEF);
    address internal constant SENATOR_ONE = address(0xA11CE);
    address internal constant SENATOR_TWO = address(0xB0B);

    ConstitutionKernel internal kernel;
    ActionTimelock internal timelock;
    GovernanceRouter internal router;
    MockModule internal identityAuthority;
    MockModule internal stakeAuthority;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    SenateSeatRegistry internal senateSeatRegistry;
    SenatePowersPolicy internal senatePowersPolicy;
    SenateApp internal senateApp;
    TreasuryVault internal treasuryVault;
    BudgetEnvelopeRegistry internal budgetEnvelopeRegistry;
    OfficeRegistry internal officeRegistry;
    OfficePermissionPolicy internal officePermissionPolicy;
    TreasurySpendingPolicy internal treasurySpendingPolicy;
    PayoutQueue internal payoutQueue;
    OfficeExecutor internal officeExecutor;

    function setUp() public {
        _deployFoundation();
        _registerCitizen(SENATOR_ONE_PERSON_ID, SENATOR_ONE, 10_000);
        _registerCitizen(SENATOR_TWO_PERSON_ID, SENATOR_TWO, 12_000);
        _seedInitialSenateSeats();
        _bootstrapOffices();

        officeExecutor.disableBootstrapAuthority();
        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();

        vm.deal(address(this), 25 ether);
        (bool funded,) = address(treasuryVault).call{value: 10 ether}("");
        assertTrue(funded);
    }

    function test_Milestone6InterfacesExposeSelectors() public pure {
        assertTrue(IBudgetEnvelopeRegistry.recordBudgetApproval.selector != bytes4(0));
        assertTrue(IConstitutionKernel.governanceUpdateModule.selector != bytes4(0));
        assertTrue(IOfficeExecutor.requestBudgetApproval.selector != bytes4(0));
        assertTrue(IOfficePermissionPolicy.isActionAuthorized.selector != bytes4(0));
        assertTrue(IOfficeRegistry.registerOffice.selector != bytes4(0));
        assertTrue(IPayoutQueue.syncPayoutState.selector != bytes4(0));
        assertTrue(ISenateApp.supportActionCancellation.selector != bytes4(0));
        assertTrue(ITreasurySpendingPolicy.isPayoutAllowed.selector != bytes4(0));
    }

    function test_OfficeAdminsCanChooseClerksWithinTheirOwnOffice() public {
        vm.prank(MINISTER_OF_FINANCE);
        officeExecutor.assignClerk(FINANCE_OFFICE_ID, FINANCE_CLERK);

        assertEq(
            uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, FINANCE_CLERK)), uint256(OfficeTypes.OfficeRole.Clerk)
        );

        vm.prank(IDENTITY_ADMIN);
        officeExecutor.assignClerk(IDENTITY_OFFICE_ID, IDENTITY_CLERK);

        assertEq(
            uint256(officeRegistry.roleOf(IDENTITY_OFFICE_ID, IDENTITY_CLERK)), uint256(OfficeTypes.OfficeRole.Clerk)
        );

        vm.prank(FINANCE_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOfficeExecutor.UnauthorizedOfficeAction.selector,
                FINANCE_CLERK,
                FINANCE_OFFICE_ID,
                OfficeTypes.OfficeActionClass.ManageClerks
            )
        );
        officeExecutor.assignClerk(FINANCE_OFFICE_ID, address(0xCC11));

        vm.prank(IDENTITY_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOfficeExecutor.UnauthorizedOfficeAction.selector,
                IDENTITY_ADMIN,
                FINANCE_OFFICE_ID,
                OfficeTypes.OfficeActionClass.ManageClerks
            )
        );
        officeExecutor.assignClerk(FINANCE_OFFICE_ID, address(0xCC12));
    }

    function test_BudgetApproval_IsDelayedAndExecutableThroughTimelock() public {
        bytes32 actionId = _requestBudgetApproval(OPERATIONS_BUDGET_ID, 8 ether);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Queued));
        assertFalse(budgetEnvelopeRegistry.budgetExists(OPERATIONS_BUDGET_ID));

        vm.warp(block.timestamp + 2 days);
        timelock.executeAction(actionId);

        TreasuryTypes.BudgetEnvelope memory budgetEnvelope =
            budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID);
        assertEq(budgetEnvelope.budgetId, OPERATIONS_BUDGET_ID);
        assertEq(budgetEnvelope.officeId, FINANCE_OFFICE_ID);
        assertEq(uint256(budgetEnvelope.disbursementType), uint256(TreasuryTypes.DisbursementType.Operations));
        assertEq(budgetEnvelope.allocatedAmount, 8 ether);
        assertEq(budgetEnvelope.spentAmount, 0);
        assertEq(budgetEnvelope.committedAmount, 0);
        assertTrue(budgetEnvelopeRegistry.isBudgetActive(OPERATIONS_BUDGET_ID));
        assertEq(budgetEnvelopeRegistry.availableAmount(OPERATIONS_BUDGET_ID), 8 ether);
    }

    function test_SenateCanVetoQueuedBudgetApproval() public {
        bytes32 actionId = _requestBudgetApproval(VETO_BUDGET_ID, 4 ether);

        vm.prank(SENATOR_ONE);
        senateApp.supportActionCancellation(actionId, 0);
        vm.prank(SENATOR_TWO);
        senateApp.supportActionCancellation(actionId, 1);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));
        assertFalse(budgetEnvelopeRegistry.budgetExists(VETO_BUDGET_ID));
    }

    function test_FinanceClerkCanRouteAndExecutePayoutAgainstApprovedBudget() public {
        vm.prank(MINISTER_OF_FINANCE);
        officeExecutor.assignClerk(FINANCE_OFFICE_ID, FINANCE_CLERK);

        _approveBudget(OPERATIONS_BUDGET_ID, 10 ether);

        vm.prank(FINANCE_CLERK);
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID,
            TreasuryTypes.DisbursementRequestInput({
                requestId: PAYOUT_REQUEST_ID,
                budgetId: OPERATIONS_BUDGET_ID,
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(0),
                recipient: TREASURY_RECIPIENT,
                amount: 1 ether,
                policyReference: bytes32(0),
                noteHash: keccak256("ops-payout"),
                noteURI: "ipfs://ops-payout"
            })
        );

        TreasuryTypes.DisbursementRequest memory request = payoutQueue.getDisbursementRequest(PAYOUT_REQUEST_ID);
        assertEq(uint256(request.state), uint256(TreasuryTypes.DisbursementState.Proposed));
        assertEq(request.amount, 1 ether);

        vm.warp(request.routeAfter);

        vm.prank(FINANCE_CLERK);
        bytes32 actionId = officeExecutor.routePayout(FINANCE_OFFICE_ID, PAYOUT_REQUEST_ID);

        request = payoutQueue.getDisbursementRequest(PAYOUT_REQUEST_ID);
        assertEq(uint256(request.state), uint256(TreasuryTypes.DisbursementState.Queued));
        assertEq(request.actionId, actionId);

        TreasuryTypes.BudgetEnvelope memory budgetEnvelope =
            budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID);
        assertEq(budgetEnvelope.committedAmount, 1 ether);
        assertEq(budgetEnvelope.spentAmount, 0);

        vm.warp(block.timestamp + 2 days);
        timelock.executeAction(actionId);
        payoutQueue.syncPayoutState(PAYOUT_REQUEST_ID);

        request = payoutQueue.getDisbursementRequest(PAYOUT_REQUEST_ID);
        budgetEnvelope = budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID);

        assertEq(uint256(request.state), uint256(TreasuryTypes.DisbursementState.Executed));
        assertEq(address(treasuryVault).balance, 9 ether);
        assertEq(TREASURY_RECIPIENT.balance, 1 ether);
        assertEq(budgetEnvelope.committedAmount, 0);
        assertEq(budgetEnvelope.spentAmount, 1 ether);
        assertEq(budgetEnvelopeRegistry.availableAmount(OPERATIONS_BUDGET_ID), 9 ether);
    }

    function test_SenateCanVetoQueuedPayoutAndReleaseBudgetCommitment() public {
        vm.prank(MINISTER_OF_FINANCE);
        officeExecutor.assignClerk(FINANCE_OFFICE_ID, FINANCE_CLERK);

        _approveBudget(OPERATIONS_BUDGET_ID, 5 ether);

        vm.prank(FINANCE_CLERK);
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID,
            TreasuryTypes.DisbursementRequestInput({
                requestId: VETO_PAYOUT_REQUEST_ID,
                budgetId: OPERATIONS_BUDGET_ID,
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(0),
                recipient: TREASURY_RECIPIENT,
                amount: 2 ether,
                policyReference: bytes32(0),
                noteHash: keccak256("veto-payout"),
                noteURI: "ipfs://veto-payout"
            })
        );

        TreasuryTypes.DisbursementRequest memory request = payoutQueue.getDisbursementRequest(VETO_PAYOUT_REQUEST_ID);
        vm.warp(request.routeAfter);

        vm.prank(FINANCE_CLERK);
        bytes32 actionId = officeExecutor.routePayout(FINANCE_OFFICE_ID, VETO_PAYOUT_REQUEST_ID);

        vm.prank(SENATOR_ONE);
        senateApp.supportActionCancellation(actionId, 0);
        vm.prank(SENATOR_TWO);
        senateApp.supportActionCancellation(actionId, 1);

        payoutQueue.syncPayoutState(VETO_PAYOUT_REQUEST_ID);

        request = payoutQueue.getDisbursementRequest(VETO_PAYOUT_REQUEST_ID);
        TreasuryTypes.BudgetEnvelope memory budgetEnvelope =
            budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID);

        assertEq(uint256(request.state), uint256(TreasuryTypes.DisbursementState.Vetoed));
        assertEq(budgetEnvelope.committedAmount, 0);
        assertEq(budgetEnvelope.spentAmount, 0);
        assertEq(TREASURY_RECIPIENT.balance, 0);
        assertEq(address(treasuryVault).balance, 10 ether);
    }

    function test_NonFinanceOfficeCannotProposeTreasuryPayout() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOfficeExecutor.UnauthorizedOfficeAction.selector,
                IDENTITY_ADMIN,
                IDENTITY_OFFICE_ID,
                OfficeTypes.OfficeActionClass.ProposePayout
            )
        );
        vm.prank(IDENTITY_ADMIN);
        officeExecutor.proposePayout(
            IDENTITY_OFFICE_ID,
            TreasuryTypes.DisbursementRequestInput({
                requestId: keccak256("identity-payout"),
                budgetId: OPERATIONS_BUDGET_ID,
                officeId: IDENTITY_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(0),
                recipient: TREASURY_RECIPIENT,
                amount: 1 ether,
                policyReference: bytes32(0),
                noteHash: keccak256("identity"),
                noteURI: "ipfs://identity"
            })
        );
    }

    function _deployFoundation() private {
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(address(kernel));
        router = new GovernanceRouter(address(kernel), address(this));
        identityAuthority = new MockModule(keccak256("milestone6.identity-authority"));
        stakeAuthority = new MockModule(keccak256("milestone6.stake-authority"));

        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));

        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);

        senateSeatRegistry = new SenateSeatRegistry(address(kernel));
        senatePowersPolicy = new SenatePowersPolicy(SENATE_CANCELLATION_THRESHOLD);
        senateApp = new SenateApp(
            address(identityRegistry),
            address(senateSeatRegistry),
            address(senatePowersPolicy),
            address(router),
            address(timelock)
        );

        treasuryVault = new TreasuryVault(address(kernel));
        budgetEnvelopeRegistry = new BudgetEnvelopeRegistry(address(kernel));
        officeRegistry = new OfficeRegistry(address(kernel));
        officePermissionPolicy = new OfficePermissionPolicy();
        treasurySpendingPolicy =
            new TreasurySpendingPolicy(FINANCE_OFFICE_ID, FINANCE_CLERK_OPERATIONS_LIMIT, FINANCE_CLERK_SALARY_LIMIT);
        payoutQueue = new PayoutQueue(address(kernel), address(budgetEnvelopeRegistry));
        officeExecutor = new OfficeExecutor(
            address(officeRegistry),
            address(officePermissionPolicy),
            address(treasurySpendingPolicy),
            address(payoutQueue),
            address(router),
            address(this)
        );

        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(identityAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(stakeAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(stakeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(citizenEligibilityPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY, address(senateApp));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY, address(senateSeatRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_POWERS_POLICY, address(senatePowersPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(senateApp));
        kernel.bootstrapSetModule(KernelModuleIds.TREASURY_VAULT, address(treasuryVault));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY, address(budgetEnvelopeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(timelock));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, address(payoutQueue));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY, address(officeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(officeExecutor));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_PERMISSION_POLICY, address(officePermissionPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.TREASURY_SPENDING_POLICY, address(treasurySpendingPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.PAYOUT_QUEUE, address(payoutQueue));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_EXECUTOR, address(officeExecutor));

        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Office, address(officeExecutor));
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Senate, address(senateApp));
    }

    function _bootstrapOffices() private {
        officeExecutor.bootstrapCreateOffice(
            FINANCE_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "Ministry of Finance", MINISTER_OF_FINANCE
        );
        officeExecutor.bootstrapCreateOffice(
            IDENTITY_OFFICE_ID, OfficeTypes.OfficeKind.IdentityOffice, "Identity Office", IDENTITY_ADMIN
        );
        officeExecutor.bootstrapCreateOffice(
            LAND_OFFICE_ID, OfficeTypes.OfficeKind.LandRegistryOffice, "Land Registry Office", LAND_ADMIN
        );
    }

    function _registerCitizen(bytes32 personId, address wallet, uint256 stakeAmount) private {
        vm.prank(address(identityAuthority));
        identityRegistry.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256(abi.encode(personId, wallet)),
                metadataURI: "ipfs://citizen",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );

        vm.prank(address(identityAuthority));
        identityRegistry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);

        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(personId, stakeAmount);
    }

    function _seedInitialSenateSeats() private {
        senateApp.bootstrapAssignSeat(0, SENATOR_ONE);
        senateApp.bootstrapAssignSeat(1, SENATOR_TWO);
    }

    function _requestBudgetApproval(bytes32 budgetId, uint256 allocatedAmount) private returns (bytes32 actionId) {
        vm.prank(MINISTER_OF_FINANCE);
        actionId = officeExecutor.requestBudgetApproval(
            FINANCE_OFFICE_ID,
            budgetId,
            TreasuryTypes.DisbursementType.Operations,
            address(0),
            allocatedAmount,
            uint64(block.timestamp),
            uint64(block.timestamp + 30 days)
        );
    }

    function _approveBudget(bytes32 budgetId, uint256 allocatedAmount) private {
        bytes32 actionId = _requestBudgetApproval(budgetId, allocatedAmount);
        vm.warp(block.timestamp + 2 days);
        timelock.executeAction(actionId);
    }
}
