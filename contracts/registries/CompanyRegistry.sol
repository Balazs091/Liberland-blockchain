// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {KernelModule} from "../base/KernelModule.sol";
import {ICompanyRegistry} from "../interfaces/ICompanyRegistry.sol";
import {CompanyTypes} from "../types/CompanyTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title CompanyRegistry
/// @notice Stable fact registry for company records, directors, filings, and official share ledgers.
contract CompanyRegistry is ICompanyRegistry, KernelModule {
    mapping(bytes32 companyId => CompanyTypes.CompanyRecord companyRecord) private _companies;
    mapping(bytes32 nameHash => bytes32 companyId) private _companyByNameHash;
    mapping(bytes32 registrationNumberHash => bytes32 companyId) private _companyByRegistrationNumberHash;
    mapping(bytes32 companyId => mapping(address director => CompanyTypes.DirectorRecord directorRecord)) private
        _directors;
    mapping(bytes32 companyId => mapping(bytes32 classId => CompanyTypes.ShareClassRecord shareClassRecord)) private
        _shareClasses;
    mapping(bytes32 companyId => mapping(bytes32 classId => mapping(address holder => uint256 balance))) private
        _shareBalances;
    mapping(bytes32 filingId => CompanyTypes.FilingRecord filingRecord) private _filings;
    bytes32[] private _companyIds;

    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc ICompanyRegistry
    function getCompany(bytes32 companyId) external view returns (CompanyTypes.CompanyRecord memory record) {
        return _companies[companyId];
    }

    /// @inheritdoc ICompanyRegistry
    function getDirector(bytes32 companyId, address director)
        external
        view
        returns (CompanyTypes.DirectorRecord memory record)
    {
        return _directors[companyId][director];
    }

    /// @inheritdoc ICompanyRegistry
    function getShareClass(bytes32 companyId, bytes32 classId)
        external
        view
        returns (CompanyTypes.ShareClassRecord memory record)
    {
        return _shareClasses[companyId][classId];
    }

    /// @inheritdoc ICompanyRegistry
    function getFiling(bytes32 filingId) external view returns (CompanyTypes.FilingRecord memory record) {
        return _filings[filingId];
    }

    /// @inheritdoc ICompanyRegistry
    function companyExists(bytes32 companyId) public view returns (bool exists) {
        return _companies[companyId].companyId != bytes32(0);
    }

    /// @inheritdoc ICompanyRegistry
    function companyByNameHash(bytes32 nameHash) external view returns (bytes32 companyId) {
        return _companyByNameHash[nameHash];
    }

    /// @inheritdoc ICompanyRegistry
    function companyByRegistrationNumberHash(bytes32 registrationNumberHash) external view returns (bytes32 companyId) {
        return _companyByRegistrationNumberHash[registrationNumberHash];
    }

    /// @inheritdoc ICompanyRegistry
    function shareBalanceOf(bytes32 companyId, bytes32 classId, address holder)
        external
        view
        returns (uint256 balance)
    {
        return _shareBalances[companyId][classId][holder];
    }

    /// @inheritdoc ICompanyRegistry
    function totalCompanyCount() external view returns (uint256 count) {
        return _companyIds.length;
    }

    /// @inheritdoc ICompanyRegistry
    function companyIdAt(uint256 index) external view returns (bytes32 companyId) {
        return _companyIds[index];
    }

    /// @inheritdoc ICompanyRegistry
    function submitCompany(bytes32 companyId, address founder, CompanyTypes.CompanyInput calldata input) external {
        _requireRegistryAuthority(msg.sender);
        _validateNewCompany(companyId, founder, input);

        // A previously rejected id is reusable (its record is fully overwritten below); only a brand-new id is
        // appended to the enumeration so it is never listed twice.
        bool isResubmission = companyExists(companyId);

        uint64 currentTimestamp = uint64(block.timestamp);
        _companies[companyId] = CompanyTypes.CompanyRecord({
            companyId: companyId,
            registrationNumberHash: input.registrationNumberHash,
            nameHash: input.nameHash,
            jurisdictionHash: input.jurisdictionHash,
            registeredOfficeHash: input.registeredOfficeHash,
            metadataHash: input.metadataHash,
            articlesHash: input.articlesHash,
            uboHash: input.uboHash,
            registeredCapital: input.registeredCapital,
            founder: founder,
            status: CompanyTypes.CompanyStatus.Pending,
            activeDirectorCount: 0,
            shareClassCount: 0,
            submittedAt: currentTimestamp,
            approvedAt: 0,
            updatedAt: currentTimestamp
        });
        _companyByNameHash[input.nameHash] = companyId;
        if (input.registrationNumberHash != bytes32(0)) {
            _companyByRegistrationNumberHash[input.registrationNumberHash] = companyId;
        }
        if (!isResubmission) {
            _companyIds.push(companyId);
        }

        emit CompanySubmitted(companyId, input.nameHash, founder, currentTimestamp);
    }

    /// @inheritdoc ICompanyRegistry
    function approveCompany(bytes32 companyId, bytes32 registrationNumberHash) external {
        _requireRegistryAuthority(msg.sender);
        CompanyTypes.CompanyRecord storage companyRecord = _getCompanyRecord(companyId);
        if (companyRecord.status != CompanyTypes.CompanyStatus.Pending) {
            revert InvalidCompanyStatus(companyRecord.status);
        }
        _setRegistrationNumber(companyRecord, registrationNumberHash);

        companyRecord.status = CompanyTypes.CompanyStatus.Active;
        companyRecord.approvedAt = uint64(block.timestamp);
        companyRecord.updatedAt = companyRecord.approvedAt;

        emit CompanyApproved(companyId, registrationNumberHash, companyRecord.approvedAt, msg.sender);
        emit CompanyStatusUpdated(companyId, companyRecord.status, bytes32(0), companyRecord.updatedAt);
    }

    /// @inheritdoc ICompanyRegistry
    function rejectCompany(bytes32 companyId, bytes32 reasonHash) external {
        _requireRegistryAuthority(msg.sender);
        CompanyTypes.CompanyRecord storage companyRecord = _getCompanyRecord(companyId);
        if (companyRecord.status != CompanyTypes.CompanyStatus.Pending || reasonHash == bytes32(0)) {
            revert InvalidCompanyStatus(companyRecord.status);
        }

        companyRecord.status = CompanyTypes.CompanyStatus.Rejected;
        companyRecord.updatedAt = uint64(block.timestamp);
        delete _companyByNameHash[companyRecord.nameHash];
        if (companyRecord.registrationNumberHash != bytes32(0)) {
            delete _companyByRegistrationNumberHash[companyRecord.registrationNumberHash];
        }

        emit CompanyStatusUpdated(companyId, companyRecord.status, reasonHash, companyRecord.updatedAt);
    }

    /// @inheritdoc ICompanyRegistry
    function setCompanyStatus(bytes32 companyId, CompanyTypes.CompanyStatus status, bytes32 reasonHash) external {
        _requireRegistryAuthority(msg.sender);
        CompanyTypes.CompanyRecord storage companyRecord = _getCompanyRecord(companyId);
        // Source-status guard: only operating companies may transition here. Pending is handled by
        // approveCompany/rejectCompany, and Dissolved/Rejected are terminal (no resurrection).
        CompanyTypes.CompanyStatus currentStatus = companyRecord.status;
        if (
            currentStatus != CompanyTypes.CompanyStatus.Active
                && currentStatus != CompanyTypes.CompanyStatus.ComplianceWarning
                && currentStatus != CompanyTypes.CompanyStatus.Suspended
                && currentStatus != CompanyTypes.CompanyStatus.Dissolving
        ) {
            revert InvalidCompanyStatus(currentStatus);
        }
        if (
            status == CompanyTypes.CompanyStatus.Undefined || status == CompanyTypes.CompanyStatus.Pending
                || status == CompanyTypes.CompanyStatus.Rejected || reasonHash == bytes32(0)
        ) {
            revert InvalidCompanyStatus(status);
        }
        if (status == CompanyTypes.CompanyStatus.Active && companyRecord.registrationNumberHash == bytes32(0)) {
            revert InvalidRegistrationNumber(companyRecord.registrationNumberHash);
        }

        companyRecord.status = status;
        companyRecord.updatedAt = uint64(block.timestamp);

        emit CompanyStatusUpdated(companyId, status, reasonHash, companyRecord.updatedAt);
    }

    /// @inheritdoc ICompanyRegistry
    function updateCompanyMetadata(bytes32 companyId, bytes32 metadataHash, bytes32 articlesHash) external {
        _requireRegistryAuthority(msg.sender);
        CompanyTypes.CompanyRecord storage companyRecord = _getMutableCompanyRecord(companyId);
        if (metadataHash == bytes32(0) || articlesHash == bytes32(0)) {
            revert InvalidCompanyPayload(companyId);
        }

        companyRecord.metadataHash = metadataHash;
        companyRecord.articlesHash = articlesHash;
        companyRecord.updatedAt = uint64(block.timestamp);

        emit CompanyMetadataUpdated(companyId, metadataHash, articlesHash, companyRecord.updatedAt, msg.sender);
    }

    /// @inheritdoc ICompanyRegistry
    function setDirector(bytes32 companyId, address director, bytes32 roleHash, bool active) external {
        _requireRegistryAuthority(msg.sender);
        CompanyTypes.CompanyRecord storage companyRecord = _getMutableCompanyRecord(companyId);
        if (director == address(0) || (active && roleHash == bytes32(0))) {
            revert InvalidDirector(director);
        }

        CompanyTypes.DirectorRecord storage directorRecord = _directors[companyId][director];
        uint64 currentTimestamp = uint64(block.timestamp);
        if (active) {
            if (!directorRecord.active) {
                companyRecord.activeDirectorCount += 1;
                directorRecord.appointedAt = currentTimestamp;
            }
            directorRecord.director = director;
            directorRecord.roleHash = roleHash;
            directorRecord.active = true;
            directorRecord.removedAt = 0;
        } else {
            if (directorRecord.director == address(0) || !directorRecord.active) {
                revert InvalidDirector(director);
            }
            directorRecord.active = false;
            directorRecord.removedAt = currentTimestamp;
            companyRecord.activeDirectorCount -= 1;
        }

        companyRecord.updatedAt = currentTimestamp;
        emit DirectorStatusUpdated(companyId, director, active, directorRecord.roleHash, currentTimestamp);
    }

    /// @inheritdoc ICompanyRegistry
    function registerShareClass(
        bytes32 companyId,
        bytes32 classId,
        bytes32 metadataHash,
        uint256 authorizedShares,
        uint16 votingWeightBps,
        bool fractional
    ) external {
        _requireRegistryAuthority(msg.sender);
        CompanyTypes.CompanyRecord storage companyRecord = _getOperatingCompanyRecord(companyId);
        if (classId == bytes32(0) || metadataHash == bytes32(0) || authorizedShares == 0 || votingWeightBps > 10_000) {
            revert InvalidShareClass(classId);
        }
        if (_shareClasses[companyId][classId].classId != bytes32(0)) {
            revert ShareClassAlreadyRegistered(companyId, classId);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        _shareClasses[companyId][classId] = CompanyTypes.ShareClassRecord({
            companyId: companyId,
            classId: classId,
            metadataHash: metadataHash,
            authorizedShares: authorizedShares,
            issuedShares: 0,
            votingWeightBps: votingWeightBps,
            fractional: fractional,
            active: true,
            createdAt: currentTimestamp,
            updatedAt: currentTimestamp
        });
        companyRecord.shareClassCount += 1;
        companyRecord.updatedAt = currentTimestamp;

        emit ShareClassRegistered(companyId, classId, authorizedShares, currentTimestamp);
    }

    /// @inheritdoc ICompanyRegistry
    function setShareClassStatus(bytes32 companyId, bytes32 classId, bool active) external {
        _requireRegistryAuthority(msg.sender);
        _getMutableCompanyRecord(companyId);
        CompanyTypes.ShareClassRecord storage shareClassRecord = _getShareClassRecord(companyId, classId);
        shareClassRecord.active = active;
        shareClassRecord.updatedAt = uint64(block.timestamp);

        emit ShareClassStatusUpdated(companyId, classId, active, shareClassRecord.updatedAt);
    }

    /// @inheritdoc ICompanyRegistry
    function issueShares(bytes32 companyId, bytes32 classId, address to, uint256 amount, bytes32 documentHash)
        external
    {
        _requireRegistryAuthority(msg.sender);
        _getOperatingCompanyRecord(companyId);
        CompanyTypes.ShareClassRecord storage shareClassRecord = _getActiveShareClassRecord(companyId, classId);
        if (to == address(0) || amount == 0 || documentHash == bytes32(0)) {
            revert InvalidShareTransfer(address(0), to, amount);
        }
        uint256 requestedSupply = shareClassRecord.issuedShares + amount;
        if (requestedSupply > shareClassRecord.authorizedShares) {
            revert ShareTransferExceedsSupply(companyId, classId, shareClassRecord.authorizedShares, requestedSupply);
        }

        shareClassRecord.issuedShares = requestedSupply;
        shareClassRecord.updatedAt = uint64(block.timestamp);
        _shareBalances[companyId][classId][to] += amount;

        emit SharesIssued(companyId, classId, to, amount, documentHash);
    }

    /// @inheritdoc ICompanyRegistry
    function transferShares(
        bytes32 companyId,
        bytes32 classId,
        address from,
        address to,
        uint256 amount,
        bytes32 documentHash
    ) external {
        _requireRegistryAuthority(msg.sender);
        _getOperatingCompanyRecord(companyId);
        _getActiveShareClassRecord(companyId, classId);
        if (from == address(0) || to == address(0) || from == to || amount == 0 || documentHash == bytes32(0)) {
            revert InvalidShareTransfer(from, to, amount);
        }
        _debitShares(companyId, classId, from, amount);
        _shareBalances[companyId][classId][to] += amount;

        emit SharesTransferred(companyId, classId, from, to, amount, documentHash);
    }

    /// @inheritdoc ICompanyRegistry
    function burnShares(bytes32 companyId, bytes32 classId, address from, uint256 amount, bytes32 documentHash)
        external
    {
        _requireRegistryAuthority(msg.sender);
        _getOperatingCompanyRecord(companyId);
        CompanyTypes.ShareClassRecord storage shareClassRecord = _getActiveShareClassRecord(companyId, classId);
        if (from == address(0) || amount == 0 || documentHash == bytes32(0)) {
            revert InvalidShareTransfer(from, address(0), amount);
        }
        _debitShares(companyId, classId, from, amount);
        shareClassRecord.issuedShares -= amount;
        shareClassRecord.updatedAt = uint64(block.timestamp);

        emit SharesBurned(companyId, classId, from, amount, documentHash);
    }

    /// @inheritdoc ICompanyRegistry
    function recordFiling(
        bytes32 companyId,
        bytes32 filingId,
        CompanyTypes.FilingType filingType,
        bytes32 documentHash,
        address filedBy
    ) external {
        _requireRegistryAuthority(msg.sender);
        _getMutableCompanyRecord(companyId);
        if (
            filingId == bytes32(0) || filingType == CompanyTypes.FilingType.Undefined || documentHash == bytes32(0)
                || filedBy == address(0)
        ) {
            revert InvalidFilingPayload(filingId);
        }
        if (_filings[filingId].filingId != bytes32(0)) {
            revert FilingAlreadyRegistered(filingId);
        }

        _filings[filingId] = CompanyTypes.FilingRecord({
            filingId: filingId,
            companyId: companyId,
            filingType: filingType,
            documentHash: documentHash,
            filedBy: filedBy,
            filedAt: uint64(block.timestamp)
        });

        emit FilingRecorded(companyId, filingId, filingType, documentHash, filedBy);
    }

    function _validateNewCompany(bytes32 companyId, address founder, CompanyTypes.CompanyInput calldata input)
        private
        view
    {
        if (
            companyId == bytes32(0) || founder == address(0) || input.nameHash == bytes32(0)
                || input.jurisdictionHash == bytes32(0) || input.registeredOfficeHash == bytes32(0)
                || input.metadataHash == bytes32(0) || input.articlesHash == bytes32(0) || input.uboHash == bytes32(0)
                || input.registeredCapital == 0
        ) {
            revert InvalidCompanyPayload(companyId);
        }
        // An existing id may only be reused when its prior submission was rejected; live/pending ids are immutable.
        if (companyExists(companyId) && _companies[companyId].status != CompanyTypes.CompanyStatus.Rejected) {
            revert InvalidCompanyPayload(companyId);
        }
        bytes32 existingCompanyId = _companyByNameHash[input.nameHash];
        if (existingCompanyId != bytes32(0)) {
            revert CompanyNameAlreadyRegistered(input.nameHash, existingCompanyId);
        }
        if (input.registrationNumberHash != bytes32(0)) {
            existingCompanyId = _companyByRegistrationNumberHash[input.registrationNumberHash];
            if (existingCompanyId != bytes32(0)) {
                revert RegistrationNumberAlreadyRegistered(input.registrationNumberHash, existingCompanyId);
            }
        }
    }

    function _setRegistrationNumber(CompanyTypes.CompanyRecord storage companyRecord, bytes32 registrationNumberHash)
        private
    {
        if (registrationNumberHash == bytes32(0)) {
            revert InvalidRegistrationNumber(registrationNumberHash);
        }
        if (
            companyRecord.registrationNumberHash != bytes32(0)
                && companyRecord.registrationNumberHash != registrationNumberHash
        ) {
            revert InvalidRegistrationNumber(registrationNumberHash);
        }

        bytes32 existingCompanyId = _companyByRegistrationNumberHash[registrationNumberHash];
        if (existingCompanyId != bytes32(0) && existingCompanyId != companyRecord.companyId) {
            revert RegistrationNumberAlreadyRegistered(registrationNumberHash, existingCompanyId);
        }

        companyRecord.registrationNumberHash = registrationNumberHash;
        _companyByRegistrationNumberHash[registrationNumberHash] = companyRecord.companyId;
    }

    function _debitShares(bytes32 companyId, bytes32 classId, address holder, uint256 amount) private {
        uint256 balance = _shareBalances[companyId][classId][holder];
        if (balance < amount) {
            revert ShareTransferExceedsBalance(companyId, classId, holder, balance, amount);
        }
        _shareBalances[companyId][classId][holder] = balance - amount;
    }

    function _getCompanyRecord(bytes32 companyId)
        private
        view
        returns (CompanyTypes.CompanyRecord storage companyRecord)
    {
        companyRecord = _companies[companyId];
        if (companyRecord.companyId == bytes32(0)) {
            revert CompanyNotFound(companyId);
        }
    }

    function _getMutableCompanyRecord(bytes32 companyId)
        private
        view
        returns (CompanyTypes.CompanyRecord storage companyRecord)
    {
        companyRecord = _getCompanyRecord(companyId);
        if (
            companyRecord.status == CompanyTypes.CompanyStatus.Dissolved
                || companyRecord.status == CompanyTypes.CompanyStatus.Rejected
        ) {
            revert InvalidCompanyStatus(companyRecord.status);
        }
    }

    function _getOperatingCompanyRecord(bytes32 companyId)
        private
        view
        returns (CompanyTypes.CompanyRecord storage companyRecord)
    {
        companyRecord = _getCompanyRecord(companyId);
        if (
            companyRecord.status != CompanyTypes.CompanyStatus.Active
                && companyRecord.status != CompanyTypes.CompanyStatus.ComplianceWarning
        ) {
            revert InvalidCompanyStatus(companyRecord.status);
        }
    }

    function _getShareClassRecord(bytes32 companyId, bytes32 classId)
        private
        view
        returns (CompanyTypes.ShareClassRecord storage shareClassRecord)
    {
        shareClassRecord = _shareClasses[companyId][classId];
        if (shareClassRecord.classId == bytes32(0)) {
            revert ShareClassNotFound(companyId, classId);
        }
    }

    function _getActiveShareClassRecord(bytes32 companyId, bytes32 classId)
        private
        view
        returns (CompanyTypes.ShareClassRecord storage shareClassRecord)
    {
        shareClassRecord = _getShareClassRecord(companyId, classId);
        if (!shareClassRecord.active) {
            revert InvalidShareClass(classId);
        }
    }

    function _requireRegistryAuthority(address caller) private view {
        if (caller != _kernel.getModule(KernelModuleIds.COMPANY_REGISTRY_AUTHORITY)) {
            revert UnauthorizedCompanyRegistryCaller(caller);
        }
    }
}
