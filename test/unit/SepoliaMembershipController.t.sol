// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IMembershipRegistry} from "../../contracts/interfaces/IMembershipRegistry.sol";
import {ISepoliaMembershipController} from "../../contracts/interfaces/ISepoliaMembershipController.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {SepoliaFoundationFixtures} from "../../contracts/mocks/SepoliaFoundationFixtures.sol";
import {SepoliaMembershipController} from "../../contracts/mocks/SepoliaMembershipController.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {MembershipRegistry} from "../../contracts/registries/MembershipRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {MembershipTypes} from "../../contracts/types/MembershipTypes.sol";

/// @notice Tests the explicit synthetic controller without installing any production legal workflow.
contract SepoliaMembershipControllerTest is Test {
    ConstitutionKernel private _kernel;
    IdentityRegistry private _identity;
    MembershipRegistry private _membership;
    SepoliaMembershipController private _controller;

    function setUp() public {
        vm.chainId(SepoliaFoundationFixtures.CHAIN_ID);
        vm.warp(1_000_000);
        _kernel = new ConstitutionKernel(address(this));
        _identity = new IdentityRegistry(address(_kernel));
        _membership = new MembershipRegistry(address(_kernel), address(_identity));
        _controller = new SepoliaMembershipController(address(this), address(_identity), address(_membership));
        _register(_controller);
    }

    function testConstructorPinsOperatorAndMatchingDependencies() public view {
        assertEq(_controller.operator(), address(this));
        assertEq(_controller.kernel(), address(_kernel));
        assertEq(_controller.identityRegistry(), address(_identity));
        assertEq(_controller.membershipRegistry(), address(_membership));
        assertFalse(_controller.fixturesSeeded());
        assertEq(_controller.nextReceiptNonce(), 0);
    }

    function testRejectsMainnetConstructionAndCallsAfterChainChange() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.WrongChain.selector, 1));
        new SepoliaMembershipController(address(this), address(_identity), address(_membership));
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.WrongChain.selector, 1));
        _controller.seedSyntheticIdentities();
    }

    function testRejectsInvalidOperatorAndDependencyAddresses() public {
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.InvalidOperator.selector, address(0)));
        new SepoliaMembershipController(address(0), address(_identity), address(_membership));
        vm.expectRevert(
            abi.encodeWithSelector(ISepoliaMembershipController.InvalidIdentityRegistry.selector, address(0))
        );
        new SepoliaMembershipController(address(this), address(0), address(_membership));
        vm.expectRevert(
            abi.encodeWithSelector(ISepoliaMembershipController.InvalidIdentityRegistry.selector, address(0x1234))
        );
        new SepoliaMembershipController(address(this), address(0x1234), address(_membership));
        vm.expectRevert(
            abi.encodeWithSelector(ISepoliaMembershipController.InvalidMembershipRegistry.selector, address(0))
        );
        new SepoliaMembershipController(address(this), address(_identity), address(0));
        vm.expectRevert(
            abi.encodeWithSelector(ISepoliaMembershipController.InvalidMembershipRegistry.selector, address(0x1234))
        );
        new SepoliaMembershipController(address(this), address(_identity), address(0x1234));
    }

    function testRejectsDifferentKernels() public {
        ConstitutionKernel otherKernel = new ConstitutionKernel(address(this));
        IdentityRegistry otherIdentity = new IdentityRegistry(address(otherKernel));
        MembershipRegistry otherMembership = new MembershipRegistry(address(otherKernel), address(otherIdentity));
        vm.expectRevert(
            abi.encodeWithSelector(
                ISepoliaMembershipController.DependencyKernelMismatch.selector, address(_kernel), address(otherKernel)
            )
        );
        new SepoliaMembershipController(address(this), address(_identity), address(otherMembership));
    }

    function testRejectsDifferentIdentityOnSameKernel() public {
        IdentityRegistry otherIdentity = new IdentityRegistry(address(_kernel));
        MembershipRegistry otherMembership = new MembershipRegistry(address(_kernel), address(otherIdentity));
        vm.expectRevert(
            abi.encodeWithSelector(
                ISepoliaMembershipController.MembershipIdentityMismatch.selector,
                address(_identity),
                address(otherIdentity)
            )
        );
        new SepoliaMembershipController(address(this), address(_identity), address(otherMembership));
    }

    function testFixedFixturesAreDistinctAndBoundsChecked() public {
        assertEq(SepoliaFoundationFixtures.PERSON_COUNT, 3);
        assertEq(SepoliaFoundationFixtures.GENESIS_SUPPLY, 1_000_000e18);
        assertEq(SepoliaFoundationFixtures.BALANCE_PER_PERSON, 10_000e18);
        for (uint256 index; index < 3; ++index) {
            bytes32 personId = SepoliaFoundationFixtures.personIdAt(index);
            address wallet = SepoliaFoundationFixtures.walletAt(index);
            assertTrue(personId != bytes32(0));
            assertTrue(wallet != address(0));
            assertTrue(wallet != address(this));
            assertTrue(SepoliaFoundationFixtures.isSyntheticPerson(personId));
            assertTrue(SepoliaFoundationFixtures.metadataHashAt(index) != bytes32(0));
            for (uint256 prior; prior < index; ++prior) {
                assertTrue(personId != SepoliaFoundationFixtures.personIdAt(prior));
                assertTrue(wallet != SepoliaFoundationFixtures.walletAt(prior));
            }
        }
        vm.expectRevert(abi.encodeWithSelector(SepoliaFoundationFixtures.SyntheticIndexOutOfBounds.selector, 3));
        this.fixtureId(3);
    }

    function testSeedCreatesOnlyExplicitSyntheticRecordsAndLinks() public {
        _controller.seedSyntheticIdentities();
        assertTrue(_controller.fixturesSeeded());
        assertEq(_identity.totalIdentityCount(), 3);
        assertEq(_identity.electorateMutationCount(), 6);
        for (uint256 index; index < 3; ++index) {
            bytes32 personId = SepoliaFoundationFixtures.personIdAt(index);
            IdentityTypes.IdentityRecord memory record = _identity.getIdentityRecord(personId);
            assertEq(record.personId, personId);
            assertEq(record.metadataHash, SepoliaFoundationFixtures.metadataHashAt(index));
            assertEq(record.metadataURI, "synthetic://sepolia-foundation-v1/NO_REAL_PERSON");
            assertEq(uint8(record.verificationStatus), uint8(IdentityTypes.VerificationStatus.Verified));
            assertEq(uint8(record.citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.Citizen));
            assertEq(uint8(record.ageClass), uint8(IdentityTypes.AgeClass.Adult));
            assertEq(_identity.activeWalletOf(personId), SepoliaFoundationFixtures.walletAt(index));
        }
    }

    function testSeedCannotRepeatBeforeOrAfterBootstrapRetirement() public {
        _controller.seedSyntheticIdentities();
        vm.expectRevert(ISepoliaMembershipController.FixtureAlreadySeeded.selector);
        _controller.seedSyntheticIdentities();
        _kernel.disableBootstrapAuthority();
        vm.expectRevert(ISepoliaMembershipController.FixtureAlreadySeeded.selector);
        _controller.seedSyntheticIdentities();
        assertEq(_identity.totalIdentityCount(), 3);
        assertEq(_identity.electorateMutationCount(), 6);
    }

    function testUnseededControllerCannotSeedAfterBootstrapRetirement() public {
        _kernel.disableBootstrapAuthority();
        vm.expectRevert(
            abi.encodeWithSelector(ISepoliaMembershipController.FixtureBootstrapInactive.selector, address(0))
        );
        _controller.seedSyntheticIdentities();
        assertFalse(_controller.fixturesSeeded());
        assertEq(_identity.totalIdentityCount(), 0);
    }

    function testSeedingRequiresExactIdentityAuthority() public {
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        vm.expectRevert(
            abi.encodeWithSelector(ISepoliaMembershipController.FixtureAuthorityMismatch.selector, address(this))
        );
        _controller.seedSyntheticIdentities();
        assertFalse(_controller.fixturesSeeded());
        assertEq(_identity.totalIdentityCount(), 0);
    }

    function testPreexistingFixtureCannotBeOverwrittenAndSeedRollsBack() public {
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        bytes32 personId = SepoliaFoundationFixtures.personIdAt(2);
        _identity.setIdentityRecord(personId, _recordInput());
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_controller));
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.FixtureAlreadyExists.selector, personId));
        _controller.seedSyntheticIdentities();
        assertFalse(_controller.fixturesSeeded());
        assertEq(_identity.totalIdentityCount(), 1);
        assertFalse(_identity.identityExists(SepoliaFoundationFixtures.personIdAt(0)));
        assertFalse(_identity.identityExists(SepoliaFoundationFixtures.personIdAt(1)));
        assertEq(_identity.getIdentityRecord(personId).metadataHash, keccak256("preexisting"));
    }

    function testOperatorAloneCanSeedAndInvokeAllRestrictionOperations() public {
        address outsider = address(0xBAD);
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.NotFixtureOperator.selector, outsider));
        vm.prank(outsider);
        _controller.seedSyntheticIdentities();
        _seedAndRetire();
        MembershipTypes.OrderInput memory effect = _input(1, 1, 100);
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.NotFixtureOperator.selector, outsider));
        vm.prank(outsider);
        _controller.recordRestriction(effect);
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.NotFixtureOperator.selector, outsider));
        vm.prank(outsider);
        _controller.stayRestriction(effect.personId, effect.orderId, 1);
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.NotFixtureOperator.selector, outsider));
        vm.prank(outsider);
        _controller.resumeRestriction(effect.personId, effect.orderId, 1);
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.NotFixtureOperator.selector, outsider));
        vm.prank(outsider);
        _controller.revokeRestriction(effect.personId, effect.orderId, 1);
        assertEq(_controller.nextReceiptNonce(), 0);
    }

    function testRestrictionsRequireSeedingAndCannotUseNonFixturePeople() public {
        MembershipTypes.OrderInput memory effect = _input(1, 1, 100);
        vm.expectRevert(ISepoliaMembershipController.FixturesNotSeeded.selector);
        _controller.recordRestriction(effect);
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        bytes32 otherPerson = keccak256("known-but-not-fixture");
        _identity.setIdentityRecord(otherPerson, _recordInput());
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_controller));
        _seedAndRetire();
        effect.personId = otherPerson;
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.NotSyntheticPerson.selector, otherPerson));
        _controller.recordRestriction(effect);
        vm.expectRevert(abi.encodeWithSelector(ISepoliaMembershipController.NotSyntheticPerson.selector, otherPerson));
        _controller.stayRestriction(otherPerson, effect.orderId, 1);
    }

    function testOperatorCannotBypassControllerThroughRegistry() public {
        _seedAndRetire();
        MembershipTypes.OrderInput memory effect = _input(1, 1, 100);
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.UnauthorizedMembershipRegistryCaller.selector, address(this))
        );
        _membership.recordOrder(effect, keccak256("not-authenticated"));
        _controller.recordRestriction(effect);
        assertTrue(_membership.isRestrictedNow(effect.personId, MembershipTypes.Right.Political));
    }

    function testIndependentOrdersStayResumeAndRevokeWithoutErasingEachOther() public {
        _seedAndRetire();
        MembershipTypes.OrderInput memory first = _input(1, 1, 100);
        MembershipTypes.OrderInput memory second = _input(2, 3, 200);
        _controller.recordRestriction(first);
        _controller.recordRestriction(second);
        assertEq(_membership.rightsNow(first.personId).restrictedUntil[0], second.expiresAt);
        _controller.stayRestriction(second.personId, second.orderId, 1);
        assertEq(_membership.rightsNow(first.personId).restrictedUntil[0], first.expiresAt);
        assertFalse(_membership.isRestrictedNow(first.personId, MembershipTypes.Right.Community));
        _controller.resumeRestriction(second.personId, second.orderId, 2);
        assertEq(_membership.rightsNow(first.personId).restrictedUntil[0], second.expiresAt);
        _controller.revokeRestriction(second.personId, second.orderId, 3);
        assertEq(_membership.rightsNow(first.personId).restrictedUntil[0], first.expiresAt);
        assertFalse(_membership.isRestrictedNow(first.personId, MembershipTypes.Right.Community));
        uint256 revision = _membership.membershipRevisionOf(first.personId);
        vm.warp(first.expiresAt);
        assertFalse(_membership.isRestrictedNow(first.personId, MembershipTypes.Right.Political));
        assertEq(_membership.membershipRevisionOf(first.personId), revision);
    }

    function testStayCannotExtendExpiryAndFailedResumeKeepsNonce() public {
        _seedAndRetire();
        MembershipTypes.OrderInput memory effect = _input(1, 1, 100);
        _controller.recordRestriction(effect);
        _controller.stayRestriction(effect.personId, effect.orderId, 1);
        vm.warp(effect.expiresAt);
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.OrderExpired.selector, effect.expiresAt));
        _controller.resumeRestriction(effect.personId, effect.orderId, 2);
        assertEq(_controller.nextReceiptNonce(), 2);
        assertEq(_membership.orderOf(effect.personId, effect.orderId).revision, 2);
        assertFalse(_membership.isRestrictedNow(effect.personId, MembershipTypes.Right.Political));
    }

    function testInvalidRecordAndStaleReliefRollbackGeneratedNonce() public {
        _seedAndRetire();
        MembershipTypes.OrderInput memory effect = _input(1, 0, 100);
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.InvalidRestrictedMask.selector, uint16(0)));
        _controller.recordRestriction(effect);
        assertEq(_controller.nextReceiptNonce(), 0);
        effect.restrictedMask = 1;
        _controller.recordRestriction(effect);
        assertEq(_controller.nextReceiptNonce(), 1);
        vm.expectRevert(abi.encodeWithSelector(IMembershipRegistry.OrderRevisionMismatch.selector, 99, 1));
        _controller.stayRestriction(effect.personId, effect.orderId, 99);
        assertEq(_controller.nextReceiptNonce(), 1);
        assertEq(_membership.orderOf(effect.personId, effect.orderId).revision, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.OrderAlreadyRecorded.selector, effect.personId, effect.orderId)
        );
        _controller.recordRestriction(effect);
        assertEq(_controller.nextReceiptNonce(), 1);
    }

    function testGeneratedReferencesBindExactEffectOperationNonceAndController() public {
        _seedAndRetire();
        MembershipTypes.OrderInput memory effect = _input(1, 3, 100);
        bytes32 first = _controller.recordRestriction(effect);
        assertEq(first, _expectedReference(address(_controller), 0, "recordRestriction", keccak256(abi.encode(effect))));
        assertEq(_membership.orderOf(effect.personId, effect.orderId).sourceReceiptId, first);
        bytes32 stayed = _controller.stayRestriction(effect.personId, effect.orderId, 1);
        assertEq(
            stayed,
            _expectedReference(
                address(_controller),
                1,
                "stayRestriction",
                keccak256(abi.encode(effect.personId, effect.orderId, uint256(1)))
            )
        );
        bytes32 resumed = _controller.resumeRestriction(effect.personId, effect.orderId, 2);
        bytes32 revoked = _controller.revokeRestriction(effect.personId, effect.orderId, 3);
        assertTrue(first != stayed && stayed != resumed && resumed != revoked);
        assertEq(_controller.nextReceiptNonce(), 4);
        assertEq(_membership.orderOf(effect.personId, effect.orderId).sourceReceiptId, first);
        assertTrue(first != _expectedReference(address(0x1234), 0, "recordRestriction", keccak256(abi.encode(effect))));
    }

    function testNoArbitraryExecutionIdentityEditingOrTokenMintSelectors() public {
        _seedAndRetire();
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeWithSignature("execute(address,bytes)", address(_identity), hex"12345678");
        calls[1] = abi.encodeWithSignature("mint(address,uint256)", address(this), 1);
        calls[2] = abi.encodeWithSignature("transferOperator(address)", address(0xBAD));
        calls[3] =
            abi.encodeWithSignature("setWalletLink(bytes32,address,uint8)", bytes32(uint256(1)), address(this), 2);
        for (uint256 index; index < calls.length; ++index) {
            (bool success,) = address(_controller).call(calls[index]);
            assertFalse(success);
        }
        assertEq(address(_controller).balance, 0);
    }

    function fixtureId(uint256 index) external pure returns (bytes32) {
        return SepoliaFoundationFixtures.personIdAt(index);
    }

    function _register(SepoliaMembershipController controller) private {
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(_identity));
        _kernel.bootstrapSetModule(KernelModuleIds.MEMBERSHIP_REGISTRY, address(_membership));
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(controller));
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_WRITER, address(controller));
    }

    function _seedAndRetire() private {
        _controller.seedSyntheticIdentities();
        _kernel.disableBootstrapAuthority();
        assertEq(_kernel.bootstrapAuthority(), address(0));
    }

    function _input(uint256 id, uint16 mask, uint64 duration)
        private
        view
        returns (MembershipTypes.OrderInput memory effect)
    {
        effect = MembershipTypes.OrderInput({
            personId: SepoliaFoundationFixtures.personIdAt(0),
            orderId: bytes32(id),
            restrictedMask: mask,
            effectiveAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp) + duration,
            indefinite: false
        });
    }

    function _recordInput() private pure returns (IdentityTypes.IdentityRecordInput memory input) {
        input = IdentityTypes.IdentityRecordInput({
            metadataHash: keccak256("preexisting"),
            metadataURI: "synthetic://preexisting-test-record",
            verificationStatus: IdentityTypes.VerificationStatus.Pending,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.None,
            ageClass: IdentityTypes.AgeClass.Undefined,
            correctionFlag: false,
            finalSuspension: false
        });
    }

    function _expectedReference(address controller, uint256 nonce, string memory operation, bytes32 effectHash)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("SEPOLIA_SYNTHETIC_RESTRICTION_REFERENCE_V1"),
                block.chainid,
                controller,
                nonce,
                keccak256(bytes(operation)),
                effectHash
            )
        );
    }
}
