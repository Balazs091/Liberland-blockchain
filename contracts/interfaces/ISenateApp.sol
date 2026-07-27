// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {SenateTypes} from "../types/SenateTypes.sol";

/// @title ISenateApp
/// @notice User-facing interface for Senate seat succession and bounded negative-control action cancellation.
interface ISenateApp {
    // Generic negative-control process errors shared by action cancellation, referendum veto, sub-legal repeal, and
    // disbursement suspension. `processId` is the actionId / referendumId / measureId of the affected process.
    error SenateProcessAlreadyFinalized(bytes32 processId);
    error SenateProcessNotAllowed(bytes32 processId);
    error SenateVoteNotOpen(uint64 deadline, uint64 currentTimestamp);
    error SenateVoteNotFinalizable(uint64 deadline, uint64 currentTimestamp);
    error SenateSupportAlreadyActive(bytes32 processId, uint32 seatIndex);
    error SenateSupportNotActive(bytes32 processId, uint32 seatIndex);
    error SenateSupportNotReached(bytes32 processId, uint256 supportCount, uint256 presidentProxySupportCount);
    error SenateSeatRecipientNotCitizen(address wallet, bytes32 personId);
    error DisbursementAlreadySuspended(bytes32 actionId, uint64 suspendedUntil);
    error DisbursementSuspensionNotRenewable(bytes32 actionId, uint64 suspendedUntil);
    error InvalidDisbursementSuspensionReason(bytes32 reasonHash);
    error InvalidPolicy(address policyAddress);
    error InvalidPresidentRegistry(address registryAddress);
    error InvalidRegistry(address registryAddress);
    error InvalidReferendumApp(address referendumApp);
    error InvalidRouter(address routerAddress);
    error InvalidSenateVoteOption(SenateTypes.VoteOption option);
    error NotPresident(address caller);
    error InvalidTimelock(address timelockAddress);
    error NotNominatedSuccessor(uint32 seatIndex, address claimant);
    error NotSeatHolder(uint32 seatIndex, address caller);
    error SeatNotVacant(uint32 seatIndex);
    error UnauthorizedBootstrapCaller(address caller);
    error UnknownPersonReference(address wallet);

    event SenateActionCancellationOpened(
        bytes32 indexed actionId, uint32 indexed openedBySeat, address indexed openedBy, uint64 openedAt
    );

    event SenateActionSupportRecorded(
        bytes32 indexed actionId,
        uint32 indexed seatIndex,
        address indexed seatHolder,
        uint256 supportCount,
        uint64 recordedAt
    );

    event SenateActionSupportRemoved(
        bytes32 indexed actionId,
        uint32 indexed seatIndex,
        address indexed seatHolder,
        uint256 supportCount,
        uint64 removedAt
    );

    event SenateActionCanceled(
        bytes32 indexed actionId, uint256 indexed supportCount, address indexed canceledBy, uint64 canceledAt
    );

    event PresidentActionCancellationProxyVoteRecorded(
        bytes32 indexed actionId, address indexed president, SenateTypes.VoteOption option, uint64 recordedAt
    );

    event SenateActionCancellationFinalized(
        bytes32 indexed actionId,
        uint256 indexed supportCount,
        uint256 presidentProxySupportCount,
        bool canceled,
        address indexed finalizedBy,
        uint64 finalizedAt
    );

    event SenateReferendumVetoOpened(
        bytes32 indexed referendumId, uint32 indexed openedBySeat, address indexed openedBy, uint64 openedAt
    );

    event SenateReferendumSupportRecorded(
        bytes32 indexed referendumId,
        uint32 indexed seatIndex,
        address indexed seatHolder,
        uint256 supportCount,
        uint64 recordedAt
    );

    event SenateReferendumSupportRemoved(
        bytes32 indexed referendumId,
        uint32 indexed seatIndex,
        address indexed seatHolder,
        uint256 supportCount,
        uint64 removedAt
    );

    event SenateReferendumVetoed(
        bytes32 indexed referendumId, uint256 indexed supportCount, address indexed vetoedBy, uint64 vetoedAt
    );

    event PresidentReferendumVetoProxyVoteRecorded(
        bytes32 indexed referendumId, address indexed president, SenateTypes.VoteOption option, uint64 recordedAt
    );

    event SenateReferendumVetoFinalized(
        bytes32 indexed referendumId,
        uint256 indexed supportCount,
        uint256 presidentProxySupportCount,
        bool vetoed,
        address indexed finalizedBy,
        uint64 finalizedAt
    );

    event SenateSubLegalMeasureRepealOpened(
        bytes32 indexed measureId,
        bytes32 indexed repealId,
        uint32 indexed openedBySeat,
        address openedBy,
        uint64 openedAt,
        uint64 deadline
    );

    event SenateSubLegalMeasureRepealSupportRecorded(
        bytes32 indexed measureId,
        uint32 indexed seatIndex,
        address indexed seatHolder,
        uint256 supportCount,
        uint64 recordedAt
    );

    event SenateSubLegalMeasureRepealSupportRemoved(
        bytes32 indexed measureId,
        uint32 indexed seatIndex,
        address indexed seatHolder,
        uint256 supportCount,
        uint64 removedAt
    );

    event PresidentSubLegalMeasureRepealProxyVoteRecorded(
        bytes32 indexed measureId, address indexed president, SenateTypes.VoteOption option, uint64 recordedAt
    );

    event SenateSubLegalMeasureRepealed(
        bytes32 indexed measureId,
        bytes32 indexed repealId,
        uint256 indexed supportCount,
        address repealedBy,
        uint64 repealedAt
    );

    event SenateSubLegalMeasureRepealFinalized(
        bytes32 indexed measureId,
        uint256 indexed supportCount,
        uint256 presidentProxySupportCount,
        bool repealed,
        address indexed finalizedBy,
        uint64 finalizedAt
    );

    event SenateDisbursementSuspensionSupportRecorded(
        bytes32 indexed actionId, uint32 indexed seatIndex, address indexed seatHolder, uint64 recordedAt
    );

    event SenateDisbursementSuspensionSupportRemoved(
        bytes32 indexed actionId, uint32 indexed seatIndex, address indexed seatHolder, uint64 removedAt
    );

    event PresidentDisbursementSuspensionProxyVoteRecorded(
        bytes32 indexed actionId, address indexed president, SenateTypes.VoteOption option, uint64 recordedAt
    );

    event SenateDisbursementSuspended(
        bytes32 indexed actionId,
        bytes32 indexed reasonHash,
        uint64 suspendedUntil,
        uint256 supportCount,
        uint256 presidentProxySupportCount,
        address indexed suspendedBy,
        uint64 suspendedAt
    );

    event SenateDisbursementSuspensionRenewed(
        bytes32 indexed actionId,
        bytes32 indexed reasonHash,
        uint64 suspendedUntil,
        uint32 renewalCount,
        address indexed renewedBy,
        uint64 renewedAt
    );

    /// @notice Returns the configured identity registry address used for holder and successor person resolution.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured Senate seat registry address.
    /// @return registryAddress The Senate seat registry address.
    function senateSeatRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured legislation registry address used for sub-legal repeal checks.
    /// @return registryAddress The legislation registry address.
    function legislationRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured Senate powers policy address.
    /// @return policyAddress The Senate powers policy address.
    function senatePowersPolicy() external view returns (address policyAddress);

    /// @notice Returns the configured President registry address.
    /// @return registryAddress The President registry address.
    function presidentRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured governance router address.
    /// @return routerAddress The governance router address.
    function governanceRouter() external view returns (address routerAddress);

    /// @notice Returns the configured action timelock address.
    /// @return timelockAddress The action timelock address.
    function actionTimelock() external view returns (address timelockAddress);

    /// @notice Returns the configured referendum app address used for active referendum veto.
    /// @return appAddress The referendum app address.
    function referendumApp() external view returns (address appAddress);

    /// @notice Returns the stored action-cancellation process record for a queued action.
    /// @param actionId The queued action identifier.
    /// @return record The stored Senate cancellation process record.
    function getActionCancellationRecord(bytes32 actionId)
        external
        view
        returns (SenateTypes.ActionCancellationRecord memory record);

    /// @notice Returns the current support receipt for a seat on an action cancellation process.
    /// @param actionId The queued action identifier.
    /// @param seatIndex The fixed seat index to inspect.
    /// @return support The seat's current support receipt.
    function getActionCancellationSupport(bytes32 actionId, uint32 seatIndex)
        external
        view
        returns (SenateTypes.VoteSupport memory support);

    /// @notice Returns the President proxy vote for an action-cancellation process.
    /// @param actionId The queued action identifier.
    /// @return proxyVote The stored President proxy vote, or Undefined if unset.
    function getActionCancellationPresidentProxyVote(bytes32 actionId)
        external
        view
        returns (SenateTypes.PresidentProxyVote memory proxyVote);

    /// @notice Returns the current number of valid seat supports for an action cancellation process.
    /// @param actionId The queued action identifier.
    /// @return count The current number of valid supporting seats.
    function actionCancellationSupportCount(bytes32 actionId) external view returns (uint256 count);

    /// @notice Returns the stored Senate veto process record for an active referendum.
    /// @param referendumId The referendum identifier.
    /// @return record The stored Senate referendum veto record.
    function getReferendumVetoRecord(bytes32 referendumId)
        external
        view
        returns (SenateTypes.ReferendumVetoRecord memory record);

    /// @notice Returns the current support receipt for a seat on a referendum veto process.
    /// @param referendumId The referendum identifier.
    /// @param seatIndex The fixed seat index to inspect.
    /// @return support The seat's current support receipt.
    function getReferendumVetoSupport(bytes32 referendumId, uint32 seatIndex)
        external
        view
        returns (SenateTypes.VoteSupport memory support);

    /// @notice Returns the President proxy vote for a referendum-veto process.
    /// @param referendumId The referendum identifier.
    /// @return proxyVote The stored President proxy vote, or Undefined if unset.
    function getReferendumVetoPresidentProxyVote(bytes32 referendumId)
        external
        view
        returns (SenateTypes.PresidentProxyVote memory proxyVote);

    /// @notice Returns the current number of valid seat supports for a referendum veto process.
    /// @param referendumId The referendum identifier.
    /// @return count The current number of valid supporting seats.
    function referendumVetoSupportCount(bytes32 referendumId) external view returns (uint256 count);

    /// @notice Returns the stored Senate repeal process record for a sub-legal measure.
    /// @param measureId The enacted measure identifier.
    /// @return record The stored Senate sub-legal repeal record.
    function getSubLegalMeasureRepealRecord(bytes32 measureId)
        external
        view
        returns (SenateTypes.SubLegalMeasureRepealRecord memory record);

    /// @notice Returns the current support receipt for a seat on a sub-legal repeal process.
    /// @param measureId The enacted measure identifier.
    /// @param seatIndex The fixed seat index to inspect.
    /// @return support The seat's current support receipt.
    function getSubLegalMeasureRepealSupport(bytes32 measureId, uint32 seatIndex)
        external
        view
        returns (SenateTypes.VoteSupport memory support);

    /// @notice Returns the President proxy vote for a sub-legal repeal process.
    /// @param measureId The enacted measure identifier.
    /// @return proxyVote The stored President proxy vote, or Undefined if unset.
    function getSubLegalMeasureRepealPresidentProxyVote(bytes32 measureId)
        external
        view
        returns (SenateTypes.PresidentProxyVote memory proxyVote);

    /// @notice Returns the current number of valid seat supports for a sub-legal repeal process.
    /// @param measureId The enacted measure identifier.
    /// @return count The current number of valid supporting seats.
    function subLegalMeasureRepealSupportCount(bytes32 measureId) external view returns (uint256 count);

    /// @notice Assigns a Senate seat during bootstrap through the shared kernel bootstrap authority.
    /// @param seatIndex The seat index to assign.
    /// @param holder The holder wallet to assign.
    function bootstrapAssignSeat(uint32 seatIndex, address holder) external;

    /// @notice Vacates the caller's occupied Senate seat.
    /// @param seatIndex The seat index held by the caller.
    function vacateMySeat(uint32 seatIndex) external;

    /// @notice Transfers the caller's occupied seat directly to another eligible wallet.
    /// @param seatIndex The seat index held by the caller.
    /// @param recipient The new seat holder wallet.
    function transferMySeat(uint32 seatIndex, address recipient) external;

    /// @notice Stores or replaces the nominated successor for the caller's occupied seat.
    /// @param seatIndex The seat index held by the caller.
    /// @param nominee The nominated successor wallet.
    function nominateSuccessor(uint32 seatIndex, address nominee) external;

    /// @notice Clears the nominated successor for the caller's occupied seat.
    /// @param seatIndex The seat index held by the caller.
    function clearSuccessor(uint32 seatIndex) external;

    /// @notice Claims a vacant Senate seat when the caller is the nominated successor person.
    /// @param seatIndex The vacant seat index to claim.
    function claimSeatBySuccession(uint32 seatIndex) external;

    /// @notice Records equal-weight seat support to cancel a queued governance action.
    /// @param actionId The queued action identifier to cancel.
    /// @param seatIndex The caller-controlled seat index contributing support.
    function supportActionCancellation(bytes32 actionId, uint32 seatIndex) external;

    /// @notice Removes equal-weight seat support from an action cancellation process.
    /// @param actionId The queued action identifier to update.
    /// @param seatIndex The caller-controlled seat index to remove.
    function removeActionCancellationSupport(bytes32 actionId, uint32 seatIndex) external;

    /// @notice Records the President's proxy vote for non-voting seats in an action-cancellation process.
    /// @param actionId The queued action identifier to vote on.
    /// @param option The President proxy vote option.
    function castPresidentActionCancellationProxyVote(bytes32 actionId, SenateTypes.VoteOption option) external;

    /// @notice Finalizes an action-cancellation vote after its deadline and cancels the action if threshold is met.
    /// @param actionId The queued action identifier to finalize.
    function finalizeActionCancellation(bytes32 actionId) external;

    /// @notice Records equal-weight seat support to cancel an active veto-eligible referendum.
    /// @param referendumId The active referendum identifier to veto.
    /// @param seatIndex The caller-controlled seat index contributing support.
    function supportReferendumVeto(bytes32 referendumId, uint32 seatIndex) external;

    /// @notice Removes equal-weight seat support from a referendum veto process.
    /// @param referendumId The referendum identifier to update.
    /// @param seatIndex The caller-controlled seat index to remove.
    function removeReferendumVetoSupport(bytes32 referendumId, uint32 seatIndex) external;

    /// @notice Records the President's proxy vote for non-voting seats in a referendum-veto process.
    /// @param referendumId The active referendum identifier to vote on.
    /// @param option The President proxy vote option.
    function castPresidentReferendumVetoProxyVote(bytes32 referendumId, SenateTypes.VoteOption option) external;

    /// @notice Finalizes a referendum-veto vote after its deadline and cancels the referendum if threshold is met.
    /// @param referendumId The referendum identifier to finalize.
    function finalizeReferendumVeto(bytes32 referendumId) external;

    /// @notice Records equal-weight seat support to repeal an enacted sub-legal measure.
    /// @param measureId The enacted sub-legal measure identifier.
    /// @param seatIndex The caller-controlled seat index contributing support.
    function supportSubLegalMeasureRepeal(bytes32 measureId, uint32 seatIndex) external;

    /// @notice Removes equal-weight seat support from a sub-legal measure repeal process.
    /// @param measureId The enacted sub-legal measure identifier.
    /// @param seatIndex The caller-controlled seat index to remove.
    function removeSubLegalMeasureRepealSupport(bytes32 measureId, uint32 seatIndex) external;

    /// @notice Records the President's proxy vote for non-voting seats in a sub-legal repeal process.
    /// @param measureId The enacted sub-legal measure identifier.
    /// @param option The President proxy vote option.
    function castPresidentSubLegalMeasureRepealProxyVote(bytes32 measureId, SenateTypes.VoteOption option) external;

    /// @notice Finalizes a sub-legal repeal vote after its deadline and repeals the measure if threshold is met.
    /// @param measureId The enacted sub-legal measure identifier.
    function finalizeSubLegalMeasureRepeal(bytes32 measureId) external;

    /// @notice Returns the temporary suspension record for a queued treasury disbursement action.
    /// @param actionId The queued treasury disbursement action identifier.
    /// @return suspension The stored auto-lapsing suspension record.
    function getDisbursementSuspension(bytes32 actionId)
        external
        view
        returns (SenateTypes.DisbursementSuspension memory suspension);

    /// @notice Records equal-weight seat support to temporarily suspend a queued treasury disbursement action.
    /// @param actionId The queued treasury disbursement action identifier.
    /// @param seatIndex The caller-controlled seat index contributing support.
    function supportDisbursementSuspension(bytes32 actionId, uint32 seatIndex) external;

    /// @notice Withdraws a seat's standing disbursement-suspension support so it no longer powers future renewals.
    /// @param actionId The queued treasury disbursement action identifier.
    /// @param seatIndex The caller-controlled seat index whose support is withdrawn.
    function removeDisbursementSuspensionSupport(bytes32 actionId, uint32 seatIndex) external;

    /// @notice Records the President's proxy vote for non-voting seats in a disbursement-suspension process.
    /// @param actionId The queued treasury disbursement action identifier.
    /// @param option The President proxy vote option.
    function castPresidentDisbursementSuspensionProxyVote(bytes32 actionId, SenateTypes.VoteOption option) external;

    /// @notice Applies a temporary, auto-lapsing suspension to a queued treasury disbursement once support is reached.
    /// @param actionId The queued treasury disbursement action identifier.
    /// @param supportingSeatIndex A current supporting seat whose holder publishes the reason.
    /// @param reasonHash Hash of the published, reasoned Senate objection supporting the suspension.
    function suspendDisbursement(bytes32 actionId, uint32 supportingSeatIndex, bytes32 reasonHash) external;

    /// @notice Extends an active disbursement suspension before it lapses, under the same Senate authority.
    /// @param actionId The queued treasury disbursement action identifier.
    /// @param supportingSeatIndex A current supporting seat whose holder publishes the renewal reason.
    /// @param reasonHash Hash of the published, reasoned Senate decision supporting the renewal.
    function renewDisbursementSuspension(bytes32 actionId, uint32 supportingSeatIndex, bytes32 reasonHash) external;
}
