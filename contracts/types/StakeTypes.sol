// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title StakeTypes
/// @notice Shared structs for political stake, discrete unstaking, and welfare state.
library StakeTypes {
    struct StakeRecord {
        bytes32 personId;
        uint256 activeStake;
        uint256 protectedStakeFloor;
        uint256 totalSlashed;
        uint256 totalRecovered;
        uint256 totalUnstaked;
        uint64 welfareUntil;
        uint64 lastUnstakeAt;
        uint64 updatedAt;
    }
}
