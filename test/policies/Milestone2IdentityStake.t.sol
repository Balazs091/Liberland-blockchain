// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

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
/// @notice Covers Milestone 2 identity, stake, discrete unstaking, and welfare-based rights.
contract Milestone2IdentityStakeTest is Test {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint64 internal constant WELFARE_PERIOD = 30 days;
    uint16 internal constant ANNUAL_UNSTAKE_RATE_BPS = 1_000;

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

    event UnstakeExecuted(
        bytes32 indexed personId,
        uint256 releasedAmount,
        uint256 remainingActiveStake,
        uint64 welfareUntil,
        uint64 timestamp,
        address indexed caller
    );

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
        unstakingPolicy = new UnstakingPolicy(address(stakeRegistry), WELFARE_PERIOD, ANNUAL_UNSTAKE_RATE_BPS);

        kernel.bootstrapSetModule(KernelModuleIds.UNSTAKING_POLICY, address(unstakingPolicy));
    }

    function test_Milestone2InterfacesExposeSelectors() public pure {
        assertTrue(IIdentityRegistry.getIdentityRecord.selector != bytes4(0));
        assertTrue(IIdentityRegistry.setIdentityRecord.selector != bytes4(0));
        assertTrue(IStakeRegistry.unstake.selector != bytes4(0));
        assertTrue(IStakeRegistry.isInWelfare.selector != bytes4(0));
        assertTrue(ICitizenEligibilityPolicy.isCitizenInGoodStanding.selector != bytes4(0));
        assertTrue(IVotingPowerPolicy.votingPower.selector != bytes4(0));
        assertTrue(IUnstakingPolicy.canUnstake.selector != bytes4(0));
    }

    function test_UnstakingPolicy_ExposesConfiguredDefaults() public view {
        assertEq(unstakingPolicy.welfarePeriod(), WELFARE_PERIOD);
        assertEq(unstakingPolicy.annualUnstakeRateBps(), ANNUAL_UNSTAKE_RATE_BPS);
        assertEq(unstakingPolicy.stakeRegistry(), address(stakeRegistry));
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

    /// @notice H2: one active wallet per person, but revoke-then-activate migration is allowed.
    function test_IdentityRegistry_RejectsSecondActiveWalletButAllowsMigration() public {
        _setIdentityRecord(PERSON_ID, _defaultIdentityInput());
        _setWalletLink(PERSON_ID, WALLET, IdentityTypes.WalletLinkStatus.Active);
        assertEq(identityRegistry.activeWalletCountOf(PERSON_ID), 1);

        // A second, different wallet cannot become active while the first is active.
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistry.PersonAlreadyHasActiveWallet.selector, PERSON_ID));
        _setWalletLink(PERSON_ID, WALLET_TWO, IdentityTypes.WalletLinkStatus.Active);

        // Re-activating the same wallet is idempotent and does not revert.
        _setWalletLink(PERSON_ID, WALLET, IdentityTypes.WalletLinkStatus.Active);
        assertEq(identityRegistry.activeWalletCountOf(PERSON_ID), 1);

        // Migration: revoke the old wallet first, then activate the new one.
        _setWalletLink(PERSON_ID, WALLET, IdentityTypes.WalletLinkStatus.Revoked);
        assertEq(identityRegistry.activeWalletCountOf(PERSON_ID), 0);
        _setWalletLink(PERSON_ID, WALLET_TWO, IdentityTypes.WalletLinkStatus.Active);

        assertEq(identityRegistry.activeWalletCountOf(PERSON_ID), 1);
        assertTrue(identityRegistry.hasActiveWalletLink(WALLET_TWO));
        assertFalse(identityRegistry.hasActiveWalletLink(WALLET));
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

    /// @notice Security property: one unstake releases the 30-day portion and suspends voting during welfare.
    function test_Unstake_ReleasesDiscretePortionAndSuspendsVotingDuringWelfare() public {
        _registerCitizen(PERSON_ID, WALLET, 7_300);

        // 10%/yr * 30/365 of 7,300 == 60 exactly (7300 * 1000 * 30 days / (10_000 * 365 days)).
        assertEq(unstakingPolicy.unstakePortion(7_300), 60);
        assertTrue(unstakingPolicy.canUnstake(PERSON_ID));

        uint64 expectedWelfareUntil = uint64(block.timestamp) + WELFARE_PERIOD;

        vm.expectEmit(true, false, false, true, address(stakeRegistry));
        emit UnstakeExecuted(
            PERSON_ID, 60, 7_240, expectedWelfareUntil, uint64(block.timestamp), address(stakeAuthority)
        );

        (uint256 releasedAmount, uint64 welfareUntil) = _unstake(PERSON_ID);

        assertEq(releasedAmount, 60);
        assertEq(welfareUntil, expectedWelfareUntil);
        assertEq(stakeRegistry.activeStakeOf(PERSON_ID), 7_240);
        assertEq(stakeRegistry.getStakeRecord(PERSON_ID).totalUnstaked, 60);

        // While in welfare: voting suspended and a second unstake reverts.
        assertTrue(stakeRegistry.isInWelfare(PERSON_ID));
        assertEq(stakeRegistry.welfareUntilOf(PERSON_ID), welfareUntil);
        assertFalse(citizenEligibilityPolicy.isCitizenInGoodStanding(WALLET));
        assertEq(votingPowerPolicy.votingPower(WALLET), 0);
        assertFalse(unstakingPolicy.canUnstake(PERSON_ID));

        vm.expectRevert(abi.encodeWithSelector(IStakeRegistry.InWelfarePeriod.selector, PERSON_ID, welfareUntil));
        vm.prank(address(stakeAuthority));
        stakeRegistry.unstake(PERSON_ID);

        // After welfare elapses: rights restored and unstake works again.
        vm.warp(welfareUntil);
        assertFalse(stakeRegistry.isInWelfare(PERSON_ID));
        assertTrue(citizenEligibilityPolicy.isCitizenInGoodStanding(WALLET));
        assertEq(votingPowerPolicy.votingPower(WALLET), 7_240);
        assertTrue(unstakingPolicy.canUnstake(PERSON_ID));

        (uint256 secondRelease,) = _unstake(PERSON_ID);
        assertEq(secondRelease, unstakingPolicy.unstakePortion(7_240));
    }

    /// @notice M12 (no lien): a non-borrower can exit down to their own protected floor.
    function test_Unstake_RespectsProtectedFloorForNonBorrower() public {
        _registerCitizen(PERSON_ID, WALLET, 9_000);
        _setProtectedStakeFloor(PERSON_ID, 8_950);

        // Without a lien registry configured, the required floor equals the protected floor.
        assertEq(stakeRegistry.requiredActiveStakeFloorOf(PERSON_ID), 8_950);

        // Surplus above the floor is only 50, so the 30-day portion (73) is capped to 50.
        (uint256 releasedAmount,) = _unstake(PERSON_ID);
        assertEq(releasedAmount, 50);
        assertEq(stakeRegistry.activeStakeOf(PERSON_ID), 8_950);
    }

    function test_Unstake_RevertsWhenNoReleasableSurplus() public {
        _registerCitizen(PERSON_ID, WALLET, 9_000);
        _setProtectedStakeFloor(PERSON_ID, 9_000);

        assertFalse(unstakingPolicy.canUnstake(PERSON_ID));

        vm.expectRevert(abi.encodeWithSelector(IStakeRegistry.NothingToUnstake.selector, PERSON_ID));
        vm.prank(address(stakeAuthority));
        stakeRegistry.unstake(PERSON_ID);
    }

    function test_StakeRegistry_SlashReducesActiveStake() public {
        _registerCitizen(PERSON_ID, WALLET, 9_000);
        _slashStake(PERSON_ID, 2_000);

        StakeTypes.StakeRecord memory stakeRecord = stakeRegistry.getStakeRecord(PERSON_ID);

        assertEq(stakeRecord.activeStake, 7_000);
        assertEq(stakeRecord.totalSlashed, 2_000);
        assertFalse(stakeRegistry.isInWelfare(PERSON_ID));
        assertTrue(citizenEligibilityPolicy.isCitizenInGoodStanding(WALLET));
        assertEq(votingPowerPolicy.votingPower(WALLET), 7_000);
    }

    function test_StakeRegistry_SlashRevertsAboveActiveStake() public {
        _registerCitizen(PERSON_ID, WALLET, 5_000);

        vm.expectRevert(
            abi.encodeWithSelector(IStakeRegistry.InsufficientSlashableStake.selector, PERSON_ID, 5_000, 6_000)
        );
        vm.prank(address(stakeAuthority));
        stakeRegistry.slashStake(PERSON_ID, 6_000);
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

    function _unstake(bytes32 personId) internal returns (uint256 releasedAmount, uint64 welfareUntil) {
        vm.prank(address(stakeAuthority));
        return stakeRegistry.unstake(personId);
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
