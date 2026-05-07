// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IActionTimelock} from "../interfaces/IActionTimelock.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IGovernanceRouter} from "../interfaces/IGovernanceRouter.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ISenateApp} from "../interfaces/ISenateApp.sol";
import {ISenatePowersPolicy} from "../interfaces/ISenatePowersPolicy.sol";
import {ISenateSeatRegistry} from "../interfaces/ISenateSeatRegistry.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {SenateTypes} from "../types/SenateTypes.sol";

/// @title SenateApp
/// @notice User-facing application for v1 Senate succession flows and bounded action-cancellation support.
contract SenateApp is ISenateApp {
    IIdentityRegistry private immutable _identityRegistry;
    ISenateSeatRegistry private immutable _senateSeatRegistry;
    ISenatePowersPolicy private immutable _senatePowersPolicy;
    IGovernanceRouter private immutable _governanceRouter;
    IActionTimelock private immutable _actionTimelock;
    IConstitutionKernel private immutable _kernel;

    mapping(bytes32 actionId => SenateTypes.ActionCancellationRecord actionCancellationRecord) private
        _actionCancellationRecords;
    mapping(bytes32 actionId => mapping(uint32 seatIndex => SenateTypes.ActionCancellationSupport support)) private
        _actionCancellationSupports;

    /// @param identityRegistryAddress The identity registry used to resolve holder and successor person references.
    /// @param senateSeatRegistryAddress The Senate seat registry address.
    /// @param senatePowersPolicyAddress The Senate powers policy address.
    /// @param governanceRouterAddress The governance router address.
    /// @param actionTimelockAddress The action timelock address used to inspect queued actions.
    constructor(
        address identityRegistryAddress,
        address senateSeatRegistryAddress,
        address senatePowersPolicyAddress,
        address governanceRouterAddress,
        address actionTimelockAddress
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
        if (governanceRouterAddress == address(0) || governanceRouterAddress.code.length == 0) {
            revert InvalidRouter(governanceRouterAddress);
        }
        if (actionTimelockAddress == address(0) || actionTimelockAddress.code.length == 0) {
            revert InvalidTimelock(actionTimelockAddress);
        }

        ISenateSeatRegistry senateSeatRegistry_ = ISenateSeatRegistry(senateSeatRegistryAddress);
        ISenatePowersPolicy senatePowersPolicy_ = ISenatePowersPolicy(senatePowersPolicyAddress);
        IGovernanceRouter governanceRouter_ = IGovernanceRouter(governanceRouterAddress);

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
        if (senateSeatRegistry_.totalSeats() != senatePowersPolicy_.seatCount()) {
            revert InvalidPolicy(senatePowersPolicyAddress);
        }

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _senateSeatRegistry = senateSeatRegistry_;
        _senatePowersPolicy = senatePowersPolicy_;
        _governanceRouter = governanceRouter_;
        _actionTimelock = IActionTimelock(actionTimelockAddress);
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
    function senatePowersPolicy() external view returns (address policyAddress) {
        return address(_senatePowersPolicy);
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
        returns (SenateTypes.ActionCancellationSupport memory support)
    {
        support = _actionCancellationSupports[actionId][seatIndex];
        if (!_isSupportCurrentlyActive(actionId, seatIndex, support)) {
            support.supported = false;
        }
    }

    /// @inheritdoc ISenateApp
    function actionCancellationSupportCount(bytes32 actionId) external view returns (uint256 count) {
        return _actionCancellationSupportCount(actionId);
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
        _requireSeatHolder(seatIndex, msg.sender);
        _requireCancelableAction(actionId);

        SenateTypes.ActionCancellationRecord storage actionCancellationRecord = _actionCancellationRecords[actionId];
        uint64 currentTimestamp = uint64(block.timestamp);
        if (actionCancellationRecord.canceled) {
            revert ActionCancellationAlreadyExecuted(actionId);
        }
        if (!actionCancellationRecord.exists) {
            actionCancellationRecord.actionId = actionId;
            actionCancellationRecord.createdAt = currentTimestamp;
            actionCancellationRecord.exists = true;

            emit SenateActionCancellationOpened(actionId, seatIndex, msg.sender, currentTimestamp);
        }

        SenateTypes.ActionCancellationSupport storage support = _actionCancellationSupports[actionId][seatIndex];
        uint64 currentOccupancyNonce = _currentSeatOccupancyNonce(seatIndex);
        if (support.supported && support.seatOccupancyNonce == currentOccupancyNonce) {
            revert ActionSupportAlreadyActive(actionId, seatIndex);
        }

        support.supported = true;
        support.seatOccupancyNonce = currentOccupancyNonce;
        support.updatedAt = currentTimestamp;

        uint256 supportCount = _actionCancellationSupportCount(actionId);
        emit SenateActionSupportRecorded(actionId, seatIndex, msg.sender, supportCount, currentTimestamp);

        if (supportCount >= _senatePowersPolicy.minimumActionCancellationSupport()) {
            actionCancellationRecord.canceled = true;
            actionCancellationRecord.canceledAt = currentTimestamp;
            // forge-lint: disable-next-line(unsafe-typecast)
            actionCancellationRecord.supportSnapshot = uint32(supportCount);

            _governanceRouter.cancelAction(actionId);

            emit SenateActionCanceled(actionId, supportCount, msg.sender, currentTimestamp);
        }
    }

    /// @inheritdoc ISenateApp
    function removeActionCancellationSupport(bytes32 actionId, uint32 seatIndex) external {
        _requireSeatHolder(seatIndex, msg.sender);

        SenateTypes.ActionCancellationRecord storage actionCancellationRecord = _actionCancellationRecords[actionId];
        if (actionCancellationRecord.canceled) {
            revert ActionCancellationAlreadyExecuted(actionId);
        }

        SenateTypes.ActionCancellationSupport storage support = _actionCancellationSupports[actionId][seatIndex];
        uint64 currentOccupancyNonce = _currentSeatOccupancyNonce(seatIndex);
        if (!support.supported || support.seatOccupancyNonce != currentOccupancyNonce) {
            revert ActionSupportNotActive(actionId, seatIndex);
        }

        uint64 currentTimestamp = uint64(block.timestamp);
        support.supported = false;
        support.updatedAt = currentTimestamp;

        uint256 supportCount = _actionCancellationSupportCount(actionId);
        emit SenateActionSupportRemoved(actionId, seatIndex, msg.sender, supportCount, currentTimestamp);
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

    function _requireCancelableAction(bytes32 actionId) private view {
        GovernanceTypes.ActionRecord memory actionRecord = _actionTimelock.getAction(actionId);
        if (!_senatePowersPolicy.isActionCancellationAllowed(actionRecord)) {
            revert ActionCancellationNotAllowed(actionId);
        }
    }

    function _actionCancellationSupportCount(bytes32 actionId) private view returns (uint256 count) {
        uint32 seatCount = _senatePowersPolicy.seatCount();
        for (uint32 seatIndex = 0; seatIndex < seatCount; ++seatIndex) {
            SenateTypes.ActionCancellationSupport memory support = _actionCancellationSupports[actionId][seatIndex];
            if (_isSupportCurrentlyActive(actionId, seatIndex, support)) {
                count += 1;
            }
        }
    }

    function _isSupportCurrentlyActive(
        bytes32, /* actionId */
        uint32 seatIndex,
        SenateTypes.ActionCancellationSupport memory support
    ) private view returns (bool active) {
        if (!support.supported) {
            return false;
        }

        SenateTypes.SenateSeatRecord memory seatRecord = _senateSeatRegistry.getSeatRecord(seatIndex);
        return !seatRecord.vacant && seatRecord.holder != address(0)
            && seatRecord.occupancyNonce == support.seatOccupancyNonce;
    }

    function _currentSeatOccupancyNonce(uint32 seatIndex) private view returns (uint64 occupancyNonce) {
        return _senateSeatRegistry.getSeatRecord(seatIndex).occupancyNonce;
    }
}
