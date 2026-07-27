// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IdentityApp} from "../apps/IdentityApp.sol";
import {IDemoCitizenGateway} from "../interfaces/IDemoCitizenGateway.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILLMStakingVault} from "../interfaces/ILLMStakingVault.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IUnstakingPolicy} from "../interfaces/IUnstakingPolicy.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";

/// @title DemoCitizenGateway
/// @notice Demo-only standing identity authority and user gateway for self-registration plus merit staking and
///         unstaking. Inheriting the regular IdentityApp keeps office workflows and demo onboarding behind one
///         canonical identity-registry writer.
contract DemoCitizenGateway is IdentityApp, IDemoCitizenGateway {
    using SafeERC20 for IERC20;

    IIdentityRegistry private immutable _demoIdentityRegistry;
    IStakeRegistry public immutable stakeRegistry;
    IUnstakingPolicy public immutable unstakingPolicy;
    ILLMStakingVault public immutable stakingVault;
    IERC20 private immutable _meritToken;

    address private _registrar;

    constructor(
        address identityRegistryAddress,
        address stakeRegistryAddress,
        address stakingVaultAddress,
        address unstakingPolicyAddress,
        address meritTokenAddress,
        address registrar_,
        address officeRegistryAddress,
        bytes32 identityOfficeId,
        uint64 migrationDelaySeconds
    ) IdentityApp(identityRegistryAddress, officeRegistryAddress, identityOfficeId, migrationDelaySeconds) {
        if (registrar_ == address(0)) {
            revert InvalidRegistrar(registrar_);
        }

        _demoIdentityRegistry = IIdentityRegistry(identityRegistryAddress);
        stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        stakingVault = ILLMStakingVault(stakingVaultAddress);
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
        if (_demoIdentityRegistry.resolveWalletToPersonId(msg.sender) != bytes32(0)) {
            revert AlreadyRegistered(msg.sender);
        }

        personId = personIdFor(msg.sender);
        _demoIdentityRegistry.setIdentityRecord(
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
        _demoIdentityRegistry.setWalletLink(personId, msg.sender, IdentityTypes.WalletLinkStatus.Active);

        emit DemoRegistrationSubmitted(msg.sender, personId, metadataHash, metadataURI, uint64(block.timestamp));
    }

    /// @inheritdoc IDemoCitizenGateway
    function confirmCitizenship(address wallet, bool approved, bool adult) external {
        _requireRegistrar(msg.sender);

        bytes32 personId = _demoIdentityRegistry.resolveWalletToPersonId(wallet);
        if (personId == bytes32(0)) {
            revert NotRegistered(wallet);
        }

        IdentityTypes.IdentityRecord memory existingRecord = _demoIdentityRegistry.getIdentityRecord(personId);
        _demoIdentityRegistry.setIdentityRecord(
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
        _meritToken.safeTransferFrom(msg.sender, address(this), amount);
        _meritToken.forceApprove(address(stakingVault), amount);
        stakingVault.stakeFor(personId, amount);

        emit DemoMeritsStaked(
            msg.sender, personId, amount, stakeRegistry.activeStakeOf(personId), uint64(block.timestamp)
        );
    }

    /// @inheritdoc IDemoCitizenGateway
    function unstake() external returns (uint256 releasedAmount) {
        bytes32 personId = _requireRegisteredWallet(msg.sender);

        uint64 welfareUntil;
        (releasedAmount, welfareUntil) = stakingVault.unstakeFor(msg.sender);

        emit DemoUnstakeExecuted(
            msg.sender,
            personId,
            releasedAmount,
            stakeRegistry.activeStakeOf(personId),
            welfareUntil,
            uint64(block.timestamp)
        );
    }

    function _requireRegisteredWallet(address wallet) private view returns (bytes32 personId) {
        personId = _demoIdentityRegistry.resolveWalletToPersonId(wallet);
        if (personId == bytes32(0)) {
            revert NotRegistered(wallet);
        }

        IdentityTypes.WalletLink memory walletLink = _demoIdentityRegistry.getWalletLink(wallet);
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
