// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {KernelModule} from "../base/KernelModule.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title OfficeRegistry
/// @notice Stable fact registry for offices, office admins, and office clerk assignments.
contract OfficeRegistry is IOfficeRegistry, KernelModule {
    mapping(bytes32 officeId => OfficeTypes.OfficeRecord officeRecord) private _officeRecords;
    mapping(bytes32 officeId => mapping(address member => OfficeTypes.OfficeMembership membership)) private _clerks;
    mapping(bytes32 officeId => uint64 clerkEpoch) private _clerkEpochs;
    mapping(bytes32 officeId => mapping(address member => uint64 clerkEpoch)) private _clerkMembershipEpochs;
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
        membership = _clerks[officeId][clerk];
        if (
            _clerkMembershipEpochs[officeId][clerk] != _clerkEpochs[officeId]
                || _isAdministrationExpired(_officeRecords[officeId])
        ) {
            membership.active = false;
        }
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
        if (
            !officeRecord.active || officeRecord.officeId == bytes32(0) || account == address(0)
                || _isAdministrationExpired(officeRecord)
        ) {
            return OfficeTypes.OfficeRole.None;
        }
        if (_isCurrentAdmin(officeRecord, account)) {
            return OfficeTypes.OfficeRole.Admin;
        }
        if (_clerks[officeId][account].active && _clerkMembershipEpochs[officeId][account] == _clerkEpochs[officeId]) {
            return OfficeTypes.OfficeRole.Clerk;
        }
        return OfficeTypes.OfficeRole.None;
    }

    /// @inheritdoc IOfficeRegistry
    function isOfficeAdmin(bytes32 officeId, address account) external view returns (bool isAdmin) {
        return roleOf(officeId, account) == OfficeTypes.OfficeRole.Admin;
    }

    /// @inheritdoc IOfficeRegistry
    function isOfficeAdminAppointment(bytes32 officeId, address account) external view returns (bool isAdmin) {
        OfficeTypes.OfficeRecord storage officeRecord = _officeRecords[officeId];
        return officeRecord.officeId != bytes32(0) && _isCurrentAdmin(officeRecord, account);
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
            lastUpdatedAt: currentTimestamp,
            adminAuthorizationEndsAt: 0,
            adminPersonId: bytes32(0)
        });
        _clerkEpochs[officeId] = 1;
        _officeIds.push(officeId);

        emit OfficeRegistered(officeId, kind, admin, name, currentTimestamp, msg.sender);
    }

    /// @inheritdoc IOfficeRegistry
    function transferOfficeAdmin(bytes32 officeId, address newAdmin) external {
        _requireRegistryAuthority(msg.sender);

        _transferOfficeAdmin(officeId, newAdmin, bytes32(0), 0);
    }

    /// @inheritdoc IOfficeRegistry
    function transferOfficeAdminForTerm(
        bytes32 officeId,
        address newAdmin,
        bytes32 adminPersonId,
        uint64 authorizationEndsAt
    ) external {
        _requireRegistryAuthority(msg.sender);
        if (adminPersonId == bytes32(0)) {
            revert InvalidOfficeAdmin(newAdmin);
        }
        if (authorizationEndsAt <= block.timestamp) {
            revert InvalidOfficeAdminAuthorizationEnd(authorizationEndsAt, uint64(block.timestamp));
        }

        _transferOfficeAdmin(officeId, newAdmin, adminPersonId, authorizationEndsAt);
    }

    /// @inheritdoc IOfficeRegistry
    function revokeOfficeAdmin(bytes32 officeId) external {
        _requireRegistryAuthority(msg.sender);

        OfficeTypes.OfficeRecord storage officeRecord = _officeRecords[officeId];
        if (officeRecord.officeId == bytes32(0)) {
            revert OfficeNotFound(officeId);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        address previousAdmin = officeRecord.admin;
        officeRecord.admin = address(0);
        officeRecord.adminPersonId = bytes32(0);
        officeRecord.adminAuthorizationEndsAt = 0;
        officeRecord.lastUpdatedAt = currentTimestamp;

        uint64 nextClerkEpoch = _clerkEpochs[officeId] + 1;
        _clerkEpochs[officeId] = nextClerkEpoch;

        emit OfficeAdminTransferred(officeId, previousAdmin, address(0), 0, currentTimestamp, msg.sender);
        emit OfficeClerksInvalidated(officeId, nextClerkEpoch, currentTimestamp, msg.sender);
    }

    function _transferOfficeAdmin(bytes32 officeId, address newAdmin, bytes32 adminPersonId, uint64 authorizationEndsAt)
        private
    {
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
        officeRecord.adminPersonId = adminPersonId;
        officeRecord.adminAuthorizationEndsAt = authorizationEndsAt;
        officeRecord.lastUpdatedAt = currentTimestamp;

        uint64 nextClerkEpoch = _clerkEpochs[officeId] + 1;
        _clerkEpochs[officeId] = nextClerkEpoch;

        emit OfficeAdminTransferred(
            officeId, previousAdmin, newAdmin, authorizationEndsAt, currentTimestamp, msg.sender
        );
        emit OfficeClerksInvalidated(officeId, nextClerkEpoch, currentTimestamp, msg.sender);
    }

    function _isCurrentAdmin(OfficeTypes.OfficeRecord storage officeRecord, address account)
        private
        view
        returns (bool isAdmin)
    {
        if (account == address(0) || _isAdministrationExpired(officeRecord)) {
            return false;
        }
        if (officeRecord.adminPersonId == bytes32(0)) {
            return officeRecord.admin == account;
        }

        IIdentityRegistry identityRegistry = IIdentityRegistry(_kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY));
        return identityRegistry.hasActiveWalletLink(account)
            && identityRegistry.resolveWalletToPersonId(account) == officeRecord.adminPersonId;
    }

    function _isAdministrationExpired(OfficeTypes.OfficeRecord storage officeRecord)
        private
        view
        returns (bool expired)
    {
        return officeRecord.adminAuthorizationEndsAt != 0 && block.timestamp >= officeRecord.adminAuthorizationEndsAt;
    }

    /// @inheritdoc IOfficeRegistry
    function setClerkStatus(bytes32 officeId, address clerk, bool active) external {
        _requireRegistryAuthority(msg.sender);

        OfficeTypes.OfficeRecord storage officeRecord = _officeRecords[officeId];
        if (officeRecord.officeId == bytes32(0)) {
            revert OfficeNotFound(officeId);
        }
        if (clerk == address(0) || _isCurrentAdmin(officeRecord, clerk)) {
            revert InvalidOfficeMember(clerk);
        }

        OfficeTypes.OfficeMembership storage membership = _clerks[officeId][clerk];
        membership.officeId = officeId;
        membership.member = clerk;
        membership.role = OfficeTypes.OfficeRole.Clerk;
        membership.active = active;
        _clerkMembershipEpochs[officeId][clerk] = _clerkEpochs[officeId];

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
