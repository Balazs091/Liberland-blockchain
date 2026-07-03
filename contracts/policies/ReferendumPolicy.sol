// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ICongressElectionApp} from "../interfaces/ICongressElectionApp.sol";
import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IReferendumPolicy} from "../interfaces/IReferendumPolicy.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IVotingPowerPolicy} from "../interfaces/IVotingPowerPolicy.sol";
import {ReferendumTypes} from "../types/ReferendumTypes.sol";

/// @title ReferendumPolicy
/// @notice Evaluates referendum proposal eligibility, quorum, and pass conditions for Milestone 3.
contract ReferendumPolicy is IReferendumPolicy {
    error InvalidAuthority(address authority);
    error InvalidConstitutionalStakeThresholdBps(uint16 thresholdBps);
    error InvalidPolicy(address policyAddress);
    error InvalidProposalFeeAsset(address assetAddress);
    error InvalidQuorum(uint256 quorum);
    error UnsupportedProposalOrigin(ReferendumTypes.ProposalOrigin proposalOrigin);
    error UnsupportedReferendumClass(ReferendumTypes.ReferendumClass referendumClass);

    ICitizenEligibilityPolicy private immutable _citizenEligibilityPolicy;
    IVotingPowerPolicy private immutable _votingPowerPolicy;

    uint16 internal constant CONSTITUTIONAL_HEADCOUNT_THRESHOLD_BPS = 5_000;
    uint64 internal constant MINIMUM_VOTING_DURATION = 7 days;
    uint64 internal constant EMERGENCY_VOTING_DURATION = 3 days;
    uint64 internal constant STANDARD_ADOPTION_DELAY = 7 days;
    uint64 internal constant MAXIMUM_ADOPTION_DELAY = 7 days;

    address private immutable _congressProposalAuthority;
    address private immutable _proposalFeeAsset;
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
    /// @param proposalFeeAsset_ The ERC20 token proposal fees are denominated in (LLM by convention).
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
        address proposalFeeAsset_,
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
        if (proposalFeeAsset_ == address(0) || proposalFeeAsset_.code.length == 0) {
            revert InvalidProposalFeeAsset(proposalFeeAsset_);
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
        _proposalFeeAsset = proposalFeeAsset_;
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
    function minimumVotingDuration() external pure returns (uint64 duration) {
        return MINIMUM_VOTING_DURATION;
    }

    /// @inheritdoc IReferendumPolicy
    function emergencyVotingDuration() external pure returns (uint64 duration) {
        return EMERGENCY_VOTING_DURATION;
    }

    /// @inheritdoc IReferendumPolicy
    function standardAdoptionDelay() external pure returns (uint64 duration) {
        return STANDARD_ADOPTION_DELAY;
    }

    /// @inheritdoc IReferendumPolicy
    function maximumAdoptionDelay() external pure returns (uint64 duration) {
        return MAXIMUM_ADOPTION_DELAY;
    }

    /// @inheritdoc IReferendumPolicy
    function proposalFeeAsset() external view returns (address assetAddress) {
        return _proposalFeeAsset;
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
        // Legislation, Congress-election-policy, and module-governance referenda accept either a bonded citizen
        // proposer or a Congress member.
        if (
            referendumClass == ReferendumTypes.ReferendumClass.Legislation
                || referendumClass == ReferendumTypes.ReferendumClass.CongressElectionPolicy
                || referendumClass == ReferendumTypes.ReferendumClass.ModuleGovernance
        ) {
            if (proposalOrigin == ReferendumTypes.ProposalOrigin.Citizen) {
                return _isBondedCitizenProposer(proposer);
            }
            if (proposalOrigin == ReferendumTypes.ProposalOrigin.Congress) {
                return _isCongressProposer(proposer);
            }

            return false;
        }

        // Budget approvals and constitutional amendments are Congress-origin only.
        if (
            referendumClass == ReferendumTypes.ReferendumClass.BudgetApproval
                || referendumClass == ReferendumTypes.ReferendumClass.ConstitutionalAmendment
        ) {
            return proposalOrigin == ReferendumTypes.ProposalOrigin.Congress && _isCongressProposer(proposer);
        }

        return false;
    }

    function _isCongressProposer(address proposer) private view returns (bool isMember) {
        return ICongressElectionApp(_congressProposalAuthority).isCongressMember(proposer);
    }

    /// @inheritdoc IReferendumPolicy
    function evaluateOutcome(
        ReferendumTypes.ReferendumClass referendumClass,
        ReferendumTypes.ProposalOrigin proposalOrigin,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 forVoterCount,
        uint256 againstVoterCount,
        uint256 electorateHeadcountSnapshot,
        uint256 electorateVotingPowerSnapshot,
        bool requiresSupermajority
    ) external view returns (ReferendumTypes.PolicyOutcome memory outcome) {
        uint256 turnout = forVotes + againstVotes;

        // Rule-defining module repoints (requiresSupermajority) clear the same double-threshold as
        // constitutional amendments; every other class keeps the ordinary absolute-stake quorum.
        if (
            !requiresSupermajority
                && (referendumClass == ReferendumTypes.ReferendumClass.Legislation
                    || referendumClass == ReferendumTypes.ReferendumClass.ModuleGovernance
                    || referendumClass == ReferendumTypes.ReferendumClass.CongressElectionPolicy
                    || referendumClass == ReferendumTypes.ReferendumClass.BudgetApproval)
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

        if (referendumClass != ReferendumTypes.ReferendumClass.ConstitutionalAmendment && !requiresSupermajority) {
            revert UnsupportedReferendumClass(referendumClass);
        }

        uint256 headcountQuorumRequired = _ceilBps(electorateHeadcountSnapshot, CONSTITUTIONAL_HEADCOUNT_THRESHOLD_BPS);
        if (headcountQuorumRequired < _constitutionalForVoterQuorum) {
            headcountQuorumRequired = _constitutionalForVoterQuorum;
        }
        // Art IV §8 second prong: >= 65% of duly CAST voting instruments (weighted turnout), not of the
        // whole electorate snapshot. Broad participation is enforced separately by the 50%-of-electorate
        // headcount quorum above, so this measures the supermajority among votes actually cast.
        uint256 supermajorityRequired = _ceilBps(turnout, _constitutionalForStakeThresholdBps);
        bool quorumMet = forVoterCount >= headcountQuorumRequired && forVotes >= supermajorityRequired
            && forVoterCount > againstVoterCount;

        return ReferendumTypes.PolicyOutcome({
            turnout: turnout,
            quorumRequired: supermajorityRequired,
            headcountQuorumRequired: headcountQuorumRequired,
            electorateVotingPower: electorateVotingPowerSnapshot,
            quorumMet: quorumMet,
            passed: quorumMet && forVotes > againstVotes
        });
    }

    function _ceilBps(uint256 value, uint16 bps) private pure returns (uint256 result) {
        if (value == 0) {
            return 0;
        }

        return (value * uint256(bps) + 9_999) / 10_000;
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
}
