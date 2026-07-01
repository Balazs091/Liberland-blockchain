// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IKernelModule} from "./IKernelModule.sol";
import {ExecutiveTypes} from "../types/ExecutiveTypes.sol";

/// @title IExecutiveRegistry
/// @notice Stable fact interface for the Congress-appointed Prime Minister and the four Cabinet ministries
///         (Constitution Art V §1-2). Stores a single Prime Minister record plus one minister record per
///         ministry, each with a fixed-length term that ends by passage of time. All writes are gated to the
///         kernel EXECUTIVE_REGISTRY_AUTHORITY module pointer (the standing CabinetApp) or the temporary
///         bootstrap authority used only at genesis. This is a political record layer decoupled from the
///         operational OfficeRegistry.
interface IExecutiveRegistry is IKernelModule {
    error InvalidPrimeMinister(address primeMinister);
    error InvalidPrimeMinisterPersonId(bytes32 personId);
    error InvalidPrimeMinisterTerm(uint64 termStart, uint64 termEnd);
    error InvalidMinistry(ExecutiveTypes.MinistryKind ministry);
    error InvalidMinister(address minister);
    error InvalidMinisterPersonId(bytes32 personId);
    error InvalidMinisterTerm(uint64 termStart, uint64 termEnd);
    error UnauthorizedExecutiveRegistryCaller(address caller);

    event PrimeMinisterUpdated(
        address indexed previousPrimeMinister,
        address indexed newPrimeMinister,
        bytes32 indexed newPrimeMinisterPersonId,
        uint64 termStart,
        uint64 termEnd,
        uint32 appointmentSupport,
        uint64 updatedAt,
        address updatedBy
    );

    event PrimeMinisterCleared(address indexed previousPrimeMinister, uint64 clearedAt, address indexed clearedBy);

    event MinisterUpdated(
        ExecutiveTypes.MinistryKind indexed ministry,
        address indexed previousMinister,
        address indexed newMinister,
        bytes32 newMinisterPersonId,
        uint64 termStart,
        uint64 termEnd,
        uint64 updatedAt,
        address updatedBy
    );

    event MinisterCleared(
        ExecutiveTypes.MinistryKind indexed ministry,
        address indexed previousMinister,
        uint64 clearedAt,
        address indexed clearedBy
    );

    /// @notice Returns the current Prime Minister wallet, or zero if unset.
    /// @return primeMinisterAddress The current Prime Minister wallet.
    function primeMinister() external view returns (address primeMinisterAddress);

    /// @notice Returns the full stored Prime Minister record.
    /// @return record The stored Prime Minister record, or an empty record if unset.
    function getPrimeMinister() external view returns (ExecutiveTypes.PrimeMinisterRecord memory record);

    /// @notice Returns true when a Prime Minister is set and the current term has not yet ended by passage of time.
    /// @return inTerm Whether an in-term Prime Minister currently holds office.
    function isPrimeMinisterInTerm() external view returns (bool inTerm);

    /// @notice Returns the Congress vote count that appointed the current Prime Minister.
    /// @return appointmentSupport The recorded appointment vote tally, or zero if unset.
    function primeMinisterAppointmentSupport() external view returns (uint32 appointmentSupport);

    /// @notice Returns the stored minister record for a ministry.
    /// @param ministry The ministry to query.
    /// @return record The stored minister record, or an empty record if the slot is vacant.
    function getMinister(ExecutiveTypes.MinistryKind ministry)
        external
        view
        returns (ExecutiveTypes.MinisterRecord memory record);

    /// @notice Returns true when a ministry has a minister set and the current term has not yet ended.
    /// @param ministry The ministry to query.
    /// @return inTerm Whether an in-term minister currently holds the ministry.
    function isMinisterInTerm(ExecutiveTypes.MinistryKind ministry) external view returns (bool inTerm);

    /// @notice Sets the current Prime Minister, term, and the vote tally that appointed it.
    /// @param pm The wallet holding Prime Minister status.
    /// @param personId The person identifier for the Prime Minister wallet.
    /// @param termStart The timestamp at which the term begins.
    /// @param termEnd The timestamp at which the term ends by passage of time.
    /// @param appointmentSupport The winning Congress appointment vote count to record for the removal threshold.
    function setPrimeMinister(address pm, bytes32 personId, uint64 termStart, uint64 termEnd, uint32 appointmentSupport)
        external;

    /// @notice Clears the Prime Minister, leaving the office vacant.
    function clearPrimeMinister() external;

    /// @notice Sets the minister for a ministry and its term.
    /// @param ministry The ministry to fill; must not be Undefined.
    /// @param minister The minister wallet.
    /// @param personId The person identifier for the minister wallet.
    /// @param termStart The timestamp at which the term begins.
    /// @param termEnd The timestamp at which the term ends by passage of time.
    function setMinister(
        ExecutiveTypes.MinistryKind ministry,
        address minister,
        bytes32 personId,
        uint64 termStart,
        uint64 termEnd
    ) external;

    /// @notice Clears the minister for a ministry, leaving the slot vacant.
    /// @param ministry The ministry to clear; must not be Undefined.
    function clearMinister(ExecutiveTypes.MinistryKind ministry) external;
}
