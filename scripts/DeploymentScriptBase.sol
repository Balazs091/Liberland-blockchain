// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script} from "forge-std/Script.sol";

/// @title DeploymentScriptBase
/// @notice Shared allocation helpers used by both network-specific deployment scripts.
abstract contract DeploymentScriptBase is Script {
    error DuplicateDeploymentModule(bytes32 moduleId, uint256 firstIndex, uint256 duplicateIndex);
    error InvalidDeploymentModule(uint256 index, bytes32 moduleId, address moduleAddress);
    error InvalidDeploymentModuleBatchLength(uint256 moduleIdCount, uint256 moduleAddressCount);

    function _allocateModuleBatch(uint256 length)
        internal
        pure
        returns (bytes32[] memory moduleIds, address[] memory moduleAddresses)
    {
        moduleIds = new bytes32[](length);
        moduleAddresses = new address[](length);
    }

    function _setModuleBatchEntry(
        bytes32[] memory moduleIds,
        address[] memory moduleAddresses,
        uint256 index,
        bytes32 moduleId,
        address moduleAddress
    ) internal pure {
        moduleIds[index] = moduleId;
        moduleAddresses[index] = moduleAddress;
    }

    function _validateModuleBatch(bytes32[] memory moduleIds, address[] memory moduleAddresses) internal view {
        if (moduleIds.length != moduleAddresses.length) {
            revert InvalidDeploymentModuleBatchLength(moduleIds.length, moduleAddresses.length);
        }
        for (uint256 index = 0; index < moduleIds.length; ++index) {
            if (
                moduleIds[index] == bytes32(0) || moduleAddresses[index] == address(0)
                    || moduleAddresses[index].code.length == 0
            ) {
                revert InvalidDeploymentModule(index, moduleIds[index], moduleAddresses[index]);
            }
            for (uint256 previousIndex = 0; previousIndex < index; ++previousIndex) {
                if (moduleIds[previousIndex] == moduleIds[index]) {
                    revert DuplicateDeploymentModule(moduleIds[index], previousIndex, index);
                }
            }
        }
    }
}
