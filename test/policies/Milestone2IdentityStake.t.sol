// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {ICitizenEligibilityPolicy} from "../../contracts/interfaces/ICitizenEligibilityPolicy.sol";
import {IIdentityRegistry} from "../../contracts/interfaces/IIdentityRegistry.sol";
import {IStakeRegistry} from "../../contracts/interfaces/IStakeRegistry.sol";
import {IUnstakingPolicy} from "../../contracts/interfaces/IUnstakingPolicy.sol";
import {IVotingPowerPolicy} from "../../contracts/interfaces/IVotingPowerPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {UnstakingPolicy} from "../../contracts/policies/UnstakingPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {StakeTypes} from "../../contracts/types/StakeTypes.sol";

/// @title Milestone2IdentityStakeTest
/// @notice Covers Milestone 2 identity, stake, and political-rights policy defaults.
contract Milestone2IdentityStakeTest is Test {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint64 internal constant UNSTAKE_COOLDOWN = 7 days;

    bytes32 internal constant PERSON_ID = bytes32(uint256(1));
    bytes32 internal constant PERSON_TWO_ID = bytes32(uint256(2));

    address internal constant WALLET = address(0xA11CE);
    address internal constant WALLET_TWO = address(0xB0B);

    event IdentityRecordUpdated(
        bytes32 indexed personId,
        bytes32 metadataHash,
        string metadataURI,
        IdentityTypes.VerificationStatus verificationStatus,
        IdentityTypes.CitizenshipStatus citizenshipStatus,
        IdentityTypes.AgeClass ageClass,
        bool correctionFlag,
        bool finalSuspension,
        uint64 updatedAt,
        address indexed updatedBy
    );

    event CitizenshipStatusUpdated(
        bytes32 indexed personId,
        IdentityTypes.CitizenshipStatus previousStatus,
        IdentityTypes.CitizenshipStatus newStatus,
        uint64 updatedAt,
        address indexed updatedBy
    );

    event WalletLinkUpdated(
        address indexed wallet,
        bytes32 indexed personId,
        IdentityTypes.WalletLinkStatus status,
        uint64 linkedAt,
        uint64 unlinkedAt,
        address indexed updatedBy
    );

    event UnstakeRequested(
        bytes32 indexed personId,
        uint256 amount,
        uint256 newActiveStake,
        uint256 pendingUnstake,
        uint64 cooldownStart,
        uint64 cooldownEnd,
        address indexed updatedBy
    );

    event UnstakeClaimed(bytes32 indexed personId, uint256 claimedAmount, uint64 claimedAt, address indexed updatedBy);

    ConstitutionKernel internal kernel;
    MockModule internal identityAuthority;
    MockModule internal stakeAuthority;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    CitizenEligibilityPolicy internal citizenEligibilityPolicy;
    VotingPowerPolicy internal votingPowerPolicy;
    UnstakingPolicy internal unstakingPolicy;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));

        identityAuthority = new MockModule(keccak256("identity-authority"));
        stakeAuthority = new MockModule(keccak256("stake-authority"));

        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(identityAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(stakeAuthority));

        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));

        citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);
        votingPowerPolicy =
            new VotingPowerPolicy(address(identityRegistry), address(stakeRegistry), address(citizenEligibilityPolicy));
        unstakingPolicy = new UnstakingPolicy(address(stakeRegistry), UNSTAKE_COOLDOWN);
    }

    function test_Milestone2InterfacesExposeSelectors() public pure {
        assertTrue(IIdentityRegistry.getIdentityRecord.selector != bytes4(0));
        assertTrue(IIdentityRegistry.setIdentityRecord.selector != bytes4(0));
        assertTrue(IStakeRegistry.requestUnstake.selector != bytes4(0));
        assertTrue(IStakeRegistry.claimUnstake.selector != bytes4(0));
        assertTrue(ICitizenEligibilityPolicy.isCitizenInGoodStanding.selector != bytes4(0));
        assertTrue(IVotingPowerPolicy.votingPower.selector != bytes4(0));
        assertTrue(IUnstakingPolicy.canStartUnstake.selector != bytes4(0));
    }

    function test_IdentityRegistry_EmitsAuditEventsAndStoresWalletLink() public {
        IdentityTypes.IdentityRecordInput memory input = _defaultIdentityInput();

        vm.expectEmit(true, false, false, true, address(identityRegistry));
        emit IdentityRecordUpdated(
            PERSON_ID,
            input.metadataHash,
            input.metadataURI,
            input.verificationStatus,
            input.citizenshipStatus,
            input.ageClass,
            input.correctionFlag,
            input.finalSuspension,
            uint64(block.timestamp),
            address(identityAuthority)
        );
        vm.expectEmit(true, false, false, true, address(identityRegistry));
        emit CitizenshipStatusUpdated(
            PERSON_ID,
            IdentityTypes.CitizenshipStatus.Undefined,
            IdentityTypes.CitizenshipStatus.Citizen,
            uint64(block.timestamp),
            address(identityAuthority)
        );

        _setIdentityRecord(PERSON_ID, input);

        vm.expectEmit(true, true, false, true, address(identityRegistry));
        emit WalletLinkUpdated(
            WALLET,
            PERSON_ID,
            IdentityTypes.WalletLinkStatus.Active,
            uint64(block.timestamp),
            0,
            address(identityAuthority)
        );

        _setWalletLink(PERSON_ID, WALLET, IdentityTypes.WalletLinkStatus.Active);

        IdentityTypes.IdentityRecord memory record = identityRegistry.getIdentityRecord(PERSON_ID);
        IdentityTypes.WalletLink memory walletLink = identityRegistry.getWalletLink(WALLET);

        assertEq(record.personId, PERSON_ID);
        assertEq(record.metadataHash, input.metadataHash);
        assertEq(record.metadataURI, input.metadataURI);
        assertEq(uint256(record.verificationStatus), uint256(IdentityTypes.VerificationStatus.Verified));
        assertEq(uint256(record.citizenshipStatus), uint256(IdentityTypes.CitizenshipStatus.Citizen));
        assertEq(uint256(record.ageClass), uint256(IdentityTypes.AgeClass.Adult));
        assertFalse(record.correctionFlag);
        assertFalse(record.finalSuspension);
        assertEq(walletLink.personId, PERSON_ID);
        assertEq(uint256(walletLink.status), uint256(IdentityTypes.WalletLinkStatus.Active));
        assertTrue(identityRegistry.hasActiveWalletLink(WALLET));
    }

    function test_IdentityRegistry_RequiresAuthorizedModule() public {
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistry.UnauthorizedIdentityRegistryCaller.selector, address(this))
        );
        identityRegistry.setIdentityRecord(PERSON_ID, _defaultIdentityInput());
    }

    function test_IdentityRegistry_RequiresRevocationBeforeWalletReassignment() public {
        _setIdentityRecord(PERSON_ID, _defaultIdentityInput());
        _setIdentityRecord(PERSON_TWO_ID, _defaultIdentityInput());
        _setWalletLink(PERSON_ID, WALLET, IdentityTypes.WalletLinkStatus.Active);

        vm.expectRevert(
            abi.encodeWithSelector(
                IIdentityRegistry.WalletLinkPersonMismatch.selector, WALLET, PERSON_ID, PERSON_TWO_ID
            )
        );
        _setWalletLink(PERSON_TWO_ID, WALLET, IdentityTypes.WalletLinkStatus.Active);

        _setWalletLink(PERSON_ID, WALLET, IdentityTypes.WalletLinkStatus.Revoked);
        _setWalletLink(PERSON_TWO_ID, WALLET, IdentityTypes.WalletLinkStatus.Active);

        assertEq(identityRegistry.resolveWalletToPersonId(WALLET), PERSON_TWO_ID);
        assertTrue(identityRegistry.hasActiveWalletLink(WALLET));
    }

    function test_StakeRegistry_RequiresAuthorizedModule() public {
        vm.expectRevert(abi.encodeWithSelector(IStakeRegistry.UnauthorizedStakeRegistryCaller.selector, address(this)));
        stakeRegistry.increaseStake(PERSON_ID, 1);
    }

    function test_CitizenEligibilityAndVotingPower_FollowV1Defaults() public {
        _registerCitizen(PERSON_ID, WALLET, MINIMUM_CITIZEN_STAKE);

        assertTrue(citizenEligibilityPolicy.isCitizenInGoodStanding(WALLET));
        assertEq(votingPowerPolicy.votingPower(WALLET), MINIMUM_CITIZEN_STAKE);
    }

    function test_CitizenEligibility_ReturnsFalseForFinalSuspension() public {
        _registerCitizen(PERSON_ID, WALLET, MINIMUM_CITIZEN_STAKE + 1_000);

        IdentityTypes.IdentityRecordInput memory input = _defaultIdentityInput();
        input.finalSuspension = true;
        _setIdentityRecord(PERSON_ID, input);

        assertFalse(citizenEligibilityPolicy.isCitizenInGoodStanding(WALLET));
        assertEq(votingPowerPolicy.votingPower(WALLET), 0);
    }

    function test_UnstakingCooldown_BlocksPoliticalRightsOnlyDuringCooldown() public {
        _registerCitizen(PERSON_ID, WALLET, 7_000);

        uint64 cooldownEnd = unstakingPolicy.previewCooldownEnd(uint64(block.timestamp));
        assertTrue(unstakingPolicy.canStartUnstake(PERSON_ID, 1_000));

        vm.expectEmit(true, false, false, true, address(stakeRegistry));
        emit UnstakeRequested(
            PERSON_ID, 1_000, 6_000, 1_000, uint64(block.timestamp), cooldownEnd, address(stakeAuthority)
        );

        _requestUnstake(PERSON_ID, 1_000, cooldownEnd);

        assertTrue(unstakingPolicy.isPoliticalRightsBlocked(PERSON_ID));
        assertFalse(citizenEligibilityPolicy.isCitizenInGoodStanding(WALLET));
        assertEq(votingPowerPolicy.votingPower(WALLET), 0);

        skip(UNSTAKE_COOLDOWN);

        assertFalse(unstakingPolicy.isPoliticalRightsBlocked(PERSON_ID));
        assertTrue(citizenEligibilityPolicy.isCitizenInGoodStanding(WALLET));
        assertEq(votingPowerPolicy.votingPower(WALLET), 6_000);
    }

    function test_UnstakingPolicy_EnforcesProtectedFloorAndClaimability() public {
        _registerCitizen(PERSON_ID, WALLET, 9_000);
        _setProtectedStakeFloor(PERSON_ID, 8_500);

        assertFalse(unstakingPolicy.canStartUnstake(PERSON_ID, 600));
        assertTrue(unstakingPolicy.canStartUnstake(PERSON_ID, 500));

        uint64 blockedCooldownEnd = unstakingPolicy.previewCooldownEnd(uint64(block.timestamp));
        vm.expectRevert(
            abi.encodeWithSelector(IStakeRegistry.ProtectedStakeFloorBreached.selector, PERSON_ID, 8_400, 8_500)
        );
        _requestUnstake(PERSON_ID, 600, blockedCooldownEnd);

        uint64 cooldownEnd = unstakingPolicy.previewCooldownEnd(uint64(block.timestamp));
        _requestUnstake(PERSON_ID, 500, cooldownEnd);

        assertEq(unstakingPolicy.claimableAmount(PERSON_ID), 0);

        skip(UNSTAKE_COOLDOWN);

        vm.expectEmit(true, false, false, true, address(stakeRegistry));
        emit UnstakeClaimed(PERSON_ID, 500, uint64(block.timestamp), address(stakeAuthority));

        _claimUnstake(PERSON_ID);

        StakeTypes.StakeRecord memory stakeRecord = stakeRegistry.getStakeRecord(PERSON_ID);
        assertEq(unstakingPolicy.claimableAmount(PERSON_ID), 0);
        assertEq(stakeRecord.pendingUnstake, 0);
        assertEq(stakeRecord.cooldownEnd, 0);
        assertEq(stakeRecord.activeStake, 8_500);
    }

    function test_StakeRegistry_SlashConsumesPendingBeforeActiveAndClearsCooldown() public {
        _registerCitizen(PERSON_ID, WALLET, 9_000);

        uint64 cooldownEnd = unstakingPolicy.previewCooldownEnd(uint64(block.timestamp));
        _requestUnstake(PERSON_ID, 2_000, cooldownEnd);
        _slashStake(PERSON_ID, 2_000);

        StakeTypes.StakeRecord memory stakeRecord = stakeRegistry.getStakeRecord(PERSON_ID);

        assertEq(stakeRecord.activeStake, 7_000);
        assertEq(stakeRecord.pendingUnstake, 0);
        assertEq(stakeRecord.totalSlashed, 2_000);
        assertEq(stakeRecord.cooldownStart, 0);
        assertEq(stakeRecord.cooldownEnd, 0);
        assertFalse(unstakingPolicy.isPoliticalRightsBlocked(PERSON_ID));
        assertTrue(citizenEligibilityPolicy.isCitizenInGoodStanding(WALLET));
        assertEq(votingPowerPolicy.votingPower(WALLET), 7_000);
    }

    function test_StakeRegistry_RecordsRecoveryAccounting() public {
        _registerCitizen(PERSON_ID, WALLET, 6_000);
        _slashStake(PERSON_ID, 1_000);
        _recoverStake(PERSON_ID, 500);

        StakeTypes.StakeRecord memory stakeRecord = stakeRegistry.getStakeRecord(PERSON_ID);

        assertEq(stakeRecord.activeStake, 5_500);
        assertEq(stakeRecord.totalSlashed, 1_000);
        assertEq(stakeRecord.totalRecovered, 500);
        assertTrue(citizenEligibilityPolicy.isCitizenInGoodStanding(WALLET));
        assertEq(votingPowerPolicy.votingPower(WALLET), 5_500);
    }

    function _registerCitizen(bytes32 personId, address wallet, uint256 activeStake) internal {
        _setIdentityRecord(personId, _defaultIdentityInput());
        _setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        _increaseStake(personId, activeStake);
    }

    function _setIdentityRecord(bytes32 personId, IdentityTypes.IdentityRecordInput memory input) internal {
        vm.prank(address(identityAuthority));
        identityRegistry.setIdentityRecord(personId, input);
    }

    function _setWalletLink(bytes32 personId, address wallet, IdentityTypes.WalletLinkStatus status) internal {
        vm.prank(address(identityAuthority));
        identityRegistry.setWalletLink(personId, wallet, status);
    }

    function _increaseStake(bytes32 personId, uint256 amount) internal {
        vm.prank(address(stakeAuthority));
        stakeRegistry.increaseStake(personId, amount);
    }

    function _setProtectedStakeFloor(bytes32 personId, uint256 amount) internal {
        vm.prank(address(stakeAuthority));
        stakeRegistry.setProtectedStakeFloor(personId, amount);
    }

    function _requestUnstake(bytes32 personId, uint256 amount, uint64 cooldownEnd) internal {
        vm.prank(address(stakeAuthority));
        stakeRegistry.requestUnstake(personId, amount, cooldownEnd);
    }

    function _claimUnstake(bytes32 personId) internal returns (uint256 claimedAmount) {
        vm.prank(address(stakeAuthority));
        return stakeRegistry.claimUnstake(personId);
    }

    function _slashStake(bytes32 personId, uint256 amount) internal {
        vm.prank(address(stakeAuthority));
        stakeRegistry.slashStake(personId, amount);
    }

    function _recoverStake(bytes32 personId, uint256 amount) internal {
        vm.prank(address(stakeAuthority));
        stakeRegistry.recoverStake(personId, amount);
    }

    function _defaultIdentityInput() internal pure returns (IdentityTypes.IdentityRecordInput memory input) {
        return IdentityTypes.IdentityRecordInput({
            metadataHash: keccak256("citizen-metadata"),
            metadataURI: "ipfs://citizen",
            verificationStatus: IdentityTypes.VerificationStatus.Verified,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
            ageClass: IdentityTypes.AgeClass.Adult,
            correctionFlag: false,
            finalSuspension: false
        });
    }
}
