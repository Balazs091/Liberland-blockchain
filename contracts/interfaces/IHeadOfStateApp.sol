// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title IHeadOfStateApp
/// @notice User-facing application for the Senate-elected Head of State (Constitution Art VI §2). The Senate elects
///         a President from among its seat holders for a fixed five-year term that ends by passage of time; the
///         President appoints two Vice Presidents from among Senators; on resignation the first-sworn Vice President
///         assumes the presidency for the remainder of the term, otherwise the office is left vacant for re-election.
///         Registered as the kernel PRESIDENT_REGISTRY_AUTHORITY, it is the sole standing writer of the President
///         registry after genesis. The President holds no residual appointment power beyond appointing Vice Presidents.
interface IHeadOfStateApp {
    error InvalidPresidentRegistry(address registryAddress);
    error InvalidSenateSeatRegistry(address registryAddress);
    error KernelMismatch(address presidentRegistryKernel, address senateSeatRegistryKernel);
    error NotSeatHolder(uint32 seatIndex, address caller);
    error CandidateNotSeatHolder(address candidate);
    error PresidentAlreadyInTerm(address president);
    error ElectionMajorityNotReached(address candidate, uint256 voteCount, uint256 occupiedSeatCount);
    error NotPresident(address caller);
    error InvalidVicePresidentSlot(uint8 slot);
    error VicePresidentNotSeatHolder(address vp);
    error InvalidVicePresidentCandidate(address vp);
    error VicePresidentPersonIdMismatch(address vp, bytes32 provided, bytes32 expected);

    event PresidentVoteCast(
        uint32 indexed seatIndex,
        address indexed voter,
        address indexed candidate,
        uint64 seatOccupancyNonce,
        uint64 electionCycle,
        uint64 castAt
    );

    event PresidentElected(
        address indexed president,
        bytes32 indexed presidentPersonId,
        uint256 voteCount,
        uint256 occupiedSeatCount,
        uint64 termStart,
        uint64 termEnd,
        uint64 electedAt
    );

    event VicePresidentAppointed(
        uint8 indexed slot,
        address indexed vicePresident,
        bytes32 indexed vicePresidentPersonId,
        address appointedBy,
        uint64 appointedAt
    );

    event PresidentResigned(address indexed president, uint64 resignedAt);

    event PresidentSucceeded(
        address indexed previousPresident,
        address indexed newPresident,
        bytes32 newPresidentPersonId,
        uint64 termEnd,
        uint64 succeededAt
    );

    event PresidencyVacated(address indexed previousPresident, uint64 vacatedAt);

    /// @notice Returns the President registry this app writes as the standing authority.
    /// @return registryAddress The President registry address.
    function presidentRegistry() external view returns (address registryAddress);

    /// @notice Returns the Senate seat registry used to resolve seat holders and occupancy.
    /// @return registryAddress The Senate seat registry address.
    function senateSeatRegistry() external view returns (address registryAddress);

    /// @notice Returns the kernel shared by the President and Senate seat registries.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress);

    /// @notice Returns the fixed President term length applied by every election, in seconds.
    /// @return termSeconds The President term length in seconds.
    function presidentTerm() external view returns (uint64 termSeconds);

    /// @notice Returns the current election cycle nonce; a successful election advances it, voiding prior ballots.
    /// @return cycle The current election cycle nonce.
    function currentElectionCycle() external view returns (uint64 cycle);

    /// @notice Returns the raw ballot recorded for a seat.
    /// @param seatIndex The seat index to inspect.
    /// @return candidate The candidate the seat last voted for, or zero.
    /// @return seatOccupancyNonce The seat occupancy nonce the ballot is bound to.
    /// @return electionCycle The election cycle the ballot was cast in.
    function getSeatVote(uint32 seatIndex)
        external
        view
        returns (address candidate, uint64 seatOccupancyNonce, uint64 electionCycle);

    /// @notice Returns the count of currently valid seat ballots for a candidate in the current election cycle.
    /// @param candidate The candidate to tally.
    /// @return voteCount The number of valid seat ballots for the candidate.
    function voteCountFor(address candidate) external view returns (uint256 voteCount);

    /// @notice Returns true when electPresident would currently succeed for a candidate.
    /// @param candidate The candidate to test.
    /// @return electable Whether the candidate can currently be elected President.
    function canElectPresident(address candidate) external view returns (bool electable);

    /// @notice Casts or replaces this seat's ballot for a President candidate.
    /// @param seatIndex The seat index held by the caller.
    /// @param candidate The active seat-holder candidate to vote for.
    function voteForPresident(uint32 seatIndex, address candidate) external;

    /// @notice Finalizes an election when a candidate holds a strict majority of occupied seats and no President is
    ///         in term, installing a fresh five-year term and voiding all ballots for the next cycle.
    /// @param candidate The candidate to install as President.
    function electPresident(address candidate) external;

    /// @notice Appoints a Vice President into a slot; callable only by the sitting in-term President.
    /// @param slot The Vice President slot to fill (0 = first-sworn, 1 = second).
    /// @param vp The Vice President wallet, which must be a sitting Senator distinct from the President and other VP.
    /// @param vpPersonId The Vice President person identifier, which must match the wallet's seat record.
    function appointVicePresident(uint8 slot, address vp, bytes32 vpPersonId) external;

    /// @notice Resigns the presidency; the first-sworn Vice President succeeds for the remainder of the term, or the
    ///         office is left vacant for a fresh election when no first-sworn Vice President is set.
    function resignPresident() external;
}
