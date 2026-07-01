// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {KernelModule} from "../base/KernelModule.sol";
import {IExecutiveRegistry} from "../interfaces/IExecutiveRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {ExecutiveTypes} from "../types/ExecutiveTypes.sol";

/// @title ExecutiveRegistry
/// @notice Stable fact registry for the Congress-appointed Prime Minister and the four Cabinet ministries
///         (Constitution Art V §1-2): the Prime Minister wallet, its fixed-length term and appointing vote
///         tally, and one minister record per ministry. All writes are gated to the kernel
///         EXECUTIVE_REGISTRY_AUTHORITY module pointer (the standing CabinetApp) or the temporary bootstrap
///         authority used only at genesis. It is a political record layer, decoupled from the operational
///         OfficeRegistry: recording a minister here does not grant any operational office admin rights.
contract ExecutiveRegistry is IExecutiveRegistry, KernelModule {
    ExecutiveTypes.PrimeMinisterRecord private _primeMinister;
    mapping(ExecutiveTypes.MinistryKind ministry => ExecutiveTypes.MinisterRecord record) private _ministers;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IExecutiveRegistry
    function primeMinister() external view returns (address primeMinisterAddress) {
        return _primeMinister.primeMinister;
    }

    /// @inheritdoc IExecutiveRegistry
    function getPrimeMinister() external view returns (ExecutiveTypes.PrimeMinisterRecord memory record) {
        return _primeMinister;
    }

    /// @inheritdoc IExecutiveRegistry
    function isPrimeMinisterInTerm() external view returns (bool inTerm) {
        return _primeMinister.active && block.timestamp < _primeMinister.termEnd;
    }

    /// @inheritdoc IExecutiveRegistry
    function primeMinisterAppointmentSupport() external view returns (uint32 appointmentSupport) {
        return _primeMinister.appointmentSupport;
    }

    /// @inheritdoc IExecutiveRegistry
    function getMinister(ExecutiveTypes.MinistryKind ministry)
        external
        view
        returns (ExecutiveTypes.MinisterRecord memory record)
    {
        return _ministers[ministry];
    }

    /// @inheritdoc IExecutiveRegistry
    function isMinisterInTerm(ExecutiveTypes.MinistryKind ministry) external view returns (bool inTerm) {
        ExecutiveTypes.MinisterRecord storage record = _ministers[ministry];
        return record.active && block.timestamp < record.termEnd;
    }

    /// @inheritdoc IExecutiveRegistry
    function setPrimeMinister(address pm, bytes32 personId, uint64 termStart, uint64 termEnd, uint32 appointmentSupport)
        external
    {
        _requireRegistryAuthority(msg.sender);

        if (pm == address(0)) {
            revert InvalidPrimeMinister(pm);
        }
        if (personId == bytes32(0)) {
            revert InvalidPrimeMinisterPersonId(personId);
        }
        if (termEnd <= termStart) {
            revert InvalidPrimeMinisterTerm(termStart, termEnd);
        }

        address previousPrimeMinister = _primeMinister.primeMinister;
        _primeMinister = ExecutiveTypes.PrimeMinisterRecord({
            primeMinister: pm,
            personId: personId,
            termStart: termStart,
            termEnd: termEnd,
            appointmentSupport: appointmentSupport,
            active: true
        });

        emit PrimeMinisterUpdated(
            previousPrimeMinister,
            pm,
            personId,
            termStart,
            termEnd,
            appointmentSupport,
            uint64(block.timestamp),
            msg.sender
        );
    }

    /// @inheritdoc IExecutiveRegistry
    function clearPrimeMinister() external {
        _requireRegistryAuthority(msg.sender);

        address previousPrimeMinister = _primeMinister.primeMinister;
        delete _primeMinister;

        emit PrimeMinisterCleared(previousPrimeMinister, uint64(block.timestamp), msg.sender);
    }

    /// @inheritdoc IExecutiveRegistry
    function setMinister(
        ExecutiveTypes.MinistryKind ministry,
        address minister,
        bytes32 personId,
        uint64 termStart,
        uint64 termEnd
    ) external {
        _requireRegistryAuthority(msg.sender);

        if (ministry == ExecutiveTypes.MinistryKind.Undefined) {
            revert InvalidMinistry(ministry);
        }
        if (minister == address(0)) {
            revert InvalidMinister(minister);
        }
        if (personId == bytes32(0)) {
            revert InvalidMinisterPersonId(personId);
        }
        if (termEnd <= termStart) {
            revert InvalidMinisterTerm(termStart, termEnd);
        }

        address previousMinister = _ministers[ministry].minister;
        _ministers[ministry] = ExecutiveTypes.MinisterRecord({
            minister: minister,
            personId: personId,
            ministry: ministry,
            termStart: termStart,
            termEnd: termEnd,
            active: true
        });

        emit MinisterUpdated(
            ministry, previousMinister, minister, personId, termStart, termEnd, uint64(block.timestamp), msg.sender
        );
    }

    /// @inheritdoc IExecutiveRegistry
    function clearMinister(ExecutiveTypes.MinistryKind ministry) external {
        _requireRegistryAuthority(msg.sender);

        if (ministry == ExecutiveTypes.MinistryKind.Undefined) {
            revert InvalidMinistry(ministry);
        }

        address previousMinister = _ministers[ministry].minister;
        delete _ministers[ministry];

        emit MinisterCleared(ministry, previousMinister, uint64(block.timestamp), msg.sender);
    }

    function _requireRegistryAuthority(address caller) private view {
        if (
            caller == _kernel.bootstrapAuthority()
                || _isModuleCaller(KernelModuleIds.EXECUTIVE_REGISTRY_AUTHORITY, caller)
        ) {
            return;
        }

        revert UnauthorizedExecutiveRegistryCaller(caller);
    }
}
