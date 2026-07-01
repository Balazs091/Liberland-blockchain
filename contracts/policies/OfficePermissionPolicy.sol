// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IOfficePermissionPolicy} from "../interfaces/IOfficePermissionPolicy.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title OfficePermissionPolicy
/// @notice v1 policy that maps office roles to explicit office action classes.
contract OfficePermissionPolicy is IOfficePermissionPolicy {
    /// @inheritdoc IOfficePermissionPolicy
    function isActionAuthorized(
        OfficeTypes.OfficeKind officeKind,
        OfficeTypes.OfficeRole officeRole,
        OfficeTypes.OfficeActionClass actionClass
    ) external pure returns (bool authorized) {
        return _isActionAuthorized(officeKind, officeRole, actionClass);
    }

    /// @inheritdoc IOfficePermissionPolicy
    function computePolicyReference(
        OfficeTypes.OfficeKind officeKind,
        OfficeTypes.OfficeRole officeRole,
        OfficeTypes.OfficeActionClass actionClass
    ) external pure returns (bytes32 policyReference) {
        return keccak256(abi.encode(officeKind, officeRole, actionClass));
    }

    function _isActionAuthorized(
        OfficeTypes.OfficeKind officeKind,
        OfficeTypes.OfficeRole officeRole,
        OfficeTypes.OfficeActionClass actionClass
    ) private pure returns (bool authorized) {
        if (
            officeRole == OfficeTypes.OfficeRole.Admin
                && (actionClass == OfficeTypes.OfficeActionClass.ManageClerks
                    || actionClass == OfficeTypes.OfficeActionClass.TransferAdmin
                    || actionClass == OfficeTypes.OfficeActionClass.ManageOfficeMetadata
                    || actionClass == OfficeTypes.OfficeActionClass.SetOfficeActive)
        ) {
            return true;
        }

        if (officeKind != OfficeTypes.OfficeKind.MinistryOfFinance) {
            if (officeKind == OfficeTypes.OfficeKind.LandRegistryOffice) {
                return (officeRole == OfficeTypes.OfficeRole.Admin || officeRole == OfficeTypes.OfficeRole.Clerk)
                    && actionClass == OfficeTypes.OfficeActionClass.ManageLandRegistry;
            }

            if (officeKind == OfficeTypes.OfficeKind.CompanyRegistryOffice) {
                return (officeRole == OfficeTypes.OfficeRole.Admin || officeRole == OfficeTypes.OfficeRole.Clerk)
                    && actionClass == OfficeTypes.OfficeActionClass.ManageCompanyRegistry;
            }

            return false;
        }

        if (officeRole == OfficeTypes.OfficeRole.Admin) {
            return actionClass == OfficeTypes.OfficeActionClass.ProposeBudget
                || actionClass == OfficeTypes.OfficeActionClass.ProposePayout
                || actionClass == OfficeTypes.OfficeActionClass.RoutePayout
                || actionClass == OfficeTypes.OfficeActionClass.CancelPayout;
        }

        if (officeRole == OfficeTypes.OfficeRole.Clerk) {
            return actionClass == OfficeTypes.OfficeActionClass.ProposePayout
                || actionClass == OfficeTypes.OfficeActionClass.RoutePayout
                || actionClass == OfficeTypes.OfficeActionClass.CancelPayout;
        }

        return false;
    }
}
