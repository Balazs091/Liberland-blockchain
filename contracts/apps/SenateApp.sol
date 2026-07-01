// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IActionTimelock} from "../interfaces/IActionTimelock.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IGovernanceRouter} from "../interfaces/IGovernanceRouter.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {IPresidentRegistry} from "../interfaces/IPresidentRegistry.sol";
import {IReferendumApp} from "../interfaces/IReferendumApp.sol";
import {IReferendumRegistry} from "../interfaces/IReferendumRegistry.sol";
import {ISenateApp} from "../interfaces/ISenateApp.sol";
import {ISenatePowersPolicy} from "../interfaces/ISenatePowersPolicy.sol";
import {ISenateSeatRegistry} from "../interfaces/ISenateSeatRegistry.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {ReferendumTypes} from "../types/ReferendumTypes.sol";
import {SenateTypes} from "../types/SenateTypes.sol";

/// @title SenateApp
/// @notice User-facing application for v1 Senate succession flows and bounded action-cancellation support.
/// @dev The four negative-control processes (action cancellation, referendum veto, sub-legal repeal, and
///      disbursement suspension) share a single per-seat support representation (`SenateTypes.VoteSupport`) and a
///      common set of generic tally/threshold helpers. Only the sub-legal repeal process uses `attemptNonce`; the
///      other three always pass zero. All processes apply the same equal-weight threshold plus the President-proxy
///      floor (proxy-counted seats may never exceed seats that cast an explicit For).
contract SenateApp is ISenateApp {
    uint64 internal constant SUB_LEGAL_REPEAL_VOTING_PERIOD = 7 days;

    IIdentityRegistry private immutable _identityRegistry;
    ILegislationRegistry private immutable _legislationRegistry;
    ISenateSeatRegistry private immutable _senateSeatRegistry;
    ISenatePowersPolicy private immutable _senatePowersPolicy;
    IPresidentRegistry private immutable _presidentRegistry;
    IGovernanceRouter private immutable _governanceRouter;
    IActionTimelock private immutable _actionTimelock;
    IReferendumApp private immutable _referendumApp;
    IConstitutionKernel private immutable _kernel;

    mapping(bytes32 actionId => SenateTypes.ActionCancellationRecord actionCancellationRecord) private
        _actionCancellationRecords;
    mapping(bytes32 actionId => mapping(uint32 seatIndex => SenateTypes.VoteSupport support)) private
        _actionCancellationSupports;
    mapping(bytes32 actionId => SenateTypes.PresidentProxyVote proxyVote) private
        _actionCancellationPresidentProxyVotes;
    mapping(bytes32 referendumId => SenateTypes.ReferendumVetoRecord referendumVetoRecord) private
        _referendumVetoRecords;
    mapping(bytes32 referendumId => mapping(uint32 seatIndex => SenateTypes.VoteSupport support)) private
        _referendumVetoSupports;
    mapping(bytes32 referendumId => SenateTypes.PresidentProxyVote proxyVote) private
        _referendumVetoPresidentProxyVotes;
    mapping(bytes32 measureId => SenateTypes.SubLegalMeasureRepealRecord repealRecord) private
        _subLegalMeasureRepealRecords;
    mapping(bytes32 measureId => mapping(uint32 seatIndex => SenateTypes.VoteSupport support)) private
        _subLegalMeasureRepealSupports;
    mapping(bytes32 measureId => SenateTypes.PresidentProxyVote proxyVote) private
        _subLegalMeasureRepealPresidentProxyVotes;
    mapping(bytes32 actionId => SenateTypes.DisbursementSuspension suspension) private _disbursementSuspensions;
    mapping(bytes32 actionId => mapping(uint32 seatIndex => SenateTypes.VoteSupport support)) private
        _disbursementSuspensionSupports;
    mapping(bytes32 actionId => SenateTypes.PresidentProxyVote proxyVote) private
        _disbursementSuspensionPresidentProxyVotes;

    /// @param identityRegistryAddress The identity registry used to resolve holder and successor person references.
    /// @param senateSeatRegistryAddress The Senate seat registry address.
    /// @param senatePowersPolicyAddress The Senate powers policy address.
    /// @param presidentRegistryAddress The President registry used for deadline proxy votes.
    /// @param governanceRouterAddress The governance router address.
    /// @param actionTimelockAddress The action timelock address used to inspect queued actions.
    /// @param referendumAppAddress The referendum app used for active referendum vetoes.
    constructor(
        address identityRegistryAddress,
        address senateSeatRegistryAddress,
        address senatePowersPolicyAddress,
        address presidentRegistryAddress,
        address governanceRouterAddress,
        address actionTimelockAddress,
        address referendumAppAddress
    ) {
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidRegistry(identityRegistryAddress);
        }
        if (senateSeatRegistryAddress == address(0) || senateSeatRegistryAddress.code.length == 0) {
            revert InvalidRegistry(senateSeatRegistryAddress);
        }
        if (senatePowersPolicyAddress == address(0) || senatePowersPolicyAddress.code.length == 0) {
            revert InvalidPolicy(senatePowersPolicyAddress);
        }
        if (presidentRegistryAddress == address(0) || presidentRegistryAddress.code.length == 0) {
            revert InvalidPresidentRegistry(presidentRegistryAddress);
        }
        if (governanceRouterAddress == address(0) || governanceRouterAddress.code.length == 0) {
            revert InvalidRouter(governanceRouterAddress);
        }
        if (actionTimelockAddress == address(0) || actionTimelockAddress.code.length == 0) {
            revert InvalidTimelock(actionTimelockAddress);
        }
        if (referendumAppAddress == address(0) || referendumAppAddress.code.length == 0) {
            revert InvalidReferendumApp(referendumAppAddress);
        }

        ISenateSeatRegistry senateSeatRegistry_ = ISenateSeatRegistry(senateSeatRegistryAddress);
        ISenatePowersPolicy senatePowersPolicy_ = ISenatePowersPolicy(senatePowersPolicyAddress);
        IPresidentRegistry presidentRegistry_ = IPresidentRegistry(presidentRegistryAddress);
        IGovernanceRouter governanceRouter_ = IGovernanceRouter(governanceRouterAddress);
        IReferendumApp referendumApp_ = IReferendumApp(referendumAppAddress);
        address legislationRegistryAddress = referendumApp_.legislationRegistry();
        if (legislationRegistryAddress == address(0) || legislationRegistryAddress.code.length == 0) {
            revert InvalidRegistry(legislationRegistryAddress);
        }
        ILegislationRegistry legislationRegistry_ = ILegislationRegistry(legislationRegistryAddress);

        address kernelAddress = senateSeatRegistry_.kernel();
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) {
            revert InvalidRegistry(kernelAddress);
        }
        if (governanceRouter_.kernel() != kernelAddress) {
            revert InvalidRouter(governanceRouterAddress);
        }
        if (governanceRouter_.timelock() != actionTimelockAddress) {
            revert InvalidTimelock(actionTimelockAddress);
        }
        if (referendumApp_.governanceRouter() != governanceRouterAddress) {
            revert InvalidReferendumApp(referendumAppAddress);
        }
        if (presidentRegistry_.kernel() != kernelAddress) {
            revert InvalidPresidentRegistry(presidentRegistryAddress);
        }
        if (legislationRegistry_.kernel() != kernelAddress) {
            revert InvalidRegistry(legislationRegistryAddress);
        }
        if (senateSeatRegistry_.totalSeats() != senatePowersPolicy_.seatCount()) {
            revert InvalidPolicy(senatePowersPolicyAddress);
        }

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _legislationRegistry = legislationRegistry_;
        _senateSeatRegistry = senateSeatRegistry_;
        _senatePowersPolicy = senatePowersPolicy_;
        _presidentRegistry = presidentRegistry_;
        _governanceRouter = governanceRouter_;
        _actionTimelock = IActionTimelock(actionTimelockAddress);
        _referendumApp = referendumApp_;
        _kernel = IConstitutionKernel(kernelAddress);
    }

    /// @inheritdoc ISenateApp
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc ISenateApp
    function senateSeatRegistry() external view returns (address registryAddress) {
        return address(_senateSeatRegistry);
    }

    /// @inheritdoc ISenateApp
    function legislationRegistry() external view returns (address registryAddress) {
        return address(_legislationRegistry);
    }

    /// @inheritdoc ISenateApp
    function senatePowersPolicy() external view returns (address policyAddress) {
        return address(_senatePowersPolicy);
    }

    /// @inheritdoc ISenateApp
    function presidentRegistry() external view returns (address registryAddress) {
        return address(_presidentRegistry);
    }

    /// @inheritdoc ISenateApp
    function governanceRouter() external view returns (address routerAddress) {
        return address(_governanceRouter);
    }

    /// @inheritdoc ISenateApp
    function actionTimelock() external view returns (address timelockAddress) {
        return address(_actionTimelock);
    }

    /// @inheritdoc ISenateApp
    function referendumApp() external view returns (address appAddress) {
        return address(_referendumApp);
    }

    /// @inheritdoc ISenateApp
    function getActionCancellationRecord(bytes32 actionId)
        external
        view
        returns (SenateTypes.ActionCancellationRecord memory record)
    {
        return _actionCancellationRecords[actionId];
    }

    /// @inheritdoc ISenateApp
    function getActionCancellationSupport(bytes32 actionId, uint32 seatIndex)
        external
        view
        returns (SenateTypes.VoteSupport memory support)
    {
        support = _actionCancellationSupports[actionId][seatIndex];
        if (!_isSupportActive(seatIndex, support, 0)) {
            support.supported = false;
            support.option = SenateTypes.VoteOption.Undefined;
        }
    }

    /// @inheritdoc ISenateApp
    function getActionCancellationPresidentProxyVote(bytes32 actionId)
        external
        view
        returns (SenateTypes.PresidentProxyVote memory proxyVote)
    {
        return _actionCancellationPresidentProxyVotes[actionId];
    }

    /// @inheritdoc ISenateApp
    function actionCancellationSupportCount(bytes32 actionId) external view returns (uint256 count) {
        return _supportCount(_actionCancellationSupports[actionId], 0);
    }

    /// @inheritdoc ISenateApp
    function getReferendumVetoRecord(bytes32 referendumId)
        external
        view
        returns (SenateTypes.ReferendumVetoRecord memory record)
    {
        return _referendumVetoRecords[referendumId];
    }

    /// @inheritdoc ISenateApp
    function getReferendumVetoSupport(bytes32 referendumId, uint32 seatIndex)
        external
        view
        returns (SenateTypes.VoteSupport memory support)
    {
        support = _referendumVetoSupports[referendumId][seatIndex];
        if (!_isSupportActive(seatIndex, support, 0)) {
            support.supported = false;
            support.option = SenateTypes.VoteOption.Undefined;
        }
    }

    /// @inheritdoc ISenateApp
    function getReferendumVetoPresidentProxyVote(bytes32 referendumId)
        external
        view
        returns (SenateTypes.PresidentProxyVote memory proxyVote)
    {
        return _referendumVetoPresidentProxyVotes[referendumId];
    }

    /// @inheritdoc ISenateApp
    function referendumVetoSupportCount(bytes32 referendumId) external view returns (uint256 count) {
        return _supportCount(_referendumVetoSupports[referendumId], 0);
    }

    /// @inheritdoc ISenateApp
    function getSubLegalMeasureRepealRecord(bytes32 measureId)
        external
        view
        returns (SenateTypes.SubLegalMeasureRepealRecord memory record)
    {
        return _subLegalMeasureRepealRecords[measureId];
    }

    /// @inheritdoc ISenateApp
    function getSubLegalMeasureRepealSupport(bytes32 measureId, uint32 seatIndex)
        external
        view
        returns (SenateTypes.VoteSupport memory support)
    {
        SenateTypes.SubLegalMeasureRepealRecord memory repealRecord = _subLegalMeasureRepealRecords[measureId];
        support = _subLegalMeasureRepealSupports[measureId][seatIndex];
        if (
            !repealRecord.exists || repealRecord.finalized
                || !_isSupportActive(seatIndex, support, repealRecord.attemptNonce)
        ) {
            support.supported = false;
            support.option = SenateTypes.VoteOption.Undefined;
        }
    }

    /// @inheritdoc ISenateApp
    function getSubLegalMeasureRepealPresidentProxyVote(bytes32 measureId)
        external
        view
        returns (SenateTypes.PresidentProxyVote memory proxyVote)
    {
        return _subLegalMeasureRepealPresidentProxyVotes[measureId];
    }

    /// @inheritdoc ISenateApp
    function subLegalMeasureRepealSupportCount(bytes32 measureId) external view returns (uint256 count) {
        SenateTypes.SubLegalMeasureRepealRecord memory repealRecord = _subLegalMeasureRepealRecords[measureId];
        if (!repealRecord.exists || repealRecord.finalized) {
            return 0;
        }

        return _supportCount(_subLegalMeasureRepealSupports[measureId], repealRecord.attemptNonce);
    }

    /// @inheritdoc ISenateApp
    function bootstrapAssignSeat(uint32 seatIndex, address holder) external {
        _requireBootstrapAuthority(msg.sender);

        bytes32 holderPersonId = _resolveActivePersonId(holder);
        _senateSeatRegistry.assignSeat(seatIndex, holder, holderPersonId, false);
    }

    /// @inheritdoc ISenateApp
    function vacateMySeat(uint32 seatIndex) external {
        _requireSeatHolder(seatIndex, msg.sender);
        _senateSeatRegistry.vacateSeat(seatIndex);
    }

    /// @inheritdoc ISenateApp
    function transferMySeat(uint32 seatIndex, address recipient) external {
        _requireSeatHolder(seatIndex, msg.sender);

        bytes32 recipientPersonId = _resolveActivePersonId(recipient);
        _senateSeatRegistry.transferSeat(seatIndex, recipient, recipientPersonId);
    }

    /// @inheritdoc ISenateApp
    function nominateSuccessor(uint32 seatIndex, address nominee) external {
        _requireSeatHolder(seatIndex, msg.sender);

        bytes32 nomineePersonId = _resolveActivePersonId(nominee);
        _senateSeatRegistry.nominateSuccessor(seatIndex, nominee, nomineePersonId);
    }

    /// @inheritdoc ISenateApp
    function clearSuccessor(uint32 seatIndex) external {
        _requireSeatHolder(seatIndex, msg.sender);
        _senateSeatRegistry.clearSuccessor(seatIndex);
    }

    /// @inheritdoc ISenateApp
    function claimSeatBySuccession(uint32 seatIndex) external {
        SenateTypes.SenateSeatRecord memory seatRecord = _senateSeatRegistry.getSeatRecord(seatIndex);
        if (!seatRecord.vacant) {
            revert SeatNotVacant(seatIndex);
        }

        bytes32 claimantPersonId = _resolveActivePersonId(msg.sender);
        if (
            seatRecord.nominatedSuccessorPersonId == bytes32(0)
                || seatRecord.nominatedSuccessorPersonId != claimantPersonId
        ) {
            revert NotNominatedSuccessor(seatIndex, msg.sender);
        }

        _senateSeatRegistry.assignSeat(seatIndex, msg.sender, claimantPersonId, true);
    }

    /// @inheritdoc ISenateApp
    function supportActionCancellation(bytes32 actionId, uint32 seatIndex) external {
        _castActionCancellationVote(actionId, seatIndex);
    }

    /// @inheritdoc ISenateApp
    function removeActionCancellationSupport(bytes32 actionId, uint32 seatIndex) external {
        _requireSeatHolder(seatIndex, msg.sender);

        SenateTypes.ActionCancellationRecord storage actionCancellationRecord = _actionCancellationRecords[actionId];
        if (actionCancellationRecord.finalized) {
            revert SenateProcessAlreadyFinalized(actionId);
        }
        _requireVoteOpen(actionCancellationRecord.deadline);

        SenateTypes.VoteSupport storage support = _actionCancellationSupports[actionId][seatIndex];
        uint64 currentOccupancyNonce = _currentSeatOccupancyNonce(seatIndex);
        if (support.option == SenateTypes.VoteOption.Undefined || support.seatOccupancyNonce != currentOccupancyNonce) {
            revert SenateSupportNotActive(actionId, seatIndex);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        support.supported = false;
        support.option = SenateTypes.VoteOption.Undefined;
        support.updatedAt = currentTimestamp;

        uint256 supportCount = _supportCount(_actionCancellationSupports[actionId], 0);
        emit SenateActionSupportRemoved(actionId, seatIndex, msg.sender, supportCount, currentTimestamp);
    }

    /// @inheritdoc ISenateApp
    function castPresidentActionCancellationProxyVote(bytes32 actionId, SenateTypes.VoteOption option) external {
        _requirePresident(msg.sender);
        _requireValidVoteOption(option);

        GovernanceTypes.ActionRecord memory actionRecord = _requireCancelableAction(actionId);
        SenateTypes.ActionCancellationRecord storage actionCancellationRecord = _actionCancellationRecords[actionId];
        uint64 currentTimestamp = uint64(block.timestamp);
        if (actionCancellationRecord.finalized) {
            revert SenateProcessAlreadyFinalized(actionId);
        }
        _openActionCancellationIfNeeded(actionCancellationRecord, actionRecord, currentTimestamp);
        _requireVoteOpen(actionCancellationRecord.deadline);

        _actionCancellationPresidentProxyVotes[actionId] =
            SenateTypes.PresidentProxyVote({option: option, updatedAt: currentTimestamp});

        emit PresidentActionCancellationProxyVoteRecorded(actionId, msg.sender, option, currentTimestamp);
    }

    /// @inheritdoc ISenateApp
    function finalizeActionCancellation(bytes32 actionId) external {
        SenateTypes.ActionCancellationRecord storage actionCancellationRecord = _actionCancellationRecords[actionId];
        if (actionCancellationRecord.finalized) {
            revert SenateProcessAlreadyFinalized(actionId);
        }
        _requireVoteFinalizable(actionCancellationRecord.deadline);

        (uint256 directSupportCount, uint256 presidentProxySupportCount) = _tally(
            _actionCancellationSupports[actionId],
            _presidentProxySupports(
                _actionCancellationPresidentProxyVotes[actionId],
                actionCancellationRecord.createdAt,
                actionCancellationRecord.deadline
            ),
            0
        );
        uint256 supportCount = directSupportCount + presidentProxySupportCount;
        uint64 currentTimestamp = uint64(block.timestamp);

        actionCancellationRecord.finalized = true;
        actionCancellationRecord.finalizedAt = currentTimestamp;
        // forge-lint: disable-next-line(unsafe-typecast)
        actionCancellationRecord.supportSnapshot = uint32(supportCount);
        // forge-lint: disable-next-line(unsafe-typecast)
        actionCancellationRecord.presidentProxySupportSnapshot = uint32(presidentProxySupportCount);

        // President proxy amplifies but cannot fabricate support: proxy coverage is capped at explicit For support
        // (see _effectiveSupport), so a proxy-only majority never reaches the threshold and a supporting proxy can
        // never defeat an otherwise-passing vote.
        // L6: only cancel while the queued action is still actionable. If support+floor are met but the action
        // has already Expired (or is no longer Queued), finalize the record without reverting and skip the
        // external cancel sink so a stalled vote can always be closed.
        if (
            _effectiveSupport(directSupportCount, presidentProxySupportCount)
                >= _senatePowersPolicy.minimumActionCancellationSupport() && _isActionCancelable(actionId)
        ) {
            actionCancellationRecord.canceled = true;
            actionCancellationRecord.canceledAt = currentTimestamp;

            emit SenateActionCanceled(actionId, supportCount, msg.sender, currentTimestamp);
        }

        emit SenateActionCancellationFinalized(
            actionId,
            supportCount,
            presidentProxySupportCount,
            actionCancellationRecord.canceled,
            msg.sender,
            currentTimestamp
        );

        if (actionCancellationRecord.canceled) {
            _governanceRouter.cancelAction(actionId);
        }
    }

    /// @inheritdoc ISenateApp
    function supportReferendumVeto(bytes32 referendumId, uint32 seatIndex) external {
        _castReferendumVetoVote(referendumId, seatIndex);
    }

    /// @inheritdoc ISenateApp
    function removeReferendumVetoSupport(bytes32 referendumId, uint32 seatIndex) external {
        _requireSeatHolder(seatIndex, msg.sender);

        SenateTypes.ReferendumVetoRecord storage referendumVetoRecord = _referendumVetoRecords[referendumId];
        if (referendumVetoRecord.finalized) {
            revert SenateProcessAlreadyFinalized(referendumId);
        }
        _requireVoteOpen(referendumVetoRecord.deadline);

        SenateTypes.VoteSupport storage support = _referendumVetoSupports[referendumId][seatIndex];
        uint64 currentOccupancyNonce = _currentSeatOccupancyNonce(seatIndex);
        if (support.option == SenateTypes.VoteOption.Undefined || support.seatOccupancyNonce != currentOccupancyNonce) {
            revert SenateSupportNotActive(referendumId, seatIndex);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        support.supported = false;
        support.option = SenateTypes.VoteOption.Undefined;
        support.updatedAt = currentTimestamp;

        uint256 supportCount = _supportCount(_referendumVetoSupports[referendumId], 0);
        emit SenateReferendumSupportRemoved(referendumId, seatIndex, msg.sender, supportCount, currentTimestamp);
    }

    /// @inheritdoc ISenateApp
    function castPresidentReferendumVetoProxyVote(bytes32 referendumId, SenateTypes.VoteOption option) external {
        _requirePresident(msg.sender);
        _requireValidVoteOption(option);

        ReferendumTypes.ReferendumRecord memory referendumRecord = _requireVetoEligibleReferendum(referendumId);
        SenateTypes.ReferendumVetoRecord storage referendumVetoRecord = _referendumVetoRecords[referendumId];
        uint64 currentTimestamp = uint64(block.timestamp);
        if (referendumVetoRecord.finalized) {
            revert SenateProcessAlreadyFinalized(referendumId);
        }
        _openReferendumVetoIfNeeded(referendumVetoRecord, referendumRecord, currentTimestamp);
        _requireVoteOpen(referendumVetoRecord.deadline);

        _referendumVetoPresidentProxyVotes[referendumId] =
            SenateTypes.PresidentProxyVote({option: option, updatedAt: currentTimestamp});

        emit PresidentReferendumVetoProxyVoteRecorded(referendumId, msg.sender, option, currentTimestamp);
    }

    /// @inheritdoc ISenateApp
    function finalizeReferendumVeto(bytes32 referendumId) external {
        SenateTypes.ReferendumVetoRecord storage referendumVetoRecord = _referendumVetoRecords[referendumId];
        if (referendumVetoRecord.finalized) {
            revert SenateProcessAlreadyFinalized(referendumId);
        }
        _requireVoteFinalizable(referendumVetoRecord.deadline);

        (uint256 directSupportCount, uint256 presidentProxySupportCount) = _tally(
            _referendumVetoSupports[referendumId],
            _presidentProxySupports(
                _referendumVetoPresidentProxyVotes[referendumId],
                referendumVetoRecord.createdAt,
                referendumVetoRecord.deadline
            ),
            0
        );
        uint256 supportCount = directSupportCount + presidentProxySupportCount;
        uint64 currentTimestamp = uint64(block.timestamp);

        referendumVetoRecord.finalized = true;
        referendumVetoRecord.finalizedAt = currentTimestamp;
        // forge-lint: disable-next-line(unsafe-typecast)
        referendumVetoRecord.supportSnapshot = uint32(supportCount);
        // forge-lint: disable-next-line(unsafe-typecast)
        referendumVetoRecord.presidentProxySupportSnapshot = uint32(presidentProxySupportCount);

        // President-proxy floor (H5): the President may amplify but not fabricate a Senate veto of an
        // active citizen referendum — proxy coverage is capped at explicit direct seat support.
        if (
            _effectiveSupport(directSupportCount, presidentProxySupportCount)
                >= _senatePowersPolicy.minimumActionCancellationSupport()
        ) {
            referendumVetoRecord.vetoed = true;
            referendumVetoRecord.vetoedAt = currentTimestamp;

            emit SenateReferendumVetoed(referendumId, supportCount, msg.sender, currentTimestamp);
        }

        emit SenateReferendumVetoFinalized(
            referendumId,
            supportCount,
            presidentProxySupportCount,
            referendumVetoRecord.vetoed,
            msg.sender,
            currentTimestamp
        );

        if (referendumVetoRecord.vetoed) {
            _referendumApp.cancelReferendumBySenate(referendumId);
        }
    }

    /// @inheritdoc ISenateApp
    function supportSubLegalMeasureRepeal(bytes32 measureId, uint32 seatIndex) external {
        _castSubLegalMeasureRepealVote(measureId, seatIndex);
    }

    /// @inheritdoc ISenateApp
    function removeSubLegalMeasureRepealSupport(bytes32 measureId, uint32 seatIndex) external {
        _requireSeatHolder(seatIndex, msg.sender);

        SenateTypes.SubLegalMeasureRepealRecord storage repealRecord = _subLegalMeasureRepealRecords[measureId];
        if (repealRecord.finalized) {
            revert SenateProcessAlreadyFinalized(measureId);
        }
        _requireVoteOpen(repealRecord.deadline);

        SenateTypes.VoteSupport storage support = _subLegalMeasureRepealSupports[measureId][seatIndex];
        uint64 currentOccupancyNonce = _currentSeatOccupancyNonce(seatIndex);
        if (
            support.option == SenateTypes.VoteOption.Undefined || support.attemptNonce != repealRecord.attemptNonce
                || support.seatOccupancyNonce != currentOccupancyNonce
        ) {
            revert SenateSupportNotActive(measureId, seatIndex);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        support.supported = false;
        support.option = SenateTypes.VoteOption.Undefined;
        support.updatedAt = currentTimestamp;

        uint256 supportCount = _supportCount(_subLegalMeasureRepealSupports[measureId], repealRecord.attemptNonce);
        emit SenateSubLegalMeasureRepealSupportRemoved(measureId, seatIndex, msg.sender, supportCount, currentTimestamp);
    }

    /// @inheritdoc ISenateApp
    function castPresidentSubLegalMeasureRepealProxyVote(bytes32 measureId, SenateTypes.VoteOption option) external {
        _requirePresident(msg.sender);
        _requireValidVoteOption(option);

        LegislationTypes.LegislationRecord memory legislationRecord = _requireSubLegalMeasureRepealable(measureId);
        SenateTypes.SubLegalMeasureRepealRecord storage repealRecord = _subLegalMeasureRepealRecords[measureId];
        uint64 currentTimestamp = uint64(block.timestamp);
        bool newlyOpened = !repealRecord.exists || repealRecord.finalized;
        _openSubLegalMeasureRepealIfNeeded(repealRecord, legislationRecord, currentTimestamp);
        _requireVoteOpen(repealRecord.deadline);

        _subLegalMeasureRepealPresidentProxyVotes[measureId] =
            SenateTypes.PresidentProxyVote({option: option, updatedAt: currentTimestamp});

        if (newlyOpened) {
            emit SenateSubLegalMeasureRepealOpened(
                measureId, repealRecord.repealId, type(uint32).max, msg.sender, currentTimestamp, repealRecord.deadline
            );
        }

        emit PresidentSubLegalMeasureRepealProxyVoteRecorded(measureId, msg.sender, option, currentTimestamp);
    }

    /// @inheritdoc ISenateApp
    function finalizeSubLegalMeasureRepeal(bytes32 measureId) external {
        SenateTypes.SubLegalMeasureRepealRecord storage repealRecord = _subLegalMeasureRepealRecords[measureId];
        if (repealRecord.finalized) {
            revert SenateProcessAlreadyFinalized(measureId);
        }
        _requireVoteFinalizable(repealRecord.deadline);

        (uint256 directSupportCount, uint256 presidentProxySupportCount) = _tally(
            _subLegalMeasureRepealSupports[measureId],
            _presidentProxySupports(
                _subLegalMeasureRepealPresidentProxyVotes[measureId], repealRecord.createdAt, repealRecord.deadline
            ),
            repealRecord.attemptNonce
        );
        uint256 supportCount = directSupportCount + presidentProxySupportCount;
        uint64 currentTimestamp = uint64(block.timestamp);

        repealRecord.finalized = true;
        repealRecord.finalizedAt = currentTimestamp;
        // forge-lint: disable-next-line(unsafe-typecast)
        repealRecord.supportSnapshot = uint32(supportCount);
        // forge-lint: disable-next-line(unsafe-typecast)
        repealRecord.presidentProxySupportSnapshot = uint32(presidentProxySupportCount);

        // President proxy amplifies but cannot fabricate support: proxy coverage is capped at explicit For support
        // (see _effectiveSupport), so a proxy-only majority never reaches the threshold.
        // L6: only repeal while the measure is still sub-legal, active, and unrepealed. If support+floor are met
        // but the measure was already repealed/inactivated, finalize the record without reverting and skip the
        // external repeal sink so a stalled vote can always be closed.
        if (
            _effectiveSupport(directSupportCount, presidentProxySupportCount)
                >= _senatePowersPolicy.minimumActionCancellationSupport() && _isSubLegalMeasureRepealable(measureId)
        ) {
            repealRecord.repealed = true;
            repealRecord.repealedAt = currentTimestamp;

            emit SenateSubLegalMeasureRepealed(
                measureId, repealRecord.repealId, supportCount, msg.sender, currentTimestamp
            );
        }

        emit SenateSubLegalMeasureRepealFinalized(
            measureId, supportCount, presidentProxySupportCount, repealRecord.repealed, msg.sender, currentTimestamp
        );

        if (repealRecord.repealed) {
            _legislationRegistry.recordRepeal(measureId, LegislationTypes.RepealOrigin.Senate, repealRecord.repealId);
        }
    }

    /// @inheritdoc ISenateApp
    function getDisbursementSuspension(bytes32 actionId)
        external
        view
        returns (SenateTypes.DisbursementSuspension memory suspension)
    {
        return _disbursementSuspensions[actionId];
    }

    /// @inheritdoc ISenateApp
    function supportDisbursementSuspension(bytes32 actionId, uint32 seatIndex) external {
        _requireSeatHolder(seatIndex, msg.sender);
        _requireSuspendableDisbursement(actionId);

        SenateTypes.VoteSupport storage support = _disbursementSuspensionSupports[actionId][seatIndex];
        uint64 currentOccupancyNonce = _currentSeatOccupancyNonce(seatIndex);
        if (
            support.supported && support.option == SenateTypes.VoteOption.For
                && support.seatOccupancyNonce == currentOccupancyNonce
        ) {
            revert SenateSupportAlreadyActive(actionId, seatIndex);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        support.supported = true;
        support.option = SenateTypes.VoteOption.For;
        support.seatOccupancyNonce = currentOccupancyNonce;
        support.updatedAt = currentTimestamp;

        emit SenateDisbursementSuspensionSupportRecorded(actionId, seatIndex, msg.sender, currentTimestamp);
    }

    /// @inheritdoc ISenateApp
    function removeDisbursementSuspensionSupport(bytes32 actionId, uint32 seatIndex) external {
        _requireSeatHolder(seatIndex, msg.sender);

        SenateTypes.VoteSupport storage support = _disbursementSuspensionSupports[actionId][seatIndex];
        uint64 currentOccupancyNonce = _currentSeatOccupancyNonce(seatIndex);
        if (support.option == SenateTypes.VoteOption.Undefined || support.seatOccupancyNonce != currentOccupancyNonce) {
            revert SenateSupportNotActive(actionId, seatIndex);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        support.supported = false;
        support.option = SenateTypes.VoteOption.Undefined;
        support.updatedAt = currentTimestamp;

        emit SenateDisbursementSuspensionSupportRemoved(actionId, seatIndex, msg.sender, currentTimestamp);
    }

    /// @inheritdoc ISenateApp
    function castPresidentDisbursementSuspensionProxyVote(bytes32 actionId, SenateTypes.VoteOption option) external {
        _requirePresident(msg.sender);
        _requireValidVoteOption(option);
        _requireSuspendableDisbursement(actionId);

        uint64 currentTimestamp = uint64(block.timestamp);
        _disbursementSuspensionPresidentProxyVotes[actionId] =
            SenateTypes.PresidentProxyVote({option: option, updatedAt: currentTimestamp});

        emit PresidentDisbursementSuspensionProxyVoteRecorded(actionId, msg.sender, option, currentTimestamp);
    }

    /// @inheritdoc ISenateApp
    function suspendDisbursement(bytes32 actionId) external {
        GovernanceTypes.ActionRecord memory actionRecord = _requireSuspendableDisbursement(actionId);

        SenateTypes.DisbursementSuspension storage suspension = _disbursementSuspensions[actionId];
        if (suspension.exists && block.timestamp < suspension.suspendedUntil) {
            revert DisbursementAlreadySuspended(actionId, suspension.suspendedUntil);
        }

        (uint256 directSupportCount, uint256 presidentProxySupportCount) =
            _disbursementSuspensionSupportBreakdown(actionId);
        _requireDisbursementSuspensionAuthorized(actionId, directSupportCount, presidentProxySupportCount);

        uint64 currentTimestamp = uint64(block.timestamp);
        uint64 suspendedUntil = _boundedSuspensionDeadline(currentTimestamp, actionRecord.expiresAt);
        suspension.exists = true;
        suspension.suspendedUntil = suspendedUntil;
        suspension.renewalCount = 0;

        emit SenateDisbursementSuspended(
            actionId,
            suspendedUntil,
            directSupportCount + presidentProxySupportCount,
            presidentProxySupportCount,
            msg.sender,
            currentTimestamp
        );
    }

    /// @inheritdoc ISenateApp
    function renewDisbursementSuspension(bytes32 actionId) external {
        GovernanceTypes.ActionRecord memory actionRecord = _requireSuspendableDisbursement(actionId);

        SenateTypes.DisbursementSuspension storage suspension = _disbursementSuspensions[actionId];
        if (!suspension.exists || block.timestamp >= suspension.suspendedUntil) {
            revert DisbursementSuspensionNotRenewable(actionId, suspension.suspendedUntil);
        }

        (uint256 directSupportCount, uint256 presidentProxySupportCount) =
            _disbursementSuspensionSupportBreakdown(actionId);
        _requireDisbursementSuspensionAuthorized(actionId, directSupportCount, presidentProxySupportCount);

        uint64 currentTimestamp = uint64(block.timestamp);
        uint64 suspendedUntil = _boundedSuspensionDeadline(currentTimestamp, actionRecord.expiresAt);
        suspension.suspendedUntil = suspendedUntil;
        suspension.renewalCount += 1;

        emit SenateDisbursementSuspensionRenewed(
            actionId, suspendedUntil, suspension.renewalCount, msg.sender, currentTimestamp
        );
    }

    function _requireBootstrapAuthority(address caller) private view {
        if (_kernel.bootstrapAuthority() != caller || caller == address(0)) {
            revert UnauthorizedBootstrapCaller(caller);
        }
    }

    function _requireSeatHolder(uint32 seatIndex, address caller) private view {
        SenateTypes.SenateSeatRecord memory seatRecord = _senateSeatRegistry.getSeatRecord(seatIndex);
        if (seatRecord.vacant || seatRecord.holder != caller) {
            revert NotSeatHolder(seatIndex, caller);
        }
    }

    function _resolveActivePersonId(address wallet) private view returns (bytes32 personId) {
        IdentityTypes.WalletLink memory walletLink = _identityRegistry.getWalletLink(wallet);
        if (walletLink.personId == bytes32(0) || walletLink.status != IdentityTypes.WalletLinkStatus.Active) {
            revert UnknownPersonReference(wallet);
        }

        return walletLink.personId;
    }

    function _castActionCancellationVote(bytes32 actionId, uint32 seatIndex) private {
        _requireSeatHolder(seatIndex, msg.sender);

        GovernanceTypes.ActionRecord memory actionRecord = _requireCancelableAction(actionId);
        SenateTypes.ActionCancellationRecord storage actionCancellationRecord = _actionCancellationRecords[actionId];
        uint64 currentTimestamp = uint64(block.timestamp);
        if (actionCancellationRecord.finalized) {
            revert SenateProcessAlreadyFinalized(actionId);
        }

        bool newlyOpened = !actionCancellationRecord.exists;
        _openActionCancellationIfNeeded(actionCancellationRecord, actionRecord, currentTimestamp);
        _requireVoteOpen(actionCancellationRecord.deadline);

        SenateTypes.VoteSupport storage support = _actionCancellationSupports[actionId][seatIndex];
        uint64 currentOccupancyNonce = _currentSeatOccupancyNonce(seatIndex);
        if (support.option == SenateTypes.VoteOption.For && support.seatOccupancyNonce == currentOccupancyNonce) {
            revert SenateSupportAlreadyActive(actionId, seatIndex);
        }

        support.supported = true;
        support.option = SenateTypes.VoteOption.For;
        support.seatOccupancyNonce = currentOccupancyNonce;
        support.updatedAt = currentTimestamp;

        if (newlyOpened) {
            emit SenateActionCancellationOpened(actionId, seatIndex, msg.sender, currentTimestamp);
        }

        uint256 supportCount = _supportCount(_actionCancellationSupports[actionId], 0);
        emit SenateActionSupportRecorded(actionId, seatIndex, msg.sender, supportCount, currentTimestamp);
    }

    function _castReferendumVetoVote(bytes32 referendumId, uint32 seatIndex) private {
        _requireSeatHolder(seatIndex, msg.sender);

        ReferendumTypes.ReferendumRecord memory referendumRecord = _requireVetoEligibleReferendum(referendumId);
        SenateTypes.ReferendumVetoRecord storage referendumVetoRecord = _referendumVetoRecords[referendumId];
        uint64 currentTimestamp = uint64(block.timestamp);
        if (referendumVetoRecord.finalized) {
            revert SenateProcessAlreadyFinalized(referendumId);
        }

        bool newlyOpened = !referendumVetoRecord.exists;
        _openReferendumVetoIfNeeded(referendumVetoRecord, referendumRecord, currentTimestamp);
        _requireVoteOpen(referendumVetoRecord.deadline);

        SenateTypes.VoteSupport storage support = _referendumVetoSupports[referendumId][seatIndex];
        uint64 currentOccupancyNonce = _currentSeatOccupancyNonce(seatIndex);
        if (support.option == SenateTypes.VoteOption.For && support.seatOccupancyNonce == currentOccupancyNonce) {
            revert SenateSupportAlreadyActive(referendumId, seatIndex);
        }

        support.supported = true;
        support.option = SenateTypes.VoteOption.For;
        support.seatOccupancyNonce = currentOccupancyNonce;
        support.updatedAt = currentTimestamp;

        if (newlyOpened) {
            emit SenateReferendumVetoOpened(referendumId, seatIndex, msg.sender, currentTimestamp);
        }

        uint256 supportCount = _supportCount(_referendumVetoSupports[referendumId], 0);
        emit SenateReferendumSupportRecorded(referendumId, seatIndex, msg.sender, supportCount, currentTimestamp);
    }

    function _castSubLegalMeasureRepealVote(bytes32 measureId, uint32 seatIndex) private {
        _requireSeatHolder(seatIndex, msg.sender);

        LegislationTypes.LegislationRecord memory legislationRecord = _requireSubLegalMeasureRepealable(measureId);
        SenateTypes.SubLegalMeasureRepealRecord storage repealRecord = _subLegalMeasureRepealRecords[measureId];
        uint64 currentTimestamp = uint64(block.timestamp);

        bool newlyOpened = !repealRecord.exists || repealRecord.finalized;
        _openSubLegalMeasureRepealIfNeeded(repealRecord, legislationRecord, currentTimestamp);
        _requireVoteOpen(repealRecord.deadline);

        SenateTypes.VoteSupport storage support = _subLegalMeasureRepealSupports[measureId][seatIndex];
        uint64 currentOccupancyNonce = _currentSeatOccupancyNonce(seatIndex);
        if (
            support.option == SenateTypes.VoteOption.For && support.attemptNonce == repealRecord.attemptNonce
                && support.seatOccupancyNonce == currentOccupancyNonce
        ) {
            revert SenateSupportAlreadyActive(measureId, seatIndex);
        }

        support.supported = true;
        support.option = SenateTypes.VoteOption.For;
        support.attemptNonce = repealRecord.attemptNonce;
        support.seatOccupancyNonce = currentOccupancyNonce;
        support.updatedAt = currentTimestamp;

        if (newlyOpened) {
            emit SenateSubLegalMeasureRepealOpened(
                measureId, repealRecord.repealId, seatIndex, msg.sender, currentTimestamp, repealRecord.deadline
            );
        }

        uint256 supportCount = _supportCount(_subLegalMeasureRepealSupports[measureId], repealRecord.attemptNonce);
        emit SenateSubLegalMeasureRepealSupportRecorded(
            measureId, seatIndex, msg.sender, supportCount, currentTimestamp
        );
    }

    function _openActionCancellationIfNeeded(
        SenateTypes.ActionCancellationRecord storage actionCancellationRecord,
        GovernanceTypes.ActionRecord memory actionRecord,
        uint64 currentTimestamp
    ) private {
        if (actionCancellationRecord.exists) {
            return;
        }

        actionCancellationRecord.actionId = actionRecord.actionId;
        actionCancellationRecord.createdAt = currentTimestamp;
        actionCancellationRecord.deadline = actionRecord.earliestExecutionTime;
        actionCancellationRecord.exists = true;
    }

    function _openReferendumVetoIfNeeded(
        SenateTypes.ReferendumVetoRecord storage referendumVetoRecord,
        ReferendumTypes.ReferendumRecord memory referendumRecord,
        uint64 currentTimestamp
    ) private {
        if (referendumVetoRecord.exists) {
            return;
        }

        referendumVetoRecord.referendumId = referendumRecord.referendumId;
        referendumVetoRecord.createdAt = currentTimestamp;
        referendumVetoRecord.deadline = referendumRecord.endTime;
        referendumVetoRecord.exists = true;
    }

    function _openSubLegalMeasureRepealIfNeeded(
        SenateTypes.SubLegalMeasureRepealRecord storage repealRecord,
        LegislationTypes.LegislationRecord memory legislationRecord,
        uint64 currentTimestamp
    ) private {
        if (repealRecord.exists && !repealRecord.finalized) {
            return;
        }

        uint64 attemptNonce = repealRecord.attemptNonce + 1;
        repealRecord.measureId = legislationRecord.measureId;
        repealRecord.repealId = _subLegalMeasureRepealId(legislationRecord.measureId, attemptNonce);
        repealRecord.attemptNonce = attemptNonce;
        repealRecord.createdAt = currentTimestamp;
        repealRecord.deadline = currentTimestamp + SUB_LEGAL_REPEAL_VOTING_PERIOD;
        repealRecord.finalizedAt = 0;
        repealRecord.repealedAt = 0;
        repealRecord.supportSnapshot = 0;
        repealRecord.presidentProxySupportSnapshot = 0;
        repealRecord.exists = true;
        repealRecord.finalized = false;
        repealRecord.repealed = false;

        delete _subLegalMeasureRepealPresidentProxyVotes[legislationRecord.measureId];
    }

    function _requireCancelableAction(bytes32 actionId)
        private
        view
        returns (GovernanceTypes.ActionRecord memory actionRecord)
    {
        actionRecord = _actionTimelock.getAction(actionId);
        if (!_senatePowersPolicy.isActionCancellationAllowed(actionRecord)) {
            revert SenateProcessNotAllowed(actionId);
        }
    }

    /// @dev Non-reverting cancelability probe used at finalization so a met-but-unactionable vote can still close.
    function _isActionCancelable(bytes32 actionId) private view returns (bool cancelable) {
        GovernanceTypes.ActionRecord memory actionRecord = _actionTimelock.getAction(actionId);
        return _senatePowersPolicy.isActionCancellationAllowed(actionRecord);
    }

    function _requireVetoEligibleReferendum(bytes32 referendumId)
        private
        view
        returns (ReferendumTypes.ReferendumRecord memory referendumRecord)
    {
        IReferendumRegistry referendumRegistry = IReferendumRegistry(_referendumApp.referendumRegistry());
        referendumRecord = referendumRegistry.getReferendum(referendumId);
        if (
            referendumRecord.referendumId == bytes32(0)
                || referendumRecord.status != ReferendumTypes.ReferendumStatus.Active
                || block.timestamp < referendumRecord.startTime || block.timestamp >= referendumRecord.endTime
                || referendumRecord.referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment
        ) {
            revert SenateProcessNotAllowed(referendumId);
        }
    }

    function _requireSubLegalMeasureRepealable(bytes32 measureId)
        private
        view
        returns (LegislationTypes.LegislationRecord memory legislationRecord)
    {
        legislationRecord = _legislationRegistry.getLegislationRecord(measureId);
        if (
            legislationRecord.measureId == bytes32(0) || !legislationRecord.active || legislationRecord.repealed
                || !LegislationTypes.isSubLegalTier(legislationRecord.tier)
        ) {
            revert SenateProcessNotAllowed(measureId);
        }
    }

    /// @dev Non-reverting repealability probe used at finalization so a met-but-unactionable vote can still close.
    function _isSubLegalMeasureRepealable(bytes32 measureId) private view returns (bool repealable) {
        LegislationTypes.LegislationRecord memory legislationRecord =
            _legislationRegistry.getLegislationRecord(measureId);
        return legislationRecord.measureId != bytes32(0) && legislationRecord.active && !legislationRecord.repealed
            && LegislationTypes.isSubLegalTier(legislationRecord.tier);
    }

    function _requireValidVoteOption(SenateTypes.VoteOption option) private pure {
        if (option != SenateTypes.VoteOption.Against && option != SenateTypes.VoteOption.For) {
            revert InvalidSenateVoteOption(option);
        }
    }

    function _requirePresident(address caller) private view {
        // Only a President whose 5-year term is still running may cast proxy votes: an expired (or vacated)
        // President must not retain Senate proxy power until a successor is elected.
        if (
            caller == address(0) || caller != _presidentRegistry.currentPresident()
                || !_presidentRegistry.isPresidentInTerm()
        ) {
            revert NotPresident(caller);
        }
    }

    function _requireVoteOpen(uint64 deadline) private view {
        if (deadline == 0 || block.timestamp >= deadline) {
            revert SenateVoteNotOpen(deadline, uint64(block.timestamp));
        }
    }

    function _requireVoteFinalizable(uint64 deadline) private view {
        if (deadline == 0 || block.timestamp < deadline) {
            revert SenateVoteNotFinalizable(deadline, uint64(block.timestamp));
        }
    }

    /// @dev Shared seat tally for every negative-control threshold check. Each seat currently registering an active
    ///      For support counts toward direct support; every other occupied seat is covered by the President proxy
    ///      when `proxyActive` is true. Callers precompute `proxyActive` because the deadline-anchored processes gate
    ///      the proxy on the President's term and vote window while the live disbursement suspension does not.
    ///      `attemptNonce` gates the sub-legal repeal process (zero for the others).
    function _tally(
        mapping(uint32 => SenateTypes.VoteSupport) storage seatSupports,
        bool proxyActive,
        uint64 attemptNonce
    ) private view returns (uint256 directSupportCount, uint256 presidentProxySupportCount) {
        uint32 seatCount = _senatePowersPolicy.seatCount();
        for (uint32 seatIndex = 0; seatIndex < seatCount; ++seatIndex) {
            if (_isSupportActive(seatIndex, seatSupports[seatIndex], attemptNonce)) {
                directSupportCount += 1;
                continue;
            }

            if (proxyActive && _isSeatCurrentlyOccupied(seatIndex)) {
                presidentProxySupportCount += 1;
            }
        }
    }

    /// @dev A disbursement suspension is a temporary pause bounded by the action's own life: it never blocks past
    ///      the action's expiry. This keeps suspension from acting as an unbounded, renew-forever kill switch that
    ///      outlasts the execution window — permanently stopping a disbursement is the cancellation path's job.
    function _boundedSuspensionDeadline(uint64 currentTimestamp, uint64 actionExpiresAt)
        private
        view
        returns (uint64 suspendedUntil)
    {
        suspendedUntil = currentTimestamp + _senatePowersPolicy.disbursementSuspensionPeriod();
        if (suspendedUntil > actionExpiresAt) {
            suspendedUntil = actionExpiresAt;
        }
    }

    function _requireSuspendableDisbursement(bytes32 actionId)
        private
        view
        returns (GovernanceTypes.ActionRecord memory actionRecord)
    {
        actionRecord = _actionTimelock.getAction(actionId);
        if (
            actionRecord.actionType != GovernanceTypes.ActionType.TreasuryDisbursement
                || actionRecord.state != GovernanceTypes.ActionState.Queued
        ) {
            revert SenateProcessNotAllowed(actionId);
        }
    }

    /// @dev Live seat tally (current occupancy) mirroring the cancellation support/President-proxy-floor model. The
    ///      proxy is gated on there being a President still in term (L-2), so a resigned/expired President's stale
    ///      proxy cannot keep powering suspensions and renewals.
    function _disbursementSuspensionSupportBreakdown(bytes32 actionId)
        private
        view
        returns (uint256 directSupportCount, uint256 presidentProxySupportCount)
    {
        SenateTypes.PresidentProxyVote memory proxyVote = _disbursementSuspensionPresidentProxyVotes[actionId];
        bool proxyActive = _presidentRegistry.isPresidentInTerm() && proxyVote.option == SenateTypes.VoteOption.For
            && proxyVote.updatedAt != 0;
        return _tally(_disbursementSuspensionSupports[actionId], proxyActive, 0);
    }

    function _requireDisbursementSuspensionAuthorized(
        bytes32 actionId,
        uint256 directSupportCount,
        uint256 presidentProxySupportCount
    ) private view {
        // Threshold with the Change-2 President-proxy floor applied by capping proxy coverage at explicit seat
        // support: the proxy can amplify but never fabricate or defeat the required support.
        if (
            _effectiveSupport(directSupportCount, presidentProxySupportCount)
                < _senatePowersPolicy.minimumActionCancellationSupport()
        ) {
            revert SenateSupportNotReached(
                actionId, directSupportCount + presidentProxySupportCount, presidentProxySupportCount
            );
        }
    }

    /// @dev President-proxy floor applied as a cap: proxy coverage of silent seats counts toward the threshold only
    ///      up to the number of seats that cast an explicit For. This guarantees the proxy can never (a) manufacture
    ///      a proxy-only majority, nor (b) reduce an outcome that direct support alone achieves — a supporting proxy
    ///      only ever adds support. Recorded snapshots/events keep the raw observed counts; only the pass decision
    ///      uses this capped value.
    function _effectiveSupport(uint256 directSupportCount, uint256 presidentProxySupportCount)
        private
        pure
        returns (uint256 supportCount)
    {
        uint256 countedProxy =
            presidentProxySupportCount > directSupportCount ? directSupportCount : presidentProxySupportCount;
        return directSupportCount + countedProxy;
    }

    function _presidentProxySupports(SenateTypes.PresidentProxyVote memory proxyVote, uint64 openedAt, uint64 deadline)
        private
        view
        returns (bool proxySupports)
    {
        // The proxy counts only while there is a President whose 5-year term is still running: a resigned
        // (office vacated) or expired President's previously-cast proxy stops counting at finalization.
        return _presidentRegistry.isPresidentInTerm() && proxyVote.option == SenateTypes.VoteOption.For
            && proxyVote.updatedAt != 0 && proxyVote.updatedAt >= openedAt && proxyVote.updatedAt < deadline;
    }

    function _isSeatCurrentlyOccupied(uint32 seatIndex) private view returns (bool occupied) {
        SenateTypes.SenateSeatRecord memory seatRecord = _senateSeatRegistry.getSeatRecord(seatIndex);
        return !seatRecord.vacant && seatRecord.holder != address(0);
    }

    /// @dev Live count of seats currently registering an active For support, shared by every process's support-count
    ///      view. `attemptNonce` gates the sub-legal repeal process (zero for the others).
    function _supportCount(mapping(uint32 => SenateTypes.VoteSupport) storage seatSupports, uint64 attemptNonce)
        private
        view
        returns (uint256 count)
    {
        uint32 seatCount = _senatePowersPolicy.seatCount();
        for (uint32 seatIndex = 0; seatIndex < seatCount; ++seatIndex) {
            if (_isSupportActive(seatIndex, seatSupports[seatIndex], attemptNonce)) {
                count += 1;
            }
        }
    }

    /// @dev A seat support is currently active if it is a For support from the seat's still-current occupant with a
    ///      matching attempt nonce. Shared by the support-count views, support getters, and the live disbursement
    ///      tally.
    function _isSupportActive(uint32 seatIndex, SenateTypes.VoteSupport memory support, uint64 attemptNonce)
        private
        view
        returns (bool active)
    {
        if (!support.supported || support.option != SenateTypes.VoteOption.For || support.attemptNonce != attemptNonce)
        {
            return false;
        }

        SenateTypes.SenateSeatRecord memory seatRecord = _senateSeatRegistry.getSeatRecord(seatIndex);
        return !seatRecord.vacant && seatRecord.holder != address(0)
            && seatRecord.occupancyNonce == support.seatOccupancyNonce;
    }

    function _subLegalMeasureRepealId(bytes32 measureId, uint64 attemptNonce) private view returns (bytes32 repealId) {
        return keccak256(abi.encode(block.chainid, address(this), "senate-sub-legal-repeal", measureId, attemptNonce));
    }

    function _currentSeatOccupancyNonce(uint32 seatIndex) private view returns (uint64 occupancyNonce) {
        return _senateSeatRegistry.getSeatRecord(seatIndex).occupancyNonce;
    }
}
