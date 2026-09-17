// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";

/// @title DeploymentScriptBase
/// @notice Shared allocation helpers used by both network-specific deployment scripts.
abstract contract DeploymentScriptBase is Script {
    address[5] internal _civicReviewers;
    error DuplicateDeploymentModule(bytes32 moduleId, uint256 firstIndex, uint256 duplicateIndex);
    error InvalidDeploymentModule(uint256 index, bytes32 moduleId, address moduleAddress);
    error InvalidDeploymentModuleBatchLength(uint256 moduleIdCount, uint256 moduleAddressCount);
    error InvalidCivicReviewer(address reviewer);

    function _readCivicReviewers() internal {
        for (uint256 i; i < 5; ++i) {
            _civicReviewers[i] = vm.envAddress(string.concat("CIVIC_REVIEWER_", vm.toString(i)));
        }
    }

    function _validateCivicReviewers(address deployer, address[4] memory officeAdmins) internal view {
        for (uint256 i; i < 5; ++i) {
            address reviewer = _civicReviewers[i];
            if (reviewer == address(0) || reviewer == deployer) revert InvalidCivicReviewer(reviewer);
            for (uint256 j; j < 4; ++j) {
                if (reviewer == officeAdmins[j]) revert InvalidCivicReviewer(reviewer);
            }
            for (uint256 j; j < i; ++j) {
                if (reviewer == _civicReviewers[j]) revert InvalidCivicReviewer(reviewer);
            }
        }
    }

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
