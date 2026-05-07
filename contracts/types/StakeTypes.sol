// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title StakeTypes
/// @notice Shared structs for political stake and unstaking state.
library StakeTypes {
    struct StakeRecord {
        bytes32 personId;
        uint256 activeStake;
        uint256 pendingUnstake;
        uint256 protectedStakeFloor;
        uint256 totalSlashed;
        uint256 totalRecovered;
        uint64 cooldownStart;
        uint64 cooldownEnd;
        uint64 updatedAt;
    }
}
