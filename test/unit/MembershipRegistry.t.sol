// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IMembershipRegistry} from "../../contracts/interfaces/IMembershipRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {MembershipRegistry} from "../../contracts/registries/MembershipRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {MembershipTypes} from "../../contracts/types/MembershipTypes.sol";

contract MembershipAuthorityActor {}

contract MembershipRegistryTest is Test {
    ConstitutionKernel private _kernel;
    IdentityRegistry private _identity;
    MembershipRegistry private _membership;
    address private _writer;

    bytes32 private constant _PERSON = keccak256("person");
    bytes32 private constant _OTHER_PERSON = keccak256("other-person");
    bytes32 private constant _RECEIPT = keccak256("exact-authenticated-effect");
    uint16 private constant _POLITICAL = 1;
    uint16 private constant _COMMUNITY = 2;
    uint16 private constant _APPOINTIVE = 4;
    uint16 private constant _REPRESENTATION = 8;
    uint16 private constant _APPOINTMENT_ELIGIBILITY = 16;

    function setUp() public {
        vm.warp(1_000_000);
        _kernel = new ConstitutionKernel(address(this));
        _identity = new IdentityRegistry(address(_kernel));
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        _knownPerson(_PERSON, IdentityTypes.CitizenshipStatus.Citizen);
        _knownPerson(_OTHER_PERSON, IdentityTypes.CitizenshipStatus.None);
        _membership = new MembershipRegistry(address(_kernel), address(_identity));
        _writer = address(new MembershipAuthorityActor());
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_WRITER, _writer);
    }

    function testConstructorPinsMatchingKernelAndIdentity() public {
        assertEq(_membership.kernel(), address(_kernel));
        assertEq(_membership.identityRegistry(), address(_identity));
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.InvalidIdentityRegistry.selector, address(0)));
        new MembershipRegistry(address(_kernel), address(0));
        address eoa = makeAddr("not-registry");
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.InvalidIdentityRegistry.selector, eoa));
        new MembershipRegistry(address(_kernel), eoa);
        ConstitutionKernel otherKernel = new ConstitutionKernel(address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMembershipRegistry.IdentityRegistryKernelMismatch.selector, address(otherKernel), address(_kernel)
            )
        );
        new MembershipRegistry(address(otherKernel), address(_identity));
    }

    function testEmptyFactsDoNotCreateMembershipOrCitizenship() public view {
        MembershipTypes.RightsSummary memory summary = _membership.rightsNow(keccak256("unknown"));
        assertEq(summary.restrictedMask, 0);
        assertEq(summary.indefiniteMask, 0);
        assertEq(summary.personRevision, 0);
        for (uint8 right; right < 5; ++right) {
            assertEq(summary.restrictedUntil[right], 0);
            assertFalse(_membership.isRestrictedNow(_PERSON, MembershipTypes.Right(right)));
        }
        assertEq(uint8(_membership.orderOf(_PERSON, _id(1)).status), uint8(MembershipTypes.OrderStatus.Unset));
        assertEq(_membership.electorateMutationCount(), 0);
    }

    function testBootstrapAndOfficeHaveNoMembershipWriteBypass() public {
        _kernel.bootstrapSetModule(KernelModuleIds.INITIAL_SETUP_AUTHORITY, address(this));
        _kernel.bootstrapSetModule(KernelModuleIds.OFFICE_EXECUTOR, address(this));
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.UnauthorizedMembershipRegistryCaller.selector, address(this))
        );
        _membership.recordOrder(_input(_PERSON, 1, _POLITICAL, 100), _RECEIPT);
        _record(_input(_PERSON, 1, _POLITICAL, 100));
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.UnauthorizedMembershipRegistryCaller.selector, address(this))
        );
        _membership.stayOrder(_PERSON, _id(1), 1, _RECEIPT);
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.UnauthorizedMembershipRegistryCaller.selector, address(this))
        );
        _membership.revokeOrder(_PERSON, _id(1), 1, _RECEIPT);
        vm.prank(_writer);
        _membership.stayOrder(_PERSON, _id(1), 1, _RECEIPT);
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.UnauthorizedMembershipRegistryCaller.selector, address(this))
        );
        _membership.resumeOrder(_PERSON, _id(1), 2, _RECEIPT);
    }

    function testUnregisteredWriterFailsClosed() public {
        ConstitutionKernel emptyKernel = new ConstitutionKernel(address(this));
        IdentityRegistry identity = new IdentityRegistry(address(emptyKernel));
        MembershipRegistry membership = new MembershipRegistry(address(emptyKernel), address(identity));
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.UnauthorizedMembershipRegistryCaller.selector, address(this))
        );
        membership.recordOrder(_input(_PERSON, 1, _POLITICAL, 100), _RECEIPT);
    }

    function testWriterReplacementImmediatelyRetiresOldAuthority() public {
        address successor = address(new MembershipAuthorityActor());
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_WRITER, successor);
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.UnauthorizedMembershipRegistryCaller.selector, _writer)
        );
        vm.prank(_writer);
        _membership.recordOrder(_input(_PERSON, 1, _POLITICAL, 100), _RECEIPT);
        vm.prank(successor);
        _membership.recordOrder(_input(_PERSON, 1, _POLITICAL, 100), _RECEIPT);
        assertTrue(_membership.isRestrictedNow(_PERSON, MembershipTypes.Right.Political));
    }

    function testRejectsUnknownPersonZeroOrderAndReceiptWithoutMutating() public {
        bytes32 unknown = keccak256("unknown");
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.UnknownPerson.selector, unknown));
        _record(_input(unknown, 1, _POLITICAL, 100));
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.UnknownPerson.selector, bytes32(0)));
        _record(_input(bytes32(0), 1, _POLITICAL, 100));
        vm.expectRevert(IMembershipRegistry.InvalidOrderId.selector);
        _record(_input(_PERSON, 0, _POLITICAL, 100));
        vm.expectRevert(IMembershipRegistry.InvalidReceiptId.selector);
        vm.prank(_writer);
        _membership.recordOrder(_input(_PERSON, 1, _POLITICAL, 100), bytes32(0));
        assertEq(_membership.membershipRevisionOf(_PERSON), 0);
        assertEq(_membership.electorateMutationCount(), 0);
    }

    function testRejectsUnsupportedAndEmptyRightsWithoutPartialIndexing() public {
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.InvalidRestrictedMask.selector, uint16(0)));
        _record(_input(_PERSON, 1, 0, 100));
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.InvalidRestrictedMask.selector, uint16(33)));
        _record(_input(_PERSON, 1, 33, 100));
        assertFalse(_membership.isRestrictedNow(_PERSON, MembershipTypes.Right.Political));
        assertEq(_membership.electorateMutationCount(), 0);
    }

    function testRejectsFutureStartsExpiredOrdersAndAmbiguousIndefinite() public {
        MembershipTypes.OrderInput memory input = _input(_PERSON, 1, _POLITICAL, 100);
        input.effectiveAt = uint64(block.timestamp + 1);
        _expectIntervalRevert(input);
        input.effectiveAt = 0;
        _expectIntervalRevert(input);
        input.effectiveAt = uint64(block.timestamp);
        input.expiresAt = uint64(block.timestamp);
        _expectIntervalRevert(input);
        input.expiresAt = 0;
        _expectIntervalRevert(input);
        input.indefinite = true;
        input.expiresAt = uint64(block.timestamp + 100);
        _expectIntervalRevert(input);
        assertEq(_membership.electorateMutationCount(), 0);
    }

    function testKnownNoncitizenOrderDoesNotChangeCitizenship() public {
        _record(_input(_OTHER_PERSON, 1, _POLITICAL, 100));
        assertTrue(_membership.isRestrictedNow(_OTHER_PERSON, MembershipTypes.Right.Political));
        assertEq(
            uint8(_identity.getIdentityRecord(_OTHER_PERSON).citizenshipStatus),
            uint8(IdentityTypes.CitizenshipStatus.None)
        );
    }

    function testOverlappingOrdersAndSeparateRightsRemainIndependent() public {
        _record(_input(_PERSON, 1, _POLITICAL, 100));
        _record(_input(_PERSON, 2, _POLITICAL, 200));
        _record(_input(_PERSON, 3, _REPRESENTATION, 300));
        MembershipTypes.RightsSummary memory summary = _membership.rightsNow(_PERSON);
        assertEq(summary.restrictedMask, _POLITICAL | _REPRESENTATION);
        assertEq(summary.restrictedUntil[0], block.timestamp + 200);
        assertEq(summary.restrictedUntil[3], block.timestamp + 300);
        vm.prank(_writer);
        _membership.revokeOrder(_PERSON, _id(2), 1, keccak256("revoke-second"));
        summary = _membership.rightsNow(_PERSON);
        assertEq(summary.restrictedUntil[0], block.timestamp + 100);
        assertEq(summary.restrictedUntil[3], block.timestamp + 300);
        vm.warp(block.timestamp + 100);
        assertFalse(_membership.isRestrictedNow(_PERSON, MembershipTypes.Right.Political));
        assertTrue(_membership.isRestrictedNow(_PERSON, MembershipTypes.Right.Representation));
        assertEq(_membership.membershipRevisionOf(_PERSON), 4);
        assertEq(_membership.electorateMutationCount(), 4);
    }

    function testExpiryIsImmediateWithoutKeeperOrCounterMutation() public {
        uint64 expiry = uint64(block.timestamp + 100);
        _record(_input(_PERSON, 1, 31, 100));
        vm.warp(expiry - 1);
        assertEq(_membership.rightsNow(_PERSON).restrictedMask, 31);
        vm.warp(expiry);
        MembershipTypes.RightsSummary memory summary = _membership.rightsNow(_PERSON);
        assertEq(summary.restrictedMask, 0);
        assertEq(summary.indefiniteMask, 0);
        for (uint8 right; right < 5; ++right) {
            assertEq(summary.restrictedUntil[right], 0);
        }
        assertEq(summary.personRevision, 1);
        assertEq(_membership.electorateMutationCount(), 1);
        assertEq(uint8(_membership.orderOf(_PERSON, _id(1)).status), uint8(MembershipTypes.OrderStatus.Unstayed));
    }

    function testIndefiniteSummaryAndReliefRevealFiniteOrder() public {
        MembershipTypes.OrderInput memory input = _input(_PERSON, 1, _POLITICAL | _COMMUNITY, 100);
        input.expiresAt = type(uint64).max;
        _record(input);
        input.orderId = _id(2);
        input.indefinite = true;
        input.expiresAt = 0;
        _record(input);
        MembershipTypes.RightsSummary memory summary = _membership.rightsNow(_PERSON);
        assertEq(summary.indefiniteMask, _POLITICAL | _COMMUNITY);
        assertEq(summary.restrictedUntil[0], 0);
        vm.prank(_writer);
        _membership.stayOrder(_PERSON, _id(2), 1, keccak256("stay"));
        summary = _membership.rightsNow(_PERSON);
        assertEq(summary.indefiniteMask, 0);
        assertEq(summary.restrictedUntil[0], type(uint64).max);
        assertEq(summary.restrictedUntil[1], type(uint64).max);
    }

    function testStayResumePreserveScopeProvenanceAndOriginalClock() public {
        uint64 originalExpiry = uint64(block.timestamp + 100);
        _record(_input(_PERSON, 1, _POLITICAL | _APPOINTIVE | _APPOINTMENT_ELIGIBILITY, 100));
        _record(_input(_PERSON, 2, _COMMUNITY, 200));
        vm.prank(_writer);
        _membership.stayOrder(_PERSON, _id(1), 1, keccak256("stay"));
        assertEq(_membership.rightsNow(_PERSON).restrictedMask, _COMMUNITY);
        vm.warp(block.timestamp + 50);
        vm.prank(_writer);
        _membership.resumeOrder(_PERSON, _id(1), 2, keccak256("resume"));
        MembershipTypes.RestrictionOrder memory order = _membership.orderOf(_PERSON, _id(1));
        assertEq(order.sourceReceiptId, _RECEIPT);
        assertEq(order.expiresAt, originalExpiry);
        assertEq(order.restrictedMask, _POLITICAL | _APPOINTIVE | _APPOINTMENT_ELIGIBILITY);
        assertEq(order.revision, 3);
        assertEq(_membership.rightsNow(_PERSON).restrictedMask, 23);
        vm.warp(originalExpiry);
        assertEq(_membership.rightsNow(_PERSON).restrictedMask, _COMMUNITY);
    }

    function testRevokingStayedOrderIsPermanentAndCannotEraseAnotherOrder() public {
        _record(_input(_PERSON, 1, _POLITICAL, 100));
        _record(_input(_PERSON, 2, _POLITICAL, 200));
        vm.prank(_writer);
        _membership.stayOrder(_PERSON, _id(1), 1, keccak256("stay"));
        vm.prank(_writer);
        _membership.revokeOrder(_PERSON, _id(1), 2, keccak256("revoke"));
        assertEq(_membership.rightsNow(_PERSON).restrictedUntil[0], block.timestamp + 200);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMembershipRegistry.InvalidOrderTransition.selector, MembershipTypes.OrderStatus.Revoked
            )
        );
        vm.prank(_writer);
        _membership.resumeOrder(_PERSON, _id(1), 3, keccak256("resume"));
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.OrderAlreadyRecorded.selector, _PERSON, _id(1)));
        _record(_input(_PERSON, 1, _POLITICAL, 300));
        assertEq(_membership.orderOf(_PERSON, _id(1)).sourceReceiptId, _RECEIPT);
    }

    function testExpiredStayCannotBeLiftedToRestartRestriction() public {
        uint64 expiry = uint64(block.timestamp + 100);
        _record(_input(_PERSON, 1, _POLITICAL, 100));
        vm.prank(_writer);
        _membership.stayOrder(_PERSON, _id(1), 1, keccak256("stay"));
        vm.warp(expiry);
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.OrderExpired.selector, expiry));
        vm.prank(_writer);
        _membership.resumeOrder(_PERSON, _id(1), 2, keccak256("resume"));
        assertEq(_membership.membershipRevisionOf(_PERSON), 2);
        vm.prank(_writer);
        _membership.revokeOrder(_PERSON, _id(1), 2, keccak256("revoke"));
        assertEq(uint8(_membership.orderOf(_PERSON, _id(1)).status), uint8(MembershipTypes.OrderStatus.Revoked));
    }

    function testReliefBindsOrderRevisionAndNotUnrelatedPersonActivity() public {
        _record(_input(_PERSON, 1, _POLITICAL, 100));
        _record(_input(_PERSON, 2, _REPRESENTATION, 200));
        vm.prank(_writer);
        _membership.stayOrder(_PERSON, _id(1), 1, keccak256("stay"));
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.OrderRevisionMismatch.selector, uint256(1), uint256(2))
        );
        vm.prank(_writer);
        _membership.revokeOrder(_PERSON, _id(1), 1, keccak256("stale-revoke"));
        vm.prank(_writer);
        _membership.revokeOrder(_PERSON, _id(2), 1, keccak256("unrelated-revoke"));
        vm.prank(_writer);
        _membership.resumeOrder(_PERSON, _id(1), 2, keccak256("resume"));
        assertEq(_membership.membershipRevisionOf(_PERSON), 5);
        assertEq(_membership.orderOf(_PERSON, _id(1)).revision, 3);
    }

    function testAbsentDuplicateAndInvalidReliefLeaveCountersUnchanged() public {
        _record(_input(_PERSON, 1, _POLITICAL, 100));
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.OrderAlreadyRecorded.selector, _PERSON, _id(1)));
        _record(_input(_PERSON, 1, _COMMUNITY, 100));
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.OrderNotRecorded.selector, _PERSON, _id(2)));
        vm.prank(_writer);
        _membership.stayOrder(_PERSON, _id(2), 0, keccak256("stay"));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMembershipRegistry.InvalidOrderTransition.selector, MembershipTypes.OrderStatus.Unstayed
            )
        );
        vm.prank(_writer);
        _membership.resumeOrder(_PERSON, _id(1), 1, keccak256("resume"));
        vm.expectRevert(IMembershipRegistry.InvalidReceiptId.selector);
        vm.prank(_writer);
        _membership.revokeOrder(_PERSON, _id(1), 1, bytes32(0));
        assertEq(_membership.membershipRevisionOf(_PERSON), 1);
        assertEq(_membership.electorateMutationCount(), 1);
    }

    function testOrderIdentifiersAreScopedToPeople() public {
        _record(_input(_PERSON, 1, _POLITICAL, 100));
        _record(_input(_OTHER_PERSON, 1, _COMMUNITY, 200));
        vm.prank(_writer);
        _membership.revokeOrder(_PERSON, _id(1), 1, keccak256("revoke"));
        assertEq(_membership.rightsNow(_PERSON).restrictedMask, 0);
        assertEq(_membership.rightsNow(_OTHER_PERSON).restrictedMask, _COMMUNITY);
        assertEq(_membership.membershipRevisionOf(_PERSON), 2);
        assertEq(_membership.membershipRevisionOf(_OTHER_PERSON), 1);
        assertEq(_membership.electorateMutationCount(), 3);
    }

    function testWalletReplacementPreservesPersonBoundRestrictions() public {
        address oldWallet = makeAddr("old-wallet");
        address newWallet = makeAddr("new-wallet");
        _identity.setWalletLink(_PERSON, oldWallet, IdentityTypes.WalletLinkStatus.Active);
        _record(_input(_PERSON, 1, _POLITICAL, 100));
        _identity.setWalletLink(_PERSON, oldWallet, IdentityTypes.WalletLinkStatus.Revoked);
        _identity.setWalletLink(_PERSON, newWallet, IdentityTypes.WalletLinkStatus.Active);
        assertEq(_identity.activeWalletOf(_PERSON), newWallet);
        assertTrue(
            _membership.isRestrictedNow(_identity.resolveWalletToPersonId(newWallet), MembershipTypes.Right.Political)
        );
        assertEq(_membership.membershipRevisionOf(_PERSON), 1);
    }

    function testFuzzIndependentScopesMatchScanningOracle(uint256 seed) public {
        uint16[12] memory masks;
        uint64[12] memory expiries;
        bool[12] memory indefinite;
        bool[12] memory included;
        for (uint256 i; i < 12; ++i) {
            uint256 random = uint256(keccak256(abi.encode(seed, i)));
            masks[i] = uint16((random % 31) + 1);
            indefinite[i] = (random >> 8) % 7 == 0;
            expiries[i] = indefinite[i] ? 0 : uint64(block.timestamp + ((random >> 16) % 1_000) + 1);
            included[i] = true;
            MembershipTypes.OrderInput memory input = _input(_PERSON, i + 1, masks[i], 1);
            input.indefinite = indefinite[i];
            input.expiresAt = expiries[i];
            _record(input);
        }
        for (uint256 i; i < 12; ++i) {
            if ((uint256(keccak256(abi.encode(seed, i, "relief"))) & 1) == 0) continue;
            included[i] = false;
            vm.prank(_writer);
            if (i % 2 == 0) _membership.stayOrder(_PERSON, _id(i + 1), 1, keccak256(abi.encode(i, "stay")));
            else _membership.revokeOrder(_PERSON, _id(i + 1), 1, keccak256(abi.encode(i, "revoke")));
        }
        vm.warp(block.timestamp + (seed % 1_001));
        MembershipTypes.RightsSummary memory summary = _membership.rightsNow(_PERSON);
        uint16 expectedMask;
        uint16 expectedIndefinite;
        for (uint8 right; right < 5; ++right) {
            uint16 bit = uint16(1) << right;
            uint64 expectedExpiry;
            for (uint256 i; i < 12; ++i) {
                if (!included[i] || (masks[i] & bit) == 0) continue;
                if (indefinite[i]) expectedIndefinite |= bit;
                else if (expiries[i] > block.timestamp && expiries[i] > expectedExpiry) expectedExpiry = expiries[i];
            }
            if ((expectedIndefinite & bit) != 0 || expectedExpiry != 0) expectedMask |= bit;
            assertEq(summary.restrictedUntil[right], (expectedIndefinite & bit) == 0 ? expectedExpiry : 0);
            assertEq(_membership.isRestrictedNow(_PERSON, MembershipTypes.Right(right)), (expectedMask & bit) != 0);
        }
        assertEq(summary.restrictedMask, expectedMask);
        assertEq(summary.indefiniteMask, expectedIndefinite);
    }

    function _knownPerson(bytes32 personId, IdentityTypes.CitizenshipStatus citizenshipStatus) private {
        _identity.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256(abi.encode(personId)),
                metadataURI: "",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: citizenshipStatus,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
    }

    function _record(MembershipTypes.OrderInput memory input) private {
        vm.prank(_writer);
        _membership.recordOrder(input, _RECEIPT);
    }

    function _input(bytes32 personId, uint256 id, uint16 mask, uint64 duration)
        private
        view
        returns (MembershipTypes.OrderInput memory input)
    {
        input = MembershipTypes.OrderInput({
            personId: personId,
            orderId: _id(id),
            restrictedMask: mask,
            effectiveAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + duration),
            indefinite: false
        });
    }

    function _expectIntervalRevert(MembershipTypes.OrderInput memory input) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IMembershipRegistry.InvalidOrderInterval.selector, input.effectiveAt, input.expiresAt, input.indefinite
            )
        );
        _record(input);
    }

    function _id(uint256 number) private pure returns (bytes32) {
        return bytes32(number);
    }
}
