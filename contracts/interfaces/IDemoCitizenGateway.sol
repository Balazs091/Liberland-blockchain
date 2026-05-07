// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IDemoCitizenGateway
/// @notice Demo-only onboarding and merit staking interface for live frontend testing.
interface IDemoCitizenGateway {
    error AlreadyRegistered(address wallet);
    error InvalidRegistrar(address registrar_);
    error NotRegistered(address wallet);
    error NotRegistrar(address caller);
    error UnstakeNotAllowed(bytes32 personId, uint256 amount);
    error ZeroAmount();

    event DemoRegistrationSubmitted(
        address indexed wallet, bytes32 indexed personId, bytes32 metadataHash, string metadataURI, uint64 submittedAt
    );

    event DemoCitizenshipConfirmed(
        address indexed wallet, bytes32 indexed personId, bool approved, bool adult, uint64 decidedAt, address decidedBy
    );

    event DemoRegistrarUpdated(
        address indexed previousRegistrar, address indexed newRegistrar, address indexed updatedBy
    );

    event DemoMeritsStaked(
        address indexed wallet, bytes32 indexed personId, uint256 amount, uint256 newActiveStake, uint64 stakedAt
    );

    event DemoUnstakeRequested(
        address indexed wallet,
        bytes32 indexed personId,
        uint256 amount,
        uint64 cooldownEnd,
        uint256 remainingActiveStake,
        uint64 requestedAt
    );

    event DemoUnstakeClaimed(address indexed wallet, bytes32 indexed personId, uint256 amount, uint64 claimedAt);

    function registrar() external view returns (address registrarAddress);
    function meritToken() external view returns (address tokenAddress);
    function personIdFor(address wallet) external pure returns (bytes32 personId);
    function registerSelf(bytes32 metadataHash, string calldata metadataURI) external returns (bytes32 personId);
    function confirmCitizenship(address wallet, bool approved, bool adult) external;
    function updateRegistrar(address newRegistrar) external;
    function stake(uint256 amount) external;
    function requestUnstake(uint256 amount) external;
    function claimUnstake() external returns (uint256 claimedAmount);
}
