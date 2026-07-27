// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {ICongressElectionPolicy} from "../interfaces/ICongressElectionPolicy.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ILLMStakingVault} from "../interfaces/ILLMStakingVault.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {ISenateSeatRegistry} from "../interfaces/ISenateSeatRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {ElectionTypes} from "../types/ElectionTypes.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title InitialSetupAuthority
/// @notice Explicit, sealable setup authority for genesis citizens, offices, Senate seats, and Congress members.
contract InitialSetupAuthority {
    error InvalidSetupAddress(address account);
    error InvalidSetupInput();
    error NotSetupOwner(address caller);
    error SetupAuthorityAlreadySealed();
    error SetupReadinessCheckFailed(bytes32 checkId);

    event SetupAuthoritySealed(address indexed sealedBy);
    event SetupCitizenConfigured(
        bytes32 indexed personId, address indexed wallet, uint256 activeStake, address indexed configuredBy
    );
    event SetupSenateSeatAssigned(uint32 indexed seatIndex, address indexed holder, address indexed assignedBy);
    event SetupCongressTermSeeded(
        uint256 indexed cycleId, uint32 electedCount, uint32 runnerUpCount, address indexed seededBy
    );
    event SetupCongressContinuityCycleSeeded(
        uint256 indexed cycleId,
        uint64 nominationStart,
        uint64 votingStart,
        uint64 votingEnd,
        uint32 incumbentCount,
        address indexed seededBy
    );
    event SetupOfficeConfigured(bytes32 indexed officeId, address indexed admin, address indexed configuredBy);

    address public immutable owner;
    IIdentityRegistry public immutable identityRegistry;
    IStakeRegistry public immutable stakeRegistry;
    ILLMStakingVault public immutable stakingVault;
    ICongressCandidateRegistry public immutable congressCandidateRegistry;
    ICongressElectionPolicy public immutable congressElectionPolicy;
    ISenateSeatRegistry public immutable senateSeatRegistry;
    IOfficeRegistry public immutable officeRegistry;

    bool public isSealed;

    /// @param owner_ The explicit setup operator. This authority can be permanently sealed.
    /// @param identityRegistryAddress The identity registry address.
    /// @param stakeRegistryAddress The stake registry address.
    /// @param stakingVaultAddress The canonical LLM staking vault pre-funded for genesis stake.
    /// @param congressCandidateRegistryAddress The Congress candidate registry address.
    /// @param congressElectionPolicyAddress The Congress election policy address used for genesis cycle bounds.
    /// @param senateSeatRegistryAddress The Senate seat registry address.
    /// @param officeRegistryAddress The office registry address.
    constructor(
        address owner_,
        address identityRegistryAddress,
        address stakeRegistryAddress,
        address stakingVaultAddress,
        address congressCandidateRegistryAddress,
        address congressElectionPolicyAddress,
        address senateSeatRegistryAddress,
        address officeRegistryAddress
    ) {
        if (owner_ == address(0)) {
            revert InvalidSetupAddress(owner_);
        }
        _requireContract(identityRegistryAddress);
        _requireContract(stakeRegistryAddress);
        _requireContract(stakingVaultAddress);
        _requireContract(congressCandidateRegistryAddress);
        _requireContract(congressElectionPolicyAddress);
        _requireContract(senateSeatRegistryAddress);
        _requireContract(officeRegistryAddress);

        owner = owner_;
        identityRegistry = IIdentityRegistry(identityRegistryAddress);
        stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        stakingVault = ILLMStakingVault(stakingVaultAddress);
        congressCandidateRegistry = ICongressCandidateRegistry(congressCandidateRegistryAddress);
        congressElectionPolicy = ICongressElectionPolicy(congressElectionPolicyAddress);
        senateSeatRegistry = ISenateSeatRegistry(senateSeatRegistryAddress);
        officeRegistry = IOfficeRegistry(officeRegistryAddress);
    }

    /// @notice Permanently disables every setup write method on this authority.
    function seal() external {
        _requireOwner(msg.sender);
        if (isSealed) {
            revert SetupAuthorityAlreadySealed();
        }

        isSealed = true;
        emit SetupAuthoritySealed(msg.sender);
    }

    /// @notice Creates or updates a citizen identity, links a wallet, and optionally adds active stake.
    /// @param personId The canonical person identifier.
    /// @param wallet The wallet to link as active.
    /// @param recordInput The identity facts to store.
    /// @param activeStakeToAdd Active stake units to add for the person. Use zero to skip stake.
    function configureCitizen(
        bytes32 personId,
        address wallet,
        IdentityTypes.IdentityRecordInput calldata recordInput,
        uint256 activeStakeToAdd
    ) external {
        _requireOpenOwner(msg.sender);
        _requireNonzero(wallet);
        if (personId == bytes32(0)) {
            revert InvalidSetupInput();
        }

        emit SetupCitizenConfigured(personId, wallet, activeStakeToAdd, msg.sender);

        identityRegistry.setIdentityRecord(personId, recordInput);
        identityRegistry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        if (activeStakeToAdd != 0) {
            stakingVault.creditBackedStake(personId, activeStakeToAdd);
        }
    }

    /// @notice Adds active stake to an existing person record.
    /// @param personId The person identifier receiving stake.
    /// @param amount Active stake units to add.
    function increaseStake(bytes32 personId, uint256 amount) external {
        _requireOpenOwner(msg.sender);
        if (personId == bytes32(0) || amount == 0) {
            revert InvalidSetupInput();
        }

        stakingVault.creditBackedStake(personId, amount);
    }

    /// @notice Sets a protected stake floor for an existing person record.
    /// @param personId The person identifier to update.
    /// @param protectedFloor The protected floor to store.
    function setProtectedStakeFloor(bytes32 personId, uint256 protectedFloor) external {
        _requireOpenOwner(msg.sender);
        if (personId == bytes32(0)) {
            revert InvalidSetupInput();
        }

        stakeRegistry.setProtectedStakeFloor(personId, protectedFloor);
    }

    /// @notice Assigns a Senate seat to an active wallet-linked person.
    /// @param seatIndex The Senate seat index.
    /// @param holder The wallet that will hold the seat.
    function assignSenateSeat(uint32 seatIndex, address holder) external {
        _requireOpenOwner(msg.sender);
        emit SetupSenateSeatAssigned(seatIndex, holder, msg.sender);

        bytes32 holderPersonId = _requireActivePerson(holder);
        senateSeatRegistry.assignSeat(seatIndex, holder, holderPersonId, false);
    }

    /// @notice Seeds a finalized Congress term from candidate/member wallets without creating arbitrary powers.
    /// @param members Candidate wallets sorted in intended rank order. First policy seat-count members become elected.
    function seedCongressTerm(address[] calldata members) external returns (uint256 cycleId) {
        _requireOpenOwner(msg.sender);
        return _seedFinalizedCongressTerm(members);
    }

    /// @notice Seeds occupied Congress seats and a live shortened cycle ending at the imported pre-migration boundary.
    /// @dev The live continuity cycle may be shorter than the normal policy cadence, but must provide the full minimum
    ///      nomination and voting windows and may not exceed one normal cycle. Later cycles are created by the regular
    ///      CongressElectionApp cadence.
    /// @param members Candidate wallets sorted in intended rank order. First policy seat-count members become elected.
    /// @param continuityCycleEnd Absolute end timestamp imported from the pre-migration Congress cycle.
    /// @return officeTermCycleId Finalized seed cycle that installs the incumbent Congress office term.
    /// @return continuityCycleId Live shortened election cycle that ends at `continuityCycleEnd`.
    function seedCongressContinuityTerm(address[] calldata members, uint64 continuityCycleEnd)
        external
        returns (uint256 officeTermCycleId, uint256 continuityCycleId)
    {
        _requireOpenOwner(msg.sender);
        officeTermCycleId = _seedFinalizedCongressTerm(members);

        uint64 nominationStart = uint64(block.timestamp);
        uint64 votingStart = nominationStart + congressElectionPolicy.minimumNominationDuration();
        if (
            continuityCycleEnd <= votingStart
                || continuityCycleEnd - votingStart < congressElectionPolicy.minimumVotingDuration()
                || continuityCycleEnd - nominationStart > congressElectionPolicy.cycleDuration()
        ) {
            revert InvalidSetupInput();
        }

        continuityCycleId = officeTermCycleId + 1;
        congressCandidateRegistry.createCycle(
            continuityCycleId,
            ElectionTypes.CongressCycleInput({
                nominationStart: nominationStart,
                votingStart: votingStart,
                votingEnd: continuityCycleEnd,
                votingPowerSnapshotBlock: SafeCast.toUint48(block.number),
                seatCount: congressElectionPolicy.seatCount(),
                runnerUpCount: congressElectionPolicy.runnerUpCount(),
                maxCandidateCount: congressElectionPolicy.maxCandidateCount(),
                policy: address(congressElectionPolicy),
                policyReference: _congressPolicyReference()
            })
        );

        address[] memory incumbents = congressCandidateRegistry.currentCongressMembers();
        uint256 incumbentCount = incumbents.length;
        for (uint256 index = 0; index < incumbentCount; ++index) {
            address incumbent = incumbents[index];
            bytes32 personId = _requireActivePerson(incumbent);
            congressCandidateRegistry.registerCandidate(
                continuityCycleId,
                incumbent,
                personId,
                keccak256(abi.encode("initial.congress.continuity", continuityCycleId, incumbent)),
                ""
            );
        }

        emit SetupCongressContinuityCycleSeeded(
            continuityCycleId,
            nominationStart,
            votingStart,
            continuityCycleEnd,
            // The incumbent list cannot exceed the uint32 policy seat count.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint32(incumbentCount),
            msg.sender
        );
    }

    function _seedFinalizedCongressTerm(address[] calldata members) private returns (uint256 cycleId) {
        uint256 memberCount = members.length;
        if (memberCount == 0) {
            revert InvalidSetupInput();
        }

        uint256 latestCycleId = congressCandidateRegistry.latestCycleId();
        if (latestCycleId != 0) {
            ElectionTypes.CongressCycleRecord memory latestCycle = congressCandidateRegistry.getCycle(latestCycleId);
            if (latestCycle.status != ElectionTypes.ElectionStatus.Finalized) {
                revert InvalidSetupInput();
            }
        }

        cycleId = latestCycleId + 1;
        congressCandidateRegistry.createCycle(
            cycleId,
            ElectionTypes.CongressCycleInput({
                nominationStart: uint64(block.timestamp),
                votingStart: uint64(block.timestamp + 1),
                votingEnd: uint64(block.timestamp + 2),
                votingPowerSnapshotBlock: SafeCast.toUint48(block.number),
                seatCount: congressElectionPolicy.seatCount(),
                runnerUpCount: congressElectionPolicy.runnerUpCount(),
                maxCandidateCount: congressElectionPolicy.maxCandidateCount(),
                policy: address(congressElectionPolicy),
                policyReference: _congressPolicyReference()
            })
        );

        address[] memory rankedCandidates = new address[](memberCount);
        int256[] memory rankedVoteTotals = new int256[](memberCount);
        for (uint256 index = 0; index < memberCount; ++index) {
            address member = members[index];
            bytes32 personId = _requireActivePerson(member);
            rankedCandidates[index] = member;
            congressCandidateRegistry.registerCandidate(
                cycleId, member, personId, keccak256(abi.encode("initial.congress.application", cycleId, member)), ""
            );
        }

        uint32 electedCount = _minConfiguredCount(congressElectionPolicy.seatCount(), memberCount);
        uint256 remainingMembers = memberCount > electedCount ? memberCount - electedCount : 0;
        uint32 runnerUpCount = _minConfiguredCount(congressElectionPolicy.runnerUpCount(), remainingMembers);
        emit SetupCongressTermSeeded(cycleId, electedCount, runnerUpCount, msg.sender);

        congressCandidateRegistry.finalizeCycle(
            cycleId,
            ElectionTypes.CongressFinalizationInput({
                rankedCandidates: rankedCandidates,
                rankedVoteTotals: rankedVoteTotals,
                electedCount: electedCount,
                runnerUpCount: runnerUpCount
            })
        );
    }

    /// @notice Registers a new office.
    /// @param officeId The office identifier.
    /// @param kind The office kind.
    /// @param name The display name.
    /// @param admin The initial office admin.
    function createOffice(bytes32 officeId, OfficeTypes.OfficeKind kind, string calldata name, address admin) external {
        _requireOpenOwner(msg.sender);
        emit SetupOfficeConfigured(officeId, admin, msg.sender);
        officeRegistry.registerOffice(officeId, kind, name, admin);
    }

    /// @notice Updates an office clerk's active status.
    /// @param officeId The office identifier.
    /// @param clerk The clerk wallet.
    /// @param active Whether the clerk is active.
    function setOfficeClerk(bytes32 officeId, address clerk, bool active) external {
        _requireOpenOwner(msg.sender);
        officeRegistry.setClerkStatus(officeId, clerk, active);
    }

    /// @notice Transfers an office admin.
    /// @param officeId The office identifier.
    /// @param newAdmin The new admin wallet.
    function transferOfficeAdmin(bytes32 officeId, address newAdmin) external {
        _requireOpenOwner(msg.sender);
        officeRegistry.transferOfficeAdmin(officeId, newAdmin);
    }

    /// @notice Renames an office.
    /// @param officeId The office identifier.
    /// @param newName The new display name.
    function renameOffice(bytes32 officeId, string calldata newName) external {
        _requireOpenOwner(msg.sender);
        officeRegistry.renameOffice(officeId, newName);
    }

    /// @notice Updates an office active flag.
    /// @param officeId The office identifier.
    /// @param active Whether the office is active.
    function setOfficeActive(bytes32 officeId, bool active) external {
        _requireOpenOwner(msg.sender);
        officeRegistry.setOfficeActive(officeId, active);
    }

    /// @notice Reverts unless the core genesis state is sufficient before disabling bootstrap.
    /// @param minimumIdentityCount Minimum number of identity records required.
    /// @param minimumSenateSeats Minimum occupied Senate seats required.
    /// @param minimumCongressSeats Minimum occupied Congress seats required.
    /// @param requiredOfficeIds Offices that must exist and be active.
    function assertReadyForBootstrapDisable(
        uint256 minimumIdentityCount,
        uint32 minimumSenateSeats,
        uint32 minimumCongressSeats,
        bytes32[] calldata requiredOfficeIds
    ) external view {
        if (identityRegistry.totalIdentityCount() < minimumIdentityCount) {
            revert SetupReadinessCheckFailed(keccak256("identity-count"));
        }
        if (senateSeatRegistry.occupiedSeatCount() < minimumSenateSeats) {
            revert SetupReadinessCheckFailed(keccak256("senate-seat-count"));
        }
        if (congressCandidateRegistry.getCurrentOfficeTerm().occupiedSeatCount < minimumCongressSeats) {
            revert SetupReadinessCheckFailed(keccak256("congress-seat-count"));
        }

        uint256 officeCount = requiredOfficeIds.length;
        for (uint256 index = 0; index < officeCount; ++index) {
            OfficeTypes.OfficeRecord memory officeRecord = officeRegistry.getOfficeRecord(requiredOfficeIds[index]);
            if (officeRecord.officeId == bytes32(0) || !officeRecord.active || officeRecord.admin == address(0)) {
                revert SetupReadinessCheckFailed(requiredOfficeIds[index]);
            }
        }
    }

    function _requireOpenOwner(address caller) private view {
        _requireOwner(caller);
        if (isSealed) {
            revert SetupAuthorityAlreadySealed();
        }
    }

    function _requireOwner(address caller) private view {
        if (caller != owner) {
            revert NotSetupOwner(caller);
        }
    }

    function _requireActivePerson(address wallet) private view returns (bytes32 personId) {
        _requireNonzero(wallet);
        IdentityTypes.WalletLink memory walletLink = identityRegistry.getWalletLink(wallet);
        if (walletLink.personId == bytes32(0) || walletLink.status != IdentityTypes.WalletLinkStatus.Active) {
            revert InvalidSetupInput();
        }

        return walletLink.personId;
    }

    function _congressPolicyReference() private view returns (bytes32 policyReference) {
        return keccak256(
            abi.encode(
                address(congressElectionPolicy),
                congressElectionPolicy.seatCount(),
                congressElectionPolicy.runnerUpCount(),
                congressElectionPolicy.maxCandidateCount(),
                congressElectionPolicy.candidateBondRequirement(),
                congressElectionPolicy.maxPositiveCandidates(),
                congressElectionPolicy.minimumNominationDuration(),
                congressElectionPolicy.minimumVotingDuration(),
                congressElectionPolicy.maxScheduleLeadTime(),
                congressElectionPolicy.cycleDuration()
            )
        );
    }

    function _minConfiguredCount(uint32 configuredCount, uint256 candidateCount) private pure returns (uint32 count) {
        if (candidateCount < configuredCount) {
            // forge-lint: disable-next-line(unsafe-typecast)
            return uint32(candidateCount);
        }

        return configuredCount;
    }

    function _requireContract(address account) private view {
        if (account == address(0) || account.code.length == 0) {
            revert InvalidSetupAddress(account);
        }
    }

    function _requireNonzero(address account) private pure {
        if (account == address(0)) {
            revert InvalidSetupAddress(account);
        }
    }
}
