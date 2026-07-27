// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ICandidateEligibilityPolicy} from "../interfaces/ICandidateEligibilityPolicy.sol";
import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {ICongressElectionApp} from "../interfaces/ICongressElectionApp.sol";
import {ICongressElectionPolicy} from "../interfaces/ICongressElectionPolicy.sol";
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

    struct RankingEntry {
        address candidate;
        int256 voteTotal;
        uint64 appliedAt;
        bool eligible;
    }

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
        ElectionTypes.CongressCycleRecord memory cycleRecord = _getCycleOrRevert(cycleId);
        if (block.timestamp < cycleRecord.votingEnd) {
            revert ElectionNotEnded(cycleId, cycleRecord.votingEnd, uint64(block.timestamp));
        }
        ICongressElectionPolicy policy = _cyclePolicy(cycleRecord);

        {
            uint256 candidateCount = _congressCandidateRegistry.getCycleCandidateCount(cycleId);
            RankingEntry[] memory ranking = new RankingEntry[](candidateCount);
            uint256 qualifiedCandidateCount = 0;

            for (uint256 index = 0; index < candidateCount; ++index) {
                address candidate = _congressCandidateRegistry.getCycleCandidateAt(cycleId, index);
                ElectionTypes.CongressCandidateRecord memory candidateRecord =
                    _congressCandidateRegistry.getCandidate(cycleId, candidate);
                address currentCandidate = _identityRegistry.activeWalletOf(candidateRecord.personId);
                bool eligibleCandidate = currentCandidate != address(0) && policy.isEligibleCandidate(currentCandidate);

                ranking[index] = RankingEntry({
                    candidate: candidate,
                    voteTotal: candidateRecord.voteTotal,
                    appliedAt: candidateRecord.appliedAt,
                    eligible: eligibleCandidate
                });
                // A seat requires eligibility AND non-negative net support: a candidate net-REJECTED
                // (voteTotal < 0) by the electorate is not seated even when eligible seats remain.
                // Zero is still qualified so uncontested incumbents/genesis members keep continuity.
                if (eligibleCandidate && candidateRecord.voteTotal >= 0) {
                    qualifiedCandidateCount += 1;
                }
            }

            _sortRanking(ranking);
            address[] memory rankedCandidates = new address[](candidateCount);
            int256[] memory rankedVoteTotals = new int256[](candidateCount);
            for (uint256 index = 0; index < candidateCount; ++index) {
                rankedCandidates[index] = ranking[index].candidate;
                rankedVoteTotals[index] = ranking[index].voteTotal;
            }

            uint32 electedCount = _minConfiguredCount(cycleRecord.seatCount, qualifiedCandidateCount);
            uint256 remainingQualifiedCandidates =
                qualifiedCandidateCount > electedCount ? qualifiedCandidateCount - electedCount : 0;
            uint32 runnerUpCount = _minConfiguredCount(cycleRecord.runnerUpCount, remainingQualifiedCandidates);

            _congressCandidateRegistry.finalizeCycle(
                cycleId,
                ElectionTypes.CongressFinalizationInput({
                    rankedCandidates: rankedCandidates,
                    rankedVoteTotals: rankedVoteTotals,
                    electedCount: electedCount,
                    runnerUpCount: runnerUpCount
                })
            );
        }

        if (_congressCandidateRegistry.latestCycleId() == cycleId) {
            ICongressElectionPolicy nextPolicy = _currentElectionPolicy();
            (uint64 nominationStart, uint64 votingStart, uint64 votingEnd) = _nextElectionWindow(cycleId, nextPolicy);
            _createElectionCycle(cycleId, nominationStart, votingStart, votingEnd, nextPolicy);
        }
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
            ElectionTypes.CongressCandidateRecord memory candidateRecord =
                _congressCandidateRegistry.getCandidate(cycleId, candidate);
            address currentCandidate = _identityRegistry.activeWalletOf(candidateRecord.personId);
            if (currentCandidate == address(0) || _congressCandidateRegistry.isActiveCongressMember(currentCandidate)) {
                continue;
            }
            if (policy.isEligibleCandidate(currentCandidate) && candidateRecord.voteTotal >= 0) {
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

    function _sortRanking(RankingEntry[] memory ranking) private pure {
        for (uint256 index = 1; index < ranking.length; ++index) {
            RankingEntry memory entry = ranking[index];
            uint256 insertionIndex = index;

            while (insertionIndex > 0 && _ranksAhead(entry, ranking[insertionIndex - 1])) {
                ranking[insertionIndex] = ranking[insertionIndex - 1];

                unchecked {
                    --insertionIndex;
                }
            }

            ranking[insertionIndex] = entry;
        }
    }

    function _ranksAhead(RankingEntry memory left, RankingEntry memory right) private pure returns (bool ahead) {
        if (left.eligible != right.eligible) {
            return left.eligible;
        }
        if (left.voteTotal != right.voteTotal) {
            return left.voteTotal > right.voteTotal;
        }
        if (left.appliedAt != right.appliedAt) {
            return left.appliedAt < right.appliedAt;
        }

        return uint160(left.candidate) < uint160(right.candidate);
    }

    function _minConfiguredCount(uint32 configuredCount, uint256 candidateCount) private pure returns (uint32 count) {
        if (candidateCount < configuredCount) {
            // forge-lint: disable-next-line(unsafe-typecast)
            return uint32(candidateCount);
        }

        return configuredCount;
    }
}
