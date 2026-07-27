// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IDecisionApp} from "../interfaces/IDecisionApp.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILLMStakingVault} from "../interfaces/ILLMStakingVault.sol";
import {IMinistryTreasury} from "../interfaces/IMinistryTreasury.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {DecisionTypes} from "../types/DecisionTypes.sol";
import {ElectionTypes} from "../types/ElectionTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title DecisionApp
/// @notice Bounded Congress and ministry decisions for wallet-funded ERC20 movement, office clerk decisions, and
///         Congress-approved creation of new government offices and ministries. Registered as the kernel
///         DECISION_APP module pointer, the OfficeRegistry accepts it as a registry authority, which is what lets a
///         Congress majority register new offices after the office bootstrap authority has been retired.
contract DecisionApp is IDecisionApp, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ICongressCandidateRegistry private immutable _congressCandidateRegistry;
    IIdentityRegistry private immutable _identityRegistry;
    IOfficeRegistry private immutable _officeRegistry;
    IStakeRegistry private immutable _stakeRegistry;
    IERC20 private immutable _llmToken;
    ILLMStakingVault private immutable _stakingVault;

    mapping(bytes32 decisionId => DecisionTypes.DecisionRecord decisionRecord) private _decisionRecords;
    mapping(bytes32 decisionId => mapping(address member => bool supported)) private _congressSupports;
    mapping(bytes32 decisionId => bool authorized) private _congressSourceAuthorizations;

    /// @param congressCandidateRegistryAddress The Congress registry used for active-member checks.
    /// @param identityRegistryAddress The identity registry used for stake-recipient validation.
    /// @param officeRegistryAddress The office registry used for ministry role checks and clerk decisions.
    /// @param stakingVaultAddress The canonical LLM vault used by transfer-and-stake decisions.
    constructor(
        address congressCandidateRegistryAddress,
        address identityRegistryAddress,
        address officeRegistryAddress,
        address stakingVaultAddress
    ) {
        if (congressCandidateRegistryAddress == address(0) || congressCandidateRegistryAddress.code.length == 0) {
            revert InvalidRegistry(congressCandidateRegistryAddress);
        }
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidRegistry(identityRegistryAddress);
        }
        if (officeRegistryAddress == address(0) || officeRegistryAddress.code.length == 0) {
            revert InvalidRegistry(officeRegistryAddress);
        }
        if (stakingVaultAddress == address(0) || stakingVaultAddress.code.length == 0) {
            revert InvalidRegistry(stakingVaultAddress);
        }

        ILLMStakingVault stakingVault_ = ILLMStakingVault(stakingVaultAddress);
        address stakeRegistryAddress = stakingVault_.stakeRegistry();
        address llmTokenAddress = stakingVault_.token();

        ICongressCandidateRegistry congressCandidateRegistry_ =
            ICongressCandidateRegistry(congressCandidateRegistryAddress);
        address kernelAddress = congressCandidateRegistry_.kernel();
        if (
            IIdentityRegistry(identityRegistryAddress).kernel() != kernelAddress
                || IOfficeRegistry(officeRegistryAddress).kernel() != kernelAddress
                || IStakeRegistry(stakeRegistryAddress).kernel() != kernelAddress
        ) {
            revert InvalidRegistry(address(0));
        }

        _congressCandidateRegistry = congressCandidateRegistry_;
        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _officeRegistry = IOfficeRegistry(officeRegistryAddress);
        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _llmToken = IERC20(llmTokenAddress);
        _stakingVault = stakingVault_;
    }

    /// @inheritdoc IDecisionApp
    function congressCandidateRegistry() external view returns (address registryAddress) {
        return address(_congressCandidateRegistry);
    }

    /// @inheritdoc IDecisionApp
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc IDecisionApp
    function officeRegistry() external view returns (address registryAddress) {
        return address(_officeRegistry);
    }

    /// @inheritdoc IDecisionApp
    function stakeRegistry() external view returns (address registryAddress) {
        return address(_stakeRegistry);
    }

    /// @inheritdoc IDecisionApp
    function llmToken() external view returns (address tokenAddress) {
        return address(_llmToken);
    }

    /// @inheritdoc IDecisionApp
    function stakingVault() external view returns (address vaultAddress) {
        return address(_stakingVault);
    }

    /// @inheritdoc IDecisionApp
    function getDecision(bytes32 decisionId) external view returns (DecisionTypes.DecisionRecord memory record) {
        return _decisionRecords[decisionId];
    }

    /// @inheritdoc IDecisionApp
    function isCongressDecisionSourceAuthorized(bytes32 decisionId) external view returns (bool authorized) {
        return _congressSourceAuthorizations[decisionId];
    }

    /// @inheritdoc IDecisionApp
    function authorizeCongressDecisionSource(bytes32 decisionId) external {
        DecisionTypes.DecisionRecord storage record = _requirePreparedDecision(decisionId);
        if (record.scope != DecisionTypes.DecisionScope.Congress || record.source == address(0)) {
            revert InvalidDecisionAction(record.action);
        }
        _requireCongressDecisionTerm(record);
        if (msg.sender != record.source) {
            revert CongressDecisionSourceNotAuthorized(decisionId, msg.sender);
        }

        _congressSourceAuthorizations[decisionId] = true;
        emit CongressDecisionSourceAuthorizationUpdated(decisionId, msg.sender, true, uint64(block.timestamp));
    }

    /// @inheritdoc IDecisionApp
    function revokeCongressDecisionSource(bytes32 decisionId) external {
        DecisionTypes.DecisionRecord storage record = _requirePreparedDecision(decisionId);
        if (record.scope != DecisionTypes.DecisionScope.Congress || msg.sender != record.source) {
            revert CongressDecisionSourceNotAuthorized(decisionId, msg.sender);
        }

        _congressSourceAuthorizations[decisionId] = false;
        emit CongressDecisionSourceAuthorizationUpdated(decisionId, msg.sender, false, uint64(block.timestamp));
    }

    /// @inheritdoc IDecisionApp
    function hasCongressSupported(bytes32 decisionId, address member) external view returns (bool supported) {
        return _congressSupports[decisionId][member];
    }

    /// @inheritdoc IDecisionApp
    function requiredCongressSupport() external view returns (uint32 supportRequired) {
        return _requiredCongressSupport();
    }

    /// @inheritdoc IDecisionApp
    function createCongressTokenTransferDecision(
        bytes32 decisionId,
        address source,
        address token,
        address recipient,
        uint256 amount,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external {
        _requireActiveCongressMember(msg.sender);
        _requireNewDecisionId(decisionId);
        _validateTokenTransfer(source, token, recipient, amount);

        ElectionTypes.CongressOfficeTerm memory term = _congressCandidateRegistry.getCurrentOfficeTerm();
        uint32 supportRequired = _requiredCongressSupport(term);
        uint64 preparedAt = uint64(block.timestamp);

        DecisionTypes.DecisionRecord storage record = _decisionRecords[decisionId];
        record.decisionId = decisionId;
        record.scope = DecisionTypes.DecisionScope.Congress;
        record.action = DecisionTypes.DecisionAction.ERC20Transfer;
        record.status = DecisionTypes.DecisionStatus.Prepared;
        record.congressCycleId = term.cycleId;
        record.preparedBy = msg.sender;
        record.source = source;
        record.token = token;
        record.recipient = recipient;
        record.amount = amount;
        record.metadataHash = metadataHash;
        record.metadataURI = metadataURI;
        record.supportRequired = supportRequired;
        record.preparedAt = preparedAt;

        if (source == msg.sender) {
            _congressSourceAuthorizations[decisionId] = true;
            emit CongressDecisionSourceAuthorizationUpdated(decisionId, source, true, preparedAt);
        }

        _emitCongressDecisionPrepared(decisionId);

        _recordCongressSupport(decisionId, msg.sender);
    }

    /// @inheritdoc IDecisionApp
    function createCongressRegisterOfficeDecision(
        bytes32 decisionId,
        bytes32 officeId,
        OfficeTypes.OfficeKind kind,
        string calldata name,
        address admin,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external {
        _requireActiveCongressMember(msg.sender);
        _requireNewDecisionId(decisionId);
        _validateOfficeRegistration(officeId, kind, name, admin);

        ElectionTypes.CongressOfficeTerm memory term = _congressCandidateRegistry.getCurrentOfficeTerm();
        uint32 supportRequired = _requiredCongressSupport(term);
        uint64 preparedAt = uint64(block.timestamp);

        DecisionTypes.DecisionRecord storage record = _decisionRecords[decisionId];
        record.decisionId = decisionId;
        record.scope = DecisionTypes.DecisionScope.Congress;
        record.action = DecisionTypes.DecisionAction.RegisterOffice;
        record.status = DecisionTypes.DecisionStatus.Prepared;
        record.congressCycleId = term.cycleId;
        record.preparedBy = msg.sender;
        record.officeId = officeId;
        record.officeKind = kind;
        record.officeName = name;
        record.recipient = admin;
        record.metadataHash = metadataHash;
        record.metadataURI = metadataURI;
        record.supportRequired = supportRequired;
        record.preparedAt = preparedAt;

        emit CongressRegisterOfficeDecisionPrepared(
            decisionId, officeId, msg.sender, kind, admin, supportRequired, metadataHash, preparedAt
        );

        _recordCongressSupport(decisionId, msg.sender);
    }

    /// @inheritdoc IDecisionApp
    function createCongressFundMinistryDecision(
        bytes32 decisionId,
        bytes32 officeId,
        address source,
        address token,
        uint256 amount,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external {
        _requireActiveCongressMember(msg.sender);
        _requireNewDecisionId(decisionId);
        _validateMinistryFunding(officeId, source, token, amount);

        ElectionTypes.CongressOfficeTerm memory term = _congressCandidateRegistry.getCurrentOfficeTerm();
        uint32 supportRequired = _requiredCongressSupport(term);
        uint64 preparedAt = uint64(block.timestamp);

        DecisionTypes.DecisionRecord storage record = _decisionRecords[decisionId];
        record.decisionId = decisionId;
        record.scope = DecisionTypes.DecisionScope.Congress;
        record.action = DecisionTypes.DecisionAction.FundMinistry;
        record.status = DecisionTypes.DecisionStatus.Prepared;
        record.congressCycleId = term.cycleId;
        record.preparedBy = msg.sender;
        record.officeId = officeId;
        record.source = source;
        record.token = token;
        record.amount = amount;
        record.metadataHash = metadataHash;
        record.metadataURI = metadataURI;
        record.supportRequired = supportRequired;
        record.preparedAt = preparedAt;

        if (source == msg.sender) {
            _congressSourceAuthorizations[decisionId] = true;
            emit CongressDecisionSourceAuthorizationUpdated(decisionId, source, true, preparedAt);
        }

        emit CongressFundMinistryDecisionPrepared(
            decisionId, officeId, msg.sender, token, amount, supportRequired, metadataHash, preparedAt
        );

        _recordCongressSupport(decisionId, msg.sender);
    }

    /// @inheritdoc IDecisionApp
    function supportCongressDecision(bytes32 decisionId) external {
        _recordCongressSupport(decisionId, msg.sender);
    }

    /// @inheritdoc IDecisionApp
    function revokeCongressDecisionSupport(bytes32 decisionId) external {
        DecisionTypes.DecisionRecord storage record = _requirePreparedDecision(decisionId);
        if (record.scope != DecisionTypes.DecisionScope.Congress) {
            revert InvalidDecisionAction(record.action);
        }
        _requireCongressDecisionTerm(record);
        if (!_congressSupports[decisionId][msg.sender]) {
            return;
        }

        _congressSupports[decisionId][msg.sender] = false;
        record.supportCount -= 1;

        emit CongressDecisionSupportRemoved(
            decisionId, msg.sender, record.supportCount, record.supportRequired, uint64(block.timestamp)
        );
    }

    /// @inheritdoc IDecisionApp
    function executeCongressDecision(bytes32 decisionId) external nonReentrant {
        DecisionTypes.DecisionRecord storage record = _requirePreparedDecision(decisionId);
        if (record.scope != DecisionTypes.DecisionScope.Congress) {
            revert InvalidDecisionAction(record.action);
        }
        _requireCongressDecisionTerm(record);
        // Re-verify support against the *current* Congress roster at execution: support from members who have since
        // left the body no longer counts, and a backfilled seat cannot double-count with its predecessor. The bar
        // (supportRequired) stays snapshotted from the preparing term.
        uint32 liveSupport = _liveCongressSupport(decisionId);
        if (liveSupport < record.supportRequired) {
            revert CongressDecisionNotApproved(decisionId, liveSupport, record.supportRequired);
        }

        DecisionTypes.DecisionAction action = record.action;
        if (
            action != DecisionTypes.DecisionAction.ERC20Transfer
                && action != DecisionTypes.DecisionAction.RegisterOffice
                && action != DecisionTypes.DecisionAction.FundMinistry
        ) {
            revert InvalidDecisionAction(action);
        }
        if (
            (action == DecisionTypes.DecisionAction.ERC20Transfer
                    || action == DecisionTypes.DecisionAction.FundMinistry)
                && !_congressSourceAuthorizations[decisionId]
        ) {
            revert CongressDecisionSourceNotAuthorized(decisionId, record.source);
        }

        // Effects before interactions: finalize status before any external call so a reentrant/hook-bearing
        // token cannot re-enter while the decision is still Prepared.
        _markExecuted(record, msg.sender);

        if (action == DecisionTypes.DecisionAction.ERC20Transfer) {
            IERC20(record.token).safeTransferFrom(record.source, record.recipient, record.amount);
        } else if (action == DecisionTypes.DecisionAction.FundMinistry) {
            // Credit the office directly: the MinistryTreasury pulls the source's approved tokens in a single
            // transfer (this app is its gating funding authority, so only a Congress-approved decision can trigger
            // the pull). Resolving the treasury live means a governed repoint is honored without changing this app.
            address ministryTreasury =
                IConstitutionKernel(_congressCandidateRegistry.kernel()).getModule(KernelModuleIds.MINISTRY_TREASURY);
            IMinistryTreasury(ministryTreasury).fund(record.officeId, record.token, record.source, record.amount);
        } else {
            // registerOffice is a trusted intra-system call into the OfficeRegistry (no external hooks); it
            // re-validates uniqueness and reverts if the office id was taken between preparation and execution.
            _officeRegistry.registerOffice(record.officeId, record.officeKind, record.officeName, record.recipient);
        }
    }

    /// @inheritdoc IDecisionApp
    function prepareMinistryTokenTransferDecision(
        bytes32 officeId,
        bytes32 decisionId,
        address token,
        address recipient,
        uint256 amount,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external {
        OfficeTypes.OfficeRecord memory officeRecord = _requireMinistryPreparer(officeId, msg.sender);
        _requireNewDecisionId(decisionId);
        _validateTokenTransfer(officeRecord.admin, token, recipient, amount);

        DecisionTypes.DecisionRecord storage record = _storeBaseMinistryDecision(
            decisionId,
            officeId,
            DecisionTypes.DecisionAction.ERC20Transfer,
            officeRecord.admin,
            metadataHash,
            metadataURI
        );
        record.token = token;
        record.recipient = recipient;
        record.amount = amount;

        _emitMinistryDecisionPrepared(decisionId);
    }

    /// @inheritdoc IDecisionApp
    function prepareMinistryLlmStakeDecision(
        bytes32 officeId,
        bytes32 decisionId,
        bytes32 recipientPersonId,
        uint256 amount,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external {
        OfficeTypes.OfficeRecord memory officeRecord = _requireMinistryPreparer(officeId, msg.sender);
        _requireNewDecisionId(decisionId);
        _validateStakeRecipient(recipientPersonId);
        _validateTokenTransfer(officeRecord.admin, address(_llmToken), address(this), amount);

        DecisionTypes.DecisionRecord storage record = _storeBaseMinistryDecision(
            decisionId,
            officeId,
            DecisionTypes.DecisionAction.LLMTransferAndStake,
            officeRecord.admin,
            metadataHash,
            metadataURI
        );
        record.token = address(_llmToken);
        record.recipient = address(this);
        record.recipientPersonId = recipientPersonId;
        record.amount = amount;

        _emitMinistryDecisionPrepared(decisionId);
    }

    /// @inheritdoc IDecisionApp
    function prepareMinistryClerkDecision(
        bytes32 officeId,
        bytes32 decisionId,
        address clerk,
        bool active,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external {
        OfficeTypes.OfficeRecord memory officeRecord = _requireMinistryPreparer(officeId, msg.sender);
        _requireNewDecisionId(decisionId);
        if (clerk == address(0) || clerk == officeRecord.admin) {
            revert InvalidDecisionRecipient(clerk);
        }

        DecisionTypes.DecisionRecord storage record = _storeBaseMinistryDecision(
            decisionId,
            officeId,
            DecisionTypes.DecisionAction.ClerkStatus,
            officeRecord.admin,
            metadataHash,
            metadataURI
        );
        record.clerk = clerk;
        record.clerkActive = active;

        _emitMinistryDecisionPrepared(decisionId);
    }

    /// @inheritdoc IDecisionApp
    function executeMinistryDecision(bytes32 decisionId) external nonReentrant {
        DecisionTypes.DecisionRecord storage record = _requirePreparedDecision(decisionId);
        if (record.scope != DecisionTypes.DecisionScope.Ministry) {
            revert InvalidDecisionAction(record.action);
        }

        _requireCurrentMinister(record.officeId, msg.sender);
        if (record.source != msg.sender) {
            revert NotMinistrySigner(record.officeId, msg.sender);
        }

        // Effects before interactions: finalize status before any external transfer/stake write.
        _markExecuted(record, msg.sender);

        if (record.action == DecisionTypes.DecisionAction.ERC20Transfer) {
            IERC20(record.token).safeTransferFrom(record.source, record.recipient, record.amount);
        } else if (record.action == DecisionTypes.DecisionAction.LLMTransferAndStake) {
            _llmToken.safeTransferFrom(record.source, address(this), record.amount);
            _llmToken.forceApprove(address(_stakingVault), record.amount);
            _stakingVault.stakeFor(record.recipientPersonId, record.amount);
        } else if (record.action == DecisionTypes.DecisionAction.ClerkStatus) {
            _officeRegistry.setClerkStatus(record.officeId, record.clerk, record.clerkActive);
        } else {
            revert InvalidDecisionAction(record.action);
        }
    }

    function _storeBaseMinistryDecision(
        bytes32 decisionId,
        bytes32 officeId,
        DecisionTypes.DecisionAction action,
        address source,
        bytes32 metadataHash,
        string calldata metadataURI
    ) private returns (DecisionTypes.DecisionRecord storage record) {
        uint64 preparedAt = uint64(block.timestamp);

        record = _decisionRecords[decisionId];
        record.decisionId = decisionId;
        record.scope = DecisionTypes.DecisionScope.Ministry;
        record.action = action;
        record.status = DecisionTypes.DecisionStatus.Prepared;
        record.officeId = officeId;
        record.preparedBy = msg.sender;
        record.source = source;
        record.metadataHash = metadataHash;
        record.metadataURI = metadataURI;
        record.preparedAt = preparedAt;
    }

    function _emitCongressDecisionPrepared(bytes32 decisionId) private {
        DecisionTypes.DecisionRecord storage record = _decisionRecords[decisionId];
        emit CongressDecisionPrepared(
            record.decisionId,
            record.congressCycleId,
            record.preparedBy,
            record.action,
            record.supportRequired,
            record.metadataHash,
            record.preparedAt
        );
    }

    function _emitMinistryDecisionPrepared(bytes32 decisionId) private {
        DecisionTypes.DecisionRecord storage record = _decisionRecords[decisionId];
        emit MinistryDecisionPrepared(
            record.decisionId, record.officeId, record.preparedBy, record.action, record.metadataHash, record.preparedAt
        );
    }

    function _recordCongressSupport(bytes32 decisionId, address member) private {
        _requireActiveCongressMember(member);

        DecisionTypes.DecisionRecord storage record = _requirePreparedDecision(decisionId);
        if (record.scope != DecisionTypes.DecisionScope.Congress) {
            revert InvalidDecisionAction(record.action);
        }
        _requireCongressDecisionTerm(record);
        if (_congressSupports[decisionId][member]) {
            return;
        }

        _congressSupports[decisionId][member] = true;
        record.supportCount += 1;

        emit CongressDecisionSupportRecorded(
            decisionId, member, record.supportCount, record.supportRequired, uint64(block.timestamp)
        );
    }

    /// @dev Counts stored supports that belong to a wallet still sitting in the current Congress. Bounded by the
    ///      seat count, so the loop is small and fixed.
    function _liveCongressSupport(bytes32 decisionId) private view returns (uint32 liveSupport) {
        address[] memory members = _congressCandidateRegistry.currentCongressMembers();
        uint256 memberCount = members.length;
        for (uint256 index = 0; index < memberCount; ++index) {
            if (_congressSupports[decisionId][members[index]]) {
                liveSupport += 1;
            }
        }
    }

    function _markExecuted(DecisionTypes.DecisionRecord storage record, address executor) private {
        record.status = DecisionTypes.DecisionStatus.Executed;
        record.executedBy = executor;
        record.executedAt = uint64(block.timestamp);

        emit DecisionExecuted(record.decisionId, record.scope, record.action, executor, record.executedAt);
    }

    function _requirePreparedDecision(bytes32 decisionId)
        private
        view
        returns (DecisionTypes.DecisionRecord storage record)
    {
        record = _decisionRecords[decisionId];
        if (record.decisionId == bytes32(0)) {
            revert DecisionNotFound(decisionId);
        }
        if (record.status != DecisionTypes.DecisionStatus.Prepared) {
            revert DecisionAlreadyFinalized(decisionId);
        }
    }

    function _requireNewDecisionId(bytes32 decisionId) private view {
        if (decisionId == bytes32(0)) {
            revert InvalidDecisionId(decisionId);
        }
        if (_decisionRecords[decisionId].decisionId != bytes32(0)) {
            revert DecisionAlreadyExists(decisionId);
        }
    }

    function _requireActiveCongressMember(address caller) private view {
        if (!_congressCandidateRegistry.isActiveCongressMember(caller)) {
            revert NotActiveCongressMember(caller);
        }
    }

    function _requiredCongressSupport() private view returns (uint32 supportRequired) {
        return _requiredCongressSupport(_congressCandidateRegistry.getCurrentOfficeTerm());
    }

    function _requiredCongressSupport(ElectionTypes.CongressOfficeTerm memory term)
        private
        pure
        returns (uint32 supportRequired)
    {
        if (term.cycleId == 0 || term.occupiedSeatCount == 0) {
            revert NoActiveCongressTerm();
        }

        return term.occupiedSeatCount / 2 + 1;
    }

    function _requireCongressDecisionTerm(DecisionTypes.DecisionRecord storage record) private view {
        uint256 currentCycleId = _congressCandidateRegistry.getCurrentOfficeTerm().cycleId;
        if (currentCycleId != record.congressCycleId) {
            revert CongressDecisionTermChanged(record.decisionId, record.congressCycleId, currentCycleId);
        }
    }

    function _requireMinistryPreparer(bytes32 officeId, address caller)
        private
        view
        returns (OfficeTypes.OfficeRecord memory officeRecord)
    {
        officeRecord = _officeRegistry.getOfficeRecord(officeId);
        OfficeTypes.OfficeRole role = _officeRegistry.roleOf(officeId, caller);
        if (role != OfficeTypes.OfficeRole.Admin && role != OfficeTypes.OfficeRole.Clerk) {
            revert UnauthorizedDecisionPreparer(officeId, caller);
        }
    }

    function _requireCurrentMinister(bytes32 officeId, address caller) private view {
        if (_officeRegistry.roleOf(officeId, caller) != OfficeTypes.OfficeRole.Admin) {
            revert NotMinistrySigner(officeId, caller);
        }
    }

    function _validateTokenTransfer(address source, address token, address recipient, uint256 amount) private view {
        if (source == address(0)) {
            revert InvalidDecisionSource(source);
        }
        if (token == address(0) || token.code.length == 0) {
            revert InvalidDecisionToken(token);
        }
        if (recipient == address(0)) {
            revert InvalidDecisionRecipient(recipient);
        }
        if (amount == 0) {
            revert InvalidDecisionAmount(amount);
        }
    }

    function _validateMinistryFunding(bytes32 officeId, address source, address token, uint256 amount) private view {
        if (officeId == bytes32(0)) {
            revert InvalidOfficeId(officeId);
        }
        if (!_officeRegistry.officeExists(officeId)) {
            revert MinistryOfficeNotFound(officeId);
        }
        if (source == address(0)) {
            revert InvalidDecisionSource(source);
        }
        if (token == address(0) || token.code.length == 0) {
            revert InvalidDecisionToken(token);
        }
        if (amount == 0) {
            revert InvalidDecisionAmount(amount);
        }

        // Fail fast: the funding path must be wired before a decision is prepared, so Congress cannot approve a
        // FundMinistry decision that can never execute. getModule reverts if the treasury or the funding-authority
        // module is unregistered; then require this app is that authority (fund() enforces the same at execution).
        IConstitutionKernel kernel = IConstitutionKernel(_congressCandidateRegistry.kernel());
        address ministryTreasury = kernel.getModule(KernelModuleIds.MINISTRY_TREASURY);
        if (ministryTreasury.code.length == 0) {
            revert InvalidRegistry(ministryTreasury);
        }
        address fundingAuthority = kernel.getModule(KernelModuleIds.MINISTRY_TREASURY_FUNDING_AUTHORITY);
        if (fundingAuthority != address(this)) {
            revert MinistryFundingAuthorityMismatch(address(this), fundingAuthority);
        }
    }

    function _validateStakeRecipient(bytes32 recipientPersonId) private view {
        if (recipientPersonId == bytes32(0) || !_identityRegistry.identityExists(recipientPersonId)) {
            revert InvalidIdentityReference(recipientPersonId);
        }
    }

    function _validateOfficeRegistration(
        bytes32 officeId,
        OfficeTypes.OfficeKind kind,
        string calldata name,
        address admin
    ) private view {
        if (officeId == bytes32(0)) {
            revert InvalidOfficeId(officeId);
        }
        if (_officeRegistry.officeExists(officeId)) {
            revert OfficeAlreadyRegistered(officeId);
        }
        if (kind == OfficeTypes.OfficeKind.Undefined) {
            revert InvalidOfficeKind(kind);
        }
        if (admin == address(0)) {
            revert InvalidOfficeAdmin(admin);
        }
        if (bytes(name).length == 0) {
            revert InvalidOfficeName();
        }
    }
}
