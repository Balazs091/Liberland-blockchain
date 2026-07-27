// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IElectorateRegistry} from "../interfaces/IElectorateRegistry.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title ConstitutionKernel
/// @notice Canonical registry of governed module pointers for the protocol.
contract ConstitutionKernel is IConstitutionKernel {
    error BootstrapAlreadyDisabled();
    error CoreModuleImmutable(bytes32 moduleId);
    error InvalidBootstrapAuthority(address bootstrapAuthority_);
    error InvalidModuleBatchLength(uint256 moduleIdCount, uint256 moduleAddressCount);
    error InvalidModuleId(bytes32 moduleId);
    error ModuleAddressUnchanged(bytes32 moduleId, address moduleAddress);
    error NotBootstrapAuthority(address caller);

    event BootstrapAuthorityDisabled(address indexed disabledBy);

    mapping(bytes32 moduleId => GovernanceTypes.ModuleRecord moduleRecord) private _moduleRecords;
    mapping(address account => uint256 authorizationRefs) private _authorizedModuleRefs;

    address private _bootstrapAuthority;

    /// @param bootstrapAuthority_ Temporary setup authority used only for initial module registration.
    constructor(address bootstrapAuthority_) {
        if (bootstrapAuthority_ == address(0)) {
            revert InvalidBootstrapAuthority(bootstrapAuthority_);
        }

        _bootstrapAuthority = bootstrapAuthority_;
    }

    /// @notice Returns the temporary bootstrap authority address.
    /// @return authority The remaining bootstrap authority, or zero if disabled.
    function bootstrapAuthority() external view returns (address authority) {
        return _bootstrapAuthority;
    }

    /// @inheritdoc IConstitutionKernel
    function getModule(bytes32 moduleId) external view returns (address moduleAddress) {
        GovernanceTypes.ModuleRecord storage moduleRecord = _moduleRecords[moduleId];
        if (moduleRecord.moduleAddress == address(0) || moduleRecord.status != GovernanceTypes.ModuleStatus.Active) {
            revert ModuleNotRegistered(moduleId);
        }

        return moduleRecord.moduleAddress;
    }

    /// @inheritdoc IConstitutionKernel
    function getModuleRecord(bytes32 moduleId)
        external
        view
        returns (GovernanceTypes.ModuleRecord memory moduleRecord)
    {
        moduleRecord = _moduleRecords[moduleId];
        if (moduleRecord.moduleAddress == address(0)) {
            revert ModuleNotRegistered(moduleId);
        }
    }

    /// @inheritdoc IConstitutionKernel
    function moduleClass(bytes32 moduleId) external pure returns (GovernanceTypes.ModuleClass class) {
        return _moduleClass(moduleId);
    }

    /// @inheritdoc IConstitutionKernel
    function isAuthorizedModule(address account) external view returns (bool authorized) {
        return _authorizedModuleRefs[account] != 0;
    }

    /// @notice Registers or replaces a module while bootstrap authority is still active.
    /// @param moduleId The canonical module identifier.
    /// @param moduleAddress The module implementation address to store.
    function bootstrapSetModule(bytes32 moduleId, address moduleAddress) external {
        _requireBootstrapAuthority(msg.sender);
        _setModule(moduleId, moduleAddress, true);
    }

    /// @inheritdoc IConstitutionKernel
    function bootstrapSetModules(bytes32[] calldata moduleIds, address[] calldata moduleAddresses) external {
        _requireBootstrapAuthority(msg.sender);
        if (moduleIds.length == 0 || moduleIds.length != moduleAddresses.length) {
            revert InvalidModuleBatchLength(moduleIds.length, moduleAddresses.length);
        }

        for (uint256 index = 0; index < moduleIds.length; ++index) {
            _setModule(moduleIds[index], moduleAddresses[index], true);
        }
    }

    /// @notice Permanently removes the temporary bootstrap authority.
    function disableBootstrapAuthority() external {
        _requireBootstrapAuthority(msg.sender);
        _bootstrapAuthority = address(0);

        emit BootstrapAuthorityDisabled(msg.sender);
    }

    /// @inheritdoc IConstitutionKernel
    function governanceUpdateModule(bytes32 moduleId, address moduleAddress) external {
        _requireGovernanceCaller(msg.sender);
        if (_moduleRecords[moduleId].moduleAddress == address(0)) {
            revert ModuleNotRegistered(moduleId);
        }
        _requireRepointableModule(moduleId);

        _setModule(moduleId, moduleAddress, false);
    }

    /// @inheritdoc IConstitutionKernel
    function governanceRegisterModule(bytes32 moduleId, address moduleAddress) external {
        _requireGovernanceCaller(msg.sender);
        if (_moduleClass(moduleId) == GovernanceTypes.ModuleClass.Core) {
            revert CoreModuleImmutable(moduleId);
        }
        if (_moduleRecords[moduleId].moduleAddress != address(0)) {
            revert ModuleAlreadyRegistered(moduleId);
        }

        _setModule(moduleId, moduleAddress, true);
    }

    function _setModule(bytes32 moduleId, address moduleAddress, bool allowRegistration) private {
        if (moduleId == bytes32(0)) {
            revert InvalidModuleId(moduleId);
        }

        if (moduleAddress == address(0) || moduleAddress.code.length == 0) {
            revert InvalidModuleAddress(moduleId, moduleAddress);
        }

        GovernanceTypes.ModuleRecord storage currentRecord = _moduleRecords[moduleId];
        uint64 timestamp = uint64(block.timestamp);

        if (currentRecord.moduleAddress == address(0)) {
            if (!allowRegistration) {
                revert ModuleNotRegistered(moduleId);
            }

            _moduleRecords[moduleId] = GovernanceTypes.ModuleRecord({
                moduleId: moduleId,
                moduleAddress: moduleAddress,
                status: GovernanceTypes.ModuleStatus.Active,
                activatedAt: timestamp,
                lastUpdatedAt: timestamp
            });
            _authorizedModuleRefs[moduleAddress] += 1;

            emit ModuleRegistered(moduleId, moduleAddress, timestamp);
            return;
        }

        if (currentRecord.moduleAddress == moduleAddress) {
            revert ModuleAddressUnchanged(moduleId, moduleAddress);
        }

        address previousModule = currentRecord.moduleAddress;
        _authorizedModuleRefs[previousModule] -= 1;
        _authorizedModuleRefs[moduleAddress] += 1;

        currentRecord.moduleAddress = moduleAddress;
        currentRecord.status = GovernanceTypes.ModuleStatus.Active;
        currentRecord.activatedAt = timestamp;
        currentRecord.lastUpdatedAt = timestamp;

        emit ModuleReplaced(moduleId, previousModule, moduleAddress, timestamp);
        if (moduleId == KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY) {
            address electorateRegistry = _moduleRecords[KernelModuleIds.ELECTORATE_REGISTRY].moduleAddress;
            if (electorateRegistry != address(0)) {
                IElectorateRegistry(electorateRegistry).beginPolicyRebuild();
            }
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

    function _requireGovernanceCaller(address caller) private view {
        if (caller != _moduleRecords[KernelModuleIds.ACTION_TIMELOCK].moduleAddress) {
            revert UnauthorizedKernelCaller(caller);
        }
    }

    /// @dev Only the core action lifecycle (router + timelock) is never governance-repointable. State-bearing
    ///      modules still require an externally reviewed migration, but the kernel must not permanently prevent a
    ///      future constitutional replacement once that migration has been prepared.
    function _requireRepointableModule(bytes32 moduleId) private pure {
        GovernanceTypes.ModuleClass class = _moduleClass(moduleId);
        if (class == GovernanceTypes.ModuleClass.Core) {
            revert CoreModuleImmutable(moduleId);
        }
    }

    function _moduleClass(bytes32 moduleId) private pure returns (GovernanceTypes.ModuleClass class) {
        if (moduleId == KernelModuleIds.GOVERNANCE_ROUTER || moduleId == KernelModuleIds.ACTION_TIMELOCK) {
            return GovernanceTypes.ModuleClass.Core;
        }
        if (
            moduleId == KernelModuleIds.IDENTITY_REGISTRY || moduleId == KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY
                || moduleId == KernelModuleIds.LEGISLATION_REGISTRY || moduleId == KernelModuleIds.REFERENDUM_REGISTRY
                || moduleId == KernelModuleIds.SENATE_SEAT_REGISTRY || moduleId == KernelModuleIds.STAKE_REGISTRY
                || moduleId == KernelModuleIds.LLM_STAKING_VAULT || moduleId == KernelModuleIds.STAKE_LIEN_REGISTRY
                || moduleId == KernelModuleIds.LAND_REGISTRY || moduleId == KernelModuleIds.COMPANY_REGISTRY
                || moduleId == KernelModuleIds.TREASURY_VAULT || moduleId == KernelModuleIds.BUDGET_ENVELOPE_REGISTRY
                || moduleId == KernelModuleIds.OFFICE_REGISTRY || moduleId == KernelModuleIds.PRESIDENT_REGISTRY
                || moduleId == KernelModuleIds.EXECUTIVE_REGISTRY || moduleId == KernelModuleIds.ELECTORATE_REGISTRY
                || moduleId == KernelModuleIds.USDC_LENDING_POOL_APP || moduleId == KernelModuleIds.MINISTRY_TREASURY
        ) {
            return GovernanceTypes.ModuleClass.State;
        }
        if (
            moduleId == KernelModuleIds.CANDIDATE_ELIGIBILITY_POLICY
                || moduleId == KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY
                || moduleId == KernelModuleIds.CONGRESS_ELECTION_POLICY
                || moduleId == KernelModuleIds.OFFICE_PERMISSION_POLICY || moduleId == KernelModuleIds.REFERENDUM_POLICY
                || moduleId == KernelModuleIds.SENATE_POWERS_POLICY
                || moduleId == KernelModuleIds.TREASURY_SPENDING_POLICY
                || moduleId == KernelModuleIds.VOTING_POWER_POLICY || moduleId == KernelModuleIds.UNSTAKING_POLICY
                || moduleId == KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY
                || moduleId == KernelModuleIds.USDC_INTEREST_RATE_POLICY
                || moduleId == KernelModuleIds.LENDING_RISK_PARAMETER_POLICY
        ) {
            return GovernanceTypes.ModuleClass.Policy;
        }
        if (
            moduleId == KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY
                || moduleId == KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.COMPANY_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.INITIAL_SETUP_AUTHORITY
                || moduleId == KernelModuleIds.LAND_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.LEGISLATION_REPEAL_AUTHORITY
                || moduleId == KernelModuleIds.OFFICE_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.PRESIDENT_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.EXECUTIVE_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.STAKE_USER_GATEWAY_AUTHORITY
                || moduleId == KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY
                || moduleId == KernelModuleIds.STAKE_REGISTRY_AUTHORITY
                || moduleId == KernelModuleIds.MINISTRY_TREASURY_FUNDING_AUTHORITY
        ) {
            return GovernanceTypes.ModuleClass.Authority;
        }
        if (
            moduleId == KernelModuleIds.CABINET_APP || moduleId == KernelModuleIds.CONGRESS_ELECTION_APP
                || moduleId == KernelModuleIds.COMPANY_REGISTRY_APP || moduleId == KernelModuleIds.DECISION_APP
                || moduleId == KernelModuleIds.HEAD_OF_STATE_APP || moduleId == KernelModuleIds.LAND_REGISTRY_APP
                || moduleId == KernelModuleIds.OFFICE_EXECUTOR || moduleId == KernelModuleIds.PAYOUT_QUEUE
                || moduleId == KernelModuleIds.PUBLIC_VETO_APP || moduleId == KernelModuleIds.REFERENDUM_APP
                || moduleId == KernelModuleIds.SENATE_APP || moduleId == KernelModuleIds.CONSTITUTIONAL_REVIEW
        ) {
            return GovernanceTypes.ModuleClass.Application;
        }
        return GovernanceTypes.ModuleClass.Undefined;
    }
}
