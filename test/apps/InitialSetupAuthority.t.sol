// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {InitialSetupAuthority} from "../../contracts/apps/InitialSetupAuthority.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {CandidateEligibilityPolicy} from "../../contracts/policies/CandidateEligibilityPolicy.sol";
import {CitizenEligibilityPolicy} from "../../contracts/policies/CitizenEligibilityPolicy.sol";
import {CongressElectionPolicy} from "../../contracts/policies/CongressElectionPolicy.sol";
import {VotingPowerPolicy} from "../../contracts/policies/VotingPowerPolicy.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {SenateSeatRegistry} from "../../contracts/registries/SenateSeatRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

/// @title InitialSetupAuthorityTest
/// @notice Covers the explicit, sealable genesis setup path used to avoid production deployment deadlocks.
contract InitialSetupAuthorityTest is Test {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint256 internal constant MINIMUM_CANDIDATE_STAKE = 6_000;
    uint256 internal constant CANDIDATE_BOND_REQUIREMENT = 6_000;
    uint32 internal constant SEAT_COUNT = 2;
    uint32 internal constant RUNNER_UP_COUNT = 1;
    uint32 internal constant MAX_CANDIDATE_COUNT = 4;

    bytes32 internal constant PERSON_ONE_ID = bytes32(uint256(1));
    bytes32 internal constant PERSON_TWO_ID = bytes32(uint256(2));
    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");

    address internal constant WALLET_ONE = address(0xA11CE);
    address internal constant WALLET_TWO = address(0xB0B);
    address internal constant FINANCE_ADMIN = address(0xF1A0);

    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    CongressCandidateRegistry internal congressCandidateRegistry;
    SenateSeatRegistry internal senateSeatRegistry;
    OfficeRegistry internal officeRegistry;
    InitialSetupAuthority internal setupAuthority;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        congressCandidateRegistry = new CongressCandidateRegistry(address(kernel));
        senateSeatRegistry = new SenateSeatRegistry(address(kernel));
        officeRegistry = new OfficeRegistry(address(kernel));

        CitizenEligibilityPolicy citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(identityRegistry), address(stakeRegistry), MINIMUM_CITIZEN_STAKE);
        VotingPowerPolicy votingPowerPolicy =
            new VotingPowerPolicy(address(identityRegistry), address(stakeRegistry), address(citizenEligibilityPolicy));
        CandidateEligibilityPolicy candidateEligibilityPolicy = new CandidateEligibilityPolicy(
            address(identityRegistry),
            address(stakeRegistry),
            address(citizenEligibilityPolicy),
            MINIMUM_CANDIDATE_STAKE
        );
        CongressElectionPolicy congressElectionPolicy = new CongressElectionPolicy(
            address(candidateEligibilityPolicy),
            address(votingPowerPolicy),
            SEAT_COUNT,
            RUNNER_UP_COUNT,
            MAX_CANDIDATE_COUNT,
            CANDIDATE_BOND_REQUIREMENT,
            1 days,
            2 days,
            3 days,
            3 days
        );

        setupAuthority = new InitialSetupAuthority(
            address(this),
            address(identityRegistry),
            address(stakeRegistry),
            address(congressCandidateRegistry),
            address(congressElectionPolicy),
            address(senateSeatRegistry),
            address(officeRegistry)
        );

        _wireSetupAuthority();
    }

    function test_SetupAuthority_SeedsGovernanceAndCanBeSealed() public {
        _configureCitizen(PERSON_ONE_ID, WALLET_ONE, 10_000);
        _configureCitizen(PERSON_TWO_ID, WALLET_TWO, 12_000);

        setupAuthority.assignSenateSeat(0, WALLET_ONE);

        address[] memory members = new address[](2);
        members[0] = WALLET_ONE;
        members[1] = WALLET_TWO;
        uint256 cycleId = setupAuthority.seedCongressTerm(members);

        setupAuthority.createOffice(
            FINANCE_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "Ministry of Finance", FINANCE_ADMIN
        );

        bytes32[] memory requiredOfficeIds = new bytes32[](1);
        requiredOfficeIds[0] = FINANCE_OFFICE_ID;
        setupAuthority.assertReadyForBootstrapDisable(2, 1, 2, requiredOfficeIds);

        assertEq(cycleId, 1);
        assertEq(senateSeatRegistry.occupiedSeatCount(), 1);
        assertEq(congressCandidateRegistry.getCurrentOfficeTerm().occupiedSeatCount, 2);
        assertEq(officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID).admin, FINANCE_ADMIN);

        setupAuthority.seal();

        vm.expectRevert(InitialSetupAuthority.SetupAuthorityAlreadySealed.selector);
        setupAuthority.increaseStake(PERSON_ONE_ID, 1);
    }

    function test_SeedCongressTerm_RevertsWhenLatestCycleIsUnfinalized() public {
        _configureCitizen(PERSON_ONE_ID, WALLET_ONE, 10_000);

        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(this));
        congressCandidateRegistry.createCycle(
            1,
            ElectionTypes.CongressCycleInput({
                nominationStart: uint64(block.timestamp),
                votingStart: uint64(block.timestamp + 1),
                votingEnd: uint64(block.timestamp + 2),
                seatCount: SEAT_COUNT,
                runnerUpCount: RUNNER_UP_COUNT,
                maxCandidateCount: MAX_CANDIDATE_COUNT,
                policyReference: keccak256("unfinalized-cycle")
            })
        );
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(setupAuthority));

        address[] memory members = new address[](1);
        members[0] = WALLET_ONE;

        vm.expectRevert(InitialSetupAuthority.InvalidSetupInput.selector);
        setupAuthority.seedCongressTerm(members);
    }

    function _configureCitizen(bytes32 personId, address wallet, uint256 activeStake) private {
        setupAuthority.configureCitizen(
            personId,
            wallet,
            IdentityTypes.IdentityRecordInput({
                metadataHash: keccak256(abi.encode(personId, wallet)),
                metadataURI: "ipfs://citizen",
                verificationStatus: IdentityTypes.VerificationStatus.Verified,
                citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                ageClass: IdentityTypes.AgeClass.Adult,
                correctionFlag: false,
                finalSuspension: false
            }),
            activeStake
        );
    }

    function _wireSetupAuthority() private {
        kernel.bootstrapSetModule(KernelModuleIds.INITIAL_SETUP_AUTHORITY, address(setupAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(setupAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(setupAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(setupAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY, address(setupAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(setupAuthority));
    }
}
