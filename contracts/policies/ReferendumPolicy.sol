// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ICongressElectionApp} from "../interfaces/ICongressElectionApp.sol";
import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IReferendumPolicy} from "../interfaces/IReferendumPolicy.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IVotingPowerPolicy} from "../interfaces/IVotingPowerPolicy.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {ReferendumTypes} from "../types/ReferendumTypes.sol";

/// @title ReferendumPolicy
/// @notice Evaluates referendum proposal eligibility, quorum, and pass conditions for Milestone 3.
contract ReferendumPolicy is IReferendumPolicy {
    error InvalidAuthority(address authority);
    error InvalidConstitutionalStakeThresholdBps(uint16 thresholdBps);
    error InvalidMinimumVotingDuration(uint64 minimumVotingDuration);
    error InvalidPolicy(address policyAddress);
    error InvalidQuorum(uint256 quorum);
    error UnsupportedProposalOrigin(ReferendumTypes.ProposalOrigin proposalOrigin);
    error UnsupportedReferendumClass(ReferendumTypes.ReferendumClass referendumClass);

    ICitizenEligibilityPolicy private immutable _citizenEligibilityPolicy;
    IVotingPowerPolicy private immutable _votingPowerPolicy;

    address private immutable _congressProposalAuthority;
    uint64 private immutable _minimumVotingDuration;
    uint256 private immutable _citizenProposalFee;
    uint256 private immutable _congressProposalFee;
    uint256 private immutable _citizenQuorum;
    uint256 private immutable _congressQuorum;
    uint256 private immutable _citizenProposalBondRequirement;
    uint256 private immutable _constitutionalForVoterQuorum;
    uint16 private immutable _constitutionalForStakeThresholdBps;

    /// @param citizenEligibilityPolicyAddress The citizen eligibility policy address.
    /// @param votingPowerPolicyAddress The voting power policy address.
    /// @param congressProposalAuthority_ The Congress app used to validate real Congress proposal authority.
    /// @param minimumVotingDuration_ The minimum permitted referendum voting duration.
    /// @param citizenProposalFee_ The fee configured for citizen-origin proposals.
    /// @param congressProposalFee_ The fee configured for Congress-origin proposals.
    /// @param citizenQuorum_ The minimum turnout required for citizen-origin referenda.
    /// @param congressQuorum_ The minimum turnout required for Congress-origin referenda.
    /// @param citizenProposalBondRequirement_ The minimum active stake required to open a citizen referendum.
    /// @param constitutionalForVoterQuorum_ The minimum supporting-citizen headcount for constitutional amendments.
    /// @param constitutionalForStakeThresholdBps_ The minimum supporting stake threshold in basis points.
    constructor(
        address citizenEligibilityPolicyAddress,
        address votingPowerPolicyAddress,
        address congressProposalAuthority_,
        uint64 minimumVotingDuration_,
        uint256 citizenProposalFee_,
        uint256 congressProposalFee_,
        uint256 citizenQuorum_,
        uint256 congressQuorum_,
        uint256 citizenProposalBondRequirement_,
        uint256 constitutionalForVoterQuorum_,
        uint16 constitutionalForStakeThresholdBps_
    ) {
        if (citizenEligibilityPolicyAddress == address(0) || citizenEligibilityPolicyAddress.code.length == 0) {
            revert InvalidPolicy(citizenEligibilityPolicyAddress);
        }
        if (votingPowerPolicyAddress == address(0) || votingPowerPolicyAddress.code.length == 0) {
            revert InvalidPolicy(votingPowerPolicyAddress);
        }
        if (congressProposalAuthority_ == address(0) || congressProposalAuthority_.code.length == 0) {
            revert InvalidAuthority(congressProposalAuthority_);
        }
        if (minimumVotingDuration_ == 0) {
            revert InvalidMinimumVotingDuration(minimumVotingDuration_);
        }
        if (citizenQuorum_ == 0 || congressQuorum_ == 0) {
            revert InvalidQuorum(citizenQuorum_ == 0 ? citizenQuorum_ : congressQuorum_);
        }
        if (constitutionalForStakeThresholdBps_ == 0 || constitutionalForStakeThresholdBps_ > 10_000) {
            revert InvalidConstitutionalStakeThresholdBps(constitutionalForStakeThresholdBps_);
        }

        _citizenEligibilityPolicy = ICitizenEligibilityPolicy(citizenEligibilityPolicyAddress);
        _votingPowerPolicy = IVotingPowerPolicy(votingPowerPolicyAddress);
        _congressProposalAuthority = congressProposalAuthority_;
        _minimumVotingDuration = minimumVotingDuration_;
        _citizenProposalFee = citizenProposalFee_;
        _congressProposalFee = congressProposalFee_;
        _citizenQuorum = citizenQuorum_;
        _congressQuorum = congressQuorum_;
        _citizenProposalBondRequirement = citizenProposalBondRequirement_;
        _constitutionalForVoterQuorum = constitutionalForVoterQuorum_;
        _constitutionalForStakeThresholdBps = constitutionalForStakeThresholdBps_;
    }

    /// @inheritdoc IReferendumPolicy
    function citizenEligibilityPolicy() external view returns (address policyAddress) {
        return address(_citizenEligibilityPolicy);
    }

    /// @inheritdoc IReferendumPolicy
    function votingPowerPolicy() external view returns (address policyAddress) {
        return address(_votingPowerPolicy);
    }

    /// @inheritdoc IReferendumPolicy
    function congressProposalAuthority() external view returns (address authority) {
        return _congressProposalAuthority;
    }

    /// @inheritdoc IReferendumPolicy
    function citizenProposalBondRequirement() external view returns (uint256 amount) {
        return _citizenProposalBondRequirement;
    }

    /// @inheritdoc IReferendumPolicy
    function minimumVotingDuration() external view returns (uint64 duration) {
        return _minimumVotingDuration;
    }

    /// @inheritdoc IReferendumPolicy
    function proposalFee(ReferendumTypes.ProposalOrigin proposalOrigin) external view returns (uint256 feeAmount) {
        if (proposalOrigin == ReferendumTypes.ProposalOrigin.Citizen) {
            return _citizenProposalFee;
        }
        if (proposalOrigin == ReferendumTypes.ProposalOrigin.Congress) {
            return _congressProposalFee;
        }

        return 0;
    }

    /// @inheritdoc IReferendumPolicy
    function canCreateReferendum(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        address proposer
    ) external view returns (bool allowed) {
        if (referendumClass == ReferendumTypes.ReferendumClass.Legislation) {
            if (proposalOrigin == ReferendumTypes.ProposalOrigin.Citizen) {
                return _isBondedCitizenProposer(proposer);
            }
            if (proposalOrigin == ReferendumTypes.ProposalOrigin.Congress) {
                return ICongressElectionApp(_congressProposalAuthority).isCongressMember(proposer);
            }

            return false;
        }

        if (referendumClass == ReferendumTypes.ReferendumClass.CongressElectionPolicy) {
            if (proposalOrigin == ReferendumTypes.ProposalOrigin.Citizen) {
                return _isBondedCitizenProposer(proposer);
            }
            if (proposalOrigin == ReferendumTypes.ProposalOrigin.Congress) {
                return ICongressElectionApp(_congressProposalAuthority).isCongressMember(proposer);
            }

            return false;
        }

        if (referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment) {
            return proposalOrigin == ReferendumTypes.ProposalOrigin.Congress
                && ICongressElectionApp(_congressProposalAuthority).isCongressMember(proposer);
        }

        return false;
    }

    /// @inheritdoc IReferendumPolicy
    function evaluateOutcome(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 forVoterCount,
        uint256 againstVoterCount
    ) external view returns (ReferendumTypes.PolicyOutcome memory outcome) {
        uint256 turnout = forVotes + againstVotes;

        if (
            referendumClass == ReferendumTypes.ReferendumClass.Legislation
                || referendumClass == ReferendumTypes.ReferendumClass.CongressElectionPolicy
        ) {
            uint256 quorumRequired = _quorumRequired(proposalOrigin);
            bool legislationQuorumMet = turnout >= quorumRequired;

            return ReferendumTypes.PolicyOutcome({
                turnout: turnout,
                quorumRequired: quorumRequired,
                headcountQuorumRequired: 0,
                electorateVotingPower: 0,
                quorumMet: legislationQuorumMet,
                passed: legislationQuorumMet && forVotes > againstVotes
            });
        }

        if (referendumClass != ReferendumTypes.ReferendumClass.ConstitutionalAmendment) {
            revert UnsupportedReferendumClass(referendumClass);
        }

        (, uint256 electorateVotingPower) = _eligibleCitizenSnapshot();
        uint256 weightedQuorum = (electorateVotingPower * uint256(_constitutionalForStakeThresholdBps)) / 10_000;
        bool quorumMet = forVoterCount >= _constitutionalForVoterQuorum && forVotes >= weightedQuorum
            && forVoterCount > againstVoterCount;

        return ReferendumTypes.PolicyOutcome({
            turnout: turnout,
            quorumRequired: weightedQuorum,
            headcountQuorumRequired: _constitutionalForVoterQuorum,
            electorateVotingPower: electorateVotingPower,
            quorumMet: quorumMet,
            passed: quorumMet && forVotes > againstVotes
        });
    }

    function _quorumRequired(ReferendumTypes.ProposalOrigin proposalOrigin) private view returns (uint256 quorum) {
        if (proposalOrigin == ReferendumTypes.ProposalOrigin.Citizen) {
            return _citizenQuorum;
        }
        if (proposalOrigin == ReferendumTypes.ProposalOrigin.Congress) {
            return _congressQuorum;
        }

        revert UnsupportedProposalOrigin(proposalOrigin);
    }

    function _isBondedCitizenProposer(address proposer) private view returns (bool bonded) {
        if (!_citizenEligibilityPolicy.isCitizenInGoodStanding(proposer)) {
            return false;
        }

        bytes32 personId =
            IIdentityRegistry(_citizenEligibilityPolicy.identityRegistry()).resolveWalletToPersonId(proposer);
        if (personId == bytes32(0)) {
            return false;
        }

        return IStakeRegistry(_citizenEligibilityPolicy.stakeRegistry()).activeStakeOf(personId)
            >= _citizenProposalBondRequirement;
    }

    function _eligibleCitizenSnapshot() private view returns (uint256 citizenCount, uint256 electorateVotingPower) {
        IIdentityRegistry identityRegistry = IIdentityRegistry(_citizenEligibilityPolicy.identityRegistry());
        IStakeRegistry stakeRegistry = IStakeRegistry(_citizenEligibilityPolicy.stakeRegistry());
        uint256 identityCount = identityRegistry.totalIdentityCount();

        for (uint256 index = 0; index < identityCount; ++index) {
            bytes32 personId = identityRegistry.identityIdAt(index);
            if (!_isEligibleCitizenPerson(identityRegistry, stakeRegistry, personId)) {
                continue;
            }

            citizenCount += 1;
            electorateVotingPower += stakeRegistry.activeStakeOf(personId);
        }
    }

    function _isEligibleCitizenPerson(
        IIdentityRegistry identityRegistry,
        IStakeRegistry stakeRegistry,
        bytes32 personId
    ) private view returns (bool eligible) {
        IdentityTypes.IdentityRecord memory record = identityRegistry.getIdentityRecord(personId);
        if (record.personId == bytes32(0)) {
            return false;
        }
        if (identityRegistry.activeWalletCountOf(personId) == 0) {
            return false;
        }
        if (record.verificationStatus != IdentityTypes.VerificationStatus.Verified) {
            return false;
        }
        if (record.citizenshipStatus != IdentityTypes.CitizenshipStatus.Citizen) {
            return false;
        }
        if (record.ageClass != IdentityTypes.AgeClass.Adult || record.finalSuspension) {
            return false;
        }
        if (stakeRegistry.activeStakeOf(personId) < _citizenEligibilityPolicy.minimumCitizenStake()) {
            return false;
        }

        return !stakeRegistry.hasActiveUnstakeCooldown(personId);
    }
}
