// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IKernelModule} from "../interfaces/IKernelModule.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title KernelModule
/// @notice Base for kernel-bound modules: validates the kernel address once at construction, stores it, and
///         exposes it through the shared {IKernelModule} surface.
/// @dev `_kernel` is `immutable`, so it is embedded in bytecode rather than storage. Extracting it into this base
///      therefore adds no storage slot to inheritors and cannot shift any child contract's storage layout.
abstract contract KernelModule is IKernelModule {
    IConstitutionKernel internal immutable _kernel;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) {
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) {
            revert IConstitutionKernel.InvalidModuleAddress(bytes32(0), kernelAddress);
        }

        _kernel = IConstitutionKernel(kernelAddress);
    }

    /// @inheritdoc IKernelModule
    function kernel() external view returns (address kernelAddress) {
        return address(_kernel);
    }

    /// @notice Returns whether `caller` is the module currently registered under `moduleId`.
    /// @dev A module that is not registered (the kernel reverts on lookup) yields `false` instead of bubbling
    ///      that revert, so authorization checks can safely probe optional or not-yet-bootstrapped authorities
    ///      and fall back to other allowed callers. Use this for graceful/fallback checks; use `_kernel.getModule`
    ///      directly when a missing module should fail closed.
    /// @param moduleId The kernel module identifier to resolve.
    /// @param caller The address to compare against the resolved module.
    /// @return authorized Whether `caller` equals the resolved module address.
    function _isModuleCaller(bytes32 moduleId, address caller) internal view returns (bool authorized) {
        try _kernel.getModule(moduleId) returns (address moduleAddress) {
            return caller == moduleAddress;
        } catch {
            return false;
        }
    }

    /// @notice Returns whether `caller` is the initial setup authority AND genesis bootstrap is still active.
    /// @dev The setup authority is a genesis-only convenience. Tying its registry-write fallback to the live
    ///      bootstrap phase means it becomes inert automatically the moment `disableBootstrapAuthority()` runs at
    ///      the end of deployment — so a lingering (unsealed) setup-authority module can never be a standing
    ///      backdoor into high-value stake/identity/election writes post-genesis.
    function _isActiveSetupAuthority(address caller) internal view returns (bool authorized) {
        return
            _kernel.bootstrapAuthority() != address(0)
                && _isModuleCaller(KernelModuleIds.INITIAL_SETUP_AUTHORITY, caller);
    }
}
