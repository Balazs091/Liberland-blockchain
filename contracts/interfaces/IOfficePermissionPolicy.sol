// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title IOfficePermissionPolicy
/// @notice Policy interface for mapping office roles to explicit action classes.
interface IOfficePermissionPolicy {
    function isActionAuthorized(
        OfficeTypes.OfficeKind officeKind,
        OfficeTypes.OfficeRole officeRole,
        OfficeTypes.OfficeActionClass actionClass
    ) external view returns (bool authorized);

    function computePolicyReference(
        OfficeTypes.OfficeKind officeKind,
        OfficeTypes.OfficeRole officeRole,
        OfficeTypes.OfficeActionClass actionClass
    ) external view returns (bytes32 policyReference);
}
