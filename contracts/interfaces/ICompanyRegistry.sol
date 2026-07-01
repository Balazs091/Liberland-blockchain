// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IKernelModule} from "./IKernelModule.sol";
import {CompanyTypes} from "../types/CompanyTypes.sol";

/// @title ICompanyRegistry
/// @notice Stable fact registry interface for company records, directors, filings, and official share ledgers.
interface ICompanyRegistry is IKernelModule {
    error CompanyAlreadyRegistered(bytes32 companyId);
    error CompanyNameAlreadyRegistered(bytes32 nameHash, bytes32 companyId);
    error CompanyNotFound(bytes32 companyId);
    error FilingAlreadyRegistered(bytes32 filingId);
    error FilingNotFound(bytes32 filingId);
    error InvalidCompanyPayload(bytes32 companyId);
    error InvalidCompanyStatus(CompanyTypes.CompanyStatus status);
    error InvalidDirector(address director);
    error InvalidFilingPayload(bytes32 filingId);
    error InvalidRegistrationNumber(bytes32 registrationNumberHash);
    error InvalidShareClass(bytes32 classId);
    error InvalidShareTransfer(address from, address to, uint256 amount);
    error RegistrationNumberAlreadyRegistered(bytes32 registrationNumberHash, bytes32 companyId);
    error ShareClassAlreadyRegistered(bytes32 companyId, bytes32 classId);
    error ShareClassNotFound(bytes32 companyId, bytes32 classId);
    error ShareTransferExceedsBalance(
        bytes32 companyId, bytes32 classId, address holder, uint256 balance, uint256 amount
    );
    error ShareTransferExceedsSupply(
        bytes32 companyId, bytes32 classId, uint256 authorizedShares, uint256 requestedShares
    );
    error UnauthorizedCompanyRegistryCaller(address caller);

    event CompanySubmitted(
        bytes32 indexed companyId, bytes32 indexed nameHash, address indexed founder, uint64 submittedAt
    );
    event CompanyApproved(
        bytes32 indexed companyId, bytes32 indexed registrationNumberHash, uint64 approvedAt, address indexed recordedBy
    );
    event CompanyStatusUpdated(
        bytes32 indexed companyId,
        CompanyTypes.CompanyStatus indexed status,
        bytes32 indexed reasonHash,
        uint64 updatedAt
    );
    event CompanyMetadataUpdated(
        bytes32 indexed companyId,
        bytes32 metadataHash,
        bytes32 articlesHash,
        uint64 updatedAt,
        address indexed recordedBy
    );
    event DirectorStatusUpdated(
        bytes32 indexed companyId, address indexed director, bool active, bytes32 roleHash, uint64 updatedAt
    );
    event ShareClassRegistered(
        bytes32 indexed companyId, bytes32 indexed classId, uint256 authorizedShares, uint64 registeredAt
    );
    event ShareClassStatusUpdated(bytes32 indexed companyId, bytes32 indexed classId, bool active, uint64 updatedAt);
    event SharesIssued(
        bytes32 indexed companyId, bytes32 indexed classId, address indexed to, uint256 amount, bytes32 documentHash
    );
    event SharesTransferred(
        bytes32 indexed companyId,
        bytes32 indexed classId,
        address indexed from,
        address to,
        uint256 amount,
        bytes32 documentHash
    );
    event SharesBurned(
        bytes32 indexed companyId, bytes32 indexed classId, address indexed from, uint256 amount, bytes32 documentHash
    );
    event FilingRecorded(
        bytes32 indexed companyId,
        bytes32 indexed filingId,
        CompanyTypes.FilingType indexed filingType,
        bytes32 documentHash,
        address filedBy
    );

    function getCompany(bytes32 companyId) external view returns (CompanyTypes.CompanyRecord memory record);
    function getDirector(bytes32 companyId, address director)
        external
        view
        returns (CompanyTypes.DirectorRecord memory record);
    function getShareClass(bytes32 companyId, bytes32 classId)
        external
        view
        returns (CompanyTypes.ShareClassRecord memory record);
    function getFiling(bytes32 filingId) external view returns (CompanyTypes.FilingRecord memory record);
    function companyExists(bytes32 companyId) external view returns (bool exists);
    function companyByNameHash(bytes32 nameHash) external view returns (bytes32 companyId);
    function companyByRegistrationNumberHash(bytes32 registrationNumberHash) external view returns (bytes32 companyId);
    function shareBalanceOf(bytes32 companyId, bytes32 classId, address holder) external view returns (uint256 balance);
    function totalCompanyCount() external view returns (uint256 count);
    function companyIdAt(uint256 index) external view returns (bytes32 companyId);
    function submitCompany(bytes32 companyId, address founder, CompanyTypes.CompanyInput calldata input) external;
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
    function recordFiling(
        bytes32 companyId,
        bytes32 filingId,
        CompanyTypes.FilingType filingType,
        bytes32 documentHash,
        address filedBy
    ) external;
}
