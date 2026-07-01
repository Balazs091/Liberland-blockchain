// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IPresidentRegistry} from "../interfaces/IPresidentRegistry.sol";
import {KernelModule} from "../base/KernelModule.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @title PresidentRegistry
/// @notice Stable fact registry for the Senate-elected Head of State: the President wallet, its fixed-length term,
///         and the two Vice President slots. All writes are gated to the kernel PRESIDENT_REGISTRY_AUTHORITY module
///         pointer (the standing HeadOfStateApp) or the temporary bootstrap authority used only at genesis.
contract PresidentRegistry is IPresidentRegistry, KernelModule {
    uint8 internal constant VICE_PRESIDENT_SLOT_COUNT = 2;

    address private _currentPresident;
    bytes32 private _currentPresidentPersonId;
    bytes32 private _currentMandateHash;
    uint64 private _termStart;
    uint64 private _termEnd;

    address[VICE_PRESIDENT_SLOT_COUNT] private _vicePresidents;
    bytes32[VICE_PRESIDENT_SLOT_COUNT] private _vicePresidentPersonIds;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IPresidentRegistry
    function currentPresident() external view returns (address president) {
        return _currentPresident;
    }

    /// @inheritdoc IPresidentRegistry
    function currentPresidentPersonId() external view returns (bytes32 personId) {
        return _currentPresidentPersonId;
    }

    /// @inheritdoc IPresidentRegistry
    function currentMandateHash() external view returns (bytes32 mandateHash) {
        return _currentMandateHash;
    }

    /// @inheritdoc IPresidentRegistry
    function vicePresident(uint8 slot) external view returns (address vp) {
        _requireValidSlot(slot);
        return _vicePresidents[slot];
    }

    /// @inheritdoc IPresidentRegistry
    function vicePresidentPersonId(uint8 slot) external view returns (bytes32 personId) {
        _requireValidSlot(slot);
        return _vicePresidentPersonIds[slot];
    }

    /// @inheritdoc IPresidentRegistry
    function termStart() external view returns (uint64 startTime) {
        return _termStart;
    }

    /// @inheritdoc IPresidentRegistry
    function termEnd() external view returns (uint64 endTime) {
        return _termEnd;
    }

    /// @inheritdoc IPresidentRegistry
    function isPresidentInTerm() external view returns (bool inTerm) {
        return _currentPresident != address(0) && block.timestamp < _termEnd;
    }

    /// @inheritdoc IPresidentRegistry
    function setPresident(address president, bytes32 personId, bytes32 mandateHash, uint64 startTime, uint64 endTime)
        external
    {
        _requireRegistryAuthority(msg.sender);

        if (president == address(0)) {
            revert InvalidPresident(president);
        }
        if (personId == bytes32(0)) {
            revert InvalidPresidentPersonId(personId);
        }
        if (endTime <= startTime) {
            revert InvalidPresidentTerm(startTime, endTime);
        }

        address previousPresident = _currentPresident;
        _currentPresident = president;
        _currentPresidentPersonId = personId;
        _currentMandateHash = mandateHash;
        _termStart = startTime;
        _termEnd = endTime;

        // A new President appoints fresh Vice Presidents: clear both slots on every presidency change.
        _clearVicePresidents();

        emit PresidentUpdated(
            previousPresident, president, personId, mandateHash, startTime, endTime, uint64(block.timestamp), msg.sender
        );
    }

    /// @inheritdoc IPresidentRegistry
    function vacatePresident() external {
        _requireRegistryAuthority(msg.sender);

        address previousPresident = _currentPresident;
        _currentPresident = address(0);
        _currentPresidentPersonId = bytes32(0);
        _currentMandateHash = bytes32(0);
        _termStart = 0;
        _termEnd = 0;
        _clearVicePresidents();

        emit PresidentVacated(previousPresident, uint64(block.timestamp), msg.sender);
    }

    /// @inheritdoc IPresidentRegistry
    function setVicePresident(uint8 slot, address vp, bytes32 vpPersonId) external {
        _requireRegistryAuthority(msg.sender);
        _requireValidSlot(slot);

        if (vp == address(0)) {
            revert InvalidVicePresident(vp);
        }
        if (vpPersonId == bytes32(0)) {
            revert InvalidVicePresidentPersonId(vpPersonId);
        }

        address previousVicePresident = _vicePresidents[slot];
        _vicePresidents[slot] = vp;
        _vicePresidentPersonIds[slot] = vpPersonId;

        emit VicePresidentUpdated(slot, previousVicePresident, vp, vpPersonId, uint64(block.timestamp), msg.sender);
    }

    function _clearVicePresidents() private {
        for (uint8 slot = 0; slot < VICE_PRESIDENT_SLOT_COUNT; ++slot) {
            _vicePresidents[slot] = address(0);
            _vicePresidentPersonIds[slot] = bytes32(0);
        }
    }

    function _requireValidSlot(uint8 slot) private pure {
        if (slot >= VICE_PRESIDENT_SLOT_COUNT) {
            revert InvalidVicePresidentSlot(slot);
        }
    }

    function _requireRegistryAuthority(address caller) private view {
        if (
            caller == _kernel.bootstrapAuthority()
                || _isModuleCaller(KernelModuleIds.PRESIDENT_REGISTRY_AUTHORITY, caller)
        ) {
            return;
        }

        revert UnauthorizedPresidentRegistryCaller(caller);
    }
}
