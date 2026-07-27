// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IKernelModule} from "./IKernelModule.sol";

/// @title ILLMStakingVault
/// @notice Canonical custody contract backing every redeemable unit recorded by the stake registry.
interface ILLMStakingVault is IKernelModule {
    error BackingInvariantViolated(uint256 tokenBalance, uint256 activeStake);
    error InvalidStakeAmount(uint256 amount);
    error InvalidStakingAddress(address account);
    error StakeTransferAmountMismatch(uint256 requestedAmount, uint256 receivedAmount);
    error UnknownStakePerson(bytes32 personId);
    error UnknownActiveWallet(address wallet);
    error UnauthorizedBackingCredit(address caller);
    error UnauthorizedStakeGateway(address caller);

    event BackingFunded(address indexed source, uint256 amount, uint256 newTokenBalance);
    event BackedStakeCredited(
        bytes32 indexed personId, address indexed source, uint256 amount, uint256 newActiveStake, uint64 timestamp
    );
    event LLMStaked(
        address indexed source, bytes32 indexed personId, uint256 amount, uint256 newActiveStake, uint64 timestamp
    );
    event LLMUnstaked(
        address indexed recipient,
        bytes32 indexed personId,
        uint256 amount,
        uint256 remainingActiveStake,
        uint64 welfareUntil,
        uint64 timestamp
    );

    /// @notice Returns the LLM token held by the vault.
    function token() external view returns (address tokenAddress);

    /// @notice Returns the canonical stake registry backed by the vault.
    function stakeRegistry() external view returns (address registryAddress);

    /// @notice Returns token backing in excess of aggregate active stake.
    function backingSurplus() external view returns (uint256 amount);

    /// @notice Adds unallocated LLM backing, primarily for an atomic genesis migration.
    function fundBacking(uint256 amount) external;

    /// @notice Pulls the caller's LLM and credits stake to a person identifier.
    function stakeFor(bytes32 personId, uint256 amount) external;

    /// @notice Credits already-funded backing during the one-time setup phase.
    function creditBackedStake(bytes32 personId, uint256 amount) external;

    /// @notice Unstakes the caller's current person identifier and pays the caller.
    function unstake() external returns (uint256 releasedAmount, uint64 welfareUntil);

    /// @notice Demo/integration gateway path that always pays the supplied active wallet.
    function unstakeFor(address wallet) external returns (uint256 releasedAmount, uint64 welfareUntil);
}
