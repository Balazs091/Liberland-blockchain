// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";

import {DeploySepoliaFoundation} from "../../scripts/DeploySepoliaFoundation.s.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {IMembershipRegistry} from "../../contracts/interfaces/IMembershipRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {SepoliaFoundationFixtures} from "../../contracts/mocks/SepoliaFoundationFixtures.sol";
import {SepoliaMembershipController} from "../../contracts/mocks/SepoliaMembershipController.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {MembershipRegistry} from "../../contracts/registries/MembershipRegistry.sol";
import {LiberlandMerit} from "../../contracts/tokens/LiberlandMerit.sol";
import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {MembershipTypes} from "../../contracts/types/MembershipTypes.sol";

/// @notice Runs the same deployment internals without a private key, broadcast or output-file write.
contract DeploySepoliaFoundationHarness is DeploySepoliaFoundation {
    function deployForTest() external returns (Deployment memory deployment) {
        _requireSepolia();
        deployment = _deployAndSeed(address(this));
        _assertDeployment(deployment);
    }

    function record(address controller, MembershipTypes.OrderInput calldata effect) external returns (bytes32) {
        return SepoliaMembershipController(controller).recordRestriction(effect);
    }

    function stay(address controller, bytes32 personId, bytes32 orderId, uint256 revision) external returns (bytes32) {
        return SepoliaMembershipController(controller).stayRestriction(personId, orderId, revision);
    }

    function resume(address controller, bytes32 personId, bytes32 orderId, uint256 revision)
        external
        returns (bytes32)
    {
        return SepoliaMembershipController(controller).resumeRestriction(personId, orderId, revision);
    }

    function revoke(address controller, bytes32 personId, bytes32 orderId, uint256 revision)
        external
        returns (bytes32)
    {
        return SepoliaMembershipController(controller).revokeRestriction(personId, orderId, revision);
    }

    function seedAgain(address controller) external {
        SepoliaMembershipController(controller).seedSyntheticIdentities();
    }

    function tryRepoint(address kernel, bytes32 moduleId, address module) external {
        ConstitutionKernel(kernel).bootstrapSetModule(moduleId, module);
    }
}

/// @notice Integration checks for the isolated synthetic Sepolia deployment, not the legal decision workflows.
contract DeploySepoliaFoundationTest is Test {
    DeploySepoliaFoundationHarness private _script;
    DeploySepoliaFoundation.Deployment private _deployment;
    ConstitutionKernel private _kernel;
    IdentityRegistry private _identity;
    MembershipRegistry private _membership;
    SepoliaMembershipController private _controller;
    LiberlandMerit private _token;

    function setUp() public {
        vm.chainId(SepoliaFoundationFixtures.CHAIN_ID);
        vm.warp(1_900_000_000);
        _script = new DeploySepoliaFoundationHarness();
        _deployment = _script.deployForTest();
        _kernel = ConstitutionKernel(_deployment.constitutionKernel);
        _identity = IdentityRegistry(_deployment.identityRegistry);
        _membership = MembershipRegistry(_deployment.membershipRegistry);
        _controller = SepoliaMembershipController(_deployment.membershipController);
        _token = LiberlandMerit(_deployment.llmToken);
    }

    function test_DeploysRealFixedSupplyTokenAndCompleteSyntheticRecords() public view {
        assertEq(_token.name(), "Liberland Merit");
        assertEq(_token.symbol(), "LLM");
        assertEq(_token.decimals(), 18);
        assertEq(_token.cap(), 70_000_000e18);
        assertEq(_token.totalSupply(), SepoliaFoundationFixtures.GENESIS_SUPPLY);
        uint256 allocated;
        for (uint256 i; i < SepoliaFoundationFixtures.PERSON_COUNT; ++i) {
            bytes32 personId = SepoliaFoundationFixtures.personIdAt(i);
            address wallet = SepoliaFoundationFixtures.walletAt(i);
            IdentityTypes.IdentityRecord memory record = _identity.getIdentityRecord(personId);
            assertEq(record.personId, personId);
            assertEq(record.metadataHash, SepoliaFoundationFixtures.metadataHashAt(i));
            assertEq(uint8(record.verificationStatus), uint8(IdentityTypes.VerificationStatus.Verified));
            assertEq(uint8(record.citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.Citizen));
            assertEq(uint8(record.ageClass), uint8(IdentityTypes.AgeClass.Adult));
            assertEq(_identity.activeWalletOf(personId), wallet);
            assertEq(_identity.resolveWalletToPersonId(wallet), personId);
            assertEq(_token.balanceOf(wallet), SepoliaFoundationFixtures.BALANCE_PER_PERSON);
            assertEq(_membership.rightsNow(personId).restrictedMask, 0);
            allocated += _token.balanceOf(wallet);
        }
        assertEq(_identity.totalIdentityCount(), SepoliaFoundationFixtures.PERSON_COUNT);
        assertEq(_token.balanceOf(address(_script)), 970_000e18);
        assertEq(allocated + _token.balanceOf(address(_script)), _token.totalSupply());
        assertEq(_token.balanceOf(address(_controller)), 0);
        assertEq(_token.balanceOf(address(_membership)), 0);
    }

    function test_SoleTestControllerBindingsAndBootstrapRetirementAreComplete() public {
        assertEq(_deployment.operator, address(_script));
        assertEq(_controller.operator(), address(_script));
        assertEq(_controller.kernel(), address(_kernel));
        assertEq(_controller.identityRegistry(), address(_identity));
        assertEq(_controller.membershipRegistry(), address(_membership));
        assertEq(_membership.kernel(), address(_kernel));
        assertEq(_membership.identityRegistry(), address(_identity));
        assertEq(_kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY), address(_identity));
        assertEq(_kernel.getModule(KernelModuleIds.MEMBERSHIP_REGISTRY), address(_membership));
        assertEq(_kernel.getModule(KernelModuleIds.IDENTITY_WRITER), address(_controller));
        assertEq(_kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY), address(_controller));
        assertEq(
            uint8(_kernel.moduleClass(KernelModuleIds.MEMBERSHIP_REGISTRY)), uint8(GovernanceTypes.ModuleClass.State)
        );
        assertEq(
            uint8(_kernel.moduleClass(KernelModuleIds.IDENTITY_WRITER)), uint8(GovernanceTypes.ModuleClass.Authority)
        );
        assertTrue(_controller.fixturesSeeded());
        assertEq(_kernel.bootstrapAuthority(), address(0));

        vm.expectRevert(ConstitutionKernel.BootstrapAlreadyDisabled.selector);
        _script.tryRepoint(address(_kernel), KernelModuleIds.IDENTITY_WRITER, address(_script));
        vm.expectRevert();
        _script.seedAgain(address(_controller));
        assertEq(_identity.totalIdentityCount(), 3);

        // This deployment intentionally contains no voting/treasury governance or stake accounting.
        _expectMissing(KernelModuleIds.GOVERNANCE_ROUTER);
        _expectMissing(KernelModuleIds.ACTION_TIMELOCK);
        _expectMissing(KernelModuleIds.STAKE_REGISTRY);
        _expectMissing(KernelModuleIds.ELECTORATE_REGISTRY);
    }

    function test_CompletedDeploymentVerifiesFromOnChainBindings() public view {
        DeploySepoliaFoundation.Deployment memory verified = _script.verify(address(_kernel), address(_token));
        assertEq(verified.constitutionKernel, address(_kernel));
        assertEq(verified.llmToken, address(_token));
        assertEq(verified.identityRegistry, address(_identity));
        assertEq(verified.membershipRegistry, address(_membership));
        assertEq(verified.membershipController, address(_controller));
        assertEq(verified.operator, address(_script));
    }

    function test_OverlappingOrdersSupportScopedReliefAndClockOnlyExpiry() public {
        bytes32 personId = SepoliaFoundationFixtures.personIdAt(0);
        MembershipTypes.OrderInput memory shortOrder = _input(1, 1, 10 days);
        MembershipTypes.OrderInput memory longOrder = _input(2, 3, 20 days);
        bytes32 firstReceipt = _script.record(address(_controller), shortOrder);
        bytes32 secondReceipt = _script.record(address(_controller), longOrder);
        assertTrue(firstReceipt != bytes32(0) && secondReceipt != bytes32(0) && firstReceipt != secondReceipt);
        assertEq(_membership.orderOf(personId, shortOrder.orderId).sourceReceiptId, firstReceipt);
        assertEq(_membership.rightsNow(personId).restrictedMask, 3);

        _script.stay(address(_controller), personId, longOrder.orderId, 1);
        MembershipTypes.RightsSummary memory stayed = _membership.rightsNow(personId);
        assertEq(stayed.restrictedMask, 1);
        assertEq(stayed.restrictedUntil[0], shortOrder.expiresAt);
        _script.resume(address(_controller), personId, longOrder.orderId, 2);
        assertEq(_membership.rightsNow(personId).restrictedMask, 3);
        _script.revoke(address(_controller), personId, longOrder.orderId, 3);
        assertEq(_membership.rightsNow(personId).restrictedMask, 1);

        uint256 membershipRevision = _membership.membershipRevisionOf(personId);
        uint256 mutations = _membership.electorateMutationCount();
        uint256 identityRevision = _identity.electorateRevisionOf(personId);
        vm.warp(shortOrder.expiresAt);
        assertEq(_membership.rightsNow(personId).restrictedMask, 0);
        assertEq(_membership.membershipRevisionOf(personId), membershipRevision);
        assertEq(_membership.electorateMutationCount(), mutations);
        assertEq(_identity.electorateRevisionOf(personId), identityRevision);
        assertEq(
            uint8(_identity.getIdentityRecord(personId).citizenshipStatus),
            uint8(IdentityTypes.CitizenshipStatus.Citizen)
        );
    }

    function test_FailedExecutionRollsBackSyntheticReceiptAndRegistryState() public {
        MembershipTypes.OrderInput memory order = _input(1, 1, 10 days);
        _script.record(address(_controller), order);
        uint256 nonce = _controller.nextReceiptNonce();
        uint256 mutations = _membership.electorateMutationCount();
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.OrderRevisionMismatch.selector, uint256(2), uint256(1))
        );
        _script.stay(address(_controller), order.personId, order.orderId, 2);
        assertEq(_controller.nextReceiptNonce(), nonce);
        assertEq(_membership.electorateMutationCount(), mutations);
        assertEq(
            uint8(_membership.orderOf(order.personId, order.orderId).status),
            uint8(MembershipTypes.OrderStatus.Unstayed)
        );

        vm.expectRevert();
        _script.record(address(_controller), order);
        assertEq(_controller.nextReceiptNonce(), nonce);
        assertEq(_membership.electorateMutationCount(), mutations);
    }

    function test_PublicCallersCannotActAsTestControllerOrRegistryWriter() public {
        MembershipTypes.OrderInput memory order = _input(1, 1, 10 days);
        vm.expectRevert();
        _controller.recordRestriction(order);
        vm.expectRevert(
            abi.encodeWithSelector(IMembershipRegistry.UnauthorizedMembershipRegistryCaller.selector, address(this))
        );
        _membership.recordOrder(order, keccak256("forged-test-receipt"));
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistry.UnauthorizedIdentityRegistryCaller.selector, address(this))
        );
        _identity.setWalletLink(order.personId, address(0xBAD), IdentityTypes.WalletLinkStatus.Active);
        assertEq(_membership.electorateMutationCount(), 0);
    }

    function test_FreshDeploymentVerificationRejectsWrongTokenAndMissingModules() public {
        LiberlandMerit wrongAllocation = new LiberlandMerit(address(this), SepoliaFoundationFixtures.GENESIS_SUPPLY);
        vm.expectRevert();
        _script.verify(address(_kernel), address(wrongAllocation));
        ConstitutionKernel emptyKernel = new ConstitutionKernel(address(this));
        vm.expectRevert();
        _script.verify(address(emptyKernel), address(_token));
    }

    function test_TestnetEntryPointsRejectMainnetBeforeAnyKeyReadOrDeployment() public {
        vm.chainId(1);
        vm.expectRevert();
        _script.run();
        vm.expectRevert();
        _script.deployForTest();
        vm.expectRevert();
        _script.verify(address(_kernel), address(_token));
    }

    function test_DeployedTokenCannotUsePublicMintingOfOldDemo() public {
        uint256 supply = _token.totalSupply();
        (bool success,) = address(_token).call(abi.encodeWithSignature("mint(address,uint256)", address(this), 1e18));
        assertFalse(success);
        assertEq(_token.totalSupply(), supply);
    }

    function _input(uint256 id, uint16 mask, uint64 duration) private view returns (MembershipTypes.OrderInput memory) {
        return MembershipTypes.OrderInput({
            personId: SepoliaFoundationFixtures.personIdAt(0),
            orderId: keccak256(abi.encode("integration-order", id)),
            restrictedMask: mask,
            effectiveAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp) + duration,
            indefinite: false
        });
    }

    function _expectMissing(bytes32 moduleId) private {
        vm.expectRevert(abi.encodeWithSelector(IConstitutionKernel.ModuleNotRegistered.selector, moduleId));
        _kernel.getModule(moduleId);
    }
}
