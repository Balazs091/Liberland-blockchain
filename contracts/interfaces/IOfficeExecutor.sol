// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {TreasuryTypes} from "../types/TreasuryTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title IOfficeExecutor
/// @notice Interface for explicit office-admin actions and office-origin treasury routing.
interface IOfficeExecutor {
    error BootstrapAlreadyDisabled();
    error InvalidBootstrapAuthority(address authority);
    error NotBootstrapAuthority(address caller);
    error UnauthorizedOfficeAction(address caller, bytes32 officeId, OfficeTypes.OfficeActionClass actionClass);
    error OfficeActionOfficeMismatch(bytes32 expectedOfficeId, bytes32 actualOfficeId);

    event OfficeBootstrapAuthorityDisabled(address indexed disabledBy);

    function bootstrapAuthority() external view returns (address authority);
    function bootstrapCreateOffice(bytes32 officeId, OfficeTypes.OfficeKind kind, string calldata name, address admin)
        external;
    function disableBootstrapAuthority() external;
    function assignClerk(bytes32 officeId, address clerk) external;
    function revokeClerk(bytes32 officeId, address clerk) external;
    function transferOfficeAdmin(bytes32 officeId, address newAdmin) external;

    function requestBudgetApproval(
        bytes32 officeId,
        bytes32 budgetId,
        TreasuryTypes.DisbursementType disbursementType,
        address asset,
        uint256 allocatedAmount,
        uint64 startsAt,
        uint64 endsAt
    ) external returns (bytes32 actionId);

    function proposePayout(bytes32 officeId, TreasuryTypes.DisbursementRequestInput calldata input) external;

    function routePayout(bytes32 officeId, bytes32 requestId) external returns (bytes32 actionId);
    function cancelPayout(bytes32 officeId, bytes32 requestId) external;
}
