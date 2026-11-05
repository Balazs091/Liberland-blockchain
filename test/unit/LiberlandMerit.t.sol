// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

import {LiberlandMerit} from "../../contracts/tokens/LiberlandMerit.sol";
import {ILLMToken} from "../../contracts/interfaces/ILLMToken.sol";
import {LLMStakingVault} from "../../contracts/apps/LLMStakingVault.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {UnstakingPolicy} from "../../contracts/policies/UnstakingPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LLMTokenConstants} from "../../contracts/libraries/LLMTokenConstants.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

contract LiberlandMeritTest is Test {
    address private constant RECIPIENT = address(0xA11CE);
    address private constant SPENDER = address(0xB0B);
    address private constant DESTINATION = address(0xCAFE);
    uint256 private constant GENESIS_SUPPLY = 1_000_000e18;

    LiberlandMerit private token;

    function setUp() public {
        token = new LiberlandMerit(RECIPIENT, GENESIS_SUPPLY);
    }

    function test_ProductionMetadataAndCompleteGenesisAllocation() public view {
        ILLMToken protocolToken = ILLMToken(address(token));
        assertEq(protocolToken.name(), "Liberland Merit");
        assertEq(protocolToken.symbol(), "LLM");
        assertEq(protocolToken.decimals(), 18);
        assertEq(protocolToken.cap(), LLMTokenConstants.MAX_SUPPLY);
        assertEq(protocolToken.totalSupply(), GENESIS_SUPPLY);
        assertEq(protocolToken.balanceOf(RECIPIENT), GENESIS_SUPPLY);
        assertEq(protocolToken.balanceOf(address(this)), 0);
    }

    function test_MaximumSupplyCanBeMintedOnlyAtConstruction() public {
        LiberlandMerit fullSupply = new LiberlandMerit(RECIPIENT, LLMTokenConstants.MAX_SUPPLY);
        assertEq(fullSupply.totalSupply(), LLMTokenConstants.MAX_SUPPLY);
        assertEq(fullSupply.balanceOf(RECIPIENT), LLMTokenConstants.MAX_SUPPLY);
    }

    function test_RejectsZeroGenesisRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        new LiberlandMerit(address(0), GENESIS_SUPPLY);
    }

    function test_RejectsZeroGenesisSupply() public {
        vm.expectRevert(LiberlandMerit.ZeroGenesisSupply.selector);
        new LiberlandMerit(RECIPIENT, 0);
    }

    function test_RejectsSupplyAboveProtocolCap() public {
        uint256 excessSupply = LLMTokenConstants.MAX_SUPPLY + 1;
        vm.expectRevert(
            abi.encodeWithSelector(ERC20Capped.ERC20ExceededCap.selector, excessSupply, LLMTokenConstants.MAX_SUPPLY)
        );
        new LiberlandMerit(RECIPIENT, excessSupply);
    }

    function test_NoPostGenesisIssuanceOrAdministrativeEntryPoints() public {
        bytes[] memory unsupported = new bytes[](8);
        unsupported[0] = abi.encodeWithSignature("mint(address,uint256)", RECIPIENT, 1);
        unsupported[1] = abi.encodeWithSignature("burn(uint256)", 1);
        unsupported[2] = abi.encodeWithSignature("owner()");
        unsupported[3] = abi.encodeWithSignature("transferOwnership(address)", RECIPIENT);
        unsupported[4] = abi.encodeWithSignature("grantRole(bytes32,address)", bytes32(0), RECIPIENT);
        unsupported[5] = abi.encodeWithSignature("pause()");
        unsupported[6] = abi.encodeWithSignature("setCap(uint256)", type(uint256).max);
        unsupported[7] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", DESTINATION, bytes(""));

        for (uint256 i; i < unsupported.length; ++i) {
            // Neither the deployer nor the genesis holder gains administrative authority.
            (bool deployerSucceeded,) = address(token).call(unsupported[i]);
            assertFalse(deployerSucceeded);
            vm.prank(RECIPIENT);
            (bool recipientSucceeded,) = address(token).call(unsupported[i]);
            assertFalse(recipientSucceeded);
        }
        assertEq(token.totalSupply(), GENESIS_SUPPLY);
        assertEq(token.balanceOf(RECIPIENT), GENESIS_SUPPLY);
    }

    function test_TransferAndAllowanceHaveExactUntaxedAmounts() public {
        uint256 direct = 123e18 + 1;
        uint256 delegated = 456e18 + 7;
        vm.startPrank(RECIPIENT);
        token.transfer(DESTINATION, direct);
        token.approve(SPENDER, delegated);
        vm.stopPrank();
        vm.prank(SPENDER);
        token.transferFrom(RECIPIENT, DESTINATION, delegated);

        assertEq(token.balanceOf(RECIPIENT), GENESIS_SUPPLY - direct - delegated);
        assertEq(token.balanceOf(DESTINATION), direct + delegated);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(RECIPIENT, SPENDER), 0);
        assertEq(token.totalSupply(), GENESIS_SUPPLY);
    }

    function test_TransferToZeroCannotDestroySupply() public {
        vm.prank(RECIPIENT);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.totalSupply(), GENESIS_SUPPLY);
        assertEq(token.balanceOf(RECIPIENT), GENESIS_SUPPLY);
    }

    function testFuzz_TransfersConserveSupplyAndExactReceipts(uint256 direct, uint256 approved, uint256 spent) public {
        direct = bound(direct, 0, GENESIS_SUPPLY);
        approved = bound(approved, 0, GENESIS_SUPPLY - direct);
        spent = bound(spent, 0, approved);
        vm.startPrank(RECIPIENT);
        token.transfer(DESTINATION, direct);
        token.approve(SPENDER, approved);
        vm.stopPrank();
        vm.prank(SPENDER);
        token.transferFrom(RECIPIENT, DESTINATION, spent);

        assertEq(token.balanceOf(DESTINATION), direct + spent);
        assertEq(token.balanceOf(RECIPIENT), GENESIS_SUPPLY - direct - spent);
        assertEq(token.balanceOf(RECIPIENT) + token.balanceOf(DESTINATION), token.totalSupply());
        assertEq(token.totalSupply(), GENESIS_SUPPLY);
        assertEq(token.allowance(RECIPIENT, SPENDER), approved - spent);
    }

    function testFuzz_GenesisSupplyDoesNotHaveToEqualCap(uint256 supply) public {
        supply = bound(supply, 1, LLMTokenConstants.MAX_SUPPLY);
        LiberlandMerit configured = new LiberlandMerit(RECIPIENT, supply);
        assertEq(configured.totalSupply(), supply);
        assertEq(configured.balanceOf(RECIPIENT), supply);
        assertEq(configured.cap(), LLMTokenConstants.MAX_SUPPLY);
    }

    function test_CanonicalVaultDepositAndWithdrawalPreserveTokenBacking() public {
        ConstitutionKernel kernel = new ConstitutionKernel(address(this));
        IdentityRegistry identities = new IdentityRegistry(address(kernel));
        StakeRegistry stakes = new StakeRegistry(address(kernel));
        LLMStakingVault vault =
            new LLMStakingVault(address(kernel), address(identities), address(stakes), address(token));
        UnstakingPolicy unstaking = new UnstakingPolicy(address(stakes), 30 days, 1_064);
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(identities));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(stakes));
        kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(vault));
        kernel.bootstrapSetModule(KernelModuleIds.UNSTAKING_POLICY, address(unstaking));
        bytes32 personId = keccak256("synthetic genesis person");
        identities.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: bytes32(0),
                metadataURI: "",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identities.setWalletLink(personId, RECIPIENT, IdentityTypes.WalletLinkStatus.Active);
        kernel.disableBootstrapAuthority();

        uint256 staked = 10_000e18;
        vm.startPrank(RECIPIENT);
        token.approve(address(vault), staked);
        vault.stakeFor(personId, staked);
        assertEq(token.balanceOf(address(vault)), staked);
        assertEq(stakes.activeStakeOf(personId), staked);
        assertEq(vault.backingSurplus(), 0);
        (uint256 released,) = vault.unstake();
        vm.stopPrank();

        assertGt(released, 0);
        assertEq(token.balanceOf(RECIPIENT), GENESIS_SUPPLY - staked + released);
        assertEq(token.balanceOf(address(vault)), staked - released);
        assertEq(token.balanceOf(address(vault)), stakes.totalActiveStake());
        assertEq(vault.backingSurplus(), 0);
        assertEq(token.totalSupply(), GENESIS_SUPPLY);
    }
}
