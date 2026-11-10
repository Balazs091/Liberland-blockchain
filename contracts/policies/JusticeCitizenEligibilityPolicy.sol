// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {CitizenEligibilityPolicy} from "./CitizenEligibilityPolicy.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IMembershipRegistry} from "../interfaces/IMembershipRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {MembershipTypes} from "../types/MembershipTypes.sol";

/// @notice Explicit production rules for membership removal, welfare and scoped political restrictions.
/// @dev Existing legacy/demo deployments opt in only by replacing their policy bundle and rebuilding the roll.
contract JusticeCitizenEligibilityPolicy is CitizenEligibilityPolicy {
    IMembershipRegistry private immutable _membership;
    IConstitutionKernel private immutable _kernel;

    /// @param identityRegistryAddress The stable identity ledger.
    /// @param stakeRegistryAddress The stable political stake ledger.
    /// @param minimumCitizenStake_ Minimum active pooled stake retained for political eligibility.
    /// @param membershipRegistryAddress The stable membership lifecycle and restriction ledger.
    constructor(
        address identityRegistryAddress,
        address stakeRegistryAddress,
        uint256 minimumCitizenStake_,
        address membershipRegistryAddress
    ) CitizenEligibilityPolicy(identityRegistryAddress, stakeRegistryAddress, minimumCitizenStake_) {
        if (membershipRegistryAddress.code.length == 0) revert InvalidRegistry(membershipRegistryAddress);
        _membership = IMembershipRegistry(membershipRegistryAddress);
        _kernel = IConstitutionKernel(_identityRegistry.kernel());
        if (_membership.identityRegistry() != identityRegistryAddress || _membership.kernel() != address(_kernel)) {
            revert InvalidRegistry(membershipRegistryAddress);
        }
    }

    /// @inheritdoc CitizenEligibilityPolicy
    function membershipRegistry() public view override returns (address registryAddress) {
        return address(_membership);
    }

    /// @inheritdoc CitizenEligibilityPolicy
    function excludesWelfareFromCivicRoll() public pure override returns (bool excluded) {
        return true;
    }

    /// @inheritdoc CitizenEligibilityPolicy
    function electorateConfigurationValid() public view override returns (bool valid) {
        address justice;
        try _kernel.getModule(KernelModuleIds.JUSTICE_APP) returns (address registered) {
            justice = registered;
        } catch {
            return false;
        }
        try _kernel.getModule(KernelModuleIds.IDENTITY_WRITER) returns (address writer) {
            if (writer != justice) return false;
        } catch {
            return false;
        }
        try _kernel.getModule(KernelModuleIds.MEMBERSHIP_REGISTRY) returns (address membership) {
            return justice != address(0) && membership == address(_membership);
        } catch {
            return false;
        }
    }

    /// @inheritdoc CitizenEligibilityPolicy
    function isCitizenOnCivicRoll(bytes32 personId) public view override returns (bool eligible) {
        return electorateConfigurationValid() && _hasCivicQualifications(personId)
            && !_membership.membershipRemoved(personId) && !_stakeRegistry.isInWelfare(personId);
    }

    /// @inheritdoc CitizenEligibilityPolicy
    function isCitizenInGoodStanding(address wallet) public view override returns (bool eligible) {
        return super.isCitizenInGoodStanding(wallet)
            && !_membership.isRestrictedNow(
            _identityRegistry.resolveWalletToPersonId(wallet), MembershipTypes.Right.Political
        );
    }

    /// @inheritdoc CitizenEligibilityPolicy
    function isEligibleForAppointment(address wallet) public view override returns (bool eligible) {
        return isCitizenInGoodStanding(wallet)
            && !_membership.isRestrictedNow(
            _identityRegistry.resolveWalletToPersonId(wallet), MembershipTypes.Right.AppointmentEligibility
        );
    }
}
