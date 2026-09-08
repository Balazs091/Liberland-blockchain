// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {LLMStakingVault} from "../../contracts/apps/LLMStakingVault.sol";
import {ILLMStakingVault} from "../../contracts/interfaces/ILLMStakingVault.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {UnstakingPolicy} from "../../contracts/policies/UnstakingPolicy.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

contract StakingVaultUpgradeTest is Test {
    ConstitutionKernel private kernel;
    IdentityRegistry private identities;
    StakeRegistry private stakes;
    LLMToken private token;
    LLMStakingVault private original;
    bytes32 private constant PERSON = bytes32(uint256(1));
    address private constant CITIZEN = address(0xC171);
    address private constant KEEPER = address(0xBEEF);

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identities = new IdentityRegistry(address(kernel));
        stakes = new StakeRegistry(address(kernel));
        token = new LLMToken();
        original = new LLMStakingVault(address(kernel), address(identities), address(stakes), address(token));
        UnstakingPolicy policy = new UnstakingPolicy(address(stakes), 30 days, 1064);
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identities));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(stakes));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(original));
        kernel.bootstrapSetModule(KernelModuleIds.UNSTAKING_POLICY, address(policy));
        // Test-only authenticated kernel caller; queue/origin checks have separate integration tests.
        kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(this));
        identities.setIdentityRecord(
            PERSON,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256("synthetic person"),
                metadataURI: "ipfs://synthetic",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identities.setWalletLink(PERSON, CITIZEN, IdentityTypes.WalletLinkStatus.Active);
        token.mint(CITIZEN, 10_000e18);
        vm.startPrank(CITIZEN);
        token.approve(address(original), 10_000e18);
        original.stakeFor(PERSON, 10_000e18);
        vm.stopPrank();
        kernel.disableBootstrapAuthority();
    }

    function test_PermissionlessHandoffPreservesStakeAndWithdrawal() public {
        LLMStakingVault successor = _newVault();
        token.mint(address(original), 123e18); // Include surplus, not only active principal.
        kernel.governanceUpdateModule(KernelModuleIds.LLM_STAKING_VAULT, address(successor));
        vm.prank(KEEPER);
        assertEq(original.handoffBacking(), 10_123e18);
        assertEq(token.balanceOf(address(original)), 0);
        assertEq(token.balanceOf(address(successor)), 10_123e18);
        assertEq(stakes.activeStakeOf(PERSON), 10_000e18);
        assertEq(successor.backingSurplus(), 123e18);
        vm.prank(CITIZEN);
        (uint256 amount,) = successor.unstake();
        assertGt(amount, 0);
        assertEq(token.balanceOf(CITIZEN), amount);
        assertEq(token.balanceOf(address(successor)), stakes.totalActiveStake() + 123e18);
    }

    function test_NoCallerSelectedReceiverAndNoHandoffBeforeGovernanceReplacement() public {
        vm.prank(KEEPER);
        vm.expectRevert(abi.encodeWithSelector(ILLMStakingVault.IncompatibleVaultSuccessor.selector, address(original)));
        original.handoffBacking();
        assertEq(token.balanceOf(address(original)), 10_000e18);
    }

    function testFuzz_DifferentTokenIdentityStakeOrKernelCannotReceiveBacking(uint8 mismatch) public {
        mismatch = uint8(bound(mismatch, 0, 3));
        address nextKernel = mismatch == 0 ? address(new ConstitutionKernel(address(this))) : address(kernel);
        address nextIdentity = mismatch == 1 ? address(new IdentityRegistry(address(kernel))) : address(identities);
        address nextStake = mismatch == 2 ? address(new StakeRegistry(address(kernel))) : address(stakes);
        address nextToken = mismatch == 3 ? address(new LLMToken()) : address(token);
        LLMStakingVault incompatible = new LLMStakingVault(nextKernel, nextIdentity, nextStake, nextToken);
        kernel.governanceUpdateModule(KernelModuleIds.LLM_STAKING_VAULT, address(incompatible));
        vm.expectRevert(
            abi.encodeWithSelector(ILLMStakingVault.IncompatibleVaultSuccessor.selector, address(incompatible))
        );
        original.handoffBacking();
        assertEq(token.balanceOf(address(original)), 10_000e18);
        assertEq(token.balanceOf(address(incompatible)), 0);
    }

    function test_FactRegistryRepointNeedsSeparateMigrationNotThisHandoff() public {
        LLMStakingVault successor = _newVault();
        kernel.governanceUpdateModule(KernelModuleIds.LLM_STAKING_VAULT, address(successor));
        kernel.governanceUpdateModule(KernelModuleIds.STAKE_REGISTRY, address(new StakeRegistry(address(kernel))));
        vm.expectRevert(
            abi.encodeWithSelector(ILLMStakingVault.IncompatibleVaultSuccessor.selector, address(successor))
        );
        original.handoffBacking();
        assertEq(token.balanceOf(address(original)), 10_000e18);
    }

    function test_RetiredValueEntryPointsFailClosedAndRepeatedHandoffCannotReplay() public {
        LLMStakingVault successor = _newVault();
        kernel.governanceUpdateModule(KernelModuleIds.LLM_STAKING_VAULT, address(successor));
        vm.prank(CITIZEN);
        vm.expectRevert(abi.encodeWithSelector(ILLMStakingVault.InactiveStakingVault.selector, address(original)));
        original.unstake();
        vm.expectRevert(abi.encodeWithSelector(ILLMStakingVault.InactiveStakingVault.selector, address(original)));
        original.stakeFor(PERSON, 1);
        original.handoffBacking();
        vm.expectRevert(abi.encodeWithSelector(ILLMStakingVault.InvalidStakeAmount.selector, 0));
        original.handoffBacking();
        token.mint(address(original), 7);
        assertEq(original.handoffBacking(), 7); // Later mistaken donations can follow the same approved receiver.
        assertEq(stakes.totalActiveStake(), 10_000e18);
    }

    function test_RollbackBeforeHandoffPreservesOriginalWithdrawal() public {
        LLMStakingVault successor = _newVault();
        kernel.governanceUpdateModule(KernelModuleIds.LLM_STAKING_VAULT, address(successor));
        kernel.governanceUpdateModule(KernelModuleIds.LLM_STAKING_VAULT, address(original));
        vm.prank(CITIZEN);
        (uint256 amount,) = original.unstake();
        assertGt(amount, 0);
    }

    function test_SecondApprovedSameLedgerHandoffCanReturnCustodyWithoutCopyingStake() public {
        LLMStakingVault successor = _newVault();
        kernel.governanceUpdateModule(KernelModuleIds.LLM_STAKING_VAULT, address(successor));
        original.handoffBacking();
        kernel.governanceUpdateModule(KernelModuleIds.LLM_STAKING_VAULT, address(original));
        successor.handoffBacking();
        assertEq(stakes.totalActiveStake(), 10_000e18);
        assertEq(token.balanceOf(address(original)), 10_000e18);
        assertEq(token.balanceOf(address(successor)), 0);
    }

    function _newVault() private returns (LLMStakingVault) {
        return new LLMStakingVault(address(kernel), address(identities), address(stakes), address(token));
    }
}
