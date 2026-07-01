// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {CompanyTypes} from "../types/CompanyTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title ICompanyRegistryApp
/// @notice User-facing workflow interface for company incorporation and company registry office actions.
interface ICompanyRegistryApp {
    error InvalidCompanyRegistry(address registryAddress);
    error InvalidCompanyRegistryOffice(bytes32 officeId);
    error InvalidOfficePermissionPolicy(address policyAddress);
    error InvalidOfficeRegistry(address registryAddress);
    error UnauthorizedCompanyRegistryOfficeAction(
        address caller, bytes32 officeId, OfficeTypes.OfficeActionClass actionClass
    );

    function companyRegistry() external view returns (address registryAddress);
    function officeRegistry() external view returns (address registryAddress);
    function officePermissionPolicy() external view returns (address policyAddress);
    function companyRegistryOfficeId() external view returns (bytes32 officeId);
    function submitIncorporation(bytes32 companyId, CompanyTypes.CompanyInput calldata input) external;
    function approveCompany(bytes32 companyId, bytes32 registrationNumberHash) external;
    function rejectCompany(bytes32 companyId, bytes32 reasonHash) external;
    function setCompanyStatus(bytes32 companyId, CompanyTypes.CompanyStatus status, bytes32 reasonHash) external;
    function updateCompanyMetadata(bytes32 companyId, bytes32 metadataHash, bytes32 articlesHash) external;
    function setDirector(bytes32 companyId, address director, bytes32 roleHash, bool active) external;
    function registerShareClass(
        bytes32 companyId,
        bytes32 classId,
        bytes32 metadataHash,
        uint256 authorizedShares,
        uint16 votingWeightBps,
        bool fractional
    ) external;
    function setShareClassStatus(bytes32 companyId, bytes32 classId, bool active) external;
    function issueShares(bytes32 companyId, bytes32 classId, address to, uint256 amount, bytes32 documentHash) external;
    function transferShares(
        bytes32 companyId,
        bytes32 classId,
        address from,
        address to,
        uint256 amount,
        bytes32 documentHash
    ) external;
    function burnShares(bytes32 companyId, bytes32 classId, address from, uint256 amount, bytes32 documentHash) external;
    function recordFiling(bytes32 companyId, bytes32 filingId, CompanyTypes.FilingType filingType, bytes32 documentHash)
        external;
}
