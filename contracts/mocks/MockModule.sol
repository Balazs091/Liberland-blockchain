// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title MockModule
/// @notice Minimal deployed contract used in Milestone 1 module pointer tests.
contract MockModule {
    bytes32 public immutable label;

    constructor(bytes32 label_) {
        label = label_;
    }
}
