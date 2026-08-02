// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {TreasuryVault} from "../../contracts/apps/TreasuryVault.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockUSDC} from "../../contracts/mocks/MockUSDC.sol";
import {BudgetEnvelopeRegistry} from "../../contracts/registries/BudgetEnvelopeRegistry.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";

contract TreasuryInvariantHandler is Test {
    uint256 internal constant BUDGET_SLOTS = 8;
    uint256 internal constant REQUEST_SLOTS = 16;

    BudgetEnvelopeRegistry public immutable budgetRegistry;
    TreasuryVault public immutable treasuryVault;
    MockUSDC public immutable asset;
    address public immutable recipient;
    uint256 public immutable maximumAllocation;

    mapping(bytes32 requestId => GovernanceTypes.TreasuryDisbursementPayload payload) private _executedPayloads;
    bool public repeatedDisbursementSucceeded;

    constructor(
        BudgetEnvelopeRegistry budgetRegistry_,
        TreasuryVault treasuryVault_,
        MockUSDC asset_,
        address recipient_,
        uint256 maximumAllocation_
    ) {
        budgetRegistry = budgetRegistry_;
        treasuryVault = treasuryVault_;
        asset = asset_;
        recipient = recipient_;
        maximumAllocation = maximumAllocation_;
    }

    /// @notice Creates a bounded budget in an unused fixture slot.
    function createBudget(uint256 seed, uint96 rawAmount) external {
        bytes32 budgetId = budgetIdFor(seed % BUDGET_SLOTS);
        if (budgetRegistry.budgetExists(budgetId)) {
            return;
        }
        uint256 allocatedAmount = bound(uint256(rawAmount), 1, maximumAllocation);
        TreasuryTypes.BudgetEnvelopeInput memory input = TreasuryTypes.BudgetEnvelopeInput({
            officeId: keccak256("office.finance.invariant"),
            disbursementType: TreasuryTypes.DisbursementType.Operations,
            asset: address(asset),
            allocatedAmount: allocatedAmount,
            startsAt: uint64(block.timestamp),
            endsAt: uint64(block.timestamp + 365 days),
            policyReference: keccak256(abi.encode("invariant.treasury-policy", budgetId))
        });
        try budgetRegistry.recordBudgetApproval(budgetId, input) {} catch {}
    }

    /// @notice Attempts to reserve an exact request commitment against an active fixture budget.
    function reserveBudget(uint256 budgetSeed, uint256 requestSeed, uint96 rawAmount) external {
        bytes32 budgetId = budgetIdFor(budgetSeed % BUDGET_SLOTS);
        if (!budgetRegistry.budgetExists(budgetId) || !budgetRegistry.isBudgetActive(budgetId)) {
            return;
        }
        bytes32 requestId = requestIdFor(requestSeed % REQUEST_SLOTS);
        (,, bool activeCommitment) = budgetRegistry.getBudgetCommitment(requestId);
        if (activeCommitment || treasuryVault.isDisbursementExecuted(requestId)) {
            return;
        }
        uint256 available = budgetRegistry.availableAmount(budgetId);
        if (available == 0) {
            return;
        }
        uint256 amount = bound(uint256(rawAmount), 1, available);
        try budgetRegistry.reserveBudget(requestId, budgetId, amount) {} catch {}
    }

    /// @notice Attempts to release a live request commitment back to its budget.
    function releaseBudget(uint256 requestSeed) external {
        bytes32 requestId = requestIdFor(requestSeed % REQUEST_SLOTS);
        (,, bool activeCommitment) = budgetRegistry.getBudgetCommitment(requestId);
        if (!activeCommitment) {
            return;
        }
        try budgetRegistry.releaseBudget(requestId) {} catch {}
    }

    /// @notice Attempts to execute a committed treasury request exactly once.
    function executeDisbursement(uint256 requestSeed) external {
        bytes32 requestId = requestIdFor(requestSeed % REQUEST_SLOTS);
        (bytes32 budgetId, uint256 amount, bool activeCommitment) = budgetRegistry.getBudgetCommitment(requestId);
        if (!activeCommitment || amount == 0) {
            return;
        }
        GovernanceTypes.TreasuryDisbursementPayload memory payload = GovernanceTypes.TreasuryDisbursementPayload({
            requestId: requestId,
            budgetId: budgetId,
            asset: address(asset),
            recipient: recipient,
            amount: amount,
            noteHash: keccak256(abi.encode("invariant.disbursement", requestId))
        });
        try treasuryVault.executeDisbursement(payload) {
            budgetRegistry.recordDisbursement(requestId);
            _executedPayloads[requestId] = payload;
        } catch {}
    }

    /// @notice Probes replay resistance for a request already observed as executed.
    function replayExecutedDisbursement(uint256 requestSeed) external {
        bytes32 requestId = requestIdFor(requestSeed % REQUEST_SLOTS);
        GovernanceTypes.TreasuryDisbursementPayload memory payload = _executedPayloads[requestId];
        if (payload.requestId == bytes32(0)) {
            return;
        }
        try treasuryVault.executeDisbursement(payload) {
            repeatedDisbursementSucceeded = true;
        } catch {}
    }

    /// @notice Advances invariant time by a bounded amount.
    function advanceTime(uint64 rawSeconds) external {
        vm.warp(block.timestamp + bound(uint256(rawSeconds), 1, 30 days));
    }

    /// @notice Derives the deterministic budget identifier for a fixture slot.
    function budgetIdFor(uint256 slot) public pure returns (bytes32 budgetId) {
        return keccak256(abi.encode("invariant.budget", slot));
    }

    /// @notice Derives the deterministic request identifier for a fixture slot.
    function requestIdFor(uint256 slot) public pure returns (bytes32 requestId) {
        return keccak256(abi.encode("invariant.request", slot));
    }
}

/// @title TreasuryInvariantTest
/// @notice Stateful coverage for exact commitments, budget conservation, and single treasury execution.
contract TreasuryInvariantTest is Test {
    uint256 internal constant INITIAL_TREASURY_BALANCE = 1_000_000e6;
    uint256 internal constant BUDGET_SLOTS = 8;
    uint256 internal constant REQUEST_SLOTS = 16;
    address internal constant RECIPIENT = address(0xBEEF);

    ConstitutionKernel internal kernel;
    BudgetEnvelopeRegistry internal budgetRegistry;
    TreasuryVault internal treasuryVault;
    MockUSDC internal asset;
    TreasuryInvariantHandler internal handler;

    /// @notice Deploys and funds the treasury accounting invariant fixture.
    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        budgetRegistry = new BudgetEnvelopeRegistry(address(kernel));
        treasuryVault = new TreasuryVault(address(kernel));
        asset = new MockUSDC();
        handler =
            new TreasuryInvariantHandler(budgetRegistry, treasuryVault, asset, RECIPIENT, INITIAL_TREASURY_BALANCE);

        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(handler));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY, address(budgetRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(handler));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, address(handler));
        kernel.bootstrapSetModule(KernelModuleIds.TREASURY_VAULT, address(treasuryVault));
        kernel.disableBootstrapAuthority();

        asset.mint(address(treasuryVault), INITIAL_TREASURY_BALANCE);
        targetContract(address(handler));
    }

    /// @notice Proves treasury tokens are conserved across custody, recipients, and recorded spending.
    function invariant_TreasuryTokensAreConservedAndAccountedAsSpent() public view {
        uint256 totalSpent;
        for (uint256 slot = 0; slot < BUDGET_SLOTS; ++slot) {
            bytes32 budgetId = handler.budgetIdFor(slot);
            if (!budgetRegistry.budgetExists(budgetId)) {
                continue;
            }
            TreasuryTypes.BudgetEnvelope memory envelope = budgetRegistry.getBudgetEnvelope(budgetId);
            assertLe(envelope.spentAmount + envelope.committedAmount, envelope.allocatedAmount);
            totalSpent += envelope.spentAmount;
        }
        assertEq(asset.balanceOf(RECIPIENT), totalSpent);
        assertEq(asset.balanceOf(address(treasuryVault)) + totalSpent, INITIAL_TREASURY_BALANCE);
    }

    /// @notice Proves executed requests clear commitments and cannot produce a second transfer.
    function invariant_ExecutedRequestsHaveNoLiveCommitmentAndCannotReplay() public view {
        assertFalse(handler.repeatedDisbursementSucceeded());
        for (uint256 slot = 0; slot < REQUEST_SLOTS; ++slot) {
            bytes32 requestId = handler.requestIdFor(slot);
            if (treasuryVault.isDisbursementExecuted(requestId)) {
                (,, bool activeCommitment) = budgetRegistry.getBudgetCommitment(requestId);
                assertFalse(activeCommitment);
            }
        }
    }
}
