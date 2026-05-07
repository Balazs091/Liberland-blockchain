// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title IPayoutQueue
/// @notice Audited queue for office-authorized treasury payout requests.
interface IPayoutQueue {
    error InvalidPayoutRequest(bytes32 requestId);
    error PayoutRequestAlreadyExists(bytes32 requestId);
    error PayoutRequestAlreadyFinalized(bytes32 requestId, TreasuryTypes.DisbursementState state);
    error PayoutRequestAlreadyQueued(bytes32 requestId, bytes32 actionId);
    error PayoutRequestNotQueued(bytes32 requestId);
    error PayoutRequestNotReady(bytes32 requestId, uint64 routeAfter);
    error UnauthorizedPayoutQueueCaller(address caller);

    event PayoutProposed(
        bytes32 indexed requestId,
        bytes32 indexed budgetId,
        bytes32 indexed officeId,
        TreasuryTypes.DisbursementType disbursementType,
        address recipient,
        uint256 amount,
        bytes32 policyReference,
        bytes32 noteHash,
        uint64 createdAt,
        uint64 routeAfter,
        address proposedBy
    );

    event PayoutQueued(bytes32 indexed requestId, bytes32 indexed actionId, uint64 queuedAt, address indexed queuedBy);
    event PayoutCanceled(bytes32 indexed requestId, uint64 canceledAt, address indexed canceledBy);
    event PayoutVetoed(bytes32 indexed requestId, bytes32 indexed actionId, uint64 vetoedAt, address indexed vetoedBy);
    event PayoutExecuted(
        bytes32 indexed requestId, bytes32 indexed actionId, uint64 executedAt, address indexed recordedBy
    );
    event PayoutExpired(
        bytes32 indexed requestId, bytes32 indexed actionId, uint64 expiredAt, address indexed recordedBy
    );

    function kernel() external view returns (address kernelAddress);
    function getDisbursementRequest(bytes32 requestId)
        external
        view
        returns (TreasuryTypes.DisbursementRequest memory request);
    function requestExists(bytes32 requestId) external view returns (bool exists);
    function totalDisbursementRequestCount() external view returns (uint256 count);
    function disbursementRequestIdAt(uint256 index) external view returns (bytes32 requestId);
    function proposePayout(TreasuryTypes.DisbursementRequestInput calldata input, uint64 routeAfter) external;
    function prepareRouting(bytes32 requestId)
        external
        returns (GovernanceTypes.TreasuryDisbursementPayload memory payload);
    function confirmRouted(bytes32 requestId, bytes32 actionId) external;
    function cancelPayout(bytes32 requestId) external;
    function syncPayoutState(bytes32 requestId) external returns (TreasuryTypes.DisbursementState state);
}
