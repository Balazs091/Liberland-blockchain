// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ICandidateEligibilityPolicy} from "../interfaces/ICandidateEligibilityPolicy.sol";
import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {ICongressElectionApp} from "../interfaces/ICongressElectionApp.sol";
import {ICongressElectionPolicy} from "../interfaces/ICongressElectionPolicy.sol";
import {ICongressRankingStore} from "../interfaces/ICongressRankingStore.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IElectorateRegistry} from "../interfaces/IElectorateRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IVotingPowerPolicy} from "../interfaces/IVotingPowerPolicy.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {ElectionTypes} from "../types/ElectionTypes.sol";

/// @title CongressElectionApp
/// @notice User-facing application for bounded Congress election scheduling, candidacy, signed ballot voting, and vacancies.
contract CongressElectionApp is ICongressElectionApp {
    bytes32 private constant _INCUMBENT_CANDIDACY_TYPEHASH =
        keccak256("LiberlandCongressIncumbentCandidacy(uint256 cycleId,address incumbent)");
    string private constant _INCUMBENT_CANDIDACY_URI = "liberland://congress/incumbent-candidacy";

    IIdentityRegistry private immutable _identityRegistry;
    ICongressCandidateRegistry private immutable _congressCandidateRegistry;
    IConstitutionKernel private immutable _kernel;

    /// @param identityRegistryAddress The identity registry used to resolve candidate person references.
    /// @param congressCandidateRegistryAddress The Congress candidate registry used for durable election state.
    /// @param candidateEligibilityPolicyAddress The candidate eligibility policy used for Congress candidacy checks.
    /// @param congressElectionPolicyAddress The Congress election policy used for cycle bounds and vote weighting.
    constructor(
        address identityRegistryAddress,
        address congressCandidateRegistryAddress,
        address candidateEligibilityPolicyAddress,
        address congressElectionPolicyAddress
    ) {
        if (identityRegistryAddress == address(0) || identityRegistryAddress.code.length == 0) {
            revert InvalidRegistry(identityRegistryAddress);
        }
        if (congressCandidateRegistryAddress == address(0) || congressCandidateRegistryAddress.code.length == 0) {
            revert InvalidRegistry(congressCandidateRegistryAddress);
        }
        if (candidateEligibilityPolicyAddress == address(0) || candidateEligibilityPolicyAddress.code.length == 0) {
            revert InvalidPolicy(candidateEligibilityPolicyAddress);
        }
        if (congressElectionPolicyAddress == address(0) || congressElectionPolicyAddress.code.length == 0) {
            revert InvalidPolicy(congressElectionPolicyAddress);
        }
        address kernelAddress = ICongressCandidateRegistry(congressCandidateRegistryAddress).kernel();
        if (kernelAddress == address(0) || kernelAddress.code.length == 0) {
            revert InvalidRegistry(kernelAddress);
        }

        _validatePolicy(identityRegistryAddress, candidateEligibilityPolicyAddress, congressElectionPolicyAddress);

        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _congressCandidateRegistry = ICongressCandidateRegistry(congressCandidateRegistryAddress);
        _kernel = IConstitutionKernel(kernelAddress);
    }

    /// @inheritdoc ICongressElectionApp
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @inheritdoc ICongressElectionApp
    function congressCandidateRegistry() external view returns (address registryAddress) {
        return address(_congressCandidateRegistry);
    }

    /// @inheritdoc ICongressElectionApp
    function candidateEligibilityPolicy() external view returns (address policyAddress) {
        return _currentElectionPolicy().candidateEligibilityPolicy();
    }

    /// @inheritdoc ICongressElectionApp
    function congressElectionPolicy() external view returns (address policyAddress) {
        return address(_currentElectionPolicy());
    }

    /// @inheritdoc ICongressElectionApp
    function votingPowerPolicy() external view returns (address policyAddress) {
        return _currentElectionPolicy().votingPowerPolicy();
    }

    /// @inheritdoc ICongressElectionApp
    function currentCongressCycleId() external view returns (uint256 cycleId) {
        return _congressCandidateRegistry.getCurrentOfficeTerm().cycleId;
    }

    /// @inheritdoc ICongressElectionApp
    function isCongressMember(address wallet) external view returns (bool active) {
        return _congressCandidateRegistry.isActiveCongressMember(wallet);
    }

    /// @inheritdoc ICongressElectionApp
    function createElectionCycle(uint64 nominationStart, uint64 votingStart, uint64 votingEnd)
        external
        returns (uint256 cycleId)
    {
        uint256 previousCycleId = _congressCandidateRegistry.latestCycleId();
        ICongressElectionPolicy policy = _currentElectionPolicy();
        _validateElectionWindow(previousCycleId, nominationStart, votingStart, votingEnd, policy);

        cycleId = _createElectionCycle(previousCycleId, nominationStart, votingStart, votingEnd, policy);
    }

    /// @inheritdoc ICongressElectionApp
    function createNextElectionCycle() external returns (uint256 cycleId) {
        uint256 previousCycleId = _congressCandidateRegistry.latestCycleId();
        ICongressElectionPolicy policy = _currentElectionPolicy();
        (uint64 nominationStart, uint64 votingStart, uint64 votingEnd) = _nextElectionWindow(previousCycleId, policy);

        cycleId = _createElectionCycle(previousCycleId, nominationStart, votingStart, votingEnd, policy);
    }

    /// @inheritdoc ICongressElectionApp
    function previewNextElectionWindow()
        external
        view
        returns (uint64 nominationStart, uint64 votingStart, uint64 votingEnd)
    {
        return _nextElectionWindow(_congressCandidateRegistry.latestCycleId(), _currentElectionPolicy());
    }

    /// @inheritdoc ICongressElectionApp
    function applyAsCandidate(uint256 cycleId, bytes32 applicationHash, string calldata applicationURI) external {
        ElectionTypes.CongressCycleRecord memory cycleRecord = _getCycleOrRevert(cycleId);
        _requireNominationWindow(cycleId, cycleRecord);
        if (!_cyclePolicy(cycleRecord).isEligibleCandidate(msg.sender)) {
            revert NotEligibleCandidate(msg.sender);
        }

        bytes32 personId = _identityRegistry.resolveWalletToPersonId(msg.sender);
        if (personId == bytes32(0)) {
            revert UnknownCandidateReference(msg.sender);
        }

        _congressCandidateRegistry.registerCandidate(cycleId, msg.sender, personId, applicationHash, applicationURI);
    }

    /// @inheritdoc ICongressElectionApp
    function withdrawCandidacy(uint256 cycleId) external {
        ElectionTypes.CongressCycleRecord memory cycleRecord = _getCycleOrRevert(cycleId);
        _requireNominationWindow(cycleId, cycleRecord);

        bytes32 personId = _identityRegistry.resolveWalletToPersonId(msg.sender);
        if (personId == bytes32(0) || _identityRegistry.activeWalletOf(personId) != msg.sender) {
            revert NotActiveCandidateWallet(msg.sender);
        }
        _congressCandidateRegistry.withdrawCandidate(cycleId, msg.sender);
    }

    /// @inheritdoc ICongressElectionApp
    function castBallot(uint256 cycleId, address[] calldata candidates, int256[] calldata allocations) external {
        ElectionTypes.CongressCycleRecord memory cycleRecord = _getCycleOrRevert(cycleId);
        _requireVotingWindow(cycleId, cycleRecord);
        if (candidates.length == 0 || candidates.length != allocations.length) {
            revert InvalidBallotLength(candidates.length, allocations.length);
        }

        ICongressElectionPolicy policy = _cyclePolicy(cycleRecord);
        uint48 snapshotBlock = cycleRecord.votingPowerSnapshotBlock;
        uint256 weight = policy.votingWeightAt(msg.sender, snapshotBlock);
        if (weight == 0) {
            revert NoVotingPower(msg.sender);
        }

        _congressCandidateRegistry.recordBallot(
            ElectionTypes.CongressBallotInput({
                cycleId: cycleId,
                voterPersonId: _identityRegistry.resolveWalletToPersonId(msg.sender),
                voter: msg.sender,
                ballotWeight: weight,
                maxPositiveCandidates: policy.maxPositiveCandidates(),
                maxNegativeAllocation: policy.maxNegativeAllocationAt(msg.sender, snapshotBlock)
            }),
            candidates,
            allocations
        );
    }

    /// @inheritdoc ICongressElectionApp
    function clearBallot(uint256 cycleId) external {
        ElectionTypes.CongressCycleRecord memory cycleRecord = _getCycleOrRevert(cycleId);
        _requireVotingWindow(cycleId, cycleRecord);

        _congressCandidateRegistry.clearBallot(cycleId, msg.sender);
    }

    /// @inheritdoc ICongressElectionApp
    function finalizeElection(uint256 cycleId) external {
        _finalizeElection(cycleId, 32);
    }

    /// @inheritdoc ICongressElectionApp
    function finalizeElection(uint256 cycleId, uint256 maximumCandidates) external {
        if (maximumCandidates == 0 || maximumCandidates > 32) {
            revert InvalidFinalizationBatchSize(maximumCandidates);
        }
        _finalizeElection(cycleId, maximumCandidates);
    }

    function _finalizeElection(uint256 cycleId, uint256 maximumCandidates) private {
        ElectionTypes.CongressCycleRecord memory cycleRecord = _getCycleOrRevert(cycleId);
        if (block.timestamp < cycleRecord.votingEnd) {
            revert ElectionNotEnded(cycleId, cycleRecord.votingEnd, uint64(block.timestamp));
        }
        ICongressElectionPolicy policy = _cyclePolicy(cycleRecord);

        // At most 32 candidates enter the durable heap per transaction; nomination and scores are closed.
        ICongressRankingStore ranking = ICongressRankingStore(_congressCandidateRegistry.rankingStore());
        ranking.process(cycleId, maximumCandidates);
        ElectionTypes.FinalizationProgress memory progress = ranking.progress(cycleId);
        if (progress.processedCount != progress.candidateCount) return;

        // Stake is not newly locked. A provisional candidate must still qualify before seat activation.
        uint256 selectedCount = progress.selectedCount;
        // Remove from the end so later rejected entries are never shifted repeatedly. The relative rank of every
        // retained entry is unchanged, and each provisional person is still checked exactly once per call.
        uint256 index = selectedCount;
        while (index != 0) {
            --index;
            (, bytes32 personId) = ranking.selectedAt(cycleId, index);
            if (!_eligiblePerson(policy, personId)) {
                ranking.removeSelected(cycleId, index);
                --selectedCount;
            }
        }
        uint256 outcomeSlots = uint256(cycleRecord.seatCount) + cycleRecord.runnerUpCount;
        uint256 considered;
        while (selectedCount < outcomeSlots && considered < maximumCandidates) {
            (address candidate, bytes32 personId) = ranking.peek(cycleId);
            if (candidate == address(0)) break;
            bool eligible = _eligiblePerson(policy, personId);
            ranking.consider(cycleId, eligible);
            if (eligible) ++selectedCount;
            ++considered;
        }
        progress = ranking.progress(cycleId);
        if (selectedCount < outcomeSlots && progress.remainingRanked != 0) return;
        _congressCandidateRegistry.completeRankedCycle(cycleId);

        // New-cycle readiness must not undo this cycle's pinned outcome. Anyone may separately call
        // createNextElectionCycle once the currently governed policy/electorate bundle is ready.
    }

    function _eligiblePerson(ICongressElectionPolicy policy, bytes32 personId) private view returns (bool) {
        address wallet = _identityRegistry.activeWalletOf(personId);
        return wallet != address(0) && policy.isEligibleCandidate(wallet);
    }

    /// @inheritdoc ICongressElectionApp
    function resignSeat() external returns (uint32 seatIndex, address replacementCandidate) {
        if (!_congressCandidateRegistry.isActiveCongressMember(msg.sender)) {
            revert NotActiveCongressMember(msg.sender);
        }

        (seatIndex, replacementCandidate) = _vacateAndFill(msg.sender);
    }

    /// @inheritdoc ICongressElectionApp
    function recallMember(address member) external returns (uint32 seatIndex, address replacementCandidate) {
        if (!_congressCandidateRegistry.isActiveCongressMember(member)) {
            revert NotActiveCongressMember(member);
        }
        // Anyone may remove a sitting member who has lost candidacy eligibility (lost citizenship,
        // dropped below the bond, or entered unstaking welfare). Eligible members cannot be recalled.
        ICongressElectionPolicy termPolicy = _cyclePolicy(
            _congressCandidateRegistry.getCycle(_congressCandidateRegistry.getCurrentOfficeTerm().cycleId)
        );
        if (termPolicy.isEligibleCandidate(member)) {
            revert MemberStillEligible(member);
        }

        (seatIndex, replacementCandidate) = _vacateAndFill(member);
    }

    /// @inheritdoc ICongressElectionApp
    function recallUnrepresentedSeat(uint32 seatIndex)
        external
        returns (uint32 vacatedSeatIndex, address replacementCandidate)
    {
        ElectionTypes.CongressOfficeTerm memory term = _congressCandidateRegistry.getCurrentOfficeTerm();
        ElectionTypes.CongressSeatRecord memory seatRecord = _congressCandidateRegistry.getSeatRecord(seatIndex);
        if (
            term.cycleId == 0 || seatRecord.cycleId != term.cycleId || seatRecord.holderPersonId == bytes32(0)
                || seatRecord.holder == address(0)
        ) {
            revert CongressSeatNotOccupied(seatIndex);
        }

        address activeWallet = _identityRegistry.activeWalletOf(seatRecord.holderPersonId);
        if (activeWallet != address(0)) {
            revert CongressSeatStillRepresented(seatIndex, activeWallet);
        }

        (bool hasReplacement, uint256 runnerUpIndex) = _findNextEligibleRunnerUp();
        return
            _congressCandidateRegistry.vacateAndFillSeatForPerson(
                seatRecord.holderPersonId, hasReplacement, runnerUpIndex
            );
    }

    function _vacateAndFill(address member) private returns (uint32 seatIndex, address replacementCandidate) {
        (bool hasReplacement, uint256 runnerUpIndex) = _findNextEligibleRunnerUp();
        (seatIndex, replacementCandidate) =
            _congressCandidateRegistry.vacateAndFillSeat(member, hasReplacement, runnerUpIndex);
    }

    function _findNextEligibleRunnerUp() private view returns (bool found, uint256 runnerUpIndex) {
        ElectionTypes.CongressOfficeTerm memory term = _congressCandidateRegistry.getCurrentOfficeTerm();
        uint256 cycleId = term.cycleId;
        ICongressElectionPolicy policy = _cyclePolicy(_congressCandidateRegistry.getCycle(cycleId));
        uint256 runnerUpCount = _congressCandidateRegistry.getRunnerUpCount(cycleId);

        for (uint256 index = term.nextRunnerUpIndex; index < runnerUpCount; ++index) {
            address candidate = _congressCandidateRegistry.getRunnerUpAt(cycleId, index);
            // Succession uses identity and score facts only; do not load the candidate's metadata URI.
            (int256 voteTotal,, bytes32 personId) =
                _congressCandidateRegistry.getCandidateRankingData(cycleId, candidate);
            address currentCandidate = _identityRegistry.activeWalletOf(personId);
            if (currentCandidate == address(0) || _congressCandidateRegistry.isActiveCongressMember(currentCandidate)) {
                continue;
            }
            if (policy.isEligibleCandidate(currentCandidate) && voteTotal >= 0) {
                return (true, index);
            }
        }

        return (false, 0);
    }

    function _createElectionCycle(
        uint256 previousCycleId,
        uint64 nominationStart,
        uint64 votingStart,
        uint64 votingEnd,
        ICongressElectionPolicy policy
    ) private returns (uint256 cycleId) {
        if (previousCycleId != 0) {
            ElectionTypes.CongressCycleRecord memory previousCycle =
                _congressCandidateRegistry.getCycle(previousCycleId);
            if (previousCycle.status != ElectionTypes.ElectionStatus.Finalized) {
                revert ActiveCycleExists(previousCycleId);
            }
        }

        cycleId = previousCycleId + 1;
        uint48 votingPowerSnapshotBlock = _lastCompletedBlock();
        IElectorateRegistry electorateRegistry =
            IElectorateRegistry(_kernel.getModule(KernelModuleIds.ELECTORATE_REGISTRY));
        address votingPowerPolicyAddress = policy.votingPowerPolicy();
        address policyElectorateRegistry = IVotingPowerPolicy(votingPowerPolicyAddress).electorateRegistry();
        if (policyElectorateRegistry != address(electorateRegistry)) {
            revert VotingPowerElectorateMismatch(
                votingPowerPolicyAddress, policyElectorateRegistry, address(electorateRegistry)
            );
        }
        electorateRegistry.snapshotAtCurrentEpoch(votingPowerSnapshotBlock);
        _congressCandidateRegistry.createCycle(
            cycleId,
            ElectionTypes.CongressCycleInput({
                nominationStart: nominationStart,
                votingStart: votingStart,
                votingEnd: votingEnd,
                votingPowerSnapshotBlock: votingPowerSnapshotBlock,
                seatCount: policy.seatCount(),
                runnerUpCount: policy.runnerUpCount(),
                maxCandidateCount: policy.maxCandidateCount(),
                policy: address(policy),
                policyReference: _policyReference(policy)
            })
        );
        _autoRegisterIncumbents(cycleId);
    }

    function _autoRegisterIncumbents(uint256 cycleId) private {
        address[] memory incumbents = _congressCandidateRegistry.currentCongressMembers();
        for (uint256 index = 0; index < incumbents.length; ++index) {
            address incumbent = incumbents[index];
            bytes32 personId = _identityRegistry.resolveWalletToPersonId(incumbent);
            if (personId == bytes32(0)) {
                revert UnknownCandidateReference(incumbent);
            }

            _congressCandidateRegistry.registerCandidate(
                cycleId,
                incumbent,
                personId,
                keccak256(abi.encode(_INCUMBENT_CANDIDACY_TYPEHASH, cycleId, incumbent)),
                _INCUMBENT_CANDIDACY_URI
            );
        }
    }

    function _nextElectionWindow(uint256 previousCycleId, ICongressElectionPolicy policy)
        private
        view
        returns (uint64 nominationStart, uint64 votingStart, uint64 votingEnd)
    {
        if (previousCycleId == 0) {
            nominationStart = uint64(block.timestamp);
        } else {
            ElectionTypes.CongressCycleRecord memory previousCycle =
                _congressCandidateRegistry.getCycle(previousCycleId);
            uint64 currentTimestamp = uint64(block.timestamp);
            // Preserve the imported cycle's UTC time-of-day forever. On-time finalization starts at the prior end;
            // late finalization moves to the next daily occurrence of that same UTC boundary. This avoids a
            // past-dated nomination window while ensuring every new cycle remains a full `cycleDuration()` and ends
            // at a predictable civil hour instead of inheriting an arbitrary transaction timestamp.
            nominationStart = previousCycle.votingEnd >= currentTimestamp
                ? previousCycle.votingEnd
                : _nextDailyBoundary(currentTimestamp, previousCycle.votingEnd);
        }

        votingStart = nominationStart + policy.minimumNominationDuration();
        votingEnd = nominationStart + policy.cycleDuration();
    }

    function _nextDailyBoundary(uint64 currentTimestamp, uint64 anchorTimestamp)
        private
        pure
        returns (uint64 boundary)
    {
        uint64 dayLength = 1 days;
        uint64 secondsIntoDay = anchorTimestamp % dayLength;
        // The modulo computes a deterministic UTC day bucket; it is never used as randomness. Slither reports
        // this timestamp modulo as weak-prng, but no outcome or selection depends on unpredictability here.
        boundary = currentTimestamp - currentTimestamp % dayLength + secondsIntoDay;
        if (boundary < currentTimestamp) {
            boundary += dayLength;
        }
    }

    function _validateElectionWindow(
        uint256 previousCycleId,
        uint64 nominationStart,
        uint64 votingStart,
        uint64 votingEnd,
        ICongressElectionPolicy policy
    ) private view {
        if (previousCycleId == 0) {
            _validateInitialElectionWindow(nominationStart, votingStart, votingEnd, policy);
            return;
        }

        ElectionTypes.CongressCycleRecord memory previousCycle = _congressCandidateRegistry.getCycle(previousCycleId);
        if (previousCycle.status != ElectionTypes.ElectionStatus.Finalized) {
            revert ActiveCycleExists(previousCycleId);
        }

        (uint64 expectedNominationStart, uint64 expectedVotingStart, uint64 expectedVotingEnd) =
            _nextElectionWindow(previousCycleId, policy);
        if (
            nominationStart != expectedNominationStart || votingStart != expectedVotingStart
                || votingEnd != expectedVotingEnd
        ) {
            revert InvalidRecurringElectionWindow(
                nominationStart, votingStart, votingEnd, expectedNominationStart, expectedVotingStart, expectedVotingEnd
            );
        }
    }

    function _validateInitialElectionWindow(
        uint64 nominationStart,
        uint64 votingStart,
        uint64 votingEnd,
        ICongressElectionPolicy policy
    ) private view {
        uint64 minimumNominationDuration = policy.minimumNominationDuration();
        uint64 minimumVotingDuration = policy.minimumVotingDuration();
        uint64 currentTime = uint64(block.timestamp);
        if (
            nominationStart < currentTime || nominationStart >= votingStart || votingStart >= votingEnd
                || votingStart - nominationStart < minimumNominationDuration
                || votingEnd - votingStart < minimumVotingDuration
        ) {
            revert InvalidElectionWindow(nominationStart, votingStart, votingEnd);
        }

        uint64 latestVotingStart = uint64(block.timestamp + policy.maxScheduleLeadTime());
        if (votingStart > latestVotingStart) {
            revert InvalidScheduleLead(votingStart, latestVotingStart);
        }
    }

    function _getCycleOrRevert(uint256 cycleId)
        private
        view
        returns (ElectionTypes.CongressCycleRecord memory cycleRecord)
    {
        cycleRecord = _congressCandidateRegistry.getCycle(cycleId);
        if (cycleRecord.cycleId == 0) {
            revert ICongressCandidateRegistry.ElectionCycleNotFound(cycleId);
        }
        if (cycleRecord.status == ElectionTypes.ElectionStatus.Finalized) {
            revert ICongressCandidateRegistry.ElectionCycleAlreadyFinalized(cycleId);
        }
    }

    function _policyReference(ICongressElectionPolicy policy) private view returns (bytes32 policyRef) {
        return keccak256(
            abi.encode(
                address(policy),
                policy.seatCount(),
                policy.runnerUpCount(),
                policy.maxCandidateCount(),
                policy.candidateBondRequirement(),
                policy.maxPositiveCandidates(),
                policy.minimumNominationDuration(),
                policy.minimumVotingDuration(),
                policy.maxScheduleLeadTime(),
                policy.cycleDuration()
            )
        );
    }

    function _currentElectionPolicy() private view returns (ICongressElectionPolicy policy) {
        return ICongressElectionPolicy(_kernel.getModule(KernelModuleIds.CONGRESS_ELECTION_POLICY));
    }

    function _cyclePolicy(ElectionTypes.CongressCycleRecord memory cycleRecord)
        private
        pure
        returns (ICongressElectionPolicy policy)
    {
        return ICongressElectionPolicy(cycleRecord.policy);
    }

    /// @dev Using the last completed block makes the snapshot immune to later transactions in the creation block.
    function _lastCompletedBlock() private view returns (uint48 snapshotBlock) {
        return block.number == 0 ? 0 : SafeCast.toUint48(block.number - 1);
    }

    function _validatePolicy(
        address identityRegistryAddress,
        address candidateEligibilityPolicyAddress,
        address congressElectionPolicyAddress
    ) private view {
        if (
            ICandidateEligibilityPolicy(candidateEligibilityPolicyAddress).identityRegistry() != identityRegistryAddress
        ) {
            revert InvalidRegistry(identityRegistryAddress);
        }
        if (
            ICongressElectionPolicy(congressElectionPolicyAddress).candidateEligibilityPolicy()
                != candidateEligibilityPolicyAddress
        ) {
            revert InvalidPolicy(congressElectionPolicyAddress);
        }

        address votingPowerPolicyAddress = ICongressElectionPolicy(congressElectionPolicyAddress).votingPowerPolicy();
        if (IVotingPowerPolicy(votingPowerPolicyAddress).identityRegistry() != identityRegistryAddress) {
            revert InvalidPolicy(votingPowerPolicyAddress);
        }
    }

    function _requireNominationWindow(uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord)
        private
        view
    {
        uint64 currentTime = uint64(block.timestamp);
        if (currentTime < cycleRecord.nominationStart || currentTime >= cycleRecord.votingStart) {
            revert CandidateRegistrationClosed(
                cycleId, cycleRecord.nominationStart, cycleRecord.votingStart, currentTime
            );
        }
    }

    function _requireVotingWindow(uint256 cycleId, ElectionTypes.CongressCycleRecord memory cycleRecord) private view {
        uint64 currentTime = uint64(block.timestamp);
        if (currentTime < cycleRecord.votingStart || currentTime >= cycleRecord.votingEnd) {
            revert VotingClosed(cycleId, cycleRecord.votingStart, cycleRecord.votingEnd, currentTime);
        }
    }
}
