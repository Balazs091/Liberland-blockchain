// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

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

        if (!isActionTypeSupported(request.actionType)) {
            revert UnsupportedActionType(request.actionType);
        }

        if (!_isTargetModuleRegistered(request.targetModule)) {
            revert InvalidTargetModule(request.targetModule);
        }

        actionId = IActionTimelock(timelock()).queueAction(request);

        emit GovernanceActionRouted(actionId, request.actionType, request.origin, request.targetModule);
    }

    /// @inheritdoc IGovernanceRouter
    function cancelAction(bytes32 actionId) external {
        IActionTimelock actionTimelock = IActionTimelock(timelock());
        GovernanceTypes.ActionRecord memory actionRecord = actionTimelock.getAction(actionId);
        GovernanceTypes.ActionOrigin cancellationOrigin = _resolveCancellationOrigin(actionRecord.origin, msg.sender);

        actionTimelock.cancelAction(actionId);

        emit GovernanceActionCancellationRouted(actionId, cancellationOrigin, msg.sender);
    }

    /// @inheritdoc IGovernanceRouter
    function originAuthority(GovernanceTypes.ActionOrigin origin) external view returns (address authority) {
        return _originAuthorities[origin];
    }

    /// @inheritdoc IGovernanceRouter
    function isActionTypeSupported(GovernanceTypes.ActionType actionType) public pure returns (bool supported) {
        return actionType == GovernanceTypes.ActionType.ModulePointerUpdate
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
        if (origin == GovernanceTypes.ActionOrigin.Undefined || _originAuthorities[origin] != caller) {
            revert UnauthorizedGovernanceOrigin(caller);
        }
    }

    function _resolveCancellationOrigin(GovernanceTypes.ActionOrigin actionOrigin, address caller)
        private
        view
        returns (GovernanceTypes.ActionOrigin cancellationOrigin)
    {
        if (actionOrigin != GovernanceTypes.ActionOrigin.Undefined && _originAuthorities[actionOrigin] == caller) {
            return actionOrigin;
        }

        if (_originAuthorities[GovernanceTypes.ActionOrigin.Senate] == caller) {
            return GovernanceTypes.ActionOrigin.Senate;
        }

        revert UnauthorizedGovernanceOrigin(caller);
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
