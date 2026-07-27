// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ILandRegistry} from "../interfaces/ILandRegistry.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ILandRegistryApp} from "../interfaces/ILandRegistryApp.sol";
import {IOfficePermissionPolicy} from "../interfaces/IOfficePermissionPolicy.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {LandTypes} from "../types/LandTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title LandRegistryApp
/// @notice Office-authorized workflow app for land registry state transitions.
contract LandRegistryApp is ILandRegistryApp {
    ILandRegistry private immutable _landRegistry;
    IOfficeRegistry private immutable _officeRegistry;
    bytes32 private immutable _landOfficeId;

    constructor(
        address landRegistryAddress,
        address officeRegistryAddress,
        address officePermissionPolicyAddress,
        bytes32 landOfficeId_
    ) {
        if (landRegistryAddress == address(0) || landRegistryAddress.code.length == 0) {
            revert InvalidLandRegistry(landRegistryAddress);
        }
        if (officeRegistryAddress == address(0) || officeRegistryAddress.code.length == 0) {
            revert InvalidOfficeRegistry(officeRegistryAddress);
        }
        if (officePermissionPolicyAddress == address(0) || officePermissionPolicyAddress.code.length == 0) {
            revert InvalidOfficePermissionPolicy(officePermissionPolicyAddress);
        }
        if (landOfficeId_ == bytes32(0)) {
            revert InvalidLandRegistryOffice(landOfficeId_);
        }

        _landRegistry = ILandRegistry(landRegistryAddress);
        _officeRegistry = IOfficeRegistry(officeRegistryAddress);
        _landOfficeId = landOfficeId_;
    }

    /// @inheritdoc ILandRegistryApp
    function landRegistry() external view returns (address registryAddress) {
        return address(_landRegistry);
    }

    /// @inheritdoc ILandRegistryApp
    function officeRegistry() external view returns (address registryAddress) {
        return address(_officeRegistry);
    }

    /// @inheritdoc ILandRegistryApp
    function officePermissionPolicy() external view returns (address policyAddress) {
        return address(_currentOfficePermissionPolicy());
    }

    /// @inheritdoc ILandRegistryApp
    function landOfficeId() external view returns (bytes32 officeId) {
        return _landOfficeId;
    }

    /// @inheritdoc ILandRegistryApp
    function submitParcelDraft(bytes32 parcelId, LandTypes.ParcelInput calldata input) external {
        _requireLandRegistryOfficeAction(msg.sender);
        _landRegistry.createParcel(parcelId, input);
    }

    /// @inheritdoc ILandRegistryApp
    function updateParcel(bytes32 parcelId, LandTypes.ParcelInput calldata input) external {
        _requireLandRegistryOfficeAction(msg.sender);
        _landRegistry.updateParcel(parcelId, input);
    }

    /// @inheritdoc ILandRegistryApp
    function activateParcel(bytes32 parcelId, bytes32 documentHash) external {
        _requireLandRegistryOfficeAction(msg.sender);
        _landRegistry.activateParcel(parcelId, documentHash);
    }

    /// @inheritdoc ILandRegistryApp
    function retireParcel(bytes32 parcelId, bytes32 documentHash) external {
        _requireLandRegistryOfficeAction(msg.sender);
        _landRegistry.retireParcel(parcelId, documentHash);
    }

    /// @inheritdoc ILandRegistryApp
    function registerTitle(bytes32 titleId, LandTypes.TitleInput calldata input) external {
        _requireLandRegistryOfficeAction(msg.sender);
        _landRegistry.registerTitle(titleId, input);
    }

    /// @inheritdoc ILandRegistryApp
    function transferTitle(bytes32 titleId, address newHolder, bytes32 documentHash) external {
        _requireLandRegistryOfficeAction(msg.sender);
        _landRegistry.transferTitle(titleId, newHolder, documentHash);
    }

    /// @inheritdoc ILandRegistryApp
    function fileDispute(bytes32 disputeId, bytes32 parcelId, bytes32 evidenceHash) external {
        _landRegistry.fileDispute(disputeId, parcelId, msg.sender, evidenceHash);
    }

    /// @inheritdoc ILandRegistryApp
    function acceptDispute(bytes32 disputeId, bytes32 evidenceHash) external {
        _requireLandRegistryOfficeAction(msg.sender);
        _landRegistry.acceptDispute(disputeId, evidenceHash);
    }

    /// @inheritdoc ILandRegistryApp
    function resolveDispute(bytes32 disputeId, bytes32 resolutionHash, bool claimAccepted) external {
        _requireLandRegistryOfficeAction(msg.sender);
        _landRegistry.resolveDispute(disputeId, resolutionHash, claimAccepted);
    }

    /// @inheritdoc ILandRegistryApp
    function registerEncumbrance(bytes32 encumbranceId, bytes32 titleId, bytes32 documentHash) external {
        _requireLandRegistryOfficeAction(msg.sender);
        _landRegistry.registerEncumbrance(encumbranceId, titleId, documentHash);
    }

    /// @inheritdoc ILandRegistryApp
    function releaseEncumbrance(bytes32 encumbranceId, bytes32 documentHash) external {
        _requireLandRegistryOfficeAction(msg.sender);
        _landRegistry.releaseEncumbrance(encumbranceId, documentHash);
    }

    function _requireLandRegistryOfficeAction(address caller) private view {
        OfficeTypes.OfficeActionClass actionClass = OfficeTypes.OfficeActionClass.ManageLandRegistry;
        OfficeTypes.OfficeRecord memory officeRecord = _officeRegistry.getOfficeRecord(_landOfficeId);
        if (officeRecord.officeId == bytes32(0) || officeRecord.kind != OfficeTypes.OfficeKind.LandRegistryOffice) {
            revert InvalidLandRegistryOffice(_landOfficeId);
        }

        OfficeTypes.OfficeRole officeRole = _officeRegistry.roleOf(_landOfficeId, caller);
        if (!_currentOfficePermissionPolicy().isActionAuthorized(officeRecord.kind, officeRole, actionClass)) {
            revert UnauthorizedLandRegistryOfficeAction(caller, _landOfficeId, actionClass);
        }
    }

    function _currentOfficePermissionPolicy() private view returns (IOfficePermissionPolicy policy) {
        return IOfficePermissionPolicy(
            IConstitutionKernel(_landRegistry.kernel()).getModule(KernelModuleIds.OFFICE_PERMISSION_POLICY)
        );
    }
}
