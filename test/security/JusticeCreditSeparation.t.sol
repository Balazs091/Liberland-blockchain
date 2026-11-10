// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {LlmBackedUSDCFixture} from "../apps/LlmBackedUSDC.t.sol";
import {IUSDCLendingPoolApp} from "../../contracts/interfaces/IUSDCLendingPoolApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {CandidateEligibilityPolicy} from "../../contracts/policies/CandidateEligibilityPolicy.sol";
import {JusticeCitizenEligibilityPolicy} from "../../contracts/policies/JusticeCitizenEligibilityPolicy.sol";
import {MembershipRegistry} from "../../contracts/registries/MembershipRegistry.sol";
import {MembershipTypes} from "../../contracts/types/MembershipTypes.sol";

/// @dev Deliberately implements only the earlier policy API, as older mock/custom policies do.
contract JusticeLegacyPolicyStub {
    uint256 public immutable minimumCitizenStake;
    bool private immutable _eligible;

    constructor(uint256 minimum, bool eligible) {
        minimumCitizenStake = minimum;
        _eligible = eligible;
    }

    function isCitizenInGoodStanding(address) external view returns (bool) {
        return _eligible;
    }
}

contract JusticeCreditSeparationTest is LlmBackedUSDCFixture {
    MembershipRegistry private membership;
    JusticeCitizenEligibilityPolicy private justicePolicy;

    function setUp() public override {
        super.setUp();
        vm.warp(1_000_000);
        membership = new MembershipRegistry(address(kernel), address(identityRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.MEMBERSHIP_REGISTRY, address(membership));
        kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_APP, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_WRITER, address(this));
        justicePolicy = new JusticeCitizenEligibilityPolicy(
            address(identityRegistry), address(stakeRegistry), MINIMUM_RETAINED_STAKE, address(membership)
        );
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(justicePolicy));
    }

    function testBorrowAndQuoteIgnorePoliticalOrderButKeepCollateralBound() public {
        uint256 quote = lendingPool.maxBorrowable(BORROWER_PERSON_ID);
        membership.recordOrder(
            MembershipTypes.OrderInput(
                BORROWER_PERSON_ID,
                bytes32(uint256(1)),
                1,
                uint64(block.timestamp),
                uint64(block.timestamp + 100),
                false
            ),
            keccak256("receipt")
        );
        assertFalse(justicePolicy.isCitizenInGoodStanding(BORROWER));
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), quote);
        vm.prank(BORROWER);
        lendingPool.borrow(quote);
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 0);
        assertEq(usdc.balanceOf(BORROWER), quote);
    }

    function testFullMembershipRemovalDoesNotSeizeFinancialAccess() public {
        uint256 quote = lendingPool.maxBorrowable(BORROWER_PERSON_ID);
        membership.setMembershipRemoved(BORROWER_PERSON_ID, true, 0, keccak256("receipt"));
        assertFalse(justicePolicy.isCitizenInGoodStanding(BORROWER));
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), quote);
        vm.prank(BORROWER);
        lendingPool.borrow(100 * USDC_UNIT);
        vm.startPrank(BORROWER);
        usdc.approve(address(lendingPool), 100 * USDC_UNIT);
        lendingPool.repay(100 * USDC_UNIT);
        vm.stopPrank();
        assertEq(lendingPool.currentDebtOf(BORROWER_PERSON_ID), 0);
    }

    function testWelfareStillBlocksNewCredit() public {
        vm.prank(address(stakeAuthority));
        stakeRegistry.unstake(BORROWER_PERSON_ID);
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 0);
        vm.expectRevert(abi.encodeWithSelector(IUSDCLendingPoolApp.BorrowerNotEligible.selector, BORROWER_PERSON_ID));
        vm.prank(BORROWER);
        lendingPool.borrow(1);
    }

    function testLegacyPolicyWithoutNewMethodsRetainsCreditAndCandidateBehavior() public {
        JusticeLegacyPolicyStub eligible = new JusticeLegacyPolicyStub(MINIMUM_RETAINED_STAKE, true);
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(eligible));
        CandidateEligibilityPolicy candidate = new CandidateEligibilityPolicy(
            address(identityRegistry), address(stakeRegistry), address(eligible), MINIMUM_RETAINED_STAKE
        );
        assertTrue(candidate.isEligibleCandidate(BORROWER));
        assertGt(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 0);
        vm.prank(BORROWER);
        lendingPool.borrow(100 * USDC_UNIT);
        JusticeLegacyPolicyStub ineligible = new JusticeLegacyPolicyStub(MINIMUM_RETAINED_STAKE, false);
        kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(ineligible));
        candidate = new CandidateEligibilityPolicy(
            address(identityRegistry), address(stakeRegistry), address(ineligible), MINIMUM_RETAINED_STAKE
        );
        assertFalse(candidate.isEligibleCandidate(BORROWER));
        assertEq(lendingPool.maxBorrowable(BORROWER_PERSON_ID), 0);
        vm.expectRevert(abi.encodeWithSelector(IUSDCLendingPoolApp.BorrowerNotEligible.selector, BORROWER_PERSON_ID));
        vm.prank(BORROWER);
        lendingPool.borrow(1);
    }
}
