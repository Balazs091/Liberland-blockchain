// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DeploySepoliaFoundation} from "../../scripts/DeploySepoliaFoundation.s.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {SepoliaMembershipController} from "../../contracts/mocks/SepoliaMembershipController.sol";
import {SepoliaFoundationFixtures} from "../../contracts/mocks/SepoliaFoundationFixtures.sol";
import {MembershipRegistry} from "../../contracts/registries/MembershipRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LiberlandMerit} from "../../contracts/tokens/LiberlandMerit.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MembershipTypes} from "../../contracts/types/MembershipTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

/// @notice Uses the actual five-contract deployment and an independent finite order ledger.
contract SepoliaFoundationJourneyHandler is DeploySepoliaFoundation {
    struct ExpectedOrder {
        MembershipTypes.OrderInput effect;
        MembershipTypes.OrderStatus status;
        uint256 revision;
        bytes32 originalReceipt;
    }

    Deployment private _deployment;
    ExpectedOrder[] private _expected;
    uint256 public successfulWrites;
    bool public unexpectedAuthorization;
    bool public unexpectedValidCallFailure;

    constructor() {
        _deployment = _deployAndSeed(address(this));
        _assertDeployment(_deployment);
    }

    function deployment() external view returns (Deployment memory) {
        return _deployment;
    }

    function create(uint8 personSeed, uint8 maskSeed, uint32 durationSeed, bool indefinite) external {
        if (_expected.length == 12) return;
        MembershipTypes.OrderInput memory effect = MembershipTypes.OrderInput({
            personId: SepoliaFoundationFixtures.personIdAt(personSeed % 3),
            orderId: keccak256(abi.encode("journey-order", _expected.length)),
            restrictedMask: uint16(1 + maskSeed % 31),
            effectiveAt: uint64(block.timestamp),
            expiresAt: indefinite ? 0 : uint64(block.timestamp + 1 + durationSeed % 7 days),
            indefinite: indefinite
        });
        try SepoliaMembershipController(_deployment.membershipController).recordRestriction(effect) returns (
            bytes32 receipt
        ) {
            if (receipt == bytes32(0)) unexpectedValidCallFailure = true;
            _expected.push(ExpectedOrder(effect, MembershipTypes.OrderStatus.Unstayed, 1, receipt));
            ++successfulWrites;
        } catch {
            // Persist unexpected failure; the shared invariant profile permits target-call reverts.
            unexpectedValidCallFailure = true;
        }
    }

    function stay(uint8 seed) external {
        if (_expected.length == 0) return;
        ExpectedOrder storage item = _expected[seed % _expected.length];
        if (item.status != MembershipTypes.OrderStatus.Unstayed) return;
        try SepoliaMembershipController(_deployment.membershipController)
            .stayRestriction(item.effect.personId, item.effect.orderId, item.revision) returns (
            bytes32
        ) {
            item.status = MembershipTypes.OrderStatus.Stayed;
            ++item.revision;
            ++successfulWrites;
        } catch {
            unexpectedValidCallFailure = true;
        }
    }

    function resume(uint8 seed) external {
        if (_expected.length == 0) return;
        ExpectedOrder storage item = _expected[seed % _expected.length];
        if (item.status != MembershipTypes.OrderStatus.Stayed) return;
        if (!item.effect.indefinite && block.timestamp >= item.effect.expiresAt) return;
        try SepoliaMembershipController(_deployment.membershipController)
            .resumeRestriction(item.effect.personId, item.effect.orderId, item.revision) returns (
            bytes32
        ) {
            item.status = MembershipTypes.OrderStatus.Unstayed;
            ++item.revision;
            ++successfulWrites;
        } catch {
            unexpectedValidCallFailure = true;
        }
    }

    function revoke(uint8 seed) external {
        if (_expected.length == 0) return;
        ExpectedOrder storage item = _expected[seed % _expected.length];
        if (item.status == MembershipTypes.OrderStatus.Revoked) return;
        try SepoliaMembershipController(_deployment.membershipController)
            .revokeRestriction(item.effect.personId, item.effect.orderId, item.revision) returns (
            bytes32
        ) {
            item.status = MembershipTypes.OrderStatus.Revoked;
            ++item.revision;
            ++successfulWrites;
        } catch {
            unexpectedValidCallFailure = true;
        }
    }

    function advance(uint32 secondsSeed) external {
        vm.warp(block.timestamp + 1 + secondsSeed % 3 days);
    }

    function probeUnauthorized() external {
        MembershipTypes.OrderInput memory effect = MembershipTypes.OrderInput({
            personId: SepoliaFoundationFixtures.personIdAt(0),
            orderId: keccak256("unauthorized-probe"),
            restrictedMask: 1,
            effectiveAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + 1 days),
            indefinite: false
        });
        vm.prank(address(0xBAD));
        (bool success,) = _deployment.membershipController
            .call(abi.encodeCall(SepoliaMembershipController.recordRestriction, (effect)));
        if (success) unexpectedAuthorization = true;
    }

    function checkIndependentLedger() external view {
        MembershipRegistry membership = MembershipRegistry(_deployment.membershipRegistry);
        require(membership.electorateMutationCount() == successfulWrites, "mutation accounting mismatch");
        require(
            SepoliaMembershipController(_deployment.membershipController).nextReceiptNonce() == successfulWrites,
            "nonce accounting mismatch"
        );
        for (uint256 personIndex; personIndex < 3; ++personIndex) {
            bytes32 personId = SepoliaFoundationFixtures.personIdAt(personIndex);
            uint16 expectedMask;
            uint16 expectedIndefinite;
            uint64[5] memory expectedUntil;
            uint256 expectedPersonRevision;
            for (uint256 i; i < _expected.length; ++i) {
                ExpectedOrder storage item = _expected[i];
                if (item.effect.personId != personId) continue;
                expectedPersonRevision += item.revision;
                MembershipTypes.RestrictionOrder memory stored = membership.orderOf(personId, item.effect.orderId);
                require(stored.status == item.status && stored.revision == item.revision, "order history mismatch");
                require(stored.sourceReceiptId == item.originalReceipt, "original provenance changed");
                if (item.status != MembershipTypes.OrderStatus.Unstayed) continue;
                if (!item.effect.indefinite && block.timestamp >= item.effect.expiresAt) continue;
                expectedMask |= item.effect.restrictedMask;
                for (uint8 right; right < 5; ++right) {
                    uint16 bit = uint16(1) << right;
                    if ((item.effect.restrictedMask & bit) == 0) continue;
                    if (item.effect.indefinite) expectedIndefinite |= bit;
                    else if (item.effect.expiresAt > expectedUntil[right]) expectedUntil[right] = item.effect.expiresAt;
                }
            }
            MembershipTypes.RightsSummary memory summary = membership.rightsNow(personId);
            require(summary.restrictedMask == expectedMask, "independent rights mismatch");
            require(summary.indefiniteMask == expectedIndefinite, "independent indefinite mismatch");
            require(summary.personRevision == expectedPersonRevision, "person revision mismatch");
            for (uint8 right; right < 5; ++right) {
                uint16 bit = uint16(1) << right;
                uint64 finiteEnd = (expectedIndefinite & bit) != 0 ? 0 : expectedUntil[right];
                require(summary.restrictedUntil[right] == finiteEnd, "independent expiry mismatch");
                require(
                    membership.isRestrictedNow(personId, MembershipTypes.Right(right)) == ((expectedMask & bit) != 0),
                    "single-right mismatch"
                );
            }
        }
    }
}

contract SepoliaFoundationInvariantTest is Test {
    SepoliaFoundationJourneyHandler private _handler;

    function setUp() public {
        vm.chainId(11155111);
        vm.warp(1_900_000_000);
        _handler = new SepoliaFoundationJourneyHandler();
        targetContract(address(_handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = _handler.create.selector;
        selectors[1] = _handler.stay.selector;
        selectors[2] = _handler.resume.selector;
        selectors[3] = _handler.revoke.selector;
        selectors[4] = _handler.advance.selector;
        selectors[5] = _handler.probeUnauthorized.selector;
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
    }

    function invariant_RealControllerMatchesIndependentOrderHistory() public view {
        assertFalse(_handler.unexpectedAuthorization());
        assertFalse(_handler.unexpectedValidCallFailure());
        _handler.checkIndependentLedger();
        DeploySepoliaFoundation.Deployment memory d = _handler.deployment();
        assertEq(ConstitutionKernel(d.constitutionKernel).bootstrapAuthority(), address(0));
        assertEq(LiberlandMerit(d.llmToken).totalSupply(), 1_000_000e18);
        assertEq(LiberlandMerit(d.llmToken).balanceOf(d.operator), 970_000e18);
    }

    function test_SealedTestEnvironmentHasNoGovernedUpgradeRoute() public {
        DeploySepoliaFoundation.Deployment memory d = _handler.deployment();
        ConstitutionKernel kernel = ConstitutionKernel(d.constitutionKernel);
        vm.prank(d.operator);
        vm.expectRevert();
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_WRITER, address(this));
        vm.prank(d.operator);
        vm.expectRevert();
        kernel.governanceUpdateModule(KernelModuleIds.IDENTITY_WRITER, address(this));
        assertEq(kernel.getModule(KernelModuleIds.IDENTITY_WRITER), d.membershipController);
    }

    function test_PredeploymentApiWalletLookupMatchesSyntheticIdentityAndUnknownState() public view {
        DeploySepoliaFoundation.Deployment memory d = _handler.deployment();
        IdentityRegistry identity = IdentityRegistry(d.identityRegistry);
        for (uint256 i; i < 3; ++i) {
            bytes32 personId = SepoliaFoundationFixtures.personIdAt(i);
            address wallet = SepoliaFoundationFixtures.walletAt(i);
            IdentityTypes.IdentityRecord memory byWallet = identity.getWalletIdentityRecord(wallet);
            IdentityTypes.IdentityRecord memory byPerson = identity.getIdentityRecord(personId);
            assertEq(keccak256(abi.encode(byWallet)), keccak256(abi.encode(byPerson)));
            assertEq(identity.resolveWalletToPersonId(wallet), personId);
            assertEq(identity.activeWalletOf(personId), wallet);
        }
        assertEq(identity.getWalletIdentityRecord(address(0xBAD)).personId, bytes32(0));
    }

    function test_FiniteRestrictionExpiresButIndefiniteNeedsOperatorRelief() public {
        _handler.create(0, 0, 1, false);
        _handler.create(1, 0, 1, true);
        DeploySepoliaFoundation.Deployment memory d = _handler.deployment();
        MembershipRegistry membership = MembershipRegistry(d.membershipRegistry);
        vm.warp(block.timestamp + 10 * 365 days);
        assertFalse(
            membership.isRestrictedNow(SepoliaFoundationFixtures.personIdAt(0), MembershipTypes.Right.Political)
        );
        assertTrue(membership.isRestrictedNow(SepoliaFoundationFixtures.personIdAt(1), MembershipTypes.Right.Political));
        _handler.revoke(1);
        assertFalse(
            membership.isRestrictedNow(SepoliaFoundationFixtures.personIdAt(1), MembershipTypes.Right.Political)
        );
        _handler.checkIndependentLedger();
    }

    function test_PoliticalRestrictionDoesNotFreezeERC20TransferOrAllowance() public {
        _handler.create(0, 0, 1, true);
        DeploySepoliaFoundation.Deployment memory d = _handler.deployment();
        LiberlandMerit token = LiberlandMerit(d.llmToken);
        address wallet = SepoliaFoundationFixtures.walletAt(0);
        address spender = address(0xA11CE);
        // Models a valid transaction from that address; public dummy fixtures do not supply signing keys.
        vm.prank(wallet);
        token.approve(spender, 100e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(wallet, address(0xB0B), 100e18));
        assertEq(token.balanceOf(wallet), 9_900e18);
        assertEq(token.balanceOf(address(0xB0B)), 100e18);
        assertTrue(
            MembershipRegistry(d.membershipRegistry)
                .isRestrictedNow(SepoliaFoundationFixtures.personIdAt(0), MembershipTypes.Right.Political)
        );
    }
}
