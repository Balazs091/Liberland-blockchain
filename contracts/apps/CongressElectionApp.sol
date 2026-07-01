// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ICandidateEligibilityPolicy} from "../interfaces/ICandidateEligibilityPolicy.sol";
import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {ICongressElectionApp} from "../interfaces/ICongressElectionApp.sol";
import {ICongressElectionPolicy} from "../interfaces/ICongressElectionPolicy.sol";
import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IVotingPowerPolicy} from "../interfaces/IVotingPowerPolicy.sol";
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
        if (!_currentElectionPolicy().isEligibleCandidate(msg.sender)) {
            revert NotEligibleCandidate(msg.sender);
        }

        ElectionTypes.CongressCycleRecord memory cycleRecord = _getCycleOrRevert(cycleId);
        _requireNominationWindow(cycleId, cycleRecord);

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

        _congressCandidateRegistry.withdrawCandidate(cycleId, msg.sender);
    }

    /// @inheritdoc ICongressElectionApp
    function castBallot(uint256 cycleId, address[] calldata candidates, int256[] calldata allocations) external {
        ElectionTypes.CongressCycleRecord memory cycleRecord = _getCycleOrRevert(cycleId);
        _requireVotingWindow(cycleId, cycleRecord);
        if (candidates.length == 0 || candidates.length != allocations.length) {
            revert InvalidBallotLength(candidates.length, allocations.length);
        }

        ICongressElectionPolicy policy = _currentElectionPolicy();
        uint256 weight = policy.votingWeight(msg.sender);
        if (weight == 0) {
            revert NoVotingPower(msg.sender);
        }

        _congressCandidateRegistry.recordBallot(
            cycleId,
            msg.sender,
            candidates,
            allocations,
            weight,
            policy.maxPositiveCandidates(),
            policy.maxNegativeAllocation(msg.sender)
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
        ICongressElectionPolicy policy = _currentElectionPolicy();

        {
            uint256 candidateCount = _congressCandidateRegistry.getCycleCandidateCount(cycleId);
            RankingEntry[] memory ranking = new RankingEntry[](candidateCount);
            uint256 qualifiedCandidateCount = 0;

            for (uint256 index = 0; index < candidateCount; ++index) {
                address candidate = _congressCandidateRegistry.getCycleCandidateAt(cycleId, index);
                ElectionTypes.CongressCandidateRecord memory candidateRecord =
                    _congressCandidateRegistry.getCandidate(cycleId, candidate);
                bool eligibleCandidate = policy.isEligibleCandidate(candidate);

                ranking[index] = RankingEntry({
                    candidate: candidate,
                    voteTotal: candidateRecord.voteTotal,
                    appliedAt: candidateRecord.appliedAt,
                    eligible: eligibleCandidate
                });
                // A seat requires eligibility AND non-negative net support: a candidate net-REJECTED
                // (voteTotal < 0) by the electorate is not seated even when eligible seats remain (M10).
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
            (uint64 nominationStart, uint64 votingStart, uint64 votingEnd) = _nextElectionWindow(cycleId, policy);
            _createElectionCycle(cycleId, nominationStart, votingStart, votingEnd, policy);
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
        // dropped below the bond, or entered unstaking welfare). Eligible members cannot be recalled (M9).
        if (_currentElectionPolicy().isEligibleCandidate(member)) {
            revert MemberStillEligible(member);
        }

        (seatIndex, replacementCandidate) = _vacateAndFill(member);
    }

    /// @inheritdoc ICongressElectionApp
    function purgeIneligibleStandingBallots(uint256 cycleId, address[] calldata voters) external {
        // Permissionless cleanup: drop the persisted standing ballot of any listed voter who no longer has
        // voting power (welfare/ineligible/insufficient stake), so their frozen weight stops counting (M2).
        ICongressElectionPolicy policy = _currentElectionPolicy();
        for (uint256 index = 0; index < voters.length; ++index) {
            address voter = voters[index];
            if (policy.votingWeight(voter) == 0) {
                _congressCandidateRegistry.dropStandingBallot(cycleId, voter);
            }
        }
    }

    function _vacateAndFill(address member) private returns (uint32 seatIndex, address replacementCandidate) {
        (bool hasReplacement, uint256 runnerUpIndex) = _findNextEligibleRunnerUp();
        (seatIndex, replacementCandidate) =
            _congressCandidateRegistry.vacateAndFillSeat(member, hasReplacement, runnerUpIndex);
    }

    function _findNextEligibleRunnerUp() private view returns (bool found, uint256 runnerUpIndex) {
        ElectionTypes.CongressOfficeTerm memory term = _congressCandidateRegistry.getCurrentOfficeTerm();
        uint256 cycleId = term.cycleId;
        ICongressElectionPolicy policy = _currentElectionPolicy();
        uint256 runnerUpCount = _congressCandidateRegistry.getRunnerUpCount(cycleId);

        for (uint256 index = term.nextRunnerUpIndex; index < runnerUpCount; ++index) {
            address candidate = _congressCandidateRegistry.getRunnerUpAt(cycleId, index);
            if (_congressCandidateRegistry.isActiveCongressMember(candidate)) {
                continue;
            }
            if (
                policy.isEligibleCandidate(candidate)
                    && _congressCandidateRegistry.getCandidate(cycleId, candidate).voteTotal >= 0
            ) {
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
        _congressCandidateRegistry.createCycle(
            cycleId,
            ElectionTypes.CongressCycleInput({
                nominationStart: nominationStart,
                votingStart: votingStart,
                votingEnd: votingEnd,
                seatCount: policy.seatCount(),
                runnerUpCount: policy.runnerUpCount(),
                maxCandidateCount: policy.maxCandidateCount(),
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
            nominationStart = previousCycle.votingEnd;
        }

        votingStart = nominationStart + policy.minimumNominationDuration();
        votingEnd = nominationStart + policy.cycleDuration();
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
