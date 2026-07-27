// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ICompanyRegistry} from "../interfaces/ICompanyRegistry.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ICompanyRegistryApp} from "../interfaces/ICompanyRegistryApp.sol";
import {IOfficePermissionPolicy} from "../interfaces/IOfficePermissionPolicy.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {CompanyTypes} from "../types/CompanyTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title CompanyRegistryApp
/// @notice Public incorporation submission and office-authorized company registry workflows.
contract CompanyRegistryApp is ICompanyRegistryApp {
    ICompanyRegistry private immutable _companyRegistry;
    IOfficeRegistry private immutable _officeRegistry;
    bytes32 private immutable _companyRegistryOfficeId;

    constructor(
        address companyRegistryAddress,
        address officeRegistryAddress,
        address officePermissionPolicyAddress,
        bytes32 companyRegistryOfficeId_
    ) {
        if (companyRegistryAddress == address(0) || companyRegistryAddress.code.length == 0) {
            revert InvalidCompanyRegistry(companyRegistryAddress);
        }
        if (officeRegistryAddress == address(0) || officeRegistryAddress.code.length == 0) {
            revert InvalidOfficeRegistry(officeRegistryAddress);
        }
        if (officePermissionPolicyAddress == address(0) || officePermissionPolicyAddress.code.length == 0) {
            revert InvalidOfficePermissionPolicy(officePermissionPolicyAddress);
        }
        if (companyRegistryOfficeId_ == bytes32(0)) {
            revert InvalidCompanyRegistryOffice(companyRegistryOfficeId_);
        }

        _companyRegistry = ICompanyRegistry(companyRegistryAddress);
        _officeRegistry = IOfficeRegistry(officeRegistryAddress);
        _companyRegistryOfficeId = companyRegistryOfficeId_;
    }

    /// @inheritdoc ICompanyRegistryApp
    function companyRegistry() external view returns (address registryAddress) {
        return address(_companyRegistry);
    }

    /// @inheritdoc ICompanyRegistryApp
    function officeRegistry() external view returns (address registryAddress) {
        return address(_officeRegistry);
    }

    /// @inheritdoc ICompanyRegistryApp
    function officePermissionPolicy() external view returns (address policyAddress) {
        return address(_currentOfficePermissionPolicy());
    }

    /// @inheritdoc ICompanyRegistryApp
    function companyRegistryOfficeId() external view returns (bytes32 officeId) {
        return _companyRegistryOfficeId;
    }

    /// @inheritdoc ICompanyRegistryApp
    function submitIncorporation(bytes32 companyId, CompanyTypes.CompanyInput calldata input) external {
        _companyRegistry.submitCompany(companyId, msg.sender, input);
    }

    /// @inheritdoc ICompanyRegistryApp
    function approveCompany(bytes32 companyId, bytes32 registrationNumberHash) external {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.approveCompany(companyId, registrationNumberHash);
    }

    /// @inheritdoc ICompanyRegistryApp
    function rejectCompany(bytes32 companyId, bytes32 reasonHash) external {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.rejectCompany(companyId, reasonHash);
    }

    /// @inheritdoc ICompanyRegistryApp
    function setCompanyStatus(bytes32 companyId, CompanyTypes.CompanyStatus status, bytes32 reasonHash) external {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.setCompanyStatus(companyId, status, reasonHash);
    }

    /// @inheritdoc ICompanyRegistryApp
    function updateCompanyMetadata(bytes32 companyId, bytes32 metadataHash, bytes32 articlesHash) external {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.updateCompanyMetadata(companyId, metadataHash, articlesHash);
    }

    /// @inheritdoc ICompanyRegistryApp
    function setDirector(bytes32 companyId, address director, bytes32 roleHash, bool active) external {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.setDirector(companyId, director, roleHash, active);
    }

    /// @inheritdoc ICompanyRegistryApp
    function registerShareClass(
        bytes32 companyId,
        bytes32 classId,
        bytes32 metadataHash,
        uint256 authorizedShares,
        uint16 votingWeightBps,
        bool fractional
    ) external {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.registerShareClass(
            companyId, classId, metadataHash, authorizedShares, votingWeightBps, fractional
        );
    }

    /// @inheritdoc ICompanyRegistryApp
    function setShareClassStatus(bytes32 companyId, bytes32 classId, bool active) external {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.setShareClassStatus(companyId, classId, active);
    }

    /// @inheritdoc ICompanyRegistryApp
    function issueShares(bytes32 companyId, bytes32 classId, address to, uint256 amount, bytes32 documentHash)
        external
    {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.issueShares(companyId, classId, to, amount, documentHash);
    }

    /// @inheritdoc ICompanyRegistryApp
    function transferShares(
        bytes32 companyId,
        bytes32 classId,
        address from,
        address to,
        uint256 amount,
        bytes32 documentHash
    ) external {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.transferShares(companyId, classId, from, to, amount, documentHash);
    }

    /// @inheritdoc ICompanyRegistryApp
    function burnShares(bytes32 companyId, bytes32 classId, address from, uint256 amount, bytes32 documentHash)
        external
    {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.burnShares(companyId, classId, from, amount, documentHash);
    }

    /// @inheritdoc ICompanyRegistryApp
    function recordFiling(bytes32 companyId, bytes32 filingId, CompanyTypes.FilingType filingType, bytes32 documentHash)
        external
    {
        _requireCompanyRegistryOfficeAction(msg.sender);
        _companyRegistry.recordFiling(companyId, filingId, filingType, documentHash, msg.sender);
    }

    function _requireCompanyRegistryOfficeAction(address caller) private view {
        OfficeTypes.OfficeActionClass actionClass = OfficeTypes.OfficeActionClass.ManageCompanyRegistry;
        OfficeTypes.OfficeRecord memory officeRecord = _officeRegistry.getOfficeRecord(_companyRegistryOfficeId);
        if (officeRecord.officeId == bytes32(0) || officeRecord.kind != OfficeTypes.OfficeKind.CompanyRegistryOffice) {
            revert InvalidCompanyRegistryOffice(_companyRegistryOfficeId);
        }

        OfficeTypes.OfficeRole officeRole = _officeRegistry.roleOf(_companyRegistryOfficeId, caller);
        if (!_currentOfficePermissionPolicy().isActionAuthorized(officeRecord.kind, officeRole, actionClass)) {
            revert UnauthorizedCompanyRegistryOfficeAction(caller, _companyRegistryOfficeId, actionClass);
        }
    }

    function _currentOfficePermissionPolicy() private view returns (IOfficePermissionPolicy policy) {
        return IOfficePermissionPolicy(
            IConstitutionKernel(_companyRegistry.kernel()).getModule(KernelModuleIds.OFFICE_PERMISSION_POLICY)
        );
    }
}
