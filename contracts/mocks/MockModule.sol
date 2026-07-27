// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title MockModule
/// @notice Minimal deployed contract used in module-pointer tests.
contract MockModule {
    bytes32 public immutable label;

    constructor(bytes32 label_) {
        label = label_;
    }
}
