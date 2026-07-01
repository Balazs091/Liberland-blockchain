// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IBudgetEnvelopeRegistry} from "../interfaces/IBudgetEnvelopeRegistry.sol";
import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {ILegislationRegistry} from "../interfaces/ILegislationRegistry.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {IReferendumRegistry} from "../interfaces/IReferendumRegistry.sol";
import {ElectionTypes} from "../types/ElectionTypes.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {LegislationTypes} from "../types/LegislationTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";
import {ReferendumTypes} from "../types/ReferendumTypes.sol";
import {TreasuryTypes} from "../types/TreasuryTypes.sol";

/// @title DemoSetupAuthority
/// @notice Explicit demo-only authority contract used to seed realistic read-state before bootstrap is disabled.
contract DemoSetupAuthority {
    error NotOwner(address caller);
    error InvalidOwner(address owner_);

    address public immutable owner;
    IIdentityRegistry public immutable identityRegistry;
    IStakeRegistry public immutable stakeRegistry;
    ILegislationRegistry public immutable legislationRegistry;
    IReferendumRegistry public immutable referendumRegistry;
    ICongressCandidateRegistry public immutable congressCandidateRegistry;
    IOfficeRegistry public immutable officeRegistry;
    IBudgetEnvelopeRegistry public immutable budgetEnvelopeRegistry;

    constructor(
        address owner_,
        address identityRegistryAddress,
        address stakeRegistryAddress,
        address legislationRegistryAddress,
        address referendumRegistryAddress,
        address congressCandidateRegistryAddress,
        address officeRegistryAddress,
        address budgetEnvelopeRegistryAddress
    ) {
        if (owner_ == address(0)) {
            revert InvalidOwner(owner_);
        }

        owner = owner_;
        identityRegistry = IIdentityRegistry(identityRegistryAddress);
        stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        legislationRegistry = ILegislationRegistry(legislationRegistryAddress);
        referendumRegistry = IReferendumRegistry(referendumRegistryAddress);
        congressCandidateRegistry = ICongressCandidateRegistry(congressCandidateRegistryAddress);
        officeRegistry = IOfficeRegistry(officeRegistryAddress);
        budgetEnvelopeRegistry = IBudgetEnvelopeRegistry(budgetEnvelopeRegistryAddress);
    }

    /// @notice Seeds a verified adult citizen and active stake for demo read-state.
    function seedCitizen(
        bytes32 personId,
        address wallet,
        uint256 activeStake,
        string calldata metadataURI,
        bytes32 metadataHash
    ) external {
        _requireOwner(msg.sender);

        identityRegistry.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: metadataHash,
                metadataURI: metadataURI,
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            })
        );
        identityRegistry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        stakeRegistry.increaseStake(personId, activeStake);
    }

    /// @notice Seeds a protected stake floor for a demo citizen.
    function setProtectedStakeFloor(bytes32 personId, uint256 protectedFloor) external {
        _requireOwner(msg.sender);
        stakeRegistry.setProtectedStakeFloor(personId, protectedFloor);
    }

    /// @notice Seeds an enacted legislation record for demo read-state.
    function seedLegislation(bytes32 measureId, LegislationTypes.LegislationRecordInput calldata input) external {
        _requireOwner(msg.sender);
        legislationRegistry.recordEnactment(measureId, input);
    }

    /// @notice Seeds a referendum record for demo read-state.
    function seedReferendum(bytes32 referendumId, ReferendumTypes.ReferendumRecordInput calldata input) external {
        _requireOwner(msg.sender);
        referendumRegistry.createReferendum(referendumId, input);
    }

    /// @notice Seeds a referendum vote for demo read-state.
    function seedReferendumVote(bytes32 referendumId, address voter, ReferendumTypes.VoteOption option, uint256 weight)
        external
    {
        _requireOwner(msg.sender);
        referendumRegistry.recordVote(
            referendumId, identityRegistry.resolveWalletToPersonId(voter), voter, option, weight
        );
    }

    /// @notice Seeds a finalized referendum result for demo read-state.
    function finalizeReferendum(bytes32 referendumId, ReferendumTypes.ReferendumResultInput calldata input) external {
        _requireOwner(msg.sender);
        referendumRegistry.finalizeReferendum(referendumId, input);
    }

    /// @notice Seeds a Congress election cycle for demo read-state.
    function seedCongressCycle(uint256 cycleId, ElectionTypes.CongressCycleInput calldata input) external {
        _requireOwner(msg.sender);
        congressCandidateRegistry.createCycle(cycleId, input);
    }

    /// @notice Seeds an accepted Congress candidate for demo read-state.
    function seedCongressCandidate(
        uint256 cycleId,
        address candidate,
        bytes32 personId,
        bytes32 applicationHash,
        string calldata applicationURI
    ) external {
        _requireOwner(msg.sender);
        congressCandidateRegistry.registerCandidate(cycleId, candidate, personId, applicationHash, applicationURI);
    }

    /// @notice Seeds a signed Congress ballot for demo read-state.
    function seedCongressBallot(
        uint256 cycleId,
        address voter,
        address[] calldata candidates,
        int256[] calldata allocations,
        uint256 ballotWeight,
        uint32 maxPositiveCandidates,
        uint256 maxNegativeAllocation
    ) external {
        _requireOwner(msg.sender);
        congressCandidateRegistry.recordBallot(
            cycleId,
            identityRegistry.resolveWalletToPersonId(voter),
            voter,
            candidates,
            allocations,
            ballotWeight,
            maxPositiveCandidates,
            maxNegativeAllocation
        );
    }

    /// @notice Seeds finalized Congress rankings and active seat occupancy for demo read-state.
    function finalizeCongressCycle(uint256 cycleId, ElectionTypes.CongressFinalizationInput calldata input) external {
        _requireOwner(msg.sender);
        congressCandidateRegistry.finalizeCycle(cycleId, input);
    }

    /// @notice Seeds an office record for demo read-state.
    function seedOffice(bytes32 officeId, OfficeTypes.OfficeKind kind, string calldata name, address admin) external {
        _requireOwner(msg.sender);
        officeRegistry.registerOffice(officeId, kind, name, admin);
    }

    /// @notice Seeds office clerk status for demo read-state.
    function seedClerk(bytes32 officeId, address clerk, bool active) external {
        _requireOwner(msg.sender);
        officeRegistry.setClerkStatus(officeId, clerk, active);
    }

    /// @notice Seeds an approved budget envelope for demo read-state.
    function seedBudget(bytes32 budgetId, TreasuryTypes.BudgetEnvelopeInput calldata input) external {
        _requireOwner(msg.sender);
        budgetEnvelopeRegistry.recordBudgetApproval(budgetId, input);
    }

    function _requireOwner(address caller) private view {
        if (caller != owner) {
            revert NotOwner(caller);
        }
    }
}
