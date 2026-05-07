// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title IOfficeRegistry
/// @notice Stable fact registry for office definitions and office role assignments.
interface IOfficeRegistry {
    error InvalidOfficeAdmin(address admin);
    error InvalidOfficeId(bytes32 officeId);
    error InvalidOfficeKind(OfficeTypes.OfficeKind kind);
    error InvalidOfficeMember(address member);
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
        uint64 transferredAt,
        address transferredBy
    );

    event OfficeClerkStatusUpdated(
        bytes32 indexed officeId, address indexed clerk, bool active, uint64 updatedAt, address indexed updatedBy
    );

    function kernel() external view returns (address kernelAddress);
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
    function isOfficeClerk(bytes32 officeId, address account) external view returns (bool isClerk);
    function registerOffice(bytes32 officeId, OfficeTypes.OfficeKind kind, string calldata name, address admin) external;
    function transferOfficeAdmin(bytes32 officeId, address newAdmin) external;
    function setClerkStatus(bytes32 officeId, address clerk, bool active) external;
}
