// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {JusticeCompensation} from "../../contracts/registries/JusticeCompensation.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {IJusticeCompensation} from "../../contracts/interfaces/IJusticeCompensation.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";

contract JusticeCompensationTokenFixture is ERC20 {
    bool public fee;
    bool public rejectTransfers;

    constructor() ERC20("Justice LLM fixture", "LLM") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configure(bool fee_, bool reject_) external {
        fee = fee_;
        rejectTransfers = reject_;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            require(!rejectTransfers, "fixture rejected transfer");
            if (fee && amount != 0) {
                super._update(from, address(0), 1);
                --amount;
            }
        }
        super._update(from, to, amount);
    }
}

/// @notice Tests voluntary liquid exposure without giving justice any access to wallets or political stake.
contract JusticeCompensationTest is Test {
    bytes32 private constant ALICE_ID = keccak256("justice.alice");
    bytes32 private constant BOB_ID = keccak256("justice.bob");
    bytes32 private constant LOT = keccak256("justice.lot");
    bytes32 private constant AWARD = keccak256("justice.award");
    bytes32 private constant TERMS = keccak256("justice.explicit.exposure.terms");
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant DONOR = address(0xD010);
    address private constant NEXT_ALICE = address(0xA112);
    address private constant NEXT_BOB = address(0xB0B2);
    uint48 private constant END = 1_000 + 30 days;

    ConstitutionKernel private kernel;
    IdentityRegistry private identity;
    JusticeCompensation private escrow;
    JusticeCompensationTokenFixture private token;
    MockModule private justice;

    function setUp() public {
        vm.warp(1_000);
        vm.roll(100);
        kernel = new ConstitutionKernel(address(this));
        identity = new IdentityRegistry(address(kernel));
        token = new JusticeCompensationTokenFixture();
        justice = new MockModule(keccak256("justice.test.authority"));
        escrow = new JusticeCompensation(address(kernel), address(token), address(identity));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identity));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_COMPENSATION, address(escrow));
        kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_APP, address(justice));
        _person(identity, ALICE_ID, ALICE);
        _person(identity, BOB_ID, BOB);
        token.mint(ALICE, 1_000 ether);
        token.mint(DONOR, 1_000 ether);
        vm.prank(ALICE);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(DONOR);
        token.approve(address(escrow), type(uint256).max);
    }

    function test_DepositRecordsExactOwnerConsentAndCannotBeToppedUpOrReused() public {
        _deposit(100 ether);
        IJusticeCompensation.ExposureLot memory lot = escrow.getLot(LOT);
        assertEq(lot.personId, ALICE_ID);
        assertEq(lot.termsHash, TERMS);
        assertEq(lot.depositedAmount, 100 ether);
        assertEq(lot.remainingAmount, 100 ether);
        assertEq(lot.depositedBlock, 100);
        assertEq(lot.exposureEndsAt, END);
        assertEq(escrow.totalLiabilities(), 100 ether);
        assertEq(token.balanceOf(address(escrow)), 100 ether);
        vm.prank(ALICE);
        vm.expectPartialRevert(IJusticeCompensation.InvalidLot.selector);
        escrow.deposit(LOT, 1 ether, TERMS, END);
        vm.warp(END);
        vm.prank(ALICE);
        escrow.refund(LOT);
        vm.prank(ALICE);
        vm.expectPartialRevert(IJusticeCompensation.InvalidLot.selector);
        escrow.deposit(LOT, 1 ether, TERMS, END + 1 days);
        assertEq(escrow.getLot(LOT).depositedAmount, 100 ether);
        assertEq(escrow.getLot(LOT).remainingAmount, 0);
    }

    function test_AllowanceAndDirectDonationDoNotCreateExposureForAnotherPerson() public {
        // Alice's standing token allowance does not let Bob take or expose Alice's tokens.
        vm.startPrank(BOB);
        token.approve(address(escrow), type(uint256).max);
        vm.expectRevert();
        escrow.deposit(LOT, 100 ether, TERMS, END);
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), 1_000 ether);
        assertEq(escrow.getLot(LOT).personId, bytes32(0));
        vm.prank(ALICE);
        token.transfer(address(escrow), 100 ether);
        vm.roll(101);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InvalidLot.selector);
        escrow.award(AWARD, LOT, ALICE_ID, BOB_ID, 100 ether, 100, TERMS);
        assertEq(escrow.totalLiabilities(), 0);
    }

    function test_OnlyCurrentJusticeMayApplyExactAward() public {
        _deposit(100 ether);
        vm.roll(101);
        vm.prank(BOB);
        vm.expectPartialRevert(IJusticeCompensation.UnauthorizedJusticeCaller.selector);
        escrow.award(AWARD, LOT, ALICE_ID, BOB_ID, 50 ether, 100, TERMS);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.TermsMismatch.selector);
        escrow.award(AWARD, LOT, ALICE_ID, BOB_ID, 50 ether, 100, keccak256("other terms"));
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InvalidLot.selector);
        escrow.award(AWARD, LOT, BOB_ID, ALICE_ID, 50 ether, 100, TERMS);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InvalidAwardParties.selector);
        escrow.award(AWARD, LOT, ALICE_ID, ALICE_ID, 50 ether, 100, TERMS);
        MockModule replacement = new MockModule(keccak256("justice.replacement"));
        kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_APP, address(replacement));
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.UnauthorizedJusticeCaller.selector);
        escrow.award(AWARD, LOT, ALICE_ID, BOB_ID, 50 ether, 100, TERMS);
        vm.prank(address(replacement));
        escrow.award(AWARD, LOT, ALICE_ID, BOB_ID, 50 ether, 100, TERMS);
        assertEq(escrow.claimableOf(BOB_ID), 50 ether);
    }

    function test_CutoffMustBeCompletedAndCannotReachLaterDeposits() public {
        _deposit(100 ether);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InvalidCutoff.selector);
        escrow.award(AWARD, LOT, ALICE_ID, BOB_ID, 100 ether, 100, TERMS);
        vm.roll(101);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InvalidCutoff.selector);
        escrow.award(AWARD, LOT, ALICE_ID, BOB_ID, 100 ether, 99, TERMS);
        _award(AWARD, 100 ether);
        vm.prank(ALICE);
        escrow.deposit(keccak256("later lot"), 100 ether, TERMS, END);
        vm.roll(102);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InvalidCutoff.selector);
        escrow.award(keccak256("later award"), keccak256("later lot"), ALICE_ID, BOB_ID, 100 ether, 100, TERMS);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InsufficientLotBalance.selector);
        escrow.award(keccak256("old cohort exhausted"), LOT, ALICE_ID, BOB_ID, 1, 100, TERMS);
        assertEq(escrow.getLot(keccak256("later lot")).remainingAmount, 100 ether);
    }

    function test_AwardsConsumeOnlyAvailableFundsAndCannotReplay() public {
        _deposit(100 ether);
        vm.roll(101);
        _award(AWARD, 60 ether);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InvalidAward.selector);
        escrow.award(AWARD, LOT, ALICE_ID, BOB_ID, 1, 100, TERMS);
        bytes32 second = keccak256("second award");
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InsufficientLotBalance.selector);
        escrow.award(second, LOT, ALICE_ID, BOB_ID, 41 ether, 100, TERMS);
        assertEq(escrow.getAward(second).lotId, bytes32(0));
        assertEq(escrow.getLot(LOT).remainingAmount, 40 ether);
        _award(second, 40 ether);
        assertEq(escrow.claimableOf(BOB_ID), 100 ether);
        assertEq(escrow.totalLiabilities(), 100 ether);
    }

    function test_ExpiryRejectsNewAwardsAndRefundsOnlyUnawardedResidual() public {
        _deposit(100 ether);
        vm.roll(101);
        _award(AWARD, 60 ether);
        vm.prank(ALICE);
        vm.expectPartialRevert(IJusticeCompensation.ExposureNotEnded.selector);
        escrow.refund(LOT);
        vm.warp(END);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.ExposureEnded.selector);
        escrow.award(keccak256("expired award"), LOT, ALICE_ID, BOB_ID, 40 ether, 100, TERMS);
        vm.prank(BOB);
        vm.expectPartialRevert(IJusticeCompensation.InvalidLot.selector);
        escrow.refund(LOT);
        vm.prank(ALICE);
        escrow.refund(LOT);
        assertEq(token.balanceOf(ALICE), 940 ether);
        assertEq(escrow.claimableOf(BOB_ID), 60 ether);
        vm.prank(BOB);
        escrow.claim();
        assertEq(token.balanceOf(BOB), 60 ether);
        assertEq(escrow.totalLiabilities(), 0);
        vm.prank(BOB);
        vm.expectPartialRevert(IJusticeCompensation.InvalidAmount.selector);
        escrow.claim();
    }

    function test_ClaimsAndRefundsFollowWalletMigrationDespitePoliticalStatus() public {
        _deposit(100 ether);
        vm.roll(101);
        _award(AWARD, 60 ether);
        identity.setWalletLink(BOB_ID, BOB, IdentityTypes.WalletLinkStatus.Revoked);
        identity.setWalletLink(BOB_ID, NEXT_BOB, IdentityTypes.WalletLinkStatus.Active);
        identity.setWalletLink(ALICE_ID, ALICE, IdentityTypes.WalletLinkStatus.Revoked);
        identity.setWalletLink(ALICE_ID, NEXT_ALICE, IdentityTypes.WalletLinkStatus.Active);
        IdentityTypes.IdentityRecordInput memory input = _identityInput();
        input.citizenshipStatus = IdentityTypes.CitizenshipStatus.Revoked;
        input.finalSuspension = true;
        identity.setIdentityRecord(BOB_ID, input);
        vm.prank(BOB);
        vm.expectPartialRevert(IJusticeCompensation.UnauthorizedWallet.selector);
        escrow.claim();
        vm.prank(NEXT_BOB);
        escrow.claim();
        vm.warp(END);
        vm.prank(ALICE);
        vm.expectPartialRevert(IJusticeCompensation.UnauthorizedWallet.selector);
        escrow.refund(LOT);
        vm.prank(NEXT_ALICE);
        escrow.refund(LOT);
        assertEq(token.balanceOf(NEXT_BOB), 60 ether);
        assertEq(token.balanceOf(NEXT_ALICE), 40 ether);
        assertEq(escrow.totalLiabilities(), 0);
    }

    function test_RetirementBlocksNewLiabilityButPreservesExistingPullExits() public {
        _deposit(100 ether);
        vm.roll(101);
        _award(AWARD, 60 ether);
        JusticeCompensation successor = new JusticeCompensation(address(kernel), address(token), address(identity));
        kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_COMPENSATION, address(successor));
        vm.prank(ALICE);
        vm.expectRevert(IJusticeCompensation.InactiveCompensation.selector);
        escrow.deposit(keccak256("retired deposit"), 1 ether, TERMS, END);
        vm.prank(DONOR);
        vm.expectRevert(IJusticeCompensation.InactiveCompensation.selector);
        escrow.fundRestoration(AWARD, 1 ether);
        vm.prank(address(justice));
        vm.expectRevert(IJusticeCompensation.InactiveCompensation.selector);
        escrow.award(keccak256("retired award"), LOT, ALICE_ID, BOB_ID, 1 ether, 100, TERMS);
        vm.prank(BOB);
        escrow.claim();
        vm.warp(END);
        vm.prank(ALICE);
        escrow.refund(LOT);
        assertEq(escrow.totalLiabilities(), 0);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_IdentityRegistryReplacementCannotReviveOldWalletForExits() public {
        _deposit(100 ether);
        vm.roll(101);
        _award(AWARD, 60 ether);
        IdentityRegistry successor = new IdentityRegistry(address(kernel));
        _person(successor, ALICE_ID, NEXT_ALICE);
        _person(successor, BOB_ID, NEXT_BOB);
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(successor));
        vm.prank(address(justice));
        vm.expectRevert(IJusticeCompensation.InactiveCompensation.selector);
        escrow.award(keccak256("stale identity"), LOT, ALICE_ID, BOB_ID, 1 ether, 100, TERMS);
        vm.prank(BOB);
        vm.expectPartialRevert(IJusticeCompensation.UnauthorizedWallet.selector);
        escrow.claim();
        vm.prank(NEXT_BOB);
        escrow.claim();
        vm.warp(END);
        vm.prank(NEXT_ALICE);
        escrow.refund(LOT);
        assertEq(escrow.totalLiabilities(), 0);
    }

    function test_RestorationNeedsSeparateFundsAndNeverRecoversBeneficiaryAssets() public {
        _deposit(100 ether);
        vm.roll(101);
        _award(AWARD, 100 ether);
        vm.prank(BOB);
        escrow.claim();
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InsufficientRestorationFunding.selector);
        escrow.restore(AWARD, 100 ether);
        vm.prank(DONOR);
        escrow.fundRestoration(AWARD, 60 ether);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InsufficientRestorationFunding.selector);
        escrow.restore(AWARD, 61 ether);
        vm.prank(BOB);
        vm.expectPartialRevert(IJusticeCompensation.UnauthorizedJusticeCaller.selector);
        escrow.restore(AWARD, 60 ether);
        vm.prank(address(justice));
        escrow.restore(AWARD, 20 ether);
        vm.prank(address(justice));
        escrow.restore(AWARD, 40 ether);
        assertEq(token.balanceOf(BOB), 100 ether);
        assertEq(escrow.claimableOf(ALICE_ID), 60 ether);
        vm.prank(DONOR);
        vm.expectPartialRevert(IJusticeCompensation.InvalidAmount.selector);
        escrow.fundRestoration(AWARD, 41 ether);
        vm.prank(DONOR);
        escrow.fundRestoration(AWARD, 40 ether);
        vm.prank(DONOR);
        vm.expectPartialRevert(IJusticeCompensation.InvalidAmount.selector);
        escrow.fundRestoration(AWARD, 1);
        vm.prank(address(justice));
        escrow.restore(AWARD, 40 ether);
        vm.prank(ALICE);
        escrow.claim();
        assertEq(token.balanceOf(ALICE), 1_000 ether);
        assertEq(token.balanceOf(BOB), 100 ether);
        assertEq(escrow.getAward(AWARD).restoredAmount, 100 ether);
        assertEq(escrow.totalLiabilities(), 0);
        vm.prank(address(justice));
        vm.expectPartialRevert(IJusticeCompensation.InsufficientRestorationFunding.selector);
        escrow.restore(AWARD, 1);
    }

    function test_InexactReceiptAndFailedPayoutRollBackAllAccounting() public {
        token.configure(true, false);
        vm.prank(ALICE);
        vm.expectPartialRevert(IJusticeCompensation.UnexpectedTokenAmount.selector);
        escrow.deposit(LOT, 100 ether, TERMS, END);
        assertEq(escrow.totalLiabilities(), 0);
        assertEq(token.balanceOf(ALICE), 1_000 ether);
        token.configure(false, false);
        _deposit(100 ether);
        vm.roll(101);
        _award(AWARD, 100 ether);
        token.configure(true, false);
        vm.prank(DONOR);
        vm.expectPartialRevert(IJusticeCompensation.UnexpectedTokenAmount.selector);
        escrow.fundRestoration(AWARD, 10 ether);
        assertEq(escrow.getAward(AWARD).restorationFunding, 0);
        vm.prank(BOB);
        vm.expectPartialRevert(IJusticeCompensation.UnexpectedTokenAmount.selector);
        escrow.claim();
        assertEq(escrow.claimableOf(BOB_ID), 100 ether);
        assertEq(escrow.totalLiabilities(), 100 ether);
        token.configure(false, true);
        vm.prank(BOB);
        vm.expectRevert("fixture rejected transfer");
        escrow.claim();
        token.configure(false, false);
        vm.prank(BOB);
        escrow.claim();
        assertEq(escrow.totalLiabilities(), 0);
    }

    function testFuzz_LotAwardRestorationAndRefundConserveLiquidAssets(
        uint128 depositRaw,
        uint128 awardRaw,
        uint128 restoreRaw
    ) public {
        uint128 depositAmount = uint128(bound(depositRaw, 1, 1_000 ether));
        uint128 awardAmount = uint128(bound(awardRaw, 1, depositAmount));
        uint128 restored = uint128(bound(restoreRaw, 1, awardAmount));
        _deposit(depositAmount);
        vm.roll(101);
        _award(AWARD, awardAmount);
        vm.prank(DONOR);
        escrow.fundRestoration(AWARD, restored);
        vm.prank(address(justice));
        escrow.restore(AWARD, restored);
        assertEq(escrow.totalLiabilities(), uint256(depositAmount) + restored);
        assertEq(token.balanceOf(address(escrow)), escrow.totalLiabilities());
        vm.prank(BOB);
        escrow.claim();
        vm.prank(ALICE);
        escrow.claim();
        vm.warp(END);
        if (depositAmount > awardAmount) {
            vm.prank(ALICE);
            escrow.refund(LOT);
        }
        assertEq(escrow.totalLiabilities(), 0);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.balanceOf(ALICE), 1_000 ether - awardAmount + restored);
        assertEq(token.balanceOf(BOB), awardAmount);
        assertEq(token.balanceOf(DONOR), 1_000 ether - restored);
        assertEq(token.totalSupply(), token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(DONOR));
    }

    function _deposit(uint128 amount) private {
        vm.prank(ALICE);
        escrow.deposit(LOT, amount, TERMS, END);
    }

    function _award(bytes32 awardId, uint128 amount) private {
        vm.prank(address(justice));
        escrow.award(awardId, LOT, ALICE_ID, BOB_ID, amount, 100, TERMS);
    }

    function _person(IdentityRegistry registry, bytes32 personId, address wallet) private {
        registry.setIdentityRecord(personId, _identityInput());
        registry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
    }

    function _identityInput() private pure returns (IdentityTypes.IdentityRecordInput memory) {
        return IdentityTypes.IdentityRecordInput({
            metadataHash: keccak256("synthetic justice identity"),
            metadataURI: "",
            verificationStatus: IdentityTypes.VerificationStatus.Verified,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
            ageClass: IdentityTypes.AgeClass.Adult,
            correctionFlag: false,
            finalSuspension: false
        });
    }
}
