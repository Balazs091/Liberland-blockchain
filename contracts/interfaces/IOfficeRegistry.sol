// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IKernelModule} from "./IKernelModule.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title IOfficeRegistry
/// @notice Stable fact registry for office definitions and office role assignments.
interface IOfficeRegistry is IKernelModule {
    error InvalidOfficeAdmin(address admin);
    error InvalidOfficeId(bytes32 officeId);
    error InvalidOfficeKind(OfficeTypes.OfficeKind kind);
    error InvalidOfficeMember(address member);
    error InvalidOfficeAdminAuthorizationEnd(uint64 authorizationEndsAt, uint64 currentTime);
    error OfficeAlreadyRegistered(bytes32 officeId);
    error OfficeNotFound(bytes32 officeId);
    error UnauthorizedOfficeRegistryCaller(address caller);

    event OfficeRegistered(
        bytes32 indexed officeId,
        OfficeTypes.OfficeKind indexed kind,
        address indexed admin,
        string name,
        uint64 recordedAt,
        address recordedBy
    );

    event OfficeAdminTransferred(
        bytes32 indexed officeId,
        address indexed previousAdmin,
        address indexed newAdmin,
        uint64 authorizationEndsAt,
        uint64 transferredAt,
        address transferredBy
    );

    event OfficeClerksInvalidated(
        bytes32 indexed officeId, uint64 indexed clerkEpoch, uint64 invalidatedAt, address indexed invalidatedBy
    );

    event OfficeClerkStatusUpdated(
        bytes32 indexed officeId, address indexed clerk, bool active, uint64 updatedAt, address indexed updatedBy
    );

    event OfficeRenamed(
        bytes32 indexed officeId, string previousName, string newName, uint64 updatedAt, address indexed updatedBy
    );

    event OfficeActiveStatusUpdated(bytes32 indexed officeId, bool active, uint64 updatedAt, address indexed updatedBy);

    function getOfficeRecord(bytes32 officeId) external view returns (OfficeTypes.OfficeRecord memory officeRecord);
    function getClerkRecord(bytes32 officeId, address clerk)
        external
        view
        returns (OfficeTypes.OfficeMembership memory membership);
    function officeExists(bytes32 officeId) external view returns (bool exists);
    function totalOfficeCount() external view returns (uint256 count);
    function officeIdAt(uint256 index) external view returns (bytes32 officeId);
    function roleOf(bytes32 officeId, address account) external view returns (OfficeTypes.OfficeRole role);
    function isOfficeAdmin(bytes32 officeId, address account) external view returns (bool isAdmin);
    /// @notice Checks the current admin appointment without requiring the office itself to be active.
    function isOfficeAdminAppointment(bytes32 officeId, address account) external view returns (bool isAdmin);
    function isOfficeClerk(bytes32 officeId, address account) external view returns (bool isClerk);
    function registerOffice(bytes32 officeId, OfficeTypes.OfficeKind kind, string calldata name, address admin) external;
    function transferOfficeAdmin(bytes32 officeId, address newAdmin) external;
    /// @notice Transfers an office admin role that automatically expires at `authorizationEndsAt`.
    /// @dev Used by CabinetApp so operational ministry authority cannot outlive the ministerial term.
    function transferOfficeAdminForTerm(
        bytes32 officeId,
        address newAdmin,
        bytes32 adminPersonId,
        uint64 authorizationEndsAt
    ) external;
    /// @notice Removes the current admin and invalidates every clerk appointment for the office.
    function revokeOfficeAdmin(bytes32 officeId) external;
    function setClerkStatus(bytes32 officeId, address clerk, bool active) external;
    function renameOffice(bytes32 officeId, string calldata newName) external;
    function setOfficeActive(bytes32 officeId, bool active) external;
}
