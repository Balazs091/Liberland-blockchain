// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {GovernanceTypes} from "../types/GovernanceTypes.sol";
import {KernelModuleIds} from "./KernelModuleIds.sol";

/// @title ModuleUpgradeRules
/// @notice Shared fixed bounds and exact pointer/runtime checks; supplies no political authority.
library ModuleUpgradeRules {
    error InvalidModuleUpdateCount(uint256 count);
    error InvalidModuleUpdateOrder(bytes32 previousId, bytes32 moduleId);
    error ForbiddenBundledModule(bytes32 moduleId);
    error InvalidModuleUpdateAddress(bytes32 moduleId, address moduleAddress);
    error UnchangedModuleUpdate(bytes32 moduleId, address moduleAddress);
    error ModuleUpdateExpectedAddressMismatch(bytes32 moduleId, address expected, address actual);
    error ModuleUpdateRuntimeHashMismatch(bytes32 moduleId, bytes32 expected, bytes32 actual);

    uint256 internal constant MAX_UPDATES = 16;

    function validateCount(uint256 count) internal pure {
        if (count == 0 || count > MAX_UPDATES) revert InvalidModuleUpdateCount(count);
    }

    function validateEntry(
        GovernanceTypes.ModuleUpdate memory update,
        bytes32 previousId,
        GovernanceTypes.ModuleClass moduleClass,
        address currentAddress,
        bool checkCurrent
    ) internal view {
        if (update.moduleId == bytes32(0) || uint256(update.moduleId) <= uint256(previousId)) {
            revert InvalidModuleUpdateOrder(previousId, update.moduleId);
        }
        // Exact self-replacement exceptions must not be extended to unrelated bundle members.
        if (
            moduleClass == GovernanceTypes.ModuleClass.Core || update.moduleId == KernelModuleIds.SENATE_APP
                || update.moduleId == KernelModuleIds.CONSTITUTIONAL_REVIEW
        ) {
            revert ForbiddenBundledModule(update.moduleId);
        }
        if (update.expectedCurrentAddress == address(0) || update.expectedCurrentAddress.code.length == 0) {
            revert InvalidModuleUpdateAddress(update.moduleId, update.expectedCurrentAddress);
        }
        if (update.newModuleAddress == address(0) || update.newModuleAddress.code.length == 0) {
            revert InvalidModuleUpdateAddress(update.moduleId, update.newModuleAddress);
        }
        if (update.expectedCurrentAddress == update.newModuleAddress) {
            revert UnchangedModuleUpdate(update.moduleId, update.newModuleAddress);
        }
        if (checkCurrent && currentAddress != update.expectedCurrentAddress) {
            revert ModuleUpdateExpectedAddressMismatch(update.moduleId, update.expectedCurrentAddress, currentAddress);
        }
        bytes32 actualHash = update.newModuleAddress.codehash;
        if (update.newRuntimeCodeHash != actualHash) {
            revert ModuleUpdateRuntimeHashMismatch(update.moduleId, update.newRuntimeCodeHash, actualHash);
        }
    }
}
