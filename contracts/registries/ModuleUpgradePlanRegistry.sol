// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {KernelModule} from "../base/KernelModule.sol";
import {IModuleUpgradePlanRegistry} from "../interfaces/IModuleUpgradePlanRegistry.sol";
import {ModuleUpgradePlanHash} from "../libraries/ModuleUpgradePlanHash.sol";
import {ModuleUpgradeRules} from "../libraries/ModuleUpgradeRules.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title ModuleUpgradePlanRegistry
/// @notice Immutable shared plan storage, never an executor, approver or state migrator.
contract ModuleUpgradePlanRegistry is IModuleUpgradePlanRegistry, KernelModule {
    struct Plan {
        bytes32 evidenceHash;
        GovernanceTypes.ModuleUpdate[] updates;
    }
    mapping(bytes32 planId => Plan plan) private _plans;

    /// @param kernelAddress Kernel whose exact module replacements the published plans describe.
    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IModuleUpgradePlanRegistry
    function planExists(bytes32 planId) external view returns (bool exists) {
        return _plans[planId].updates.length != 0;
    }

    /// @inheritdoc IModuleUpgradePlanRegistry
    function computePlanId(GovernanceTypes.ModuleUpdate[] calldata updates, bytes32 evidenceHash)
        external
        view
        returns (bytes32 planId)
    {
        return ModuleUpgradePlanHash.hash(block.chainid, address(_kernel), address(this), evidenceHash, updates);
    }

    /// @inheritdoc IModuleUpgradePlanRegistry
    function publishPlan(GovernanceTypes.ModuleUpdate[] calldata updates, bytes32 evidenceHash)
        external
        returns (bytes32 planId)
    {
        if (evidenceHash == bytes32(0)) revert InvalidPlanEvidence();
        ModuleUpgradeRules.validateCount(updates.length);
        bytes32 previousId;
        for (uint256 i; i < updates.length; ++i) {
            GovernanceTypes.ModuleUpdate calldata update = updates[i];
            address currentAddress = _kernel.getModule(update.moduleId);
            ModuleUpgradeRules.validateEntry(
                update, previousId, _kernel.moduleClass(update.moduleId), currentAddress, false
            );
            previousId = update.moduleId;
        }
        planId = ModuleUpgradePlanHash.hash(block.chainid, address(_kernel), address(this), evidenceHash, updates);
        Plan storage plan = _plans[planId];
        if (plan.updates.length != 0) revert UpgradePlanAlreadyPublished(planId);
        plan.evidenceHash = evidenceHash;
        for (uint256 i; i < updates.length; ++i) {
            plan.updates.push(updates[i]);
        }
        emit UpgradePlanPublished(planId, evidenceHash, msg.sender, updates.length);
    }

    /// @inheritdoc IModuleUpgradePlanRegistry
    function getPlan(bytes32 planId)
        external
        view
        returns (GovernanceTypes.ModuleUpdate[] memory updates, bytes32 evidenceHash)
    {
        Plan storage plan = _plans[planId];
        if (plan.updates.length == 0) revert UpgradePlanNotFound(planId);
        return (plan.updates, plan.evidenceHash);
    }
}
