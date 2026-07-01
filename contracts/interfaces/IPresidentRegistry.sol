// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IKernelModule} from "./IKernelModule.sol";

/// @title IPresidentRegistry
/// @notice Stable fact interface for the Senate-elected Head of State: the wallet currently holding President
///         status, its fixed-length term, and the two Vice President slots the President appoints from the Senate.
interface IPresidentRegistry is IKernelModule {
    error InvalidPresident(address president);
    error InvalidPresidentPersonId(bytes32 personId);
    error InvalidPresidentTerm(uint64 termStart, uint64 termEnd);
    error InvalidVicePresident(address vicePresident);
    error InvalidVicePresidentPersonId(bytes32 personId);
    error InvalidVicePresidentSlot(uint8 slot);
    error UnauthorizedPresidentRegistryCaller(address caller);

    event PresidentUpdated(
        address indexed previousPresident,
        address indexed newPresident,
        bytes32 indexed newPresidentPersonId,
        bytes32 mandateHash,
        uint64 termStart,
        uint64 termEnd,
        uint64 updatedAt,
        address updatedBy
    );

    event PresidentVacated(address indexed previousPresident, uint64 vacatedAt, address vacatedBy);

    event VicePresidentUpdated(
        uint8 indexed slot,
        address indexed previousVicePresident,
        address indexed newVicePresident,
        bytes32 newVicePresidentPersonId,
        uint64 updatedAt,
        address updatedBy
    );

    /// @notice Returns the current President wallet, or zero if unset.
    /// @return president The current President wallet.
    function currentPresident() external view returns (address president);

    /// @notice Returns the current President person identifier, or zero if unset.
    /// @return personId The current President person identifier.
    function currentPresidentPersonId() external view returns (bytes32 personId);

    /// @notice Returns the mandate or source-document hash associated with the current President status.
    /// @return mandateHash The current mandate hash.
    function currentMandateHash() external view returns (bytes32 mandateHash);

    /// @notice Returns the Vice President wallet for a slot (0 or 1), or zero if unset.
    /// @param slot The Vice President slot to inspect (0 = first-sworn, 1 = second).
    /// @return vp The Vice President wallet for the slot.
    function vicePresident(uint8 slot) external view returns (address vp);

    /// @notice Returns the Vice President person identifier for a slot (0 or 1), or zero if unset.
    /// @param slot The Vice President slot to inspect (0 = first-sworn, 1 = second).
    /// @return personId The Vice President person identifier for the slot.
    function vicePresidentPersonId(uint8 slot) external view returns (bytes32 personId);

    /// @notice Returns the timestamp at which the current President term began.
    /// @return startTime The current term start timestamp.
    function termStart() external view returns (uint64 startTime);

    /// @notice Returns the timestamp at which the current President term ends by passage of time.
    /// @return endTime The current term end timestamp.
    function termEnd() external view returns (uint64 endTime);

    /// @notice Returns true when a President is set and the current term has not yet ended by passage of time.
    /// @return inTerm Whether an in-term President currently holds office.
    function isPresidentInTerm() external view returns (bool inTerm);

    /// @notice Sets the current President and term, clearing both Vice President slots for fresh appointment.
    /// @param president The wallet holding President status.
    /// @param personId The person identifier for the President wallet.
    /// @param mandateHash The legal/source-document hash supporting the status update.
    /// @param startTime The timestamp at which the term begins.
    /// @param endTime The timestamp at which the term ends by passage of time.
    function setPresident(address president, bytes32 personId, bytes32 mandateHash, uint64 startTime, uint64 endTime)
        external;

    /// @notice Clears the President and both Vice President slots, leaving the office vacant.
    function vacatePresident() external;

    /// @notice Sets the Vice President wallet and person identifier for a slot (0 or 1).
    /// @param slot The Vice President slot to set (0 = first-sworn, 1 = second).
    /// @param vp The Vice President wallet.
    /// @param vpPersonId The Vice President person identifier.
    function setVicePresident(uint8 slot, address vp, bytes32 vpPersonId) external;
}
