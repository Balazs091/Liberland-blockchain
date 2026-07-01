// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title IKernelModule
/// @notice Shared surface for kernel-bound modules that resolve their write authorizations through the kernel.
interface IKernelModule {
    /// @notice Returns the canonical kernel registry this module reads authorizations from.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress);
}
