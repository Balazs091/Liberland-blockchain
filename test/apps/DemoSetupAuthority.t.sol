// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {DemoSetupAuthority} from "../../contracts/mocks/DemoSetupAuthority.sol";
import {BudgetEnvelopeRegistry} from "../../contracts/registries/BudgetEnvelopeRegistry.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {LegislationRegistry} from "../../contracts/registries/LegislationRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {ReferendumRegistry} from "../../contracts/registries/ReferendumRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {LegislationTypes} from "../../contracts/types/LegislationTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";
import {ReferendumTypes} from "../../contracts/types/ReferendumTypes.sol";
import {TreasuryTypes} from "../../contracts/types/TreasuryTypes.sol";

contract DemoSetupAuthorityTest is Test {
    bytes32 internal constant PERSON_ID = bytes32(uint256(1));
    bytes32 internal constant MEASURE_ID = keccak256("demo.measure");
    bytes32 internal constant REFERENDUM_ID = keccak256("demo.referendum");
    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    bytes32 internal constant BUDGET_ID = keccak256("demo.budget.operations");
    uint256 internal constant CONGRESS_CYCLE_ID = 1;

    ConstitutionKernel internal kernel;
    IdentityRegistry internal identityRegistry;
    StakeRegistry internal stakeRegistry;
    LegislationRegistry internal legislationRegistry;
    ReferendumRegistry internal referendumRegistry;
    CongressCandidateRegistry internal congressCandidateRegistry;
    OfficeRegistry internal officeRegistry;
    BudgetEnvelopeRegistry internal budgetEnvelopeRegistry;
    DemoSetupAuthority internal demoAuthority;

    address internal owner = address(this);
    address internal wallet = address(0xA11CE);

    function setUp() public {
        vm.warp(30 days);

        kernel = new ConstitutionKernel(owner);
        identityRegistry = new IdentityRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        legislationRegistry = new LegislationRegistry(address(kernel));
        referendumRegistry = new ReferendumRegistry(address(kernel));
        congressCandidateRegistry = new CongressCandidateRegistry(address(kernel));
        officeRegistry = new OfficeRegistry(address(kernel));
        budgetEnvelopeRegistry = new BudgetEnvelopeRegistry(address(kernel));
        demoAuthority = new DemoSetupAuthority(
            owner,
            address(identityRegistry),
            address(stakeRegistry),
            address(legislationRegistry),
            address(referendumRegistry),
            address(congressCandidateRegistry),
            address(officeRegistry),
            address(budgetEnvelopeRegistry)
        );

        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(demoAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(demoAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(demoAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(demoAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(demoAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(demoAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(demoAuthority));
    }

    function test_SeedCitizen_Legislation_Referendum_Office_AndBudget() public {
        demoAuthority.seedCitizen(PERSON_ID, wallet, 9_000, "ipfs://demo/person-1.json", keccak256("person-1"));

        IdentityTypes.IdentityRecord memory record = identityRegistry.getIdentityRecord(PERSON_ID);
        assertEq(uint8(record.verificationStatus), uint8(IdentityTypes.VerificationStatus.Verified));
        assertEq(uint8(record.citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.Citizen));
        assertEq(uint8(record.ageClass), uint8(IdentityTypes.AgeClass.Adult));
        assertEq(stakeRegistry.activeStakeOf(PERSON_ID), 9_000);
        assertEq(identityRegistry.resolveWalletToPersonId(wallet), PERSON_ID);

        demoAuthority.seedLegislation(
            MEASURE_ID,
            LegislationTypes.LegislationRecordInput({
                tier: LegislationTypes.LegislationTier.Law,
                textHash: keccak256("demo-law"),
                proposerReference: PERSON_ID,
                enactedByReferendumId: keccak256("demo-law-referendum"),
                amendsMeasureId: bytes32(0)
            })
        );

        assertTrue(legislationRegistry.legislationExists(MEASURE_ID));

        demoAuthority.seedReferendum(
            REFERENDUM_ID,
            ReferendumTypes.ReferendumRecordInput({
                referendumClass: ReferendumTypes.ReferendumClass.Legislation,
                proposalOrigin: ReferendumTypes.ProposalOrigin.Citizen,
                proposalMetadataHash: keccak256("demo-referendum"),
                proposedMeasureId: keccak256("demo-new-law"),
                amendsMeasureId: bytes32(0),
                legislationTextHash: keccak256("demo-new-law-text"),
                legislationTier: LegislationTypes.LegislationTier.Law,
                targetModule: bytes32(0),
                proposedModuleAddress: address(0),
                registerNewModule: false,
                proposerReference: PERSON_ID,
                startTime: uint64(block.timestamp - 1 days),
                endTime: uint64(block.timestamp + 1 days),
                adoptionDelay: 7 days,
                electorateHeadcountSnapshot: 0,
                electorateVotingPowerSnapshot: 0,
                requiresSupermajority: false
            })
        );
        demoAuthority.seedReferendumVote(REFERENDUM_ID, wallet, ReferendumTypes.VoteOption.For, 9_000);

        ReferendumTypes.ReferendumRecord memory referendum = referendumRegistry.getReferendum(REFERENDUM_ID);
        assertEq(referendum.forVotes, 9_000);
        assertEq(referendum.voterCount, 1);

        demoAuthority.seedCongressCycle(
            CONGRESS_CYCLE_ID,
            ElectionTypes.CongressCycleInput({
                nominationStart: uint64(block.timestamp - 25 hours),
                votingStart: uint64(block.timestamp - 1 hours),
                votingEnd: uint64(block.timestamp + 47 hours),
                seatCount: 1,
                runnerUpCount: 1,
                maxCandidateCount: 2,
                policyReference: keccak256("demo-election-policy")
            })
        );
        demoAuthority.seedCongressCandidate(
            CONGRESS_CYCLE_ID, wallet, PERSON_ID, keccak256("candidate-one"), "ipfs://demo/candidate-one.json"
        );
        demoAuthority.seedCongressBallot(
            CONGRESS_CYCLE_ID, wallet, _asAddressArray(wallet), _asIntArray(int256(9_000)), 9_000, 1, 3_000
        );

        ElectionTypes.CongressCycleRecord memory cycle = congressCandidateRegistry.getCycle(CONGRESS_CYCLE_ID);
        assertEq(uint8(cycle.status), uint8(ElectionTypes.ElectionStatus.Voting));
        assertEq(cycle.candidateCount, 1);
        assertEq(congressCandidateRegistry.getCandidate(CONGRESS_CYCLE_ID, wallet).voteTotal, int256(9_000));
        assertEq(congressCandidateRegistry.getBallotReceipt(CONGRESS_CYCLE_ID, wallet).ballotWeight, 9_000);

        demoAuthority.seedOffice(
            FINANCE_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "Ministry of Finance", owner
        );
        demoAuthority.seedClerk(FINANCE_OFFICE_ID, wallet, true);

        OfficeTypes.OfficeRecord memory officeRecord = officeRegistry.getOfficeRecord(FINANCE_OFFICE_ID);
        assertEq(uint8(officeRecord.kind), uint8(OfficeTypes.OfficeKind.MinistryOfFinance));
        assertEq(officeRecord.admin, owner);
        assertEq(uint8(officeRegistry.roleOf(FINANCE_OFFICE_ID, owner)), uint8(OfficeTypes.OfficeRole.Admin));
        assertEq(uint8(officeRegistry.roleOf(FINANCE_OFFICE_ID, wallet)), uint8(OfficeTypes.OfficeRole.Clerk));

        demoAuthority.seedBudget(
            BUDGET_ID,
            TreasuryTypes.BudgetEnvelopeInput({
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(0),
                allocatedAmount: 25 ether,
                startsAt: uint64(block.timestamp - 1 days),
                endsAt: uint64(block.timestamp + 30 days),
                policyReference: keccak256("demo-budget-policy")
            })
        );

        TreasuryTypes.BudgetEnvelope memory budgetEnvelope = budgetEnvelopeRegistry.getBudgetEnvelope(BUDGET_ID);
        assertEq(budgetEnvelope.officeId, FINANCE_OFFICE_ID);
        assertEq(uint8(budgetEnvelope.disbursementType), uint8(TreasuryTypes.DisbursementType.Operations));
        assertEq(budgetEnvelope.allocatedAmount, 25 ether);
        assertEq(uint8(budgetEnvelope.status), uint8(TreasuryTypes.BudgetStatus.Active));
    }

    function _asAddressArray(address first) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = first;
    }

    function _asIntArray(int256 first) internal pure returns (int256[] memory values) {
        values = new int256[](1);
        values[0] = first;
    }
}
