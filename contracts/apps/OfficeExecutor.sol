// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IGovernanceRouter} from "../interfaces/IGovernanceRouter.sol";
import {IOfficeExecutor} from "../interfaces/IOfficeExecutor.sol";
import {IOfficePermissionPolicy} from "../interfaces/IOfficePermissionPolicy.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {IPayoutQueue} from "../interfaces/IPayoutQueue.sol";
import {ITreasurySpendingPolicy} from "../interfaces/ITreasurySpendingPolicy.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title OfficeExecutor
/// @notice Explicit office-role executor for office administration and treasury payout routing.
contract OfficeExecutor is IOfficeExecutor {
    IOfficeRegistry private immutable _officeRegistry;
    IOfficePermissionPolicy private immutable _officePermissionPolicy;
    ITreasurySpendingPolicy private immutable _treasurySpendingPolicy;
    IPayoutQueue private immutable _payoutQueue;
    IGovernanceRouter private immutable _governanceRouter;

    address private _bootstrapAuthority;

    constructor(
        address officeRegistryAddress,
        address officePermissionPolicyAddress,
        address treasurySpendingPolicyAddress,
        address payoutQueueAddress,
        address governanceRouterAddress,
        address bootstrapAuthority_
    ) {
        if (officeRegistryAddress == address(0) || officeRegistryAddress.code.length == 0) {
            revert InvalidBootstrapAuthority(officeRegistryAddress);
        }
        if (officePermissionPolicyAddress == address(0) || officePermissionPolicyAddress.code.length == 0) {
            revert InvalidBootstrapAuthority(officePermissionPolicyAddress);
        }
        if (treasurySpendingPolicyAddress == address(0) || treasurySpendingPolicyAddress.code.length == 0) {
            revert InvalidBootstrapAuthority(treasurySpendingPolicyAddress);
        }
        if (payoutQueueAddress == address(0) || payoutQueueAddress.code.length == 0) {
            revert InvalidBootstrapAuthority(payoutQueueAddress);
        }
        if (governanceRouterAddress == address(0) || governanceRouterAddress.code.length == 0) {
            revert InvalidBootstrapAuthority(governanceRouterAddress);
        }
        if (bootstrapAuthority_ == address(0)) {
            revert InvalidBootstrapAuthority(bootstrapAuthority_);
        }

        _officeRegistry = IOfficeRegistry(officeRegistryAddress);
        _officePermissionPolicy = IOfficePermissionPolicy(officePermissionPolicyAddress);
        _treasurySpendingPolicy = ITreasurySpendingPolicy(treasurySpendingPolicyAddress);
        _payoutQueue = IPayoutQueue(payoutQueueAddress);
        _governanceRouter = IGovernanceRouter(governanceRouterAddress);
        _bootstrapAuthority = bootstrapAuthority_;
    }

    /// @inheritdoc IOfficeExecutor
    function bootstrapAuthority() external view returns (address authority) {
        return _bootstrapAuthority;
    }

    /// @inheritdoc IOfficeExecutor
    function bootstrapCreateOffice(bytes32 officeId, OfficeTypes.OfficeKind kind, string calldata name, address admin)
        external
    {
        _requireBootstrapAuthority(msg.sender);
        _officeRegistry.registerOffice(officeId, kind, name, admin);
    }

    /// @inheritdoc IOfficeExecutor
    function disableBootstrapAuthority() external {
        _requireBootstrapAuthority(msg.sender);
        _bootstrapAuthority = address(0);

        emit OfficeBootstrapAuthorityDisabled(msg.sender);
    }

    /// @inheritdoc IOfficeExecutor
    function assignClerk(bytes32 officeId, address clerk) external {
        _authorizeOfficeAction(officeId, msg.sender, OfficeTypes.OfficeActionClass.ManageClerks);
        _officeRegistry.setClerkStatus(officeId, clerk, true);
    }

    /// @inheritdoc IOfficeExecutor
    function revokeClerk(bytes32 officeId, address clerk) external {
        _authorizeOfficeAction(officeId, msg.sender, OfficeTypes.OfficeActionClass.ManageClerks);
        _officeRegistry.setClerkStatus(officeId, clerk, false);
    }

    /// @inheritdoc IOfficeExecutor
    function transferOfficeAdmin(bytes32 officeId, address newAdmin) external {
        _authorizeOfficeAction(officeId, msg.sender, OfficeTypes.OfficeActionClass.TransferAdmin);
        _officeRegistry.transferOfficeAdmin(officeId, newAdmin);
    }

    /// @inheritdoc IOfficeExecutor
    function renameOffice(bytes32 officeId, string calldata newName) external {
        _authorizeOfficeAdminIncludingInactive(officeId, msg.sender, OfficeTypes.OfficeActionClass.ManageOfficeMetadata);
        _officeRegistry.renameOffice(officeId, newName);
    }

    /// @inheritdoc IOfficeExecutor
    function setOfficeActive(bytes32 officeId, bool active) external {
        _authorizeOfficeAdminIncludingInactive(officeId, msg.sender, OfficeTypes.OfficeActionClass.SetOfficeActive);
        _officeRegistry.setOfficeActive(officeId, active);
    }

    /// @inheritdoc IOfficeExecutor
    function computeBudgetId(bytes32 officeId, uint256 sequence) external pure returns (bytes32 budgetId) {
        return keccak256(abi.encode("budget-envelope", officeId, sequence));
    }

    /// @inheritdoc IOfficeExecutor
    function requestBudgetApproval(
        bytes32,
        bytes32 budgetId,
        TreasuryTypes.DisbursementType,
        address,
        uint256,
        uint64,
        uint64
    ) external pure returns (bytes32) {
        revert BudgetApprovalRequiresReferendum(budgetId);
    }

    /// @inheritdoc IOfficeExecutor
    function proposePayout(bytes32 officeId, TreasuryTypes.DisbursementRequestInput calldata input) external {
        (, OfficeTypes.OfficeRole officeRole) =
            _authorizeOfficeAction(officeId, msg.sender, OfficeTypes.OfficeActionClass.ProposePayout);

        if (input.officeId != officeId) {
            revert OfficeActionOfficeMismatch(officeId, input.officeId);
        }
        if (!_treasurySpendingPolicy.isPayoutAllowed(
                officeId, officeRole, input.disbursementType, input.asset, input.amount
            )) {
            revert UnauthorizedOfficeAction(msg.sender, officeId, OfficeTypes.OfficeActionClass.ProposePayout);
        }

        TreasuryTypes.DisbursementRequestInput memory normalizedInput = TreasuryTypes.DisbursementRequestInput({
            requestId: input.requestId,
            budgetId: input.budgetId,
            officeId: input.officeId,
            disbursementType: input.disbursementType,
            asset: input.asset,
            recipient: input.recipient,
            amount: input.amount,
            policyReference: _treasurySpendingPolicy.computePolicyReference(
                officeId, officeRole, input.disbursementType, input.amount
            ),
            noteHash: input.noteHash,
            noteURI: input.noteURI
        });

        _payoutQueue.proposePayout(
            normalizedInput,
            uint64(block.timestamp)
                + _treasurySpendingPolicy.minimumQueueDelay(officeId, officeRole, input.disbursementType, input.amount)
        );
    }

    /// @inheritdoc IOfficeExecutor
    function routePayout(bytes32 officeId, bytes32 requestId) external returns (bytes32 actionId) {
        (, OfficeTypes.OfficeRole officeRole) =
            _authorizeOfficeAction(officeId, msg.sender, OfficeTypes.OfficeActionClass.RoutePayout);

        TreasuryTypes.DisbursementRequest memory request = _payoutQueue.getDisbursementRequest(requestId);
        if (request.officeId != officeId) {
            revert OfficeActionOfficeMismatch(officeId, request.officeId);
        }
        if (!_treasurySpendingPolicy.isPayoutAllowed(
                officeId, officeRole, request.disbursementType, request.asset, request.amount
            )) {
            revert UnauthorizedOfficeAction(msg.sender, officeId, OfficeTypes.OfficeActionClass.RoutePayout);
        }
        bytes32 expectedPolicyReference = _treasurySpendingPolicy.computePolicyReference(
            officeId, officeRole, request.disbursementType, request.amount
        );
        if (request.policyReference != expectedPolicyReference) {
            revert UnauthorizedOfficeAction(msg.sender, officeId, OfficeTypes.OfficeActionClass.RoutePayout);
        }

        GovernanceTypes.TreasuryDisbursementPayload memory payload = _payoutQueue.prepareRouting(requestId);

        actionId = _governanceRouter.routeAction(
            GovernanceTypes.ActionRequest({
                actionType: GovernanceTypes.ActionType.TreasuryDisbursement,
                origin: GovernanceTypes.ActionOrigin.Office,
                originReference: officeId,
                policyReference: expectedPolicyReference,
                targetModule: KernelModuleIds.TREASURY_VAULT,
                payload: abi.encode(payload),
                requestedExecutionTime: 0,
                expiresAt: 0
            })
        );

        _payoutQueue.confirmRouted(requestId, actionId);
    }

    /// @inheritdoc IOfficeExecutor
    function cancelPayout(bytes32 officeId, bytes32 requestId) external {
        _authorizeOfficeAction(officeId, msg.sender, OfficeTypes.OfficeActionClass.CancelPayout);

        TreasuryTypes.DisbursementRequest memory request = _payoutQueue.getDisbursementRequest(requestId);
        if (request.officeId != officeId) {
            revert OfficeActionOfficeMismatch(officeId, request.officeId);
        }

        _payoutQueue.cancelPayout(requestId);
    }

    function _authorizeOfficeAction(bytes32 officeId, address caller, OfficeTypes.OfficeActionClass actionClass)
        private
        view
        returns (OfficeTypes.OfficeRecord memory officeRecord, OfficeTypes.OfficeRole officeRole)
    {
        officeRecord = _officeRegistry.getOfficeRecord(officeId);
        officeRole = _officeRegistry.roleOf(officeId, caller);

        if (
            officeRecord.officeId == bytes32(0) || !officeRecord.active
                || !_officePermissionPolicy.isActionAuthorized(officeRecord.kind, officeRole, actionClass)
        ) {
            revert UnauthorizedOfficeAction(caller, officeId, actionClass);
        }
    }

    function _authorizeOfficeAdminIncludingInactive(
        bytes32 officeId,
        address caller,
        OfficeTypes.OfficeActionClass actionClass
    ) private view {
        OfficeTypes.OfficeRecord memory officeRecord = _officeRegistry.getOfficeRecord(officeId);
        if (
            officeRecord.officeId == bytes32(0) || officeRecord.admin != caller
                || !_officePermissionPolicy.isActionAuthorized(
                    officeRecord.kind, OfficeTypes.OfficeRole.Admin, actionClass
                )
        ) {
            revert UnauthorizedOfficeAction(caller, officeId, actionClass);
        }
    }

    function _requireBootstrapAuthority(address caller) private view {
        if (_bootstrapAuthority == address(0)) {
            revert BootstrapAlreadyDisabled();
        }
        if (caller != _bootstrapAuthority) {
            revert NotBootstrapAuthority(caller);
        }
    }
}
