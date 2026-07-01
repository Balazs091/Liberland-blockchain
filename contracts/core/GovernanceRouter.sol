// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IActionTimelock} from "../interfaces/IActionTimelock.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IGovernanceRouter} from "../interfaces/IGovernanceRouter.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title GovernanceRouter
/// @notice Validates approved governance-origin requests and forwards them into the timelock.
contract GovernanceRouter is IGovernanceRouter {
    error BootstrapAlreadyDisabled();
    error InvalidBootstrapAuthority(address bootstrapAuthority_);
    error InvalidOrigin(GovernanceTypes.ActionOrigin origin);
    error InvalidOriginAuthority(address authority);
    error NotBootstrapAuthority(address caller);
    error UnauthorizedDisbursementOrigin(GovernanceTypes.ActionOrigin origin);

    event BootstrapAuthorityDisabled(address indexed disabledBy);

    IConstitutionKernel private immutable _kernel;

    mapping(GovernanceTypes.ActionOrigin origin => address authority) private _originAuthorities;

    address private _bootstrapAuthority;

    /// @param kernelAddress The canonical kernel registry address.
    /// @param bootstrapAuthority_ Temporary setup authority used only for initial origin configuration.
    constructor(address kernelAddress, address bootstrapAuthority_) {
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) {
            revert IConstitutionKernel.InvalidModuleAddress(bytes32(0), kernelAddress);
        }

        if (bootstrapAuthority_ == address(0)) {
            revert InvalidBootstrapAuthority(bootstrapAuthority_);
        }

        _kernel = IConstitutionKernel(kernelAddress);
        _bootstrapAuthority = bootstrapAuthority_;
    }

    /// @notice Returns the temporary bootstrap authority address.
    /// @return authority The remaining bootstrap authority, or zero if disabled.
    function bootstrapAuthority() external view returns (address authority) {
        return _bootstrapAuthority;
    }

    /// @inheritdoc IGovernanceRouter
    function kernel() external view returns (address kernelAddress) {
        return address(_kernel);
    }

    /// @inheritdoc IGovernanceRouter
    function timelock() public view returns (address timelockAddress) {
        return _kernel.getModule(KernelModuleIds.ACTION_TIMELOCK);
    }

    /// @inheritdoc IGovernanceRouter
    function previewActionId(GovernanceTypes.ActionRequest calldata request) external view returns (bytes32 actionId) {
        return IActionTimelock(timelock()).computeActionId(request);
    }

    /// @inheritdoc IGovernanceRouter
    function routeAction(GovernanceTypes.ActionRequest calldata request) external returns (bytes32 actionId) {
        _requireAuthorizedOrigin(request.origin, msg.sender);

        // Defense-in-depth (L2): treasury disbursements may only be routed by the Office origin
        // (OfficeExecutor), the sole legitimate builder of the disbursement payload today.
        if (
            request.actionType == GovernanceTypes.ActionType.TreasuryDisbursement
                && request.origin != GovernanceTypes.ActionOrigin.Office
        ) {
            revert UnauthorizedDisbursementOrigin(request.origin);
        }

        if (!isActionTypeSupported(request.actionType)) {
            revert UnsupportedActionType(request.actionType);
        }

        if (!_isTargetModuleValid(request.actionType, request.targetModule)) {
            revert InvalidTargetModule(request.targetModule);
        }

        IActionTimelock actionTimelock = IActionTimelock(timelock());
        actionId = actionTimelock.computeActionId(request);
        emit GovernanceActionRouted(actionId, request.actionType, request.origin, request.targetModule);
        bytes32 queuedActionId = actionTimelock.queueAction(request);
        assert(queuedActionId == actionId);
    }

    /// @inheritdoc IGovernanceRouter
    function cancelAction(bytes32 actionId) external {
        IActionTimelock actionTimelock = IActionTimelock(timelock());
        GovernanceTypes.ActionRecord memory actionRecord = actionTimelock.getAction(actionId);
        GovernanceTypes.ActionOrigin cancellationOrigin = _resolveCancellationOrigin(actionRecord.origin, msg.sender);

        emit GovernanceActionCancellationRouted(actionId, cancellationOrigin, msg.sender);
        actionTimelock.cancelAction(actionId);
    }

    /// @inheritdoc IGovernanceRouter
    function originAuthority(GovernanceTypes.ActionOrigin origin) external view returns (address authority) {
        return _originAuthority(origin);
    }

    /// @inheritdoc IGovernanceRouter
    function isActionTypeSupported(GovernanceTypes.ActionType actionType) public pure returns (bool supported) {
        return actionType == GovernanceTypes.ActionType.ModulePointerUpdate
            || actionType == GovernanceTypes.ActionType.ModuleRegistration
            || actionType == GovernanceTypes.ActionType.TreasuryBudgetApproval
            || actionType == GovernanceTypes.ActionType.LegislationEnactment
            || actionType == GovernanceTypes.ActionType.TreasuryDisbursement;
    }

    /// @notice Configures the authority address for a supported governance origin.
    /// @param origin The governance origin to configure.
    /// @param authority The address allowed to route actions for that origin.
    function configureOriginAuthority(GovernanceTypes.ActionOrigin origin, address authority) external {
        _requireBootstrapAuthority(msg.sender);

        if (origin == GovernanceTypes.ActionOrigin.Undefined) {
            revert InvalidOrigin(origin);
        }

        if (authority == address(0)) {
            revert InvalidOriginAuthority(authority);
        }

        address previousAuthority = _originAuthorities[origin];
        _originAuthorities[origin] = authority;

        emit OriginAuthorityConfigured(origin, previousAuthority, authority);
    }

    /// @notice Permanently removes the temporary bootstrap authority.
    function disableBootstrapAuthority() external {
        _requireBootstrapAuthority(msg.sender);
        _bootstrapAuthority = address(0);

        emit BootstrapAuthorityDisabled(msg.sender);
    }

    function _requireAuthorizedOrigin(GovernanceTypes.ActionOrigin origin, address caller) private view {
        if (origin == GovernanceTypes.ActionOrigin.Undefined || _originAuthority(origin) != caller) {
            revert UnauthorizedGovernanceOrigin(caller);
        }
    }

    function _resolveCancellationOrigin(GovernanceTypes.ActionOrigin actionOrigin, address caller)
        private
        view
        returns (GovernanceTypes.ActionOrigin cancellationOrigin)
    {
        if (actionOrigin != GovernanceTypes.ActionOrigin.Undefined && _originAuthority(actionOrigin) == caller) {
            return actionOrigin;
        }

        if (_originAuthority(GovernanceTypes.ActionOrigin.Senate) == caller) {
            return GovernanceTypes.ActionOrigin.Senate;
        }

        revert UnauthorizedGovernanceOrigin(caller);
    }

    function _originAuthority(GovernanceTypes.ActionOrigin origin) private view returns (address authority) {
        bytes32 moduleId = _originModuleId(origin);
        if (moduleId != bytes32(0)) {
            try _kernel.getModule(moduleId) returns (address moduleAddress) {
                return moduleAddress;
            } catch {
                return _originAuthorities[origin];
            }
        }

        return _originAuthorities[origin];
    }

    function _originModuleId(GovernanceTypes.ActionOrigin origin) private pure returns (bytes32 moduleId) {
        if (origin == GovernanceTypes.ActionOrigin.Referendum) {
            return KernelModuleIds.REFERENDUM_APP;
        }
        if (origin == GovernanceTypes.ActionOrigin.Congress) {
            return KernelModuleIds.CONGRESS_ELECTION_APP;
        }
        if (origin == GovernanceTypes.ActionOrigin.Senate) {
            return KernelModuleIds.SENATE_APP;
        }
        if (origin == GovernanceTypes.ActionOrigin.Office) {
            return KernelModuleIds.OFFICE_EXECUTOR;
        }

        return bytes32(0);
    }

    function _isTargetModuleValid(GovernanceTypes.ActionType actionType, bytes32 moduleId)
        private
        view
        returns (bool valid)
    {
        if (moduleId == bytes32(0)) {
            return false;
        }

        bool registered = _isTargetModuleRegistered(moduleId);
        if (actionType == GovernanceTypes.ActionType.ModuleRegistration) {
            return !registered;
        }

        return registered;
    }

    function _isTargetModuleRegistered(bytes32 moduleId) private view returns (bool registered) {
        try _kernel.getModuleRecord(moduleId) returns (GovernanceTypes.ModuleRecord memory moduleRecord) {
            return
                moduleRecord.status == GovernanceTypes.ModuleStatus.Active && moduleRecord.moduleAddress != address(0);
        } catch {
            return false;
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
