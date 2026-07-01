// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {KernelModule} from "../base/KernelModule.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title OfficeRegistry
/// @notice Stable fact registry for offices, office admins, and office clerk assignments.
contract OfficeRegistry is IOfficeRegistry, KernelModule {
    mapping(bytes32 officeId => OfficeTypes.OfficeRecord officeRecord) private _officeRecords;
    mapping(bytes32 officeId => mapping(address member => OfficeTypes.OfficeMembership membership)) private _clerks;
    bytes32[] private _officeIds;

    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IOfficeRegistry
    function getOfficeRecord(bytes32 officeId) external view returns (OfficeTypes.OfficeRecord memory officeRecord) {
        return _officeRecords[officeId];
    }

    /// @inheritdoc IOfficeRegistry
    function getClerkRecord(bytes32 officeId, address clerk)
        external
        view
        returns (OfficeTypes.OfficeMembership memory membership)
    {
        return _clerks[officeId][clerk];
    }

    /// @inheritdoc IOfficeRegistry
    function officeExists(bytes32 officeId) public view returns (bool exists) {
        return _officeRecords[officeId].officeId != bytes32(0);
    }

    /// @inheritdoc IOfficeRegistry
    function totalOfficeCount() external view returns (uint256 count) {
        return _officeIds.length;
    }

    /// @inheritdoc IOfficeRegistry
    function officeIdAt(uint256 index) external view returns (bytes32 officeId) {
        return _officeIds[index];
    }

    /// @inheritdoc IOfficeRegistry
    function roleOf(bytes32 officeId, address account) public view returns (OfficeTypes.OfficeRole role) {
        OfficeTypes.OfficeRecord storage officeRecord = _officeRecords[officeId];
        if (!officeRecord.active || officeRecord.officeId == bytes32(0) || account == address(0)) {
            return OfficeTypes.OfficeRole.None;
        }
        if (officeRecord.admin == account) {
            return OfficeTypes.OfficeRole.Admin;
        }
        if (_clerks[officeId][account].active) {
            return OfficeTypes.OfficeRole.Clerk;
        }
        return OfficeTypes.OfficeRole.None;
    }

    /// @inheritdoc IOfficeRegistry
    function isOfficeAdmin(bytes32 officeId, address account) external view returns (bool isAdmin) {
        return roleOf(officeId, account) == OfficeTypes.OfficeRole.Admin;
    }

    /// @inheritdoc IOfficeRegistry
    function isOfficeClerk(bytes32 officeId, address account) external view returns (bool isClerk) {
        return roleOf(officeId, account) == OfficeTypes.OfficeRole.Clerk;
    }

    /// @inheritdoc IOfficeRegistry
    function registerOffice(bytes32 officeId, OfficeTypes.OfficeKind kind, string calldata name, address admin)
        external
    {
        _requireRegistryAuthority(msg.sender);

        if (officeId == bytes32(0)) {
            revert InvalidOfficeId(officeId);
        }
        if (kind == OfficeTypes.OfficeKind.Undefined) {
            revert InvalidOfficeKind(kind);
        }
        if (admin == address(0)) {
            revert InvalidOfficeAdmin(admin);
        }
        if (officeExists(officeId)) {
            revert OfficeAlreadyRegistered(officeId);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        _officeRecords[officeId] = OfficeTypes.OfficeRecord({
            officeId: officeId,
            kind: kind,
            name: name,
            admin: admin,
            active: true,
            createdAt: currentTimestamp,
            lastUpdatedAt: currentTimestamp
        });
        _officeIds.push(officeId);

        emit OfficeRegistered(officeId, kind, admin, name, currentTimestamp, msg.sender);
    }

    /// @inheritdoc IOfficeRegistry
    function transferOfficeAdmin(bytes32 officeId, address newAdmin) external {
        _requireRegistryAuthority(msg.sender);

        OfficeTypes.OfficeRecord storage officeRecord = _officeRecords[officeId];
        if (officeRecord.officeId == bytes32(0)) {
            revert OfficeNotFound(officeId);
        }
        if (newAdmin == address(0)) {
            revert InvalidOfficeAdmin(newAdmin);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        address previousAdmin = officeRecord.admin;
        officeRecord.admin = newAdmin;
        officeRecord.lastUpdatedAt = currentTimestamp;

        _clearClerkRecord(officeId, previousAdmin, currentTimestamp);
        _clearClerkRecord(officeId, newAdmin, currentTimestamp);

        emit OfficeAdminTransferred(officeId, previousAdmin, newAdmin, currentTimestamp, msg.sender);
    }

    /// @inheritdoc IOfficeRegistry
    function setClerkStatus(bytes32 officeId, address clerk, bool active) external {
        _requireRegistryAuthority(msg.sender);

        OfficeTypes.OfficeRecord storage officeRecord = _officeRecords[officeId];
        if (officeRecord.officeId == bytes32(0)) {
            revert OfficeNotFound(officeId);
        }
        if (clerk == address(0) || clerk == officeRecord.admin) {
            revert InvalidOfficeMember(clerk);
        }

        OfficeTypes.OfficeMembership storage membership = _clerks[officeId][clerk];
        membership.officeId = officeId;
        membership.member = clerk;
        membership.role = OfficeTypes.OfficeRole.Clerk;
        membership.active = active;

        uint64 currentTimestamp = uint64(block.timestamp);
        if (active) {
            membership.grantedAt = currentTimestamp;
            membership.revokedAt = 0;
        } else {
            membership.revokedAt = currentTimestamp;
        }

        officeRecord.lastUpdatedAt = currentTimestamp;

        emit OfficeClerkStatusUpdated(officeId, clerk, active, currentTimestamp, msg.sender);
    }

    /// @inheritdoc IOfficeRegistry
    function renameOffice(bytes32 officeId, string calldata newName) external {
        _requireRegistryAuthority(msg.sender);

        OfficeTypes.OfficeRecord storage officeRecord = _officeRecords[officeId];
        if (officeRecord.officeId == bytes32(0)) {
            revert OfficeNotFound(officeId);
        }
        if (bytes(newName).length == 0) {
            revert InvalidOfficeId(officeId);
        }

        string memory previousName = officeRecord.name;
        uint64 currentTimestamp = uint64(block.timestamp);
        officeRecord.name = newName;
        officeRecord.lastUpdatedAt = currentTimestamp;

        emit OfficeRenamed(officeId, previousName, newName, currentTimestamp, msg.sender);
    }

    /// @inheritdoc IOfficeRegistry
    function setOfficeActive(bytes32 officeId, bool active) external {
        _requireRegistryAuthority(msg.sender);

        OfficeTypes.OfficeRecord storage officeRecord = _officeRecords[officeId];
        if (officeRecord.officeId == bytes32(0)) {
            revert OfficeNotFound(officeId);
        }
        if (officeRecord.active == active) {
            revert InvalidOfficeId(officeId);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        officeRecord.active = active;
        officeRecord.lastUpdatedAt = currentTimestamp;

        emit OfficeActiveStatusUpdated(officeId, active, currentTimestamp, msg.sender);
    }

    function _clearClerkRecord(bytes32 officeId, address member, uint64 currentTimestamp) private {
        if (member == address(0)) {
            return;
        }

        OfficeTypes.OfficeMembership storage membership = _clerks[officeId][member];
        if (!membership.active) {
            return;
        }

        membership.active = false;
        membership.revokedAt = currentTimestamp;

        emit OfficeClerkStatusUpdated(officeId, member, false, currentTimestamp, msg.sender);
    }

    function _requireRegistryAuthority(address caller) private view {
        if (caller == _kernel.getModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY)) {
            return;
        }
        if (_isModuleCaller(KernelModuleIds.DECISION_APP, caller)) {
            return;
        }
        if (_isModuleCaller(KernelModuleIds.CABINET_APP, caller)) {
            return;
        }
        if (_isActiveSetupAuthority(caller)) {
            return;
        }

        revert UnauthorizedOfficeRegistryCaller(caller);
    }
}
