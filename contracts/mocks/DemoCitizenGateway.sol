// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDemoCitizenGateway} from "../interfaces/IDemoCitizenGateway.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IUnstakingPolicy} from "../interfaces/IUnstakingPolicy.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";

/// @title DemoCitizenGateway
/// @notice Demo-only authority and user gateway for self-registration plus merit staking and unstaking.
contract DemoCitizenGateway is IDemoCitizenGateway {
    IIdentityRegistry public immutable identityRegistry;
    IStakeRegistry public immutable stakeRegistry;
    IUnstakingPolicy public immutable unstakingPolicy;
    IERC20 private immutable _meritToken;

    address private _registrar;

    constructor(
        address identityRegistryAddress,
        address stakeRegistryAddress,
        address unstakingPolicyAddress,
        address meritTokenAddress,
        address registrar_
    ) {
        if (registrar_ == address(0)) {
            revert InvalidRegistrar(registrar_);
        }

        identityRegistry = IIdentityRegistry(identityRegistryAddress);
        stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        unstakingPolicy = IUnstakingPolicy(unstakingPolicyAddress);
        _meritToken = IERC20(meritTokenAddress);
        _registrar = registrar_;
    }

    /// @inheritdoc IDemoCitizenGateway
    function registrar() external view returns (address registrarAddress) {
        return _registrar;
    }

    /// @inheritdoc IDemoCitizenGateway
    function meritToken() external view returns (address tokenAddress) {
        return address(_meritToken);
    }

    /// @inheritdoc IDemoCitizenGateway
    function personIdFor(address wallet) public pure returns (bytes32 personId) {
        return keccak256(abi.encodePacked("demo.person", wallet));
    }

    /// @inheritdoc IDemoCitizenGateway
    function registerSelf(bytes32 metadataHash, string calldata metadataURI) external returns (bytes32 personId) {
        if (identityRegistry.resolveWalletToPersonId(msg.sender) != bytes32(0)) {
            revert AlreadyRegistered(msg.sender);
        }

        personId = personIdFor(msg.sender);
        identityRegistry.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: metadataHash,
                metadataURI: metadataURI,
                verificationStatus: IdentityTypes.VerificationStatus.Pending,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.None,
                ageClass: IdentityTypes.AgeClass.Undefined,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identityRegistry.setWalletLink(personId, msg.sender, IdentityTypes.WalletLinkStatus.Active);

        emit DemoRegistrationSubmitted(msg.sender, personId, metadataHash, metadataURI, uint64(block.timestamp));
    }

    /// @inheritdoc IDemoCitizenGateway
    function confirmCitizenship(address wallet, bool approved, bool adult) external {
        _requireRegistrar(msg.sender);

        bytes32 personId = identityRegistry.resolveWalletToPersonId(wallet);
        if (personId == bytes32(0)) {
            revert NotRegistered(wallet);
        }

        IdentityTypes.IdentityRecord memory existingRecord = identityRegistry.getIdentityRecord(personId);
        identityRegistry.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: existingRecord.metadataHash,
                metadataURI: existingRecord.metadataURI,
                verificationStatus: approved
                    ? IdentityTypes.VerificationStatus.Verified
                    : IdentityTypes.VerificationStatus.Rejected,
                citizenshipStatus: approved
                    ? IdentityTypes.CitizenshipStatus.Citizen
                    : IdentityTypes.CitizenshipStatus.None,
                ageClass: adult ? IdentityTypes.AgeClass.Adult : IdentityTypes.AgeClass.Minor,
                correctionFlag: false,
                finalSuspension: false
            })
        );

        emit DemoCitizenshipConfirmed(wallet, personId, approved, adult, uint64(block.timestamp), msg.sender);
    }

    /// @inheritdoc IDemoCitizenGateway
    function updateRegistrar(address newRegistrar) external {
        _requireRegistrar(msg.sender);
        if (newRegistrar == address(0)) {
            revert InvalidRegistrar(newRegistrar);
        }

        address previousRegistrar = _registrar;
        _registrar = newRegistrar;

        emit DemoRegistrarUpdated(previousRegistrar, newRegistrar, msg.sender);
    }

    /// @inheritdoc IDemoCitizenGateway
    function stake(uint256 amount) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        bytes32 personId = _requireRegisteredWallet(msg.sender);
        bool transferred = _meritToken.transferFrom(msg.sender, address(this), amount);
        require(transferred, "demo stake transfer failed");

        stakeRegistry.increaseStake(personId, amount);

        emit DemoMeritsStaked(
            msg.sender, personId, amount, stakeRegistry.activeStakeOf(personId), uint64(block.timestamp)
        );
    }

    /// @inheritdoc IDemoCitizenGateway
    function requestUnstake(uint256 amount) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        bytes32 personId = _requireRegisteredWallet(msg.sender);
        if (!unstakingPolicy.canStartUnstake(personId, amount)) {
            revert UnstakeNotAllowed(personId, amount);
        }

        uint64 cooldownEnd = unstakingPolicy.previewCooldownEnd(uint64(block.timestamp));
        stakeRegistry.requestUnstake(personId, amount, cooldownEnd);

        emit DemoUnstakeRequested(
            msg.sender, personId, amount, cooldownEnd, stakeRegistry.activeStakeOf(personId), uint64(block.timestamp)
        );
    }

    /// @inheritdoc IDemoCitizenGateway
    function claimUnstake() external returns (uint256 claimedAmount) {
        bytes32 personId = _requireRegisteredWallet(msg.sender);
        claimedAmount = stakeRegistry.claimUnstake(personId);
        bool transferred = _meritToken.transfer(msg.sender, claimedAmount);
        require(transferred, "demo unstake transfer failed");

        emit DemoUnstakeClaimed(msg.sender, personId, claimedAmount, uint64(block.timestamp));
    }

    function _requireRegisteredWallet(address wallet) private view returns (bytes32 personId) {
        personId = identityRegistry.resolveWalletToPersonId(wallet);
        if (personId == bytes32(0)) {
            revert NotRegistered(wallet);
        }

        IdentityTypes.WalletLink memory walletLink = identityRegistry.getWalletLink(wallet);
        if (walletLink.status != IdentityTypes.WalletLinkStatus.Active) {
            revert NotRegistered(wallet);
        }
    }

    function _requireRegistrar(address caller) private view {
        if (caller != _registrar) {
            revert NotRegistrar(caller);
        }
    }
}
