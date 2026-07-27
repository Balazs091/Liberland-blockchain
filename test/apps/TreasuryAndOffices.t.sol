// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {BudgetEnvelopeRegistry} from "../../contracts/registries/BudgetEnvelopeRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LegislationRegistry} from "../../contracts/registries/LegislationRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {PresidentRegistry} from "../../contracts/registries/PresidentRegistry.sol";
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
import {ITreasuryVault} from "../../contracts/interfaces/ITreasuryVault.sol";
import {ITreasurySpendingPolicy} from "../../contracts/interfaces/ITreasurySpendingPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {MockUSDC} from "../../contracts/mocks/MockUSDC.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {OfficePermissionPolicy} from "../../contracts/policies/OfficePermissionPolicy.sol";
import {SenatePowersPolicy} from "../../contracts/policies/SenatePowersPolicy.sol";
import {TreasurySpendingPolicy} from "../../contracts/policies/TreasurySpendingPolicy.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";

contract MockReferendumAppForTreasury {
    address public immutable governanceRouter;
    address public immutable legislationRegistry;
    address public immutable referendumRegistry;

    constructor(address governanceRouterAddress, address legislationRegistryAddress) {
        governanceRouter = governanceRouterAddress;
        legislationRegistry = legislationRegistryAddress;
        referendumRegistry = address(0);
    }

    function routeAction(GovernanceTypes.ActionRequest calldata request) external returns (bytes32 actionId) {
        return GovernanceRouter(governanceRouter).routeAction(request);
    }
}

/// @title TreasuryAndOfficesTest
/// @notice Covers v1 office administration, budget approval, delayed payouts, and Senate-vetoable treasury execution.
contract TreasuryAndOfficesTest is Test {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint32 internal constant SENATE_CANCELLATION_THRESHOLD = 2;
    uint64 internal constant DISBURSEMENT_SUSPENSION_PERIOD = 30 days;
    uint256 internal constant ONE_USDC = 1e6;
    uint256 internal constant ONE_LLM = 1e18;
    uint256 internal constant CONTRIBUTION_REWARD_AMOUNT = 1_250 * ONE_LLM;
    uint256 internal constant FINANCE_CLERK_OPERATIONS_LIMIT = 3_000 * ONE_USDC;
    uint256 internal constant FINANCE_CLERK_SALARY_LIMIT = 2_000 * ONE_USDC;

    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    bytes32 internal constant IDENTITY_OFFICE_ID = keccak256("office.identity");
    bytes32 internal constant LAND_OFFICE_ID = keccak256("office.land");
    bytes32 internal constant COMPANY_REGISTRY_OFFICE_ID = keccak256("office.company-registry");
    bytes32 internal constant OPERATIONS_BUDGET_ID = keccak256("budget.operations");
    bytes32 internal constant VETO_BUDGET_ID = keccak256("budget.veto");
    bytes32 internal constant CONTRIBUTION_REWARD_BUDGET_ID = keccak256("budget.contribution-rewards");
    bytes32 internal constant PAYOUT_REQUEST_ID = keccak256("payout.operations");
    bytes32 internal constant VETO_PAYOUT_REQUEST_ID = keccak256("payout.veto");

    bytes32 internal constant SENATOR_ONE_PERSON_ID = bytes32(uint256(1));
    bytes32 internal constant SENATOR_TWO_PERSON_ID = bytes32(uint256(2));

    address internal constant MINISTER_OF_FINANCE = address(0xF1A0);
    address internal constant FINANCE_CLERK = address(0xF1A1);
    address internal constant IDENTITY_ADMIN = address(0x1D01);
    address internal constant IDENTITY_CLERK = address(0x1D02);
    address internal constant LAND_ADMIN = address(0x1A01);
    address internal constant COMPANY_REGISTRY_ADMIN = address(0xC001);
    address internal constant COMPANY_REGISTRY_CLERK = address(0xC002);
    address internal constant TREASURY_RECIPIENT = address(0xBEEF);
    address internal constant SENATOR_ONE = address(0xA11CE);
    address internal constant SENATOR_TWO = address(0xB0B);

    ConstitutionKernel internal kernel;
    ActionTimelock internal timelock;
    GovernanceRouter internal router;
    MockModule internal identityAuthority;
    MockModule internal stakeAuthority;
    IdentityRegistry internal identityRegistry;
    LegislationRegistry internal legislationRegistry;
    StakeRegistry internal stakeRegistry;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    SenateSeatRegistry internal senateSeatRegistry;
    PresidentRegistry internal presidentRegistry;
    SenatePowersPolicy internal senatePowersPolicy;
    MockReferendumAppForTreasury internal mockReferendumApp;
    SenateApp internal senateApp;
    TreasuryVault internal treasuryVault;
    LLMToken internal llm;
    MockUSDC internal usdc;
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
        presidentRegistry.setPresident(
            SENATOR_ONE,
            SENATOR_ONE_PERSON_ID,
            keccak256("president.mandate"),
            uint64(block.timestamp),
            type(uint64).max
        );
        _seedInitialSenateSeats();
        _bootstrapOffices();

        officeExecutor.disableBootstrapAuthority();
        router.disableBootstrapAuthority();
        kernel.disableBootstrapAuthority();

        usdc.mint(address(treasuryVault), 10_000 * ONE_USDC);
    }

    function test_InterfacesExposeSelectors() public pure {
        assertTrue(IBudgetEnvelopeRegistry.recordBudgetApproval.selector != bytes4(0));
        assertTrue(IConstitutionKernel.governanceUpdateModule.selector != bytes4(0));
        assertTrue(IOfficeExecutor.requestBudgetApproval.selector != bytes4(0));
        assertTrue(IOfficePermissionPolicy.isActionAuthorized.selector != bytes4(0));
        assertTrue(IOfficeRegistry.registerOffice.selector != bytes4(0));
        assertTrue(IPayoutQueue.syncPayoutState.selector != bytes4(0));
        assertTrue(ISenateApp.supportActionCancellation.selector != bytes4(0));
        assertTrue(ITreasuryVault.receiveTokenDeposit.selector != bytes4(0));
        assertTrue(ITreasurySpendingPolicy.isPayoutAllowed.selector != bytes4(0));
    }

    function test_TreasurySpendingPolicy_RejectsZeroLlmAsset() public {
        ITreasurySpendingPolicy.AssetSpendingLimit[] memory assetLimits =
            new ITreasurySpendingPolicy.AssetSpendingLimit[](1);
        assetLimits[0] = ITreasurySpendingPolicy.AssetSpendingLimit({
            asset: address(usdc),
            clerkOperationsLimit: FINANCE_CLERK_OPERATIONS_LIMIT,
            clerkSalaryLimit: FINANCE_CLERK_SALARY_LIMIT
        });

        vm.expectRevert(abi.encodeWithSelector(TreasurySpendingPolicy.LlmAssetNotAllowed.selector, address(0)));
        new TreasurySpendingPolicy(FINANCE_OFFICE_ID, address(0), assetLimits);
    }

    function test_TreasuryVault_ReceivesTokenDepositsThroughExplicitEntrypoint() public {
        uint256 balanceBefore = treasuryVault.treasuryBalanceOf(address(usdc));

        usdc.mint(address(this), 100 * ONE_USDC);
        usdc.approve(address(treasuryVault), 100 * ONE_USDC);
        treasuryVault.receiveTokenDeposit(address(usdc), 100 * ONE_USDC, keccak256("test.deposit"));

        assertEq(treasuryVault.treasuryBalanceOf(address(usdc)), balanceBefore + 100 * ONE_USDC);
    }

    function test_TreasuryVault_RejectsNativeValue() public {
        vm.deal(address(this), 1 ether);
        (bool accepted,) = address(treasuryVault).call{value: 1 ether}("");
        assertFalse(accepted);
    }

    function test_ContributionReward_UsesEvidenceBackedLlmBudgetAndFinanceAdmin() public {
        llm.mint(address(this), CONTRIBUTION_REWARD_AMOUNT);
        llm.approve(address(treasuryVault), CONTRIBUTION_REWARD_AMOUNT);
        treasuryVault.receiveTokenDeposit(
            address(llm), CONTRIBUTION_REWARD_AMOUNT, keccak256("llm.contribution-reward-reserve")
        );
        _approveContributionRewardBudget(CONTRIBUTION_REWARD_BUDGET_ID, CONTRIBUTION_REWARD_AMOUNT);

        vm.prank(MINISTER_OF_FINANCE);
        officeExecutor.assignClerk(FINANCE_OFFICE_ID, FINANCE_CLERK);

        assertEq(treasurySpendingPolicy.llmAsset(), address(llm));
        assertFalse(
            treasurySpendingPolicy.isPayoutAllowed(
                FINANCE_OFFICE_ID,
                OfficeTypes.OfficeRole.Admin,
                TreasuryTypes.DisbursementType.ContributionReward,
                address(usdc),
                CONTRIBUTION_REWARD_AMOUNT
            )
        );

        bytes32 requestId = keccak256("payout.contribution-reward");
        vm.prank(FINANCE_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOfficeExecutor.UnauthorizedOfficeAction.selector,
                FINANCE_CLERK,
                FINANCE_OFFICE_ID,
                OfficeTypes.OfficeActionClass.ProposePayout
            )
        );
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID,
            _contributionRewardInput(requestId, keccak256("verified-contribution"), "ipfs://contribution-evidence")
        );

        vm.prank(MINISTER_OF_FINANCE);
        vm.expectRevert(abi.encodeWithSelector(IOfficeExecutor.ContributionRewardEvidenceRequired.selector, requestId));
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID, _contributionRewardInput(requestId, bytes32(0), "ipfs://contribution-evidence")
        );

        vm.prank(MINISTER_OF_FINANCE);
        vm.expectRevert(abi.encodeWithSelector(IOfficeExecutor.ContributionRewardEvidenceRequired.selector, requestId));
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID, _contributionRewardInput(requestId, keccak256("verified-contribution"), "")
        );

        vm.prank(MINISTER_OF_FINANCE);
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID,
            _contributionRewardInput(requestId, keccak256("verified-contribution"), "ipfs://contribution-evidence")
        );

        TreasuryTypes.DisbursementRequest memory request = payoutQueue.getDisbursementRequest(requestId);
        assertEq(request.routeAfter, uint64(block.timestamp + 1 days));
        assertEq(request.noteHash, keccak256("verified-contribution"));
        assertEq(request.noteURI, "ipfs://contribution-evidence");

        vm.warp(request.routeAfter);
        vm.prank(MINISTER_OF_FINANCE);
        bytes32 actionId = officeExecutor.routePayout(FINANCE_OFFICE_ID, requestId);
        _warpToActionDeadline(actionId);
        timelock.executeAction(actionId);
        payoutQueue.syncPayoutState(requestId);

        assertEq(llm.balanceOf(TREASURY_RECIPIENT), CONTRIBUTION_REWARD_AMOUNT);
        assertEq(llm.balanceOf(address(treasuryVault)), 0);
        assertEq(
            uint256(payoutQueue.getDisbursementRequest(requestId).state),
            uint256(TreasuryTypes.DisbursementState.Executed)
        );
    }

    function test_ProposePayout_RejectsAssetOutsideAllowlist() public {
        LLMToken rogueToken = new LLMToken();
        _approveBudget(OPERATIONS_BUDGET_ID, 10_000 * ONE_USDC);

        vm.prank(MINISTER_OF_FINANCE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOfficeExecutor.UnauthorizedOfficeAction.selector,
                MINISTER_OF_FINANCE,
                FINANCE_OFFICE_ID,
                OfficeTypes.OfficeActionClass.ProposePayout
            )
        );
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID,
            TreasuryTypes.DisbursementRequestInput({
                requestId: keccak256("rogue-asset-payout"),
                budgetId: OPERATIONS_BUDGET_ID,
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(rogueToken),
                recipient: TREASURY_RECIPIENT,
                amount: 1_000 * ONE_USDC,
                policyReference: bytes32(0),
                noteHash: keccak256("rogue-asset"),
                noteURI: "ipfs://rogue-asset"
            })
        );
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

    function test_CompanyRegistryOffice_IsPlaceholderWithoutTreasuryPayoutAuthority() public {
        vm.prank(COMPANY_REGISTRY_ADMIN);
        officeExecutor.assignClerk(COMPANY_REGISTRY_OFFICE_ID, COMPANY_REGISTRY_CLERK);

        assertEq(
            uint256(officeRegistry.roleOf(COMPANY_REGISTRY_OFFICE_ID, COMPANY_REGISTRY_CLERK)),
            uint256(OfficeTypes.OfficeRole.Clerk)
        );

        vm.prank(COMPANY_REGISTRY_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOfficeExecutor.UnauthorizedOfficeAction.selector,
                COMPANY_REGISTRY_ADMIN,
                COMPANY_REGISTRY_OFFICE_ID,
                OfficeTypes.OfficeActionClass.ProposePayout
            )
        );
        officeExecutor.proposePayout(
            COMPANY_REGISTRY_OFFICE_ID,
            TreasuryTypes.DisbursementRequestInput({
                requestId: keccak256("company-registry-payout"),
                budgetId: OPERATIONS_BUDGET_ID,
                officeId: COMPANY_REGISTRY_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(usdc),
                recipient: TREASURY_RECIPIENT,
                amount: 1_000 * ONE_USDC,
                policyReference: bytes32(0),
                noteHash: keccak256("company-registry"),
                noteURI: "ipfs://company-registry"
            })
        );
    }

    function test_OfficeBudgetApproval_RevertsBecauseBudgetsRequireReferendum() public {
        vm.prank(MINISTER_OF_FINANCE);
        vm.expectRevert(
            abi.encodeWithSelector(IOfficeExecutor.BudgetApprovalRequiresReferendum.selector, OPERATIONS_BUDGET_ID)
        );
        officeExecutor.requestBudgetApproval(
            FINANCE_OFFICE_ID,
            OPERATIONS_BUDGET_ID,
            TreasuryTypes.DisbursementType.Operations,
            address(usdc),
            8_000 * ONE_USDC,
            uint64(block.timestamp),
            uint64(block.timestamp + 30 days)
        );
    }

    function test_ReferendumBudgetApproval_IsExecutableThroughTimelock() public {
        bytes32 actionId = _queueBudgetApprovalFromReferendum(
            OPERATIONS_BUDGET_ID, TreasuryTypes.DisbursementType.Operations, address(usdc), 8_000 * ONE_USDC
        );

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Queued));
        assertFalse(budgetEnvelopeRegistry.budgetExists(OPERATIONS_BUDGET_ID));

        _warpToActionDeadline(actionId);
        timelock.executeAction(actionId);

        TreasuryTypes.BudgetEnvelope memory budgetEnvelope =
            budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID);
        assertEq(budgetEnvelope.budgetId, OPERATIONS_BUDGET_ID);
        assertEq(budgetEnvelope.officeId, FINANCE_OFFICE_ID);
        assertEq(uint256(budgetEnvelope.disbursementType), uint256(TreasuryTypes.DisbursementType.Operations));
        assertEq(budgetEnvelope.allocatedAmount, 8_000 * ONE_USDC);
        assertEq(budgetEnvelope.spentAmount, 0);
        assertEq(budgetEnvelope.committedAmount, 0);
        assertTrue(budgetEnvelopeRegistry.isBudgetActive(OPERATIONS_BUDGET_ID));
        assertEq(budgetEnvelopeRegistry.availableAmount(OPERATIONS_BUDGET_ID), 8_000 * ONE_USDC);
    }

    function test_SenateCanVetoQueuedBudgetApproval() public {
        bytes32 actionId = _queueBudgetApprovalFromReferendum(
            VETO_BUDGET_ID, TreasuryTypes.DisbursementType.Operations, address(usdc), 4_000 * ONE_USDC
        );

        vm.prank(SENATOR_ONE);
        senateApp.supportActionCancellation(actionId, 0);
        vm.prank(SENATOR_TWO);
        senateApp.supportActionCancellation(actionId, 1);

        _finalizeActionCancellationAtDeadline(actionId);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));
        assertFalse(budgetEnvelopeRegistry.budgetExists(VETO_BUDGET_ID));
    }

    function test_FinanceClerkCanRouteAndExecutePayoutAgainstApprovedBudget() public {
        vm.prank(MINISTER_OF_FINANCE);
        officeExecutor.assignClerk(FINANCE_OFFICE_ID, FINANCE_CLERK);

        _approveBudget(OPERATIONS_BUDGET_ID, 10_000 * ONE_USDC);

        vm.prank(FINANCE_CLERK);
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID,
            TreasuryTypes.DisbursementRequestInput({
                requestId: PAYOUT_REQUEST_ID,
                budgetId: OPERATIONS_BUDGET_ID,
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(usdc),
                recipient: TREASURY_RECIPIENT,
                amount: 1_000 * ONE_USDC,
                policyReference: bytes32(0),
                noteHash: keccak256("ops-payout"),
                noteURI: "ipfs://ops-payout"
            })
        );

        TreasuryTypes.DisbursementRequest memory request = payoutQueue.getDisbursementRequest(PAYOUT_REQUEST_ID);
        assertEq(uint256(request.state), uint256(TreasuryTypes.DisbursementState.Proposed));
        assertEq(request.amount, 1_000 * ONE_USDC);

        vm.warp(request.routeAfter);

        vm.prank(FINANCE_CLERK);
        bytes32 actionId = officeExecutor.routePayout(FINANCE_OFFICE_ID, PAYOUT_REQUEST_ID);

        request = payoutQueue.getDisbursementRequest(PAYOUT_REQUEST_ID);
        assertEq(uint256(request.state), uint256(TreasuryTypes.DisbursementState.Queued));
        assertEq(request.actionId, actionId);

        TreasuryTypes.BudgetEnvelope memory budgetEnvelope =
            budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID);
        assertEq(budgetEnvelope.committedAmount, 1_000 * ONE_USDC);
        assertEq(budgetEnvelope.spentAmount, 0);

        vm.warp(block.timestamp + 2 days);
        timelock.executeAction(actionId);
        payoutQueue.syncPayoutState(PAYOUT_REQUEST_ID);

        request = payoutQueue.getDisbursementRequest(PAYOUT_REQUEST_ID);
        budgetEnvelope = budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID);

        assertEq(uint256(request.state), uint256(TreasuryTypes.DisbursementState.Executed));
        assertEq(usdc.balanceOf(address(treasuryVault)), 9_000 * ONE_USDC);
        assertEq(usdc.balanceOf(TREASURY_RECIPIENT), 1_000 * ONE_USDC);
        assertEq(budgetEnvelope.committedAmount, 0);
        assertEq(budgetEnvelope.spentAmount, 1_000 * ONE_USDC);
        assertEq(budgetEnvelopeRegistry.availableAmount(OPERATIONS_BUDGET_ID), 9_000 * ONE_USDC);
    }

    function test_ExecutedPayoutCanSyncAfterTreasuryVaultReplacement() public {
        vm.prank(MINISTER_OF_FINANCE);
        officeExecutor.assignClerk(FINANCE_OFFICE_ID, FINANCE_CLERK);

        _approveBudget(OPERATIONS_BUDGET_ID, 10_000 * ONE_USDC);

        vm.prank(FINANCE_CLERK);
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID,
            TreasuryTypes.DisbursementRequestInput({
                requestId: PAYOUT_REQUEST_ID,
                budgetId: OPERATIONS_BUDGET_ID,
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(usdc),
                recipient: TREASURY_RECIPIENT,
                amount: 1_000 * ONE_USDC,
                policyReference: bytes32(0),
                noteHash: keccak256("vault-replacement"),
                noteURI: "ipfs://vault-replacement"
            })
        );

        TreasuryTypes.DisbursementRequest memory request = payoutQueue.getDisbursementRequest(PAYOUT_REQUEST_ID);
        vm.warp(request.routeAfter);

        vm.prank(FINANCE_CLERK);
        bytes32 payoutActionId = officeExecutor.routePayout(FINANCE_OFFICE_ID, PAYOUT_REQUEST_ID);
        _warpToActionDeadline(payoutActionId);
        timelock.executeAction(payoutActionId);

        TreasuryVault replacementVault = new TreasuryVault(address(kernel));
        bytes32 replacementActionId = mockReferendumApp.routeAction(
            GovernanceTypes.ActionRequest({
                actionType: GovernanceTypes.ActionType.ModulePointerUpdate,
                origin: GovernanceTypes.ActionOrigin.Referendum,
                originReference: keccak256("replace.treasury-vault"),
                policyReference: bytes32(0),
                targetModule: KernelModuleIds.TREASURY_VAULT,
                payload: abi.encode(GovernanceTypes.ModuleUpdatePayload({newModuleAddress: address(replacementVault)})),
                requestedExecutionTime: 0,
                expiresAt: 0
            })
        );
        _warpToActionDeadline(replacementActionId);
        timelock.executeAction(replacementActionId);

        assertEq(kernel.getModule(KernelModuleIds.TREASURY_VAULT), address(replacementVault));
        assertTrue(treasuryVault.isDisbursementExecuted(PAYOUT_REQUEST_ID));
        assertFalse(replacementVault.isDisbursementExecuted(PAYOUT_REQUEST_ID));

        payoutQueue.syncPayoutState(PAYOUT_REQUEST_ID);

        TreasuryTypes.BudgetEnvelope memory budgetEnvelope =
            budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID);
        assertEq(
            uint256(payoutQueue.getDisbursementRequest(PAYOUT_REQUEST_ID).state),
            uint256(TreasuryTypes.DisbursementState.Executed)
        );
        assertEq(budgetEnvelope.committedAmount, 0);
        assertEq(budgetEnvelope.spentAmount, 1_000 * ONE_USDC);
    }

    function test_SenateCanVetoQueuedPayoutAndReleaseBudgetCommitment() public {
        vm.prank(MINISTER_OF_FINANCE);
        officeExecutor.assignClerk(FINANCE_OFFICE_ID, FINANCE_CLERK);

        _approveBudget(OPERATIONS_BUDGET_ID, 5_000 * ONE_USDC);

        vm.prank(FINANCE_CLERK);
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID,
            TreasuryTypes.DisbursementRequestInput({
                requestId: VETO_PAYOUT_REQUEST_ID,
                budgetId: OPERATIONS_BUDGET_ID,
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(usdc),
                recipient: TREASURY_RECIPIENT,
                amount: 2_000 * ONE_USDC,
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

        _finalizeActionCancellationAtDeadline(actionId);
        payoutQueue.syncPayoutState(VETO_PAYOUT_REQUEST_ID);

        request = payoutQueue.getDisbursementRequest(VETO_PAYOUT_REQUEST_ID);
        TreasuryTypes.BudgetEnvelope memory budgetEnvelope =
            budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID);

        assertEq(uint256(request.state), uint256(TreasuryTypes.DisbursementState.Vetoed));
        assertEq(budgetEnvelope.committedAmount, 0);
        assertEq(budgetEnvelope.spentAmount, 0);
        assertEq(usdc.balanceOf(TREASURY_RECIPIENT), 0);
        assertEq(usdc.balanceOf(address(treasuryVault)), 10_000 * ONE_USDC);
    }

    function test_FinanceOfficeCanCancelRoutedPayoutAndReleaseBudgetCommitment() public {
        vm.prank(MINISTER_OF_FINANCE);
        officeExecutor.assignClerk(FINANCE_OFFICE_ID, FINANCE_CLERK);

        _approveBudget(OPERATIONS_BUDGET_ID, 5_000 * ONE_USDC);

        vm.prank(FINANCE_CLERK);
        officeExecutor.proposePayout(
            FINANCE_OFFICE_ID,
            TreasuryTypes.DisbursementRequestInput({
                requestId: PAYOUT_REQUEST_ID,
                budgetId: OPERATIONS_BUDGET_ID,
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(usdc),
                recipient: TREASURY_RECIPIENT,
                amount: 1_000 * ONE_USDC,
                policyReference: bytes32(0),
                noteHash: keccak256("office-canceled"),
                noteURI: "ipfs://office-canceled"
            })
        );

        TreasuryTypes.DisbursementRequest memory request = payoutQueue.getDisbursementRequest(PAYOUT_REQUEST_ID);
        vm.warp(request.routeAfter);
        vm.prank(FINANCE_CLERK);
        bytes32 actionId = officeExecutor.routePayout(FINANCE_OFFICE_ID, PAYOUT_REQUEST_ID);

        assertEq(budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID).committedAmount, 1_000 * ONE_USDC);

        vm.prank(FINANCE_CLERK);
        officeExecutor.cancelPayout(FINANCE_OFFICE_ID, PAYOUT_REQUEST_ID);

        assertEq(uint256(timelock.getActionState(actionId)), uint256(GovernanceTypes.ActionState.Canceled));
        assertEq(
            uint256(payoutQueue.getDisbursementRequest(PAYOUT_REQUEST_ID).state),
            uint256(TreasuryTypes.DisbursementState.Canceled)
        );
        assertEq(budgetEnvelopeRegistry.getBudgetEnvelope(OPERATIONS_BUDGET_ID).committedAmount, 0);
        assertEq(usdc.balanceOf(TREASURY_RECIPIENT), 0);
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
                asset: address(usdc),
                recipient: TREASURY_RECIPIENT,
                amount: 1_000 * ONE_USDC,
                policyReference: bytes32(0),
                noteHash: keccak256("identity"),
                noteURI: "ipfs://identity"
            })
        );
    }

    function _deployFoundation() private {
        kernel = new ConstitutionKernel(address(this));
        timelock = new ActionTimelock(address(kernel), _defaultDelayConfig());
        router = new GovernanceRouter(address(kernel), address(this));
        identityAuthority = new MockModule(keccak256("test.treasury.identity-authority"));
        stakeAuthority = new MockModule(keccak256("test.treasury.stake-authority"));

        kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(router));
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(timelock));

        identityRegistry = new IdentityRegistry(address(kernel));
        legislationRegistry = new LegislationRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);

        senateSeatRegistry = new SenateSeatRegistry(address(kernel));
        presidentRegistry = new PresidentRegistry(address(kernel));
        senatePowersPolicy = new SenatePowersPolicy(SENATE_CANCELLATION_THRESHOLD, DISBURSEMENT_SUSPENSION_PERIOD);
        mockReferendumApp = new MockReferendumAppForTreasury(address(router), address(legislationRegistry));
        senateApp = new SenateApp(
            address(identityRegistry),
            address(senateSeatRegistry),
            address(senatePowersPolicy),
            address(presidentRegistry),
            address(router),
            address(timelock),
            address(mockReferendumApp)
        );

        llm = new LLMToken();
        usdc = new MockUSDC();
        treasuryVault = new TreasuryVault(address(kernel));
        budgetEnvelopeRegistry = new BudgetEnvelopeRegistry(address(kernel));
        officeRegistry = new OfficeRegistry(address(kernel));
        officePermissionPolicy = new OfficePermissionPolicy();
        ITreasurySpendingPolicy.AssetSpendingLimit[] memory assetLimits =
            new ITreasurySpendingPolicy.AssetSpendingLimit[](2);
        assetLimits[0] = ITreasurySpendingPolicy.AssetSpendingLimit({
            asset: address(llm), clerkOperationsLimit: 3_000 * ONE_LLM, clerkSalaryLimit: 2_000 * ONE_LLM
        });
        assetLimits[1] = ITreasurySpendingPolicy.AssetSpendingLimit({
            asset: address(usdc),
            clerkOperationsLimit: FINANCE_CLERK_OPERATIONS_LIMIT,
            clerkSalaryLimit: FINANCE_CLERK_SALARY_LIMIT
        });
        treasurySpendingPolicy = new TreasurySpendingPolicy(FINANCE_OFFICE_ID, address(llm), assetLimits);
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
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(stakeAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY, address(legislationRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(stakeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(citizenEligibilityPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY, address(senateApp));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY, address(senateSeatRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.PRESIDENT_REGISTRY, address(presidentRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_POWERS_POLICY, address(senatePowersPolicy));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(senateApp));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_APP, address(mockReferendumApp));
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
        router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, address(this));
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
        officeExecutor.bootstrapCreateOffice(
            COMPANY_REGISTRY_OFFICE_ID,
            OfficeTypes.OfficeKind.CompanyRegistryOffice,
            "Company Registry Office",
            COMPANY_REGISTRY_ADMIN
        );
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

    function _queueBudgetApprovalFromReferendum(
        bytes32 budgetId,
        TreasuryTypes.DisbursementType disbursementType,
        address asset,
        uint256 allocatedAmount
    ) private returns (bytes32 actionId) {
        GovernanceTypes.TreasuryBudgetApprovalPayload memory payload =
            GovernanceTypes.TreasuryBudgetApprovalPayload({
                budgetId: budgetId,
                officeId: FINANCE_OFFICE_ID,
                disbursementType: disbursementType,
                asset: asset,
                allocatedAmount: allocatedAmount,
                startsAt: uint64(block.timestamp),
                endsAt: uint64(block.timestamp + 30 days),
                policyReference: treasurySpendingPolicy.computePolicyReference(
                    FINANCE_OFFICE_ID, OfficeTypes.OfficeRole.Admin, disbursementType, asset, allocatedAmount
                )
            });

        actionId = mockReferendumApp.routeAction(
            GovernanceTypes.ActionRequest({
                actionType: GovernanceTypes.ActionType.TreasuryBudgetApproval,
                origin: GovernanceTypes.ActionOrigin.Referendum,
                originReference: keccak256(abi.encodePacked("budget-law", budgetId)),
                policyReference: payload.policyReference,
                targetModule: KernelModuleIds.BUDGET_ENVELOPE_REGISTRY,
                payload: abi.encode(payload),
                requestedExecutionTime: uint64(block.timestamp + 7 days),
                expiresAt: 0
            })
        );
    }

    function _approveBudget(bytes32 budgetId, uint256 allocatedAmount) private {
        bytes32 actionId = _queueBudgetApprovalFromReferendum(
            budgetId, TreasuryTypes.DisbursementType.Operations, address(usdc), allocatedAmount
        );
        _warpToActionDeadline(actionId);
        timelock.executeAction(actionId);
    }

    function _approveContributionRewardBudget(bytes32 budgetId, uint256 allocatedAmount) private {
        bytes32 actionId = _queueBudgetApprovalFromReferendum(
            budgetId, TreasuryTypes.DisbursementType.ContributionReward, address(llm), allocatedAmount
        );
        _warpToActionDeadline(actionId);
        timelock.executeAction(actionId);
    }

    function _contributionRewardInput(bytes32 requestId, bytes32 noteHash, string memory noteURI)
        private
        view
        returns (TreasuryTypes.DisbursementRequestInput memory input)
    {
        input = TreasuryTypes.DisbursementRequestInput({
            requestId: requestId,
            budgetId: CONTRIBUTION_REWARD_BUDGET_ID,
            officeId: FINANCE_OFFICE_ID,
            disbursementType: TreasuryTypes.DisbursementType.ContributionReward,
            asset: address(llm),
            recipient: TREASURY_RECIPIENT,
            amount: CONTRIBUTION_REWARD_AMOUNT,
            policyReference: bytes32(0),
            noteHash: noteHash,
            noteURI: noteURI
        });
    }

    function _finalizeActionCancellationAtDeadline(bytes32 actionId) private {
        _warpToActionDeadline(actionId);
        senateApp.finalizeActionCancellation(actionId);
    }

    function _warpToActionDeadline(bytes32 actionId) private {
        GovernanceTypes.ActionRecord memory actionRecord = timelock.getAction(actionId);
        vm.warp(actionRecord.earliestExecutionTime);
    }
}
