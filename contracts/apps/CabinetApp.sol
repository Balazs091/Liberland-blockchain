// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ICabinetApp} from "../interfaces/ICabinetApp.sol";
import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IExecutiveRegistry} from "../interfaces/IExecutiveRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {ExecutiveTypes} from "../types/ExecutiveTypes.sol";

/// @title CabinetApp
/// @notice Standing authority for the Congress-appointed Prime Minister and the four-seat Cabinet (Constitution
///         Art V §1-2). Registered as the kernel EXECUTIVE_REGISTRY_AUTHORITY, it is the sole live writer of the
///         Executive registry after genesis.
///
///         Appointment: Congress members cast wallet-keyed ballots; a permissionless finalizer installs a
///         candidate whose valid ballots are a strict majority of the current Congress office term's occupied
///         seats (`votes * 2 > occupiedSeatCount`) for a fixed five-year term, and records the winning tally as
///         the removal threshold. Removal: a permissionless finalizer clears the Prime Minister once valid
///         removal votes reach that recorded tally (`removalVotes >= appointmentSupport`) — a fixed absolute
///         count independent of the current seat count (owner's rule: appointed by N ⇒ removal needs >= N).
///
///         Ministers: the sitting in-term Prime Minister appoints each of the four ministers for a five-year
///         term but cannot fire them — an in-term minister slot cannot be reassigned, so replacement is only
///         possible once the slot is vacant or expired. Only Congress dismisses a minister, by strict majority
///         of occupied seats, which leaves the slot vacant for the Prime Minister to re-appoint.
///
///         Congress ballots are bound to the Congress office cycle: a ballot counts only while the voter is a
///         current active Congress member and its cycle matches the registry's current office term cycle, and an
///         internal per-book nonce voids a book's ballots after each finalized decision.
///
///         Operational wiring: each ministry that has a mapped OfficeRegistry office is kept in sync with its
///         political minister. Appointing a minister transfers that office's admin to the minister and activates
///         the office (the minister gains operational power, e.g. the Finance Minister running the Ministry of
///         Finance treasury office); dismissal or resignation deactivates the office so no operations run without a
///         sitting minister. Only the Finance ministry has an operational office today; the other three stay
///         unwired (`bytes32(0)`) until their offices exist and a future CabinetApp deployment maps them via
///         module-pointer governance. Registered as the kernel CABINET_APP module pointer, the OfficeRegistry
///         accepts it as a registry authority for these admin/active transitions.
contract CabinetApp is ICabinetApp {
    /// @dev Fixed five-year Prime Minister term (5 * 365 days) that ends by passage of time.
    uint64 internal constant PRIME_MINISTER_TERM = 1825 days;
    /// @dev Fixed five-year minister term (5 * 365 days) that ends by passage of time.
    uint64 internal constant MINISTER_TERM = 1825 days;

    IExecutiveRegistry private immutable _executiveRegistry;
    ICongressCandidateRegistry private immutable _congressCandidateRegistry;
    IIdentityRegistry private immutable _identityRegistry;
    IOfficeRegistry private immutable _officeRegistry;
    address private immutable _kernel;

    /// @dev Ministry → operational office wired to it; `bytes32(0)` means the ministry has no office (unwired).
    mapping(ExecutiveTypes.MinistryKind ministry => bytes32 officeId) private _ministryOfficeId;

    struct CongressBallot {
        address target;
        uint256 congressCycleId;
        uint64 ballotNonce;
        uint64 castAt;
    }

    mapping(address voter => CongressBallot ballot) private _appointmentBallots;
    mapping(address voter => CongressBallot ballot) private _removalBallots;
    mapping(ExecutiveTypes.MinistryKind ministry => mapping(address voter => CongressBallot ballot)) private
        _dismissalBallots;

    uint64 private _appointmentNonce;
    uint64 private _removalNonce;
    mapping(ExecutiveTypes.MinistryKind ministry => uint64 nonce) private _dismissalNonce;

    /// @param executiveRegistryAddress The Executive registry mutated as the standing authority.
    /// @param congressCandidateRegistryAddress The Congress candidate registry used to resolve members and cycles.
    /// @param citizenEligibilityPolicyAddress The policy used to validate Prime Minister and minister appointees.
    /// @param financeOfficeId The operational Ministry of Finance office wired to the Finance ministry; the other
    ///        three ministries stay unwired (`bytes32(0)`) until their operational offices exist and a future
    ///        CabinetApp deployment maps them via module-pointer governance.
    /// @param officeRegistryAddress The office registry whose ministry offices track cabinet appointments.
    constructor(
        address executiveRegistryAddress,
        address congressCandidateRegistryAddress,
        address citizenEligibilityPolicyAddress,
        bytes32 financeOfficeId,
        address officeRegistryAddress
    ) {
        if (executiveRegistryAddress == address(0) || executiveRegistryAddress.code.length == 0) {
            revert InvalidExecutiveRegistry(executiveRegistryAddress);
        }
        if (congressCandidateRegistryAddress == address(0) || congressCandidateRegistryAddress.code.length == 0) {
            revert InvalidCongressCandidateRegistry(congressCandidateRegistryAddress);
        }
        if (citizenEligibilityPolicyAddress == address(0) || citizenEligibilityPolicyAddress.code.length == 0) {
            revert InvalidCitizenEligibilityPolicy(citizenEligibilityPolicyAddress);
        }
        if (officeRegistryAddress == address(0) || officeRegistryAddress.code.length == 0) {
            revert InvalidOfficeRegistry(officeRegistryAddress);
        }

        address executiveKernel = IExecutiveRegistry(executiveRegistryAddress).kernel();
        if (executiveKernel == address(0) || executiveKernel.code.length == 0) {
            revert KernelMismatch(executiveKernel, executiveKernel);
        }

        address congressKernel = ICongressCandidateRegistry(congressCandidateRegistryAddress).kernel();
        if (congressKernel != executiveKernel) {
            revert KernelMismatch(executiveKernel, congressKernel);
        }

        // The citizen eligibility policy is not a kernel-gated registry, so its kernel is resolved through the
        // identity registry it reads, which must share the Executive registry's kernel.
        address identityRegistryAddress = ICitizenEligibilityPolicy(citizenEligibilityPolicyAddress).identityRegistry();
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidIdentityRegistry(identityRegistryAddress);
        }
        address identityKernel = IIdentityRegistry(identityRegistryAddress).kernel();
        if (identityKernel != executiveKernel) {
            revert KernelMismatch(executiveKernel, identityKernel);
        }

        address officeKernel = IOfficeRegistry(officeRegistryAddress).kernel();
        if (officeKernel != executiveKernel) {
            revert KernelMismatch(executiveKernel, officeKernel);
        }

        _executiveRegistry = IExecutiveRegistry(executiveRegistryAddress);
        _congressCandidateRegistry = ICongressCandidateRegistry(congressCandidateRegistryAddress);
        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _officeRegistry = IOfficeRegistry(officeRegistryAddress);
        _kernel = executiveKernel;

        // Wire the Finance ministry to its operational Ministry of Finance office. The other three ministries are
        // left unwired (`bytes32(0)`) until their offices exist and a future CabinetApp maps them.
        _ministryOfficeId[ExecutiveTypes.MinistryKind.Finance] = financeOfficeId;

        // Start book nonces at 1 so a never-voted member's default (zero) ballot never matches an open book.
        _appointmentNonce = 1;
        _removalNonce = 1;
    }

    /// @inheritdoc ICabinetApp
    function executiveRegistry() external view returns (address registryAddress) {
        return address(_executiveRegistry);
    }

    /// @inheritdoc ICabinetApp
    function congressCandidateRegistry() external view returns (address registryAddress) {
        return address(_congressCandidateRegistry);
    }

    /// @inheritdoc ICabinetApp
    function citizenEligibilityPolicy() external view returns (address policyAddress) {
        return address(_currentCitizenEligibilityPolicy());
    }

    /// @inheritdoc ICabinetApp
    function officeRegistry() external view returns (address registryAddress) {
        return address(_officeRegistry);
    }

    /// @inheritdoc ICabinetApp
    function ministryOfficeId(ExecutiveTypes.MinistryKind ministry) external view returns (bytes32 officeId) {
        return _ministryOfficeId[ministry];
    }

    /// @inheritdoc ICabinetApp
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc ICabinetApp
    function kernel() external view returns (address kernelAddress) {
        return _kernel;
    }

    /// @inheritdoc ICabinetApp
    function primeMinisterTerm() external pure returns (uint64 termSeconds) {
        return PRIME_MINISTER_TERM;
    }

    /// @inheritdoc ICabinetApp
    function ministerTerm() external pure returns (uint64 termSeconds) {
        return MINISTER_TERM;
    }

    /// @inheritdoc ICabinetApp
    function primeMinister() external view returns (address primeMinisterAddress) {
        return _executiveRegistry.primeMinister();
    }

    /// @inheritdoc ICabinetApp
    function getPrimeMinister() external view returns (ExecutiveTypes.PrimeMinisterRecord memory record) {
        return _executiveRegistry.getPrimeMinister();
    }

    /// @inheritdoc ICabinetApp
    function isPrimeMinisterInTerm() external view returns (bool inTerm) {
        return _executiveRegistry.isPrimeMinisterInTerm();
    }

    /// @inheritdoc ICabinetApp
    function primeMinisterAppointmentSupport() external view returns (uint32 appointmentSupport) {
        return _executiveRegistry.primeMinisterAppointmentSupport();
    }

    /// @inheritdoc ICabinetApp
    function getMinister(ExecutiveTypes.MinistryKind ministry)
        external
        view
        returns (ExecutiveTypes.MinisterRecord memory record)
    {
        return _executiveRegistry.getMinister(ministry);
    }

    /// @inheritdoc ICabinetApp
    function isMinisterInTerm(ExecutiveTypes.MinistryKind ministry) external view returns (bool inTerm) {
        return _executiveRegistry.isMinisterInTerm(ministry);
    }

    /// @inheritdoc ICabinetApp
    function appointmentVoteCount(address candidate) external view returns (uint256 voteCount) {
        return _appointmentVoteCount(candidate);
    }

    /// @inheritdoc ICabinetApp
    function removalVoteCount() external view returns (uint256 voteCount) {
        return _removalVoteCount();
    }

    /// @inheritdoc ICabinetApp
    function dismissalVoteCount(ExecutiveTypes.MinistryKind ministry) external view returns (uint256 voteCount) {
        return _dismissalVoteCount(ministry);
    }

    /// @inheritdoc ICabinetApp
    function getAppointmentBallot(address voter)
        external
        view
        returns (address candidate, uint256 congressCycleId, uint64 appointmentNonce)
    {
        CongressBallot memory ballot = _appointmentBallots[voter];
        return (ballot.target, ballot.congressCycleId, ballot.ballotNonce);
    }

    /// @inheritdoc ICabinetApp
    function getRemovalBallot(address voter)
        external
        view
        returns (address targetPrimeMinister, uint256 congressCycleId, uint64 removalNonce)
    {
        CongressBallot memory ballot = _removalBallots[voter];
        return (ballot.target, ballot.congressCycleId, ballot.ballotNonce);
    }

    /// @inheritdoc ICabinetApp
    function getDismissalBallot(ExecutiveTypes.MinistryKind ministry, address voter)
        external
        view
        returns (address targetMinister, uint256 congressCycleId, uint64 dismissalNonce)
    {
        CongressBallot memory ballot = _dismissalBallots[ministry][voter];
        return (ballot.target, ballot.congressCycleId, ballot.ballotNonce);
    }

    /// @inheritdoc ICabinetApp
    function canAppointPrimeMinister(address candidate) external view returns (bool appointable) {
        if (_executiveRegistry.isPrimeMinisterInTerm()) {
            return false;
        }
        if (!_currentCitizenEligibilityPolicy().isCitizenInGoodStanding(candidate)) {
            return false;
        }

        return _appointmentVoteCount(candidate) * 2 > _occupiedSeatCount();
    }

    /// @inheritdoc ICabinetApp
    function canRemovePrimeMinister() external view returns (bool removable) {
        if (!_executiveRegistry.isPrimeMinisterInTerm()) {
            return false;
        }

        return _removalVoteCount() >= _executiveRegistry.primeMinisterAppointmentSupport();
    }

    /// @inheritdoc ICabinetApp
    function canDismissMinister(ExecutiveTypes.MinistryKind ministry) external view returns (bool dismissable) {
        if (ministry == ExecutiveTypes.MinistryKind.Undefined) {
            return false;
        }
        if (!_executiveRegistry.isMinisterInTerm(ministry)) {
            return false;
        }

        return _dismissalVoteCount(ministry) * 2 > _occupiedSeatCount();
    }

    /// @inheritdoc ICabinetApp
    function voteForPrimeMinister(address candidate) external {
        _requireActiveCongressMember(msg.sender);
        if (!_currentCitizenEligibilityPolicy().isCitizenInGoodStanding(candidate)) {
            revert CandidateNotInGoodStanding(candidate);
        }

        uint256 cycleId = _currentCongressCycleId();
        uint64 nonce = _appointmentNonce;
        uint64 castAt = uint64(block.timestamp);

        _appointmentBallots[msg.sender] =
            CongressBallot({target: candidate, congressCycleId: cycleId, ballotNonce: nonce, castAt: castAt});

        emit PrimeMinisterVoteCast(msg.sender, candidate, cycleId, nonce, castAt);
    }

    /// @inheritdoc ICabinetApp
    function appointPrimeMinister(address candidate) external {
        if (_executiveRegistry.isPrimeMinisterInTerm()) {
            revert PrimeMinisterAlreadyInTerm(_executiveRegistry.primeMinister());
        }
        if (!_currentCitizenEligibilityPolicy().isCitizenInGoodStanding(candidate)) {
            revert CandidateNotInGoodStanding(candidate);
        }

        uint256 voteCount = _appointmentVoteCount(candidate);
        uint256 occupiedSeats = _occupiedSeatCount();
        if (voteCount * 2 <= occupiedSeats) {
            revert AppointmentMajorityNotReached(candidate, voteCount, occupiedSeats);
        }

        bytes32 personId = _identityRegistry.resolveWalletToPersonId(candidate);
        uint64 termStart = uint64(block.timestamp);
        uint64 termEnd = termStart + PRIME_MINISTER_TERM;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 appointmentSupport = uint32(voteCount);

        // Void every appointment ballot for the next contest and reset the removal book for the fresh tenure.
        _appointmentNonce += 1;
        _removalNonce += 1;

        _executiveRegistry.setPrimeMinister(candidate, personId, termStart, termEnd, appointmentSupport);

        emit PrimeMinisterAppointed(
            candidate, personId, voteCount, occupiedSeats, termStart, termEnd, uint64(block.timestamp)
        );
    }

    /// @inheritdoc ICabinetApp
    function voteToRemovePrimeMinister() external {
        _requireActiveCongressMember(msg.sender);
        if (!_executiveRegistry.isPrimeMinisterInTerm()) {
            revert NoPrimeMinisterInTerm();
        }

        address sittingPrimeMinister = _executiveRegistry.primeMinister();
        uint256 cycleId = _currentCongressCycleId();
        uint64 nonce = _removalNonce;
        uint64 castAt = uint64(block.timestamp);

        _removalBallots[msg.sender] = CongressBallot({
            target: sittingPrimeMinister, congressCycleId: cycleId, ballotNonce: nonce, castAt: castAt
        });

        emit PrimeMinisterRemovalVoteCast(msg.sender, sittingPrimeMinister, cycleId, nonce, castAt);
    }

    /// @inheritdoc ICabinetApp
    function removePrimeMinister() external {
        if (!_executiveRegistry.isPrimeMinisterInTerm()) {
            revert NoPrimeMinisterInTerm();
        }

        address sittingPrimeMinister = _executiveRegistry.primeMinister();
        uint256 removalVotes = _removalVoteCount();
        uint256 appointmentSupport = _executiveRegistry.primeMinisterAppointmentSupport();
        if (removalVotes < appointmentSupport) {
            revert RemovalThresholdNotReached(removalVotes, appointmentSupport);
        }

        // Void the removal book so stale removal ballots never carry into a future tenure.
        _removalNonce += 1;

        _executiveRegistry.clearPrimeMinister();

        emit PrimeMinisterRemoved(sittingPrimeMinister, removalVotes, appointmentSupport, uint64(block.timestamp));
    }

    /// @inheritdoc ICabinetApp
    function resignPrimeMinister() external {
        ExecutiveTypes.PrimeMinisterRecord memory record = _executiveRegistry.getPrimeMinister();
        if (!record.active || !_isActiveWalletForPerson(msg.sender, record.personId)) {
            revert NotPrimeMinister(msg.sender);
        }

        _removalNonce += 1;

        _executiveRegistry.clearPrimeMinister();

        emit PrimeMinisterResigned(msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc ICabinetApp
    function appointMinister(ExecutiveTypes.MinistryKind ministry, address minister) external {
        _requireSittingPrimeMinister(msg.sender);
        if (ministry == ExecutiveTypes.MinistryKind.Undefined) {
            revert InvalidMinistry(ministry);
        }
        // "The PM cannot fire ministers": a sitting in-term slot cannot be reassigned; only a vacant or expired
        // slot may be filled. Congress dismissal (or minister resignation/term expiry) is the only way to vacate.
        if (_executiveRegistry.isMinisterInTerm(ministry)) {
            revert MinisterSlotOccupied(ministry, _executiveRegistry.getMinister(ministry).minister);
        }
        if (!_currentCitizenEligibilityPolicy().isCitizenInGoodStanding(minister)) {
            revert CandidateNotInGoodStanding(minister);
        }
        if (_identityRegistry.resolveWalletToPersonId(minister) == _executiveRegistry.getPrimeMinister().personId) {
            revert InvalidMinisterCandidate(minister);
        }
        if (_isSittingMinister(minister)) {
            revert MinisterAlreadyServing(minister);
        }

        bytes32 personId = _identityRegistry.resolveWalletToPersonId(minister);
        uint64 termStart = uint64(block.timestamp);
        uint64 termEnd = termStart + MINISTER_TERM;

        // Reset this ministry's dismissal book for the fresh minister tenure.
        _dismissalNonce[ministry] += 1;

        _executiveRegistry.setMinister(ministry, minister, personId, termStart, termEnd);

        emit MinisterAppointed(ministry, minister, personId, msg.sender, termStart, termEnd, uint64(block.timestamp));

        // Grant the minister operational control of the ministry's office (admin + active) where one is wired.
        _syncMinisterOffice(ministry, minister, termEnd, true);
    }

    /// @inheritdoc ICabinetApp
    function voteToDismissMinister(ExecutiveTypes.MinistryKind ministry) external {
        _requireActiveCongressMember(msg.sender);
        if (ministry == ExecutiveTypes.MinistryKind.Undefined) {
            revert InvalidMinistry(ministry);
        }
        if (!_executiveRegistry.isMinisterInTerm(ministry)) {
            revert MinisterNotInTerm(ministry);
        }

        address sittingMinister = _executiveRegistry.getMinister(ministry).minister;
        uint256 cycleId = _currentCongressCycleId();
        uint64 nonce = _dismissalNonce[ministry];
        uint64 castAt = uint64(block.timestamp);

        _dismissalBallots[ministry][msg.sender] =
            CongressBallot({target: sittingMinister, congressCycleId: cycleId, ballotNonce: nonce, castAt: castAt});

        emit MinisterDismissalVoteCast(ministry, msg.sender, sittingMinister, cycleId, nonce, castAt);
    }

    /// @inheritdoc ICabinetApp
    function dismissMinister(ExecutiveTypes.MinistryKind ministry) external {
        if (ministry == ExecutiveTypes.MinistryKind.Undefined) {
            revert InvalidMinistry(ministry);
        }
        if (!_executiveRegistry.isMinisterInTerm(ministry)) {
            revert MinisterNotInTerm(ministry);
        }

        address sittingMinister = _executiveRegistry.getMinister(ministry).minister;
        uint256 dismissalVotes = _dismissalVoteCount(ministry);
        uint256 occupiedSeats = _occupiedSeatCount();
        if (dismissalVotes * 2 <= occupiedSeats) {
            revert DismissalMajorityNotReached(ministry, dismissalVotes, occupiedSeats);
        }

        // Void this ministry's dismissal book; the slot is left vacant for the Prime Minister to re-appoint.
        _dismissalNonce[ministry] += 1;

        _executiveRegistry.clearMinister(ministry);

        emit MinisterDismissed(ministry, sittingMinister, dismissalVotes, occupiedSeats, uint64(block.timestamp));

        // Deactivate the ministry's office (where one is wired): no operations run without a sitting minister.
        _syncMinisterOffice(ministry, address(0), 0, false);
    }

    /// @inheritdoc ICabinetApp
    function retireExpiredMinister(ExecutiveTypes.MinistryKind ministry) external {
        if (ministry == ExecutiveTypes.MinistryKind.Undefined) {
            revert InvalidMinistry(ministry);
        }

        ExecutiveTypes.MinisterRecord memory record = _executiveRegistry.getMinister(ministry);
        if (!record.active) {
            revert NotMinister(ministry, address(0));
        }
        // Only an out-of-term minister can be retired this way; an in-term minister is removable only by Congress.
        if (_executiveRegistry.isMinisterInTerm(ministry)) {
            revert MinisterStillInTerm(ministry);
        }

        _dismissalNonce[ministry] += 1;
        _executiveRegistry.clearMinister(ministry);

        emit MinisterTermRetired(ministry, record.minister, uint64(block.timestamp), msg.sender);

        // Deactivate the ministry's office (where one is wired): out-of-term officials keep no operational authority.
        _syncMinisterOffice(ministry, address(0), 0, false);
    }

    /// @inheritdoc ICabinetApp
    function resignMinister(ExecutiveTypes.MinistryKind ministry) external {
        if (ministry == ExecutiveTypes.MinistryKind.Undefined) {
            revert InvalidMinistry(ministry);
        }

        ExecutiveTypes.MinisterRecord memory record = _executiveRegistry.getMinister(ministry);
        if (!record.active || !_isActiveWalletForPerson(msg.sender, record.personId)) {
            revert NotMinister(ministry, msg.sender);
        }

        _dismissalNonce[ministry] += 1;

        _executiveRegistry.clearMinister(ministry);

        emit MinisterResigned(ministry, msg.sender, uint64(block.timestamp));

        // Deactivate the ministry's office (where one is wired): no operations run without a sitting minister.
        _syncMinisterOffice(ministry, address(0), 0, false);
    }

    function _appointmentVoteCount(address candidate) private view returns (uint256 voteCount) {
        if (candidate == address(0)) {
            return 0;
        }

        uint256 cycleId = _currentCongressCycleId();
        uint64 nonce = _appointmentNonce;
        address[] memory members = _congressCandidateRegistry.currentCongressMembers();
        for (uint256 index = 0; index < members.length; ++index) {
            CongressBallot memory ballot = _appointmentBallots[members[index]];
            if (ballot.target == candidate && ballot.congressCycleId == cycleId && ballot.ballotNonce == nonce) {
                voteCount += 1;
            }
        }
    }

    function _removalVoteCount() private view returns (uint256 voteCount) {
        uint256 cycleId = _currentCongressCycleId();
        uint64 nonce = _removalNonce;
        address[] memory members = _congressCandidateRegistry.currentCongressMembers();
        for (uint256 index = 0; index < members.length; ++index) {
            CongressBallot memory ballot = _removalBallots[members[index]];
            if (ballot.congressCycleId == cycleId && ballot.ballotNonce == nonce) {
                voteCount += 1;
            }
        }
    }

    function _dismissalVoteCount(ExecutiveTypes.MinistryKind ministry) private view returns (uint256 voteCount) {
        uint256 cycleId = _currentCongressCycleId();
        uint64 nonce = _dismissalNonce[ministry];
        address[] memory members = _congressCandidateRegistry.currentCongressMembers();
        for (uint256 index = 0; index < members.length; ++index) {
            CongressBallot memory ballot = _dismissalBallots[ministry][members[index]];
            if (ballot.congressCycleId == cycleId && ballot.ballotNonce == nonce) {
                voteCount += 1;
            }
        }
    }

    function _isSittingMinister(address wallet) private view returns (bool serving) {
        bytes32 personId = _identityRegistry.resolveWalletToPersonId(wallet);
        ExecutiveTypes.MinistryKind[4] memory ministries = [
            ExecutiveTypes.MinistryKind.Finance,
            ExecutiveTypes.MinistryKind.ForeignAffairs,
            ExecutiveTypes.MinistryKind.Interior,
            ExecutiveTypes.MinistryKind.Justice
        ];
        for (uint256 index = 0; index < ministries.length; ++index) {
            // Single registry read: isMinisterInTerm is (active && now < termEnd) on the same record.
            ExecutiveTypes.MinisterRecord memory record = _executiveRegistry.getMinister(ministries[index]);
            if (record.active && block.timestamp < record.termEnd && record.personId == personId) {
                return true;
            }
        }

        return false;
    }

    /// @dev Syncs a ministry's operational office with its political minister. A no-op for unwired ministries
    ///      (`officeId == 0`). On appointment the minister becomes the office admin and the office is (re)activated;
    ///      on dismissal or resignation the office is deactivated so no operations run without a sitting minister.
    ///      The `setOfficeActive` calls are guarded on the current active state so they never revert on same-state.
    function _syncMinisterOffice(
        ExecutiveTypes.MinistryKind ministry,
        address minister,
        uint64 authorizationEndsAt,
        bool appointed
    ) private {
        bytes32 officeId = _ministryOfficeId[ministry];
        if (officeId == bytes32(0)) {
            return;
        }

        if (appointed) {
            _officeRegistry.transferOfficeAdminForTerm(
                officeId, minister, _identityRegistry.resolveWalletToPersonId(minister), authorizationEndsAt
            );
            if (!_officeRegistry.getOfficeRecord(officeId).active) {
                _officeRegistry.setOfficeActive(officeId, true);
            }
        } else {
            _officeRegistry.revokeOfficeAdmin(officeId);
            if (_officeRegistry.getOfficeRecord(officeId).active) {
                _officeRegistry.setOfficeActive(officeId, false);
            }
        }
    }

    function _requireActiveCongressMember(address caller) private view {
        if (!_congressCandidateRegistry.isActiveCongressMember(caller)) {
            revert NotCongressMember(caller);
        }
    }

    function _requireSittingPrimeMinister(address caller) private view {
        ExecutiveTypes.PrimeMinisterRecord memory record = _executiveRegistry.getPrimeMinister();
        if (!_isActiveWalletForPerson(caller, record.personId) || !_executiveRegistry.isPrimeMinisterInTerm()) {
            revert NotPrimeMinister(caller);
        }
    }

    function _isActiveWalletForPerson(address wallet, bytes32 personId) private view returns (bool active) {
        return personId != bytes32(0) && _identityRegistry.hasActiveWalletLink(wallet)
            && _identityRegistry.resolveWalletToPersonId(wallet) == personId;
    }

    function _currentCongressCycleId() private view returns (uint256 cycleId) {
        return _congressCandidateRegistry.getCurrentOfficeTerm().cycleId;
    }

    function _occupiedSeatCount() private view returns (uint256 occupiedSeats) {
        return _congressCandidateRegistry.getCurrentOfficeTerm().occupiedSeatCount;
    }

    function _currentCitizenEligibilityPolicy() private view returns (ICitizenEligibilityPolicy policy) {
        return
            ICitizenEligibilityPolicy(
                IConstitutionKernel(_kernel).getModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY)
            );
    }
}
