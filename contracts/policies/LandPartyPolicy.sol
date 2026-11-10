// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {ICompanyRegistry} from "../interfaces/ICompanyRegistry.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILandPartyPolicy} from "../interfaces/ILandPartyPolicy.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {CompanyTypes} from "../types/CompanyTypes.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {LandTypes} from "../types/LandTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title LandPartyPolicy
/// @notice V1 resolution policy for person, company, and public-office cadastral parties.
/// @dev New namespaces, ownership groups, and different corporate signing rules can be added by replacing this
///      policy without rewriting title records, because titles store namespaced stable identifiers.
contract LandPartyPolicy is ILandPartyPolicy {
    bytes32 private constant _PERSON_NAMESPACE = keccak256("party.person");
    bytes32 private constant _OFFICE_NAMESPACE = keccak256("party.office");

    IIdentityRegistry private immutable _identityRegistry;
    ICompanyRegistry private immutable _companyRegistry;
    IOfficeRegistry private immutable _officeRegistry;
    IConstitutionKernel private immutable _kernel;

    constructor(address identityRegistryAddress, address companyRegistryAddress, address officeRegistryAddress) {
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidIdentityRegistry(identityRegistryAddress);
        }
        if (companyRegistryAddress == address(0) || companyRegistryAddress.code.length == 0) {
            revert InvalidCompanyRegistry(companyRegistryAddress);
        }
        if (officeRegistryAddress == address(0) || officeRegistryAddress.code.length == 0) {
            revert InvalidOfficeRegistry(officeRegistryAddress);
        }

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _companyRegistry = ICompanyRegistry(companyRegistryAddress);
        _officeRegistry = IOfficeRegistry(officeRegistryAddress);
        _kernel = IConstitutionKernel(_companyRegistry.kernel());
    }

    /// @inheritdoc ILandPartyPolicy
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc ILandPartyPolicy
    function companyRegistry() external view returns (address registryAddress) {
        return address(_companyRegistry);
    }

    /// @inheritdoc ILandPartyPolicy
    function officeRegistry() external view returns (address registryAddress) {
        return address(_officeRegistry);
    }

    /// @inheritdoc ILandPartyPolicy
    function personNamespace() external pure returns (bytes32 namespace) {
        return _PERSON_NAMESPACE;
    }

    /// @inheritdoc ILandPartyPolicy
    function companyNamespace() external pure returns (bytes32 namespace) {
        return LandTypes.COMPANY_NAMESPACE;
    }

    /// @inheritdoc ILandPartyPolicy
    function officeNamespace() external pure returns (bytes32 namespace) {
        return _OFFICE_NAMESPACE;
    }

    /// @inheritdoc ILandPartyPolicy
    function partyKey(LandTypes.PartyRef calldata party) external pure returns (bytes32 key) {
        return _partyKey(party);
    }

    /// @inheritdoc ILandPartyPolicy
    function partyExists(LandTypes.PartyRef calldata party) external view returns (bool exists) {
        return _partyExists(party);
    }

    /// @inheritdoc ILandPartyPolicy
    function canAcquireLand(LandTypes.PartyRef calldata party) external view returns (bool eligible) {
        if (party.namespace == _PERSON_NAMESPACE) {
            (IdentityTypes.VerificationStatus verificationStatus,,,) = _identityRegistry.getCitizenshipSummary(party.id);
            return _identityRegistry.identityExists(party.id)
                && verificationStatus == IdentityTypes.VerificationStatus.Verified
                && _identityRegistry.activeWalletOf(party.id) != address(0);
        }
        if (party.namespace == LandTypes.COMPANY_NAMESPACE) {
            (CompanyTypes.CompanyStatus status, uint32 activeDirectorCount) =
                _currentCompanyRegistry().getCompanyRepresentation(party.id);
            return (status == CompanyTypes.CompanyStatus.Active
                    || status == CompanyTypes.CompanyStatus.ComplianceWarning) && activeDirectorCount != 0;
        }
        if (party.namespace == _OFFICE_NAMESPACE) {
            OfficeTypes.OfficeRecord memory record = _officeRegistry.getOfficeRecord(party.id);
            if (!record.active || record.admin == address(0)) {
                return false;
            }
            if (record.adminPersonId == bytes32(0)) {
                return _officeRegistry.isOfficeAdminAppointment(party.id, record.admin);
            }
            return _identityRegistry.activeWalletOf(record.adminPersonId) != address(0)
                && (record.adminAuthorizationEndsAt == 0 || block.timestamp < record.adminAuthorizationEndsAt);
        }
        return false;
    }

    /// @inheritdoc ILandPartyPolicy
    function isAuthorizedSigner(LandTypes.PartyRef calldata party, address signer)
        external
        view
        returns (bool authorized)
    {
        if (signer == address(0)) {
            return false;
        }
        if (party.namespace == _PERSON_NAMESPACE) {
            return _identityRegistry.identityExists(party.id) && _identityRegistry.activeWalletOf(party.id) == signer;
        }
        if (party.namespace == LandTypes.COMPANY_NAMESPACE) {
            ICompanyRegistry companies = _currentCompanyRegistry();
            return companies.companyExists(party.id) && companies.getDirector(party.id, signer).active;
        }
        if (party.namespace == _OFFICE_NAMESPACE) {
            return _officeRegistry.officeExists(party.id) && _officeRegistry.isOfficeAdminAppointment(party.id, signer);
        }
        return false;
    }

    function _partyExists(LandTypes.PartyRef calldata party) private view returns (bool exists) {
        if (party.namespace == _PERSON_NAMESPACE) {
            return _identityRegistry.identityExists(party.id);
        }
        if (party.namespace == LandTypes.COMPANY_NAMESPACE) {
            return _currentCompanyRegistry().companyExists(party.id);
        }
        if (party.namespace == _OFFICE_NAMESPACE) {
            return _officeRegistry.officeExists(party.id);
        }
        return false;
    }

    function _partyKey(LandTypes.PartyRef calldata party) private pure returns (bytes32 key) {
        return keccak256(abi.encode(party.namespace, party.id));
    }

    function _currentCompanyRegistry() private view returns (ICompanyRegistry) {
        if (_kernel.getModule(KernelModuleIds.COMPANY_REGISTRY) != address(_companyRegistry)) {
            revert InvalidCompanyRegistry(address(_companyRegistry));
        }
        return _companyRegistry;
    }
}
