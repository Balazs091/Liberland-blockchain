// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IKernelModule} from "./IKernelModule.sol";
import {GovernanceTypes} from "../types/GovernanceTypes.sol";

/// @title IModuleUpgradePlanRegistry
/// @notice Permissionless, content-addressed immutable upgrade plans; publication grants no execution authority.
interface IModuleUpgradePlanRegistry is IKernelModule {
    error InvalidPlanEvidence();
    error UpgradePlanNotFound(bytes32 planId);
    error UpgradePlanAlreadyPublished(bytes32 planId);

    event UpgradePlanPublished(
        bytes32 indexed planId, bytes32 indexed evidenceHash, address indexed publisher, uint256 count
    );

    /// @notice Returns whether an immutable plan has been published.
    function planExists(bytes32 planId) external view returns (bool exists);

    /// @notice Computes the complete domain-separated plan identifier without requiring current-pointer equality.
    /// @param updates Sorted unique updates, including expected old pointers and new runtime hashes.
    /// @param evidenceHash Commitment to the reviewed transition/migration dossier; not proof of its truth.
    function computePlanId(GovernanceTypes.ModuleUpdate[] calldata updates, bytes32 evidenceHash)
        external
        view
        returns (bytes32 planId);

    /// @notice Publishes a structurally valid immutable plan, including a preplanned rollback.
    /// @dev Does not change pointers or approve a vote. Expected pointers are enforced at queue/execution time.
    function publishPlan(GovernanceTypes.ModuleUpdate[] calldata updates, bytes32 evidenceHash)
        external
        returns (bytes32 planId);

    /// @notice Returns the exact published updates and evidence commitment, or reverts for an unknown ID.
    function getPlan(bytes32 planId)
        external
        view
        returns (GovernanceTypes.ModuleUpdate[] memory updates, bytes32 evidenceHash);
}
