// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {KernelModule} from "../base/KernelModule.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILLMStakingVault} from "../interfaces/ILLMStakingVault.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";

/// @title LLMStakingVault
/// @notice Sole token-custody boundary for active political stake and unstaking payouts.
contract LLMStakingVault is ILLMStakingVault, KernelModule, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IIdentityRegistry private immutable _identityRegistry;
    IStakeRegistry private immutable _stakeRegistry;
    IERC20 private immutable _token;

    constructor(
        address kernelAddress,
        address identityRegistryAddress,
        address stakeRegistryAddress,
        address tokenAddress
    ) KernelModule(kernelAddress) {
        _requireContract(identityRegistryAddress);
        _requireContract(stakeRegistryAddress);
        _requireContract(tokenAddress);

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _token = IERC20(tokenAddress);
    }

    /// @inheritdoc ILLMStakingVault
    function token() external view returns (address tokenAddress) {
        return address(_token);
    }

    /// @inheritdoc ILLMStakingVault
    function stakeRegistry() external view returns (address registryAddress) {
        return address(_stakeRegistry);
    }

    /// @inheritdoc ILLMStakingVault
    function backingSurplus() public view returns (uint256 amount) {
        uint256 balance = _token.balanceOf(address(this));
        uint256 activeStake = _stakeRegistry.totalActiveStake();
        if (balance < activeStake) {
            revert BackingInvariantViolated(balance, activeStake);
        }
        return balance - activeStake;
    }

    /// @inheritdoc ILLMStakingVault
    function fundBacking(uint256 amount) external nonReentrant {
        _requireAmount(amount);
        _pullExact(msg.sender, amount);
        emit BackingFunded(msg.sender, amount, _token.balanceOf(address(this)));
    }

    /// @inheritdoc ILLMStakingVault
    function stakeFor(bytes32 personId, uint256 amount) external nonReentrant {
        _requireAmount(amount);
        _requireIdentity(personId);
        _pullExact(msg.sender, amount);
        _stakeRegistry.increaseStake(personId, amount);
        _requireBacked();

        emit LLMStaked(msg.sender, personId, amount, _stakeRegistry.activeStakeOf(personId), uint64(block.timestamp));
    }

    /// @inheritdoc ILLMStakingVault
    function creditBackedStake(bytes32 personId, uint256 amount) external nonReentrant {
        if (
            !_isActiveSetupAuthority(msg.sender)
                && !_isModuleCaller(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, msg.sender)
        ) {
            revert UnauthorizedBackingCredit(msg.sender);
        }
        _requireAmount(amount);
        _requireIdentity(personId);
        if (backingSurplus() < amount) {
            revert BackingInvariantViolated(_token.balanceOf(address(this)), _stakeRegistry.totalActiveStake() + amount);
        }

        _stakeRegistry.increaseStake(personId, amount);
        emit BackedStakeCredited(
            personId, msg.sender, amount, _stakeRegistry.activeStakeOf(personId), uint64(block.timestamp)
        );
    }

    /// @inheritdoc ILLMStakingVault
    function unstake() external nonReentrant returns (uint256 releasedAmount, uint64 welfareUntil) {
        bytes32 personId = _requireActiveWallet(msg.sender);
        return _unstakeTo(personId, msg.sender);
    }

    /// @inheritdoc ILLMStakingVault
    function unstakeFor(address wallet) external nonReentrant returns (uint256 releasedAmount, uint64 welfareUntil) {
        if (!_isModuleCaller(KernelModuleIds.STAKE_USER_GATEWAY_AUTHORITY, msg.sender)) {
            revert UnauthorizedStakeGateway(msg.sender);
        }
        bytes32 personId = _requireActiveWallet(wallet);
        return _unstakeTo(personId, wallet);
    }

    function _unstakeTo(bytes32 personId, address recipient)
        private
        returns (uint256 releasedAmount, uint64 welfareUntil)
    {
        (releasedAmount, welfareUntil) = _stakeRegistry.unstake(personId);
        uint256 recipientBalanceBefore = _token.balanceOf(recipient);
        _token.safeTransfer(recipient, releasedAmount);
        uint256 receivedAmount = _token.balanceOf(recipient) - recipientBalanceBefore;
        if (receivedAmount != releasedAmount) {
            revert StakeTransferAmountMismatch(releasedAmount, receivedAmount);
        }
        _requireBacked();

        emit LLMUnstaked(
            recipient,
            personId,
            releasedAmount,
            _stakeRegistry.activeStakeOf(personId),
            welfareUntil,
            uint64(block.timestamp)
        );
    }

    function _pullExact(address source, uint256 amount) private {
        uint256 balanceBefore = _token.balanceOf(address(this));
        _token.safeTransferFrom(source, address(this), amount);
        uint256 received = _token.balanceOf(address(this)) - balanceBefore;
        if (received != amount) {
            revert StakeTransferAmountMismatch(amount, received);
        }
    }

    function _requireActiveWallet(address wallet) private view returns (bytes32 personId) {
        IdentityTypes.WalletLink memory walletLink = _identityRegistry.getWalletLink(wallet);
        if (walletLink.personId == bytes32(0) || walletLink.status != IdentityTypes.WalletLinkStatus.Active) {
            revert UnknownActiveWallet(wallet);
        }
        return walletLink.personId;
    }

    function _requireBacked() private view {
        uint256 balance = _token.balanceOf(address(this));
        uint256 activeStake = _stakeRegistry.totalActiveStake();
        if (balance < activeStake) {
            revert BackingInvariantViolated(balance, activeStake);
        }
    }

    function _requireAmount(uint256 amount) private pure {
        if (amount == 0) {
            revert InvalidStakeAmount(amount);
        }
    }

    function _requireIdentity(bytes32 personId) private view {
        if (personId == bytes32(0) || !_identityRegistry.identityExists(personId)) {
            revert UnknownStakePerson(personId);
        }
    }

    function _requireContract(address account) private view {
        if (account == address(0) || account.code.length == 0) {
            revert InvalidStakingAddress(account);
        }
    }
}
