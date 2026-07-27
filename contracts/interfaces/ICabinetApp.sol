// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ExecutiveTypes} from "../types/ExecutiveTypes.sol";

/// @title ICabinetApp
/// @notice User-facing application for the Congress-appointed Prime Minister and the four-seat Cabinet
///         (Constitution Art V §1-2). Congress appoints the Prime Minister by strict majority of occupied
///         seats for a fixed five-year term, and may remove the Prime Minister with at least as many valid
///         removal votes as the tally that appointed him (owner's rule: appointed by N ⇒ removal needs >= N).
///         The Prime Minister appoints the four ministers (Finance, Foreign Affairs, Interior, Justice), each
///         for a five-year term, and cannot fire them: a sitting in-term minister slot cannot be reassigned, so
///         only Congress may dismiss a minister by strict majority. Registered as the kernel
///         EXECUTIVE_REGISTRY_AUTHORITY, it is the sole standing writer of the Executive registry after genesis.
///
///         Congress ballots are bound to the Congress office cycle: a member's ballot counts only while the
///         voter is a current active Congress member and the ballot's cycle matches the registry's current
///         office term cycle, so a prior Congress's ballots never carry into the next. Separate ballot books
///         (each with its own voiding nonce) back the appointment vote, the removal vote, and each ministry's
///         dismissal vote. Beyond recording the political cabinet, it wires each ministry to its operational
///         OfficeRegistry office (where one exists): appointing a minister makes that minister the office admin and
///         activates the office, while dismissal or resignation deactivates the office so no operations run without
///         a minister.
interface ICabinetApp {
    error InvalidExecutiveRegistry(address registryAddress);
    error InvalidCongressCandidateRegistry(address registryAddress);
    error InvalidCitizenEligibilityPolicy(address policyAddress);
    error InvalidOfficeRegistry(address registryAddress);
    error InvalidIdentityRegistry(address registryAddress);
    error KernelMismatch(address expectedKernel, address actualKernel);
    error NotCongressMember(address caller);
    error CandidateNotInGoodStanding(address candidate);
    error PrimeMinisterAlreadyInTerm(address primeMinister);
    error NoPrimeMinisterInTerm();
    error AppointmentMajorityNotReached(address candidate, uint256 voteCount, uint256 occupiedSeatCount);
    error RemovalThresholdNotReached(uint256 removalVotes, uint256 appointmentSupport);
    error NotPrimeMinister(address caller);
    error InvalidMinistry(ExecutiveTypes.MinistryKind ministry);
    error MinisterSlotOccupied(ExecutiveTypes.MinistryKind ministry, address minister);
    error MinisterNotInTerm(ExecutiveTypes.MinistryKind ministry);
    error MinisterAlreadyServing(address minister);
    error InvalidMinisterCandidate(address minister);
    error DismissalMajorityNotReached(
        ExecutiveTypes.MinistryKind ministry, uint256 voteCount, uint256 occupiedSeatCount
    );
    error NotMinister(ExecutiveTypes.MinistryKind ministry, address caller);
    error MinisterStillInTerm(ExecutiveTypes.MinistryKind ministry);

    event PrimeMinisterVoteCast(
        address indexed voter,
        address indexed candidate,
        uint256 congressCycleId,
        uint64 appointmentNonce,
        uint64 castAt
    );

    event PrimeMinisterAppointed(
        address indexed primeMinister,
        bytes32 indexed primeMinisterPersonId,
        uint256 voteCount,
        uint256 occupiedSeatCount,
        uint64 termStart,
        uint64 termEnd,
        uint64 appointedAt
    );

    event PrimeMinisterRemovalVoteCast(
        address indexed voter,
        address indexed primeMinister,
        uint256 congressCycleId,
        uint64 removalNonce,
        uint64 castAt
    );

    event PrimeMinisterRemoved(
        address indexed primeMinister, uint256 removalVotes, uint256 appointmentSupport, uint64 removedAt
    );

    event PrimeMinisterResigned(address indexed primeMinister, uint64 resignedAt);

    event MinisterAppointed(
        ExecutiveTypes.MinistryKind indexed ministry,
        address indexed minister,
        bytes32 ministerPersonId,
        address appointedBy,
        uint64 termStart,
        uint64 termEnd,
        uint64 appointedAt
    );

    event MinisterDismissalVoteCast(
        ExecutiveTypes.MinistryKind indexed ministry,
        address indexed voter,
        address indexed minister,
        uint256 congressCycleId,
        uint64 dismissalNonce,
        uint64 castAt
    );

    event MinisterDismissed(
        ExecutiveTypes.MinistryKind indexed ministry,
        address indexed minister,
        uint256 dismissalVotes,
        uint256 occupiedSeatCount,
        uint64 dismissedAt
    );

    event MinisterResigned(ExecutiveTypes.MinistryKind indexed ministry, address indexed minister, uint64 resignedAt);

    event MinisterTermRetired(
        ExecutiveTypes.MinistryKind indexed ministry,
        address indexed minister,
        uint64 retiredAt,
        address indexed retiredBy
    );

    /// @notice Returns the Executive registry this app writes as the standing authority.
    /// @return registryAddress The Executive registry address.
    function executiveRegistry() external view returns (address registryAddress);

    /// @notice Returns the Congress candidate registry used to resolve members, cycles, and occupancy.
    /// @return registryAddress The Congress candidate registry address.
    function congressCandidateRegistry() external view returns (address registryAddress);

    /// @notice Returns the citizen eligibility policy used to validate Prime Minister and minister appointees.
    /// @return policyAddress The citizen eligibility policy address.
    function citizenEligibilityPolicy() external view returns (address policyAddress);

    /// @notice Returns the office registry whose ministry offices are synced with cabinet appointments.
    /// @return registryAddress The office registry address.
    function officeRegistry() external view returns (address registryAddress);

    /// @notice Returns the operational office wired to a ministry, or zero when the ministry has no mapped office.
    /// @param ministry The ministry to resolve.
    /// @return officeId The mapped office identifier, or zero when the ministry is unwired.
    function ministryOfficeId(ExecutiveTypes.MinistryKind ministry) external view returns (bytes32 officeId);

    /// @notice Returns the identity registry used to record appointee person identifiers.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the kernel shared by the Executive and Congress registries.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress);

    /// @notice Returns the fixed Prime Minister term length applied by every appointment, in seconds.
    /// @return termSeconds The Prime Minister term length in seconds.
    function primeMinisterTerm() external view returns (uint64 termSeconds);

    /// @notice Returns the fixed minister term length applied by every appointment, in seconds.
    /// @return termSeconds The minister term length in seconds.
    function ministerTerm() external view returns (uint64 termSeconds);

    /// @notice Returns the current Prime Minister wallet, or zero if unset.
    /// @return primeMinisterAddress The current Prime Minister wallet.
    function primeMinister() external view returns (address primeMinisterAddress);

    /// @notice Returns the full stored Prime Minister record.
    /// @return record The stored Prime Minister record.
    function getPrimeMinister() external view returns (ExecutiveTypes.PrimeMinisterRecord memory record);

    /// @notice Returns true when an in-term Prime Minister currently holds office.
    /// @return inTerm Whether an in-term Prime Minister holds office.
    function isPrimeMinisterInTerm() external view returns (bool inTerm);

    /// @notice Returns the Congress vote count that appointed the current Prime Minister.
    /// @return appointmentSupport The recorded appointment vote tally.
    function primeMinisterAppointmentSupport() external view returns (uint32 appointmentSupport);

    /// @notice Returns the stored minister record for a ministry.
    /// @param ministry The ministry to query.
    /// @return record The stored minister record.
    function getMinister(ExecutiveTypes.MinistryKind ministry)
        external
        view
        returns (ExecutiveTypes.MinisterRecord memory record);

    /// @notice Returns true when an in-term minister currently holds a ministry.
    /// @param ministry The ministry to query.
    /// @return inTerm Whether an in-term minister holds the ministry.
    function isMinisterInTerm(ExecutiveTypes.MinistryKind ministry) external view returns (bool inTerm);

    /// @notice Returns the count of currently valid appointment votes for a candidate in the current cycle.
    /// @param candidate The candidate to tally.
    /// @return voteCount The number of valid appointment votes for the candidate.
    function appointmentVoteCount(address candidate) external view returns (uint256 voteCount);

    /// @notice Returns the count of currently valid Prime Minister removal votes in the current cycle.
    /// @return voteCount The number of valid removal votes.
    function removalVoteCount() external view returns (uint256 voteCount);

    /// @notice Returns the count of currently valid dismissal votes for a ministry in the current cycle.
    /// @param ministry The ministry to tally.
    /// @return voteCount The number of valid dismissal votes for the ministry.
    function dismissalVoteCount(ExecutiveTypes.MinistryKind ministry) external view returns (uint256 voteCount);

    /// @notice Returns the raw appointment ballot recorded for a Congress member.
    /// @param voter The Congress member wallet to inspect.
    /// @return candidate The candidate the member last voted for, or zero.
    /// @return congressCycleId The Congress cycle the ballot is bound to.
    /// @return appointmentNonce The appointment nonce the ballot was cast under.
    function getAppointmentBallot(address voter)
        external
        view
        returns (address candidate, uint256 congressCycleId, uint64 appointmentNonce);

    /// @notice Returns the raw removal ballot recorded for a Congress member.
    /// @param voter The Congress member wallet to inspect.
    /// @return targetPrimeMinister The Prime Minister targeted when the ballot was cast, or zero.
    /// @return congressCycleId The Congress cycle the ballot is bound to.
    /// @return removalNonce The removal nonce the ballot was cast under.
    function getRemovalBallot(address voter)
        external
        view
        returns (address targetPrimeMinister, uint256 congressCycleId, uint64 removalNonce);

    /// @notice Returns the raw dismissal ballot recorded for a Congress member and ministry.
    /// @param ministry The ministry the ballot targets.
    /// @param voter The Congress member wallet to inspect.
    /// @return targetMinister The minister targeted when the ballot was cast, or zero.
    /// @return congressCycleId The Congress cycle the ballot is bound to.
    /// @return dismissalNonce The dismissal nonce the ballot was cast under.
    function getDismissalBallot(ExecutiveTypes.MinistryKind ministry, address voter)
        external
        view
        returns (address targetMinister, uint256 congressCycleId, uint64 dismissalNonce);

    /// @notice Returns true when appointPrimeMinister would currently succeed for a candidate.
    /// @param candidate The candidate to test.
    /// @return appointable Whether the candidate can currently be appointed Prime Minister.
    function canAppointPrimeMinister(address candidate) external view returns (bool appointable);

    /// @notice Returns true when removePrimeMinister would currently succeed.
    /// @return removable Whether the sitting Prime Minister can currently be removed.
    function canRemovePrimeMinister() external view returns (bool removable);

    /// @notice Returns true when dismissMinister would currently succeed for a ministry.
    /// @param ministry The ministry to test.
    /// @return dismissable Whether the sitting minister can currently be dismissed.
    function canDismissMinister(ExecutiveTypes.MinistryKind ministry) external view returns (bool dismissable);

    /// @notice Casts or replaces the caller's Congress ballot for a Prime Minister candidate.
    /// @param candidate The citizen-in-good-standing candidate to vote for.
    function voteForPrimeMinister(address candidate) external;

    /// @notice Finalizes an appointment when a candidate holds a strict majority of occupied Congress seats and
    ///         no Prime Minister is in term, installing a five-year term and recording the winning vote tally.
    /// @param candidate The candidate to install as Prime Minister.
    function appointPrimeMinister(address candidate) external;

    /// @notice Casts or replaces the caller's Congress ballot to remove the sitting Prime Minister.
    function voteToRemovePrimeMinister() external;

    /// @notice Removes the sitting Prime Minister when valid removal votes reach the recorded appointment tally.
    function removePrimeMinister() external;

    /// @notice Resigns the Prime Minister; callable only by the sitting Prime Minister, leaving the office vacant.
    function resignPrimeMinister() external;

    /// @notice Appoints a minister to a currently vacant or expired ministry slot; callable only by the sitting
    ///         in-term Prime Minister. A sitting in-term minister slot cannot be reassigned (the Prime Minister
    ///         cannot fire ministers).
    /// @param ministry The ministry to fill; must not be Undefined.
    /// @param minister The citizen-in-good-standing minister wallet, distinct from the Prime Minister and any
    ///        other sitting minister.
    function appointMinister(ExecutiveTypes.MinistryKind ministry, address minister) external;

    /// @notice Casts or replaces the caller's Congress ballot to dismiss the sitting minister of a ministry.
    /// @param ministry The ministry whose minister the caller votes to dismiss.
    function voteToDismissMinister(ExecutiveTypes.MinistryKind ministry) external;

    /// @notice Dismisses the sitting minister of a ministry when valid dismissal votes are a strict majority of
    ///         occupied Congress seats, leaving the slot vacant for the Prime Minister to re-appoint.
    /// @param ministry The ministry whose minister is dismissed.
    function dismissMinister(ExecutiveTypes.MinistryKind ministry) external;

    /// @notice Resigns a minister; callable only by the sitting minister of that ministry, leaving the slot vacant.
    /// @param ministry The ministry the caller resigns from.
    function resignMinister(ExecutiveTypes.MinistryKind ministry) external;

    /// @notice Permissionlessly retires a minister whose fixed term has lapsed: clears the stale record and
    ///         deactivates the ministry office so an out-of-term official cannot retain operational (treasury)
    ///         authority when no sitting Prime Minister is available to re-appoint over the slot. Reverts if the
    ///         minister is still in term. Permissionless because term expiry is a pure function of time.
    /// @param ministry The ministry whose expired minister is retired.
    function retireExpiredMinister(ExecutiveTypes.MinistryKind ministry) external;
}
