// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title ConstitutionKernel
/// @notice Canonical registry of governed module pointers for the protocol.
contract ConstitutionKernel is IConstitutionKernel {
    error BootstrapAlreadyDisabled();
    error InvalidBootstrapAuthority(address bootstrapAuthority_);
    error InvalidModuleId(bytes32 moduleId);
    error ModuleAddressUnchanged(bytes32 moduleId, address moduleAddress);
    error NotBootstrapAuthority(address caller);

    event BootstrapAuthorityDisabled(address indexed disabledBy);

    mapping(bytes32 moduleId => GovernanceTypes.ModuleRecord moduleRecord) private _moduleRecords;
    mapping(address account => uint256 authorizationRefs) private _authorizedModuleRefs;

    address private _bootstrapAuthority;

    /// @param bootstrapAuthority_ Temporary setup authority used only for initial module registration.
    constructor(address bootstrapAuthority_) {
        if (bootstrapAuthority_ == address(0)) {
            revert InvalidBootstrapAuthority(bootstrapAuthority_);
        }

        _bootstrapAuthority = bootstrapAuthority_;
    }

    /// @notice Returns the temporary bootstrap authority address.
    /// @return authority The remaining bootstrap authority, or zero if disabled.
    function bootstrapAuthority() external view returns (address authority) {
        return _bootstrapAuthority;
    }

    /// @inheritdoc IConstitutionKernel
    function getModule(bytes32 moduleId) external view returns (address moduleAddress) {
        GovernanceTypes.ModuleRecord storage moduleRecord = _moduleRecords[moduleId];
        if (moduleRecord.moduleAddress == address(0) || moduleRecord.status != GovernanceTypes.ModuleStatus.Active) {
            revert ModuleNotRegistered(moduleId);
        }

        return moduleRecord.moduleAddress;
    }

    /// @inheritdoc IConstitutionKernel
    function getModuleRecord(bytes32 moduleId)
        external
        view
        returns (GovernanceTypes.ModuleRecord memory moduleRecord)
    {
        moduleRecord = _moduleRecords[moduleId];
        if (moduleRecord.moduleAddress == address(0)) {
            revert ModuleNotRegistered(moduleId);
        }
    }

    /// @inheritdoc IConstitutionKernel
    function isAuthorizedModule(address account) external view returns (bool authorized) {
        return _authorizedModuleRefs[account] != 0;
    }

    /// @notice Registers or replaces a module while bootstrap authority is still active.
    /// @param moduleId The canonical module identifier.
    /// @param moduleAddress The module implementation address to store.
    function bootstrapSetModule(bytes32 moduleId, address moduleAddress) external {
        _requireBootstrapAuthority(msg.sender);
        _setModule(moduleId, moduleAddress, true);
    }

    /// @notice Permanently removes the temporary bootstrap authority.
    function disableBootstrapAuthority() external {
        _requireBootstrapAuthority(msg.sender);
        _bootstrapAuthority = address(0);

        emit BootstrapAuthorityDisabled(msg.sender);
    }

    /// @inheritdoc IConstitutionKernel
    function governanceUpdateModule(bytes32 moduleId, address moduleAddress) external {
        if (msg.sender != _moduleRecords[KernelModuleIds.ACTION_TIMELOCK].moduleAddress) {
            revert UnauthorizedKernelCaller(msg.sender);
        }

        _setModule(moduleId, moduleAddress, false);
    }

    function _setModule(bytes32 moduleId, address moduleAddress, bool allowRegistration) private {
        if (moduleId == bytes32(0)) {
            revert InvalidModuleId(moduleId);
        }

        if (moduleAddress == address(0) || moduleAddress.code.length == 0) {
            revert InvalidModuleAddress(moduleId, moduleAddress);
        }

        GovernanceTypes.ModuleRecord storage currentRecord = _moduleRecords[moduleId];
        uint64 timestamp = uint64(block.timestamp);

        if (currentRecord.moduleAddress == address(0)) {
            if (!allowRegistration) {
                revert ModuleNotRegistered(moduleId);
            }

            _moduleRecords[moduleId] = GovernanceTypes.ModuleRecord({
                moduleId: moduleId,
                moduleAddress: moduleAddress,
                status: GovernanceTypes.ModuleStatus.Active,
                activatedAt: timestamp,
                lastUpdatedAt: timestamp
            });
            _authorizedModuleRefs[moduleAddress] += 1;

            emit ModuleRegistered(moduleId, moduleAddress, timestamp);
            return;
        }

        if (currentRecord.moduleAddress == moduleAddress) {
            revert ModuleAddressUnchanged(moduleId, moduleAddress);
        }

        address previousModule = currentRecord.moduleAddress;
        _authorizedModuleRefs[previousModule] -= 1;
        _authorizedModuleRefs[moduleAddress] += 1;

        currentRecord.moduleAddress = moduleAddress;
        currentRecord.status = GovernanceTypes.ModuleStatus.Active;
        currentRecord.activatedAt = timestamp;
        currentRecord.lastUpdatedAt = timestamp;

        emit ModuleReplaced(moduleId, previousModule, moduleAddress, timestamp);
    }

    function _requireBootstrapAuthority(address caller) private view {
        if (_bootstrapAuthority == address(0)) {
            revert BootstrapAlreadyDisabled();
        }

        if (caller != _bootstrapAuthority) {
            revert NotBootstrapAuthority(caller);
        }
    }
}
