// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {CongressElectionApp} from "../contracts/apps/CongressElectionApp.sol";
import {OfficeExecutor} from "../contracts/apps/OfficeExecutor.sol";
import {PayoutQueue} from "../contracts/apps/PayoutQueue.sol";
import {PublicVetoApp} from "../contracts/apps/PublicVetoApp.sol";
import {ReferendumApp} from "../contracts/apps/ReferendumApp.sol";
import {SenateApp} from "../contracts/apps/SenateApp.sol";
import {TreasuryVault} from "../contracts/apps/TreasuryVault.sol";
import {ActionTimelock} from "../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../contracts/core/GovernanceRouter.sol";
import {KernelModuleIds} from "../contracts/libraries/KernelModuleIds.sol";
import {DemoCitizenGateway} from "../contracts/mocks/DemoCitizenGateway.sol";
import {DemoSetupAuthority} from "../contracts/mocks/DemoSetupAuthority.sol";
import {LLMToken} from "../contracts/mocks/LLMToken.sol";
import {MockModule} from "../contracts/mocks/MockModule.sol";
import {CandidateEligibilityPolicy} from "../contracts/policies/CandidateEligibilityPolicy.sol";
import {CitizenEligibilityPolicy} from "../contracts/policies/CitizenEligibilityPolicy.sol";
import {CongressElectionPolicy} from "../contracts/policies/CongressElectionPolicy.sol";
import {OfficePermissionPolicy} from "../contracts/policies/OfficePermissionPolicy.sol";
import {ReferendumPolicy} from "../contracts/policies/ReferendumPolicy.sol";
import {SenatePowersPolicy} from "../contracts/policies/SenatePowersPolicy.sol";
import {TreasurySpendingPolicy} from "../contracts/policies/TreasurySpendingPolicy.sol";
import {UnstakingPolicy} from "../contracts/policies/UnstakingPolicy.sol";
import {VotingPowerPolicy} from "../contracts/policies/VotingPowerPolicy.sol";
import {BudgetEnvelopeRegistry} from "../contracts/registries/BudgetEnvelopeRegistry.sol";
import {CongressCandidateRegistry} from "../contracts/registries/CongressCandidateRegistry.sol";
import {IdentityRegistry} from "../contracts/registries/IdentityRegistry.sol";
import {LegislationRegistry} from "../contracts/registries/LegislationRegistry.sol";
import {OfficeRegistry} from "../contracts/registries/OfficeRegistry.sol";
import {ReferendumRegistry} from "../contracts/registries/ReferendumRegistry.sol";
import {SenateSeatRegistry} from "../contracts/registries/SenateSeatRegistry.sol";
import {StakeRegistry} from "../contracts/registries/StakeRegistry.sol";
import {ElectionTypes} from "../contracts/types/ElectionTypes.sol";
import {GovernanceTypes} from "../contracts/types/GovernanceTypes.sol";
import {LegislationTypes} from "../contracts/types/LegislationTypes.sol";
import {OfficeTypes} from "../contracts/types/OfficeTypes.sol";
import {ReferendumTypes} from "../contracts/types/ReferendumTypes.sol";
import {TreasuryTypes} from "../contracts/types/TreasuryTypes.sol";

contract DeployDemo is Script {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint256 internal constant MINIMUM_CANDIDATE_STAKE = 6_000;
    uint256 internal constant CANDIDATE_BOND_REQUIREMENT = 6_000;
    uint64 internal constant UNSTAKE_COOLDOWN = 1 days;
    uint64 internal constant MINIMUM_REFERENDUM_VOTING_DURATION = 3 days;
    uint256 internal constant CITIZEN_QUORUM = 10_000;
    uint256 internal constant CONGRESS_QUORUM = 8_000;
    uint256 internal constant CITIZEN_PROPOSAL_BOND = 6_000;
    uint256 internal constant CONSTITUTIONAL_FOR_VOTER_QUORUM = 2;
    uint16 internal constant CONSTITUTIONAL_FOR_STAKE_BPS = 5_000;
    uint32 internal constant CONGRESS_SEAT_COUNT = 2;
    uint32 internal constant CONGRESS_RUNNER_UP_COUNT = 2;
    uint32 internal constant CONGRESS_MAX_CANDIDATE_COUNT = 8;
    uint64 internal constant MINIMUM_NOMINATION_DURATION = 1 days;
    uint64 internal constant MINIMUM_ELECTION_VOTING_DURATION = 2 days;
    uint64 internal constant MAX_SCHEDULE_LEAD_TIME = 3 days;
    uint64 internal constant ELECTION_CYCLE_DURATION = 3 days;
    uint32 internal constant SENATE_CANCELLATION_THRESHOLD = 2;
    uint256 internal constant PUBLIC_VETO_THRESHOLD = 2;
    uint256 internal constant FINANCE_CLERK_OPERATIONS_LIMIT = 3 ether;
    uint256 internal constant FINANCE_CLERK_SALARY_LIMIT = 2 ether;
    uint256 internal constant DEMO_OPERATIONS_BUDGET_AMOUNT = 1 ether;

    bytes32 internal constant DEMO_PERSON_ONE = bytes32(uint256(1));
    bytes32 internal constant DEMO_PERSON_TWO = bytes32(uint256(2));
    bytes32 internal constant DEMO_PERSON_THREE = bytes32(uint256(3));
    bytes32 internal constant DEMO_PERSON_FOUR = bytes32(uint256(4));

    bytes32 internal constant ORDINARY_MEASURE_ID = keccak256("demo.measure.ordinary");
    bytes32 internal constant CONSTITUTIONAL_MEASURE_ID = keccak256("demo.measure.constitutional");
    bytes32 internal constant ACTIVE_REFERENDUM_ID = keccak256("demo.referendum.active");
    bytes32 internal constant FINALIZED_REFERENDUM_ID = keccak256("demo.referendum.finalized");
    bytes32 internal constant DEFEATED_MEASURE_ID = keccak256("demo.measure.defeated");
    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    bytes32 internal constant IDENTITY_OFFICE_ID = keccak256("office.identity");
    bytes32 internal constant LAND_OFFICE_ID = keccak256("office.land");
    bytes32 internal constant DEMO_FINANCE_BUDGET_ID = keccak256("demo.budget.finance.operations");
    uint256 internal constant DEMO_CONGRESS_CYCLE_ID = 1;

    ConstitutionKernel internal _kernel;
    ActionTimelock internal _timelock;
    GovernanceRouter internal _router;
    MockModule internal _identityAuthority;
    MockModule internal _stakeAuthority;
    IdentityRegistry internal _identityRegistry;
    StakeRegistry internal _stakeRegistry;
    LegislationRegistry internal _legislationRegistry;
    ReferendumRegistry internal _referendumRegistry;
    CongressCandidateRegistry internal _congressCandidateRegistry;
    SenateSeatRegistry internal _senateSeatRegistry;
    TreasuryVault internal _treasuryVault;
    BudgetEnvelopeRegistry internal _budgetEnvelopeRegistry;
    OfficeRegistry internal _officeRegistry;
    DemoSetupAuthority internal _demoAuthority;
    DemoCitizenGateway internal _demoCitizenGateway;
    LLMToken internal _llmToken;
    CitizenEligibilityPolicy internal _citizenEligibilityPolicy;
    UnstakingPolicy internal _unstakingPolicy;
    VotingPowerPolicy internal _votingPowerPolicy;
    CandidateEligibilityPolicy internal _candidateEligibilityPolicy;
    CongressElectionPolicy internal _congressElectionPolicy;
    ReferendumPolicy internal _referendumPolicy;
    SenatePowersPolicy internal _senatePowersPolicy;
    OfficePermissionPolicy internal _officePermissionPolicy;
    TreasurySpendingPolicy internal _treasurySpendingPolicy;
    CongressElectionApp internal _congressElectionApp;
    ReferendumApp internal _referendumApp;
    SenateApp internal _senateApp;
    PublicVetoApp internal _publicVetoApp;
    PayoutQueue internal _payoutQueue;
    OfficeExecutor internal _officeExecutor;

    address internal _financeOfficeAdmin;
    address internal _identityOfficeAdmin;
    address internal _landOfficeAdmin;
    address internal _financeClerk;
    uint256 internal _treasuryPrefundWei;

    struct Deployment {
        address deployer;
        address kernel;
        address timelock;
        address router;
        address demoAuthority;
        address demoCitizenGateway;
        address llmToken;
        address identityRegistry;
        address stakeRegistry;
        address legislationRegistry;
        address referendumRegistry;
        address congressCandidateRegistry;
        address senateSeatRegistry;
        address treasuryVault;
        address budgetEnvelopeRegistry;
        address officeRegistry;
        address citizenEligibilityPolicy;
        address unstakingPolicy;
        address votingPowerPolicy;
        address candidateEligibilityPolicy;
        address congressElectionPolicy;
        address referendumPolicy;
        address senatePowersPolicy;
        address officePermissionPolicy;
        address treasurySpendingPolicy;
        address congressElectionApp;
        address referendumApp;
        address senateApp;
        address publicVetoApp;
        address payoutQueue;
        address officeExecutor;
        bytes32 financeOfficeId;
        bytes32 identityOfficeId;
        bytes32 landOfficeId;
        bytes32 financeBudgetId;
        uint256 congressCycleId;
        uint64 congressNominationStart;
        uint64 congressVotingStart;
        uint64 congressVotingEnd;
        address financeOfficeAdmin;
        address identityOfficeAdmin;
        address landOfficeAdmin;
        address financeClerk;
        uint256 treasuryPrefundWei;
        uint256 meritReserveMinted;
    }

    function run() external returns (Deployment memory deployment) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        _financeOfficeAdmin = vm.envOr("FINANCE_ADMIN", deployer);
        _identityOfficeAdmin = vm.envOr("IDENTITY_ADMIN", address(0xB0B));
        _landOfficeAdmin = vm.envOr("LAND_ADMIN", address(0xCAFE));
        _financeClerk = vm.envOr("FINANCE_CLERK", address(0xD00D));
        _treasuryPrefundWei = vm.envOr("TREASURY_PREFUND_WEI", uint256(0));

        vm.startBroadcast(deployerPrivateKey);

        _deployCore(deployer);
        _deployRegistries();
        _deployDemoAuthority(deployer);
        _deployPoliciesAndApps(deployer);
        _registerBootstrapModules();
        _seedDemoState(deployer);
        _switchToFinalDemoWiring();
        _prefundTreasuryIfConfigured();
        _officeExecutor.disableBootstrapAuthority();
        _router.disableBootstrapAuthority();
        _kernel.disableBootstrapAuthority();

        vm.stopBroadcast();

        deployment = _snapshot(deployer);
        _writeDeploymentJson(deployment);
        _logDeployment(deployment);
    }

    function _deployCore(address deployer) internal {
        _kernel = new ConstitutionKernel(deployer);
        _timelock = new ActionTimelock(address(_kernel));
        _router = new GovernanceRouter(address(_kernel), deployer);
        _identityAuthority = new MockModule(keccak256("demo.identity-authority"));
        _stakeAuthority = new MockModule(keccak256("demo.stake-authority"));

        _kernel.bootstrapSetModule(KernelModuleIds.GOVERNANCE_ROUTER, address(_router));
        _kernel.bootstrapSetModule(KernelModuleIds.ACTION_TIMELOCK, address(_timelock));
    }

    function _deployRegistries() internal {
        _identityRegistry = new IdentityRegistry(address(_kernel));
        _stakeRegistry = new StakeRegistry(address(_kernel));
        _legislationRegistry = new LegislationRegistry(address(_kernel));
        _referendumRegistry = new ReferendumRegistry(address(_kernel));
        _congressCandidateRegistry = new CongressCandidateRegistry(address(_kernel));
        _senateSeatRegistry = new SenateSeatRegistry(address(_kernel));
        _treasuryVault = new TreasuryVault(address(_kernel));
        _budgetEnvelopeRegistry = new BudgetEnvelopeRegistry(address(_kernel));
        _officeRegistry = new OfficeRegistry(address(_kernel));
    }

    function _deployDemoAuthority(address deployer) internal {
        _demoAuthority = new DemoSetupAuthority(
            deployer,
            address(_identityRegistry),
            address(_stakeRegistry),
            address(_legislationRegistry),
            address(_referendumRegistry),
            address(_congressCandidateRegistry),
            address(_officeRegistry),
            address(_budgetEnvelopeRegistry)
        );
    }

    function _deployPoliciesAndApps(address deployer) internal {
        _llmToken = new LLMToken();
        _citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(_identityRegistry), address(_stakeRegistry), MINIMUM_CITIZEN_STAKE);
        _unstakingPolicy = new UnstakingPolicy(address(_stakeRegistry), UNSTAKE_COOLDOWN);
        _demoCitizenGateway = new DemoCitizenGateway(
            address(_identityRegistry),
            address(_stakeRegistry),
            address(_unstakingPolicy),
            address(_llmToken),
            _identityOfficeAdmin
        );
        _votingPowerPolicy = new VotingPowerPolicy(
            address(_identityRegistry), address(_stakeRegistry), address(_citizenEligibilityPolicy)
        );
        _candidateEligibilityPolicy = new CandidateEligibilityPolicy(
            address(_identityRegistry),
            address(_stakeRegistry),
            address(_citizenEligibilityPolicy),
            MINIMUM_CANDIDATE_STAKE
        );
        _congressElectionPolicy = new CongressElectionPolicy(
            address(_candidateEligibilityPolicy),
            address(_votingPowerPolicy),
            CONGRESS_SEAT_COUNT,
            CONGRESS_RUNNER_UP_COUNT,
            CONGRESS_MAX_CANDIDATE_COUNT,
            CANDIDATE_BOND_REQUIREMENT,
            MINIMUM_NOMINATION_DURATION,
            MINIMUM_ELECTION_VOTING_DURATION,
            MAX_SCHEDULE_LEAD_TIME,
            ELECTION_CYCLE_DURATION
        );
        _congressElectionApp = new CongressElectionApp(
            address(_identityRegistry),
            address(_congressCandidateRegistry),
            address(_candidateEligibilityPolicy),
            address(_congressElectionPolicy)
        );
        _referendumPolicy = new ReferendumPolicy(
            address(_citizenEligibilityPolicy),
            address(_votingPowerPolicy),
            address(_congressElectionApp),
            MINIMUM_REFERENDUM_VOTING_DURATION,
            0,
            0,
            CITIZEN_QUORUM,
            CONGRESS_QUORUM,
            CITIZEN_PROPOSAL_BOND,
            CONSTITUTIONAL_FOR_VOTER_QUORUM,
            CONSTITUTIONAL_FOR_STAKE_BPS
        );
        _referendumApp = new ReferendumApp(
            address(_identityRegistry),
            address(_legislationRegistry),
            address(_referendumRegistry),
            address(_referendumPolicy),
            address(_router),
            address(_votingPowerPolicy)
        );
        _senatePowersPolicy = new SenatePowersPolicy(SENATE_CANCELLATION_THRESHOLD);
        _senateApp = new SenateApp(
            address(_identityRegistry),
            address(_senateSeatRegistry),
            address(_senatePowersPolicy),
            address(_router),
            address(_timelock)
        );
        _publicVetoApp =
            new PublicVetoApp(address(_legislationRegistry), address(_citizenEligibilityPolicy), PUBLIC_VETO_THRESHOLD);
        _officePermissionPolicy = new OfficePermissionPolicy();
        _treasurySpendingPolicy =
            new TreasurySpendingPolicy(FINANCE_OFFICE_ID, FINANCE_CLERK_OPERATIONS_LIMIT, FINANCE_CLERK_SALARY_LIMIT);
        _payoutQueue = new PayoutQueue(address(_kernel), address(_budgetEnvelopeRegistry));
        _officeExecutor = new OfficeExecutor(
            address(_officeRegistry),
            address(_officePermissionPolicy),
            address(_treasurySpendingPolicy),
            address(_payoutQueue),
            address(_router),
            deployer
        );
    }

    function _registerBootstrapModules() internal {
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_demoAuthority));
        _kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(_demoAuthority));
        _kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(_demoAuthority));
        _kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(_demoAuthority));
        _kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(_demoAuthority));
        _kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(_demoAuthority));
        _kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(_demoAuthority));

        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(_identityRegistry));
        _kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY, address(_stakeRegistry));
        _kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY, address(_legislationRegistry));
        _kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY, address(_referendumRegistry));
        _kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY, address(_congressCandidateRegistry));
        _kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY, address(_senateSeatRegistry));
        _kernel.bootstrapSetModule(KernelModuleIds.TREASURY_VAULT, address(_treasuryVault));
        _kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY, address(_budgetEnvelopeRegistry));
        _kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY, address(_officeRegistry));

        _kernel.bootstrapSetModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY, address(_citizenEligibilityPolicy));
        _kernel.bootstrapSetModule(KernelModuleIds.UNSTAKING_POLICY, address(_unstakingPolicy));
        _kernel.bootstrapSetModule(KernelModuleIds.VOTING_POWER_POLICY, address(_votingPowerPolicy));
        _kernel.bootstrapSetModule(KernelModuleIds.CANDIDATE_ELIGIBILITY_POLICY, address(_candidateEligibilityPolicy));
        _kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_POLICY, address(_congressElectionPolicy));
        _kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_POLICY, address(_referendumPolicy));
        _kernel.bootstrapSetModule(KernelModuleIds.SENATE_POWERS_POLICY, address(_senatePowersPolicy));
        _kernel.bootstrapSetModule(KernelModuleIds.OFFICE_PERMISSION_POLICY, address(_officePermissionPolicy));
        _kernel.bootstrapSetModule(KernelModuleIds.TREASURY_SPENDING_POLICY, address(_treasurySpendingPolicy));

        _kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_APP, address(_congressElectionApp));
        _kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_APP, address(_referendumApp));
        _kernel.bootstrapSetModule(KernelModuleIds.SENATE_APP, address(_senateApp));
        _kernel.bootstrapSetModule(KernelModuleIds.PUBLIC_VETO_APP, address(_publicVetoApp));
        _kernel.bootstrapSetModule(KernelModuleIds.PAYOUT_QUEUE, address(_payoutQueue));
        _kernel.bootstrapSetModule(KernelModuleIds.OFFICE_EXECUTOR, address(_officeExecutor));
        _kernel.bootstrapSetModule(KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY, address(_senateApp));
        _kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REPEAL_AUTHORITY, address(_publicVetoApp));
    }

    function _seedDemoState(address deployer) internal {
        address walletTwo = address(0xB0B);
        address walletThree = address(0xCAFE);
        address walletFour = address(0xD00D);

        _demoAuthority.seedCitizen(
            DEMO_PERSON_ONE, deployer, 20_000, "ipfs://demo/citizen-one.json", keccak256("demo-citizen-one")
        );
        _demoAuthority.seedCitizen(
            DEMO_PERSON_TWO, walletTwo, 7_500, "ipfs://demo/citizen-two.json", keccak256("demo-citizen-two")
        );
        _demoAuthority.seedCitizen(
            DEMO_PERSON_THREE, walletThree, 12_000, "ipfs://demo/citizen-three.json", keccak256("demo-citizen-three")
        );
        _demoAuthority.seedCitizen(
            DEMO_PERSON_FOUR, walletFour, 5_500, "ipfs://demo/citizen-four.json", keccak256("demo-citizen-four")
        );
        _demoAuthority.setProtectedStakeFloor(DEMO_PERSON_ONE, 5_000);
        _seedCongressElection(deployer, walletTwo, walletThree, walletFour);

        _demoAuthority.seedLegislation(
            ORDINARY_MEASURE_ID,
            LegislationTypes.LegislationRecordInput({
                tier: LegislationTypes.LegislationTier.OrdinaryLaw,
                textHash: keccak256("demo-law-ordinary"),
                proposerReference: DEMO_PERSON_ONE,
                enactedByReferendumId: keccak256("demo-law-ordinary-referendum"),
                amendsMeasureId: bytes32(0)
            })
        );
        _demoAuthority.seedLegislation(
            CONSTITUTIONAL_MEASURE_ID,
            LegislationTypes.LegislationRecordInput({
                tier: LegislationTypes.LegislationTier.ConstitutionalLaw,
                textHash: keccak256("demo-law-constitutional"),
                proposerReference: DEMO_PERSON_THREE,
                enactedByReferendumId: keccak256("demo-law-constitutional-referendum"),
                amendsMeasureId: bytes32(0)
            })
        );

        _demoAuthority.seedReferendum(
            ACTIVE_REFERENDUM_ID,
            ReferendumTypes.ReferendumRecordInput({
                referendumClass: ReferendumTypes.ReferendumClass.Legislation,
                proposalOrigin: ReferendumTypes.ProposalOrigin.Citizen,
                proposalMetadataHash: keccak256("demo-active-referendum"),
                proposedMeasureId: keccak256("demo-active-measure"),
                amendsMeasureId: bytes32(0),
                legislationTextHash: keccak256("demo-active-law-text"),
                legislationTier: LegislationTypes.LegislationTier.OrdinaryLaw,
                targetModule: bytes32(0),
                proposedModuleAddress: address(0),
                proposerReference: DEMO_PERSON_ONE,
                startTime: uint64(block.timestamp - 1 days),
                endTime: uint64(block.timestamp + 5 days)
            })
        );
        _demoAuthority.seedReferendumVote(ACTIVE_REFERENDUM_ID, deployer, ReferendumTypes.VoteOption.For, 20_000);
        _demoAuthority.seedReferendumVote(ACTIVE_REFERENDUM_ID, walletThree, ReferendumTypes.VoteOption.Against, 12_000);

        _demoAuthority.seedReferendum(
            FINALIZED_REFERENDUM_ID,
            ReferendumTypes.ReferendumRecordInput({
                referendumClass: ReferendumTypes.ReferendumClass.Legislation,
                proposalOrigin: ReferendumTypes.ProposalOrigin.Citizen,
                proposalMetadataHash: keccak256("demo-finalized-referendum"),
                proposedMeasureId: DEFEATED_MEASURE_ID,
                amendsMeasureId: bytes32(0),
                legislationTextHash: keccak256("demo-defeated-law-text"),
                legislationTier: LegislationTypes.LegislationTier.OrdinaryLaw,
                targetModule: bytes32(0),
                proposedModuleAddress: address(0),
                proposerReference: DEMO_PERSON_TWO,
                startTime: uint64(block.timestamp - 10 days),
                endTime: uint64(block.timestamp - 5 days)
            })
        );
        _demoAuthority.finalizeReferendum(
            FINALIZED_REFERENDUM_ID,
            ReferendumTypes.ReferendumResultInput({
                turnout: 0,
                quorumRequired: CITIZEN_QUORUM,
                headcountQuorumRequired: 0,
                electorateVotingPower: 0,
                quorumMet: false,
                passed: false,
                enactedMeasureId: bytes32(0),
                enactmentActionId: bytes32(0)
            })
        );

        _demoAuthority.seedOffice(
            FINANCE_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "Ministry of Finance", _financeOfficeAdmin
        );
        _demoAuthority.seedOffice(
            IDENTITY_OFFICE_ID, OfficeTypes.OfficeKind.IdentityOffice, "Identity Office", _identityOfficeAdmin
        );
        _demoAuthority.seedOffice(
            LAND_OFFICE_ID, OfficeTypes.OfficeKind.LandRegistryOffice, "Land Registry Office", _landOfficeAdmin
        );
        _demoAuthority.seedClerk(FINANCE_OFFICE_ID, _financeClerk, true);

        _demoAuthority.seedBudget(
            DEMO_FINANCE_BUDGET_ID,
            TreasuryTypes.BudgetEnvelopeInput({
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(0),
                allocatedAmount: DEMO_OPERATIONS_BUDGET_AMOUNT,
                startsAt: uint64(block.timestamp - 1 hours),
                endsAt: uint64(block.timestamp + 30 days),
                policyReference: _treasurySpendingPolicy.computePolicyReference(
                    FINANCE_OFFICE_ID,
                    OfficeTypes.OfficeRole.Admin,
                    TreasuryTypes.DisbursementType.Operations,
                    DEMO_OPERATIONS_BUDGET_AMOUNT
                )
            })
        );

        _senateApp.bootstrapAssignSeat(0, deployer);
        _senateApp.bootstrapAssignSeat(1, walletThree);

        _publicVetoApp.castPublicVeto(ORDINARY_MEASURE_ID);
        _llmToken.mint(address(_demoCitizenGateway), 45_000);
    }

    function _seedCongressElection(address deployer, address walletTwo, address walletThree, address walletFour)
        internal
    {
        uint64 votingStart = uint64(block.timestamp - 1 hours);
        uint64 nominationStart = votingStart - MINIMUM_NOMINATION_DURATION;
        uint64 votingEnd = votingStart + MINIMUM_ELECTION_VOTING_DURATION;

        _demoAuthority.seedCongressCycle(
            DEMO_CONGRESS_CYCLE_ID,
            ElectionTypes.CongressCycleInput({
                nominationStart: nominationStart,
                votingStart: votingStart,
                votingEnd: votingEnd,
                seatCount: _congressElectionPolicy.seatCount(),
                runnerUpCount: _congressElectionPolicy.runnerUpCount(),
                maxCandidateCount: _congressElectionPolicy.maxCandidateCount(),
                policyReference: _congressElectionPolicyReference()
            })
        );

        _demoAuthority.seedCongressCandidate(
            DEMO_CONGRESS_CYCLE_ID,
            deployer,
            DEMO_PERSON_ONE,
            keccak256("demo-congress-candidate-one"),
            "ipfs://demo/congress-candidate-one.json"
        );
        _demoAuthority.seedCongressCandidate(
            DEMO_CONGRESS_CYCLE_ID,
            walletTwo,
            DEMO_PERSON_TWO,
            keccak256("demo-congress-candidate-two"),
            "ipfs://demo/congress-candidate-two.json"
        );
        _demoAuthority.seedCongressCandidate(
            DEMO_CONGRESS_CYCLE_ID,
            walletThree,
            DEMO_PERSON_THREE,
            keccak256("demo-congress-candidate-three"),
            "ipfs://demo/congress-candidate-three.json"
        );
        _demoAuthority.seedCongressCandidate(
            DEMO_CONGRESS_CYCLE_ID,
            walletFour,
            DEMO_PERSON_FOUR,
            keccak256("demo-congress-candidate-four"),
            "ipfs://demo/congress-candidate-four.json"
        );

        _seedCongressBallot(deployer, walletThree, int256(12_000), deployer, int256(8_000), 20_000);
        _seedCongressBallot(walletTwo, walletTwo, int256(7_500), 7_500);
        _seedCongressBallot(walletThree, deployer, int256(8_000), walletTwo, int256(4_000), 12_000);
        _seedCongressBallot(walletFour, walletFour, int256(5_500), 5_500);
    }

    function _seedCongressBallot(address voter, address candidate, int256 allocation, uint256 ballotWeight) internal {
        _demoAuthority.seedCongressBallot(
            DEMO_CONGRESS_CYCLE_ID,
            voter,
            _asAddressArray(candidate),
            _asIntArray(allocation),
            ballotWeight,
            _congressElectionPolicy.maxPositiveCandidates(),
            _congressElectionPolicy.maxNegativeAllocation(voter)
        );
    }

    function _seedCongressBallot(
        address voter,
        address firstCandidate,
        int256 firstAllocation,
        address secondCandidate,
        int256 secondAllocation,
        uint256 ballotWeight
    ) internal {
        _demoAuthority.seedCongressBallot(
            DEMO_CONGRESS_CYCLE_ID,
            voter,
            _asAddressArray(firstCandidate, secondCandidate),
            _asIntArray(firstAllocation, secondAllocation),
            ballotWeight,
            _congressElectionPolicy.maxPositiveCandidates(),
            _congressElectionPolicy.maxNegativeAllocation(voter)
        );
    }

    function _switchToFinalDemoWiring() internal {
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_demoCitizenGateway));
        _kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(_demoCitizenGateway));
        _kernel.bootstrapSetModule(KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(_timelock));
        _kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(_referendumApp));
        _kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(_timelock));
        _kernel.bootstrapSetModule(KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, address(_payoutQueue));
        _kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(_officeExecutor));
        _kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(_congressElectionApp));

        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, address(_referendumApp));
        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Senate, address(_senateApp));
        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Office, address(_officeExecutor));
    }

    function _prefundTreasuryIfConfigured() internal {
        if (_treasuryPrefundWei == 0) {
            return;
        }

        (bool success,) = address(_treasuryVault).call{value: _treasuryPrefundWei}("");
        require(success, "treasury prefund failed");
    }

    function _congressElectionPolicyReference() internal view returns (bytes32 policyReference) {
        return keccak256(
            abi.encode(
                address(_congressElectionPolicy),
                _congressElectionPolicy.seatCount(),
                _congressElectionPolicy.runnerUpCount(),
                _congressElectionPolicy.maxCandidateCount(),
                _congressElectionPolicy.candidateBondRequirement(),
                _congressElectionPolicy.maxPositiveCandidates(),
                _congressElectionPolicy.minimumNominationDuration(),
                _congressElectionPolicy.minimumVotingDuration(),
                _congressElectionPolicy.maxScheduleLeadTime(),
                _congressElectionPolicy.cycleDuration()
            )
        );
    }

    function _asAddressArray(address first) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = first;
    }

    function _asAddressArray(address first, address second) internal pure returns (address[] memory values) {
        values = new address[](2);
        values[0] = first;
        values[1] = second;
    }

    function _asIntArray(int256 first) internal pure returns (int256[] memory values) {
        values = new int256[](1);
        values[0] = first;
    }

    function _asIntArray(int256 first, int256 second) internal pure returns (int256[] memory values) {
        values = new int256[](2);
        values[0] = first;
        values[1] = second;
    }

    function _snapshot(address deployer) internal view returns (Deployment memory deployment) {
        deployment.deployer = deployer;
        deployment.kernel = address(_kernel);
        deployment.timelock = address(_timelock);
        deployment.router = address(_router);
        deployment.demoAuthority = address(_demoAuthority);
        deployment.demoCitizenGateway = address(_demoCitizenGateway);
        deployment.llmToken = address(_llmToken);
        deployment.identityRegistry = address(_identityRegistry);
        deployment.stakeRegistry = address(_stakeRegistry);
        deployment.legislationRegistry = address(_legislationRegistry);
        deployment.referendumRegistry = address(_referendumRegistry);
        deployment.congressCandidateRegistry = address(_congressCandidateRegistry);
        deployment.senateSeatRegistry = address(_senateSeatRegistry);
        deployment.treasuryVault = address(_treasuryVault);
        deployment.budgetEnvelopeRegistry = address(_budgetEnvelopeRegistry);
        deployment.officeRegistry = address(_officeRegistry);
        deployment.citizenEligibilityPolicy = address(_citizenEligibilityPolicy);
        deployment.unstakingPolicy = address(_unstakingPolicy);
        deployment.votingPowerPolicy = address(_votingPowerPolicy);
        deployment.candidateEligibilityPolicy = address(_candidateEligibilityPolicy);
        deployment.congressElectionPolicy = address(_congressElectionPolicy);
        deployment.referendumPolicy = address(_referendumPolicy);
        deployment.senatePowersPolicy = address(_senatePowersPolicy);
        deployment.officePermissionPolicy = address(_officePermissionPolicy);
        deployment.treasurySpendingPolicy = address(_treasurySpendingPolicy);
        deployment.congressElectionApp = address(_congressElectionApp);
        deployment.referendumApp = address(_referendumApp);
        deployment.senateApp = address(_senateApp);
        deployment.publicVetoApp = address(_publicVetoApp);
        deployment.payoutQueue = address(_payoutQueue);
        deployment.officeExecutor = address(_officeExecutor);
        deployment.financeOfficeId = FINANCE_OFFICE_ID;
        deployment.identityOfficeId = IDENTITY_OFFICE_ID;
        deployment.landOfficeId = LAND_OFFICE_ID;
        deployment.financeBudgetId = DEMO_FINANCE_BUDGET_ID;
        ElectionTypes.CongressCycleRecord memory congressCycle =
            _congressCandidateRegistry.getCycle(DEMO_CONGRESS_CYCLE_ID);
        deployment.congressCycleId = congressCycle.cycleId;
        deployment.congressNominationStart = congressCycle.nominationStart;
        deployment.congressVotingStart = congressCycle.votingStart;
        deployment.congressVotingEnd = congressCycle.votingEnd;
        deployment.financeOfficeAdmin = _financeOfficeAdmin;
        deployment.identityOfficeAdmin = _identityOfficeAdmin;
        deployment.landOfficeAdmin = _landOfficeAdmin;
        deployment.financeClerk = _financeClerk;
        deployment.treasuryPrefundWei = _treasuryPrefundWei;
        deployment.meritReserveMinted = _llmToken.balanceOf(address(_demoCitizenGateway));
    }

    function _writeDeploymentJson(Deployment memory deployment) internal {
        string memory deploymentKey = "deployment";

        vm.serializeUint(deploymentKey, "chainId", block.chainid);
        vm.serializeAddress(deploymentKey, "deployer", deployment.deployer);
        vm.serializeAddress(deploymentKey, "constitutionKernel", deployment.kernel);
        vm.serializeAddress(deploymentKey, "actionTimelock", deployment.timelock);
        vm.serializeAddress(deploymentKey, "governanceRouter", deployment.router);
        vm.serializeAddress(deploymentKey, "demoAuthority", deployment.demoAuthority);
        vm.serializeAddress(deploymentKey, "demoCitizenGateway", deployment.demoCitizenGateway);
        vm.serializeAddress(deploymentKey, "llmToken", deployment.llmToken);
        vm.serializeAddress(deploymentKey, "identityRegistry", deployment.identityRegistry);
        vm.serializeAddress(deploymentKey, "stakeRegistry", deployment.stakeRegistry);
        vm.serializeAddress(deploymentKey, "legislationRegistry", deployment.legislationRegistry);
        vm.serializeAddress(deploymentKey, "referendumRegistry", deployment.referendumRegistry);
        vm.serializeAddress(deploymentKey, "congressCandidateRegistry", deployment.congressCandidateRegistry);
        vm.serializeAddress(deploymentKey, "senateSeatRegistry", deployment.senateSeatRegistry);
        vm.serializeAddress(deploymentKey, "treasuryVault", deployment.treasuryVault);
        vm.serializeAddress(deploymentKey, "budgetEnvelopeRegistry", deployment.budgetEnvelopeRegistry);
        vm.serializeAddress(deploymentKey, "officeRegistry", deployment.officeRegistry);
        vm.serializeAddress(deploymentKey, "citizenEligibilityPolicy", deployment.citizenEligibilityPolicy);
        vm.serializeAddress(deploymentKey, "unstakingPolicy", deployment.unstakingPolicy);
        vm.serializeAddress(deploymentKey, "votingPowerPolicy", deployment.votingPowerPolicy);
        vm.serializeAddress(deploymentKey, "candidateEligibilityPolicy", deployment.candidateEligibilityPolicy);
        vm.serializeAddress(deploymentKey, "congressElectionPolicy", deployment.congressElectionPolicy);
        vm.serializeAddress(deploymentKey, "referendumPolicy", deployment.referendumPolicy);
        vm.serializeAddress(deploymentKey, "senatePowersPolicy", deployment.senatePowersPolicy);
        vm.serializeAddress(deploymentKey, "officePermissionPolicy", deployment.officePermissionPolicy);
        vm.serializeAddress(deploymentKey, "treasurySpendingPolicy", deployment.treasurySpendingPolicy);
        vm.serializeAddress(deploymentKey, "congressElectionApp", deployment.congressElectionApp);
        vm.serializeAddress(deploymentKey, "referendumApp", deployment.referendumApp);
        vm.serializeAddress(deploymentKey, "senateApp", deployment.senateApp);
        vm.serializeAddress(deploymentKey, "publicVetoApp", deployment.publicVetoApp);
        vm.serializeAddress(deploymentKey, "payoutQueue", deployment.payoutQueue);
        vm.serializeAddress(deploymentKey, "officeExecutor", deployment.officeExecutor);
        vm.serializeBytes32(deploymentKey, "financeOfficeId", deployment.financeOfficeId);
        vm.serializeBytes32(deploymentKey, "identityOfficeId", deployment.identityOfficeId);
        vm.serializeBytes32(deploymentKey, "landOfficeId", deployment.landOfficeId);
        vm.serializeBytes32(deploymentKey, "financeBudgetId", deployment.financeBudgetId);
        vm.serializeUint(deploymentKey, "congressCycleId", deployment.congressCycleId);
        vm.serializeUint(deploymentKey, "congressNominationStart", deployment.congressNominationStart);
        vm.serializeUint(deploymentKey, "congressVotingStart", deployment.congressVotingStart);
        vm.serializeUint(deploymentKey, "congressVotingEnd", deployment.congressVotingEnd);
        vm.serializeAddress(deploymentKey, "financeOfficeAdmin", deployment.financeOfficeAdmin);
        vm.serializeAddress(deploymentKey, "identityOfficeAdmin", deployment.identityOfficeAdmin);
        vm.serializeAddress(deploymentKey, "landOfficeAdmin", deployment.landOfficeAdmin);
        vm.serializeAddress(deploymentKey, "financeClerk", deployment.financeClerk);
        vm.serializeUint(deploymentKey, "treasuryPrefundWei", deployment.treasuryPrefundWei);
        string memory json = vm.serializeUint(deploymentKey, "meritReserveMinted", deployment.meritReserveMinted);

        string memory path = string.concat(vm.projectRoot(), "/deployments/sepolia-demo.json");
        vm.writeJson(json, path);
    }

    function _logDeployment(Deployment memory deployment) internal view {
        console2.log("Deployer:", deployment.deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("ConstitutionKernel:", deployment.kernel);
        console2.log("ActionTimelock:", deployment.timelock);
        console2.log("GovernanceRouter:", deployment.router);
        console2.log("DemoSetupAuthority:", deployment.demoAuthority);
        console2.log("DemoCitizenGateway:", deployment.demoCitizenGateway);
        console2.log("LLMToken:", deployment.llmToken);
        console2.log("IdentityRegistry:", deployment.identityRegistry);
        console2.log("StakeRegistry:", deployment.stakeRegistry);
        console2.log("LegislationRegistry:", deployment.legislationRegistry);
        console2.log("ReferendumRegistry:", deployment.referendumRegistry);
        console2.log("CongressCandidateRegistry:", deployment.congressCandidateRegistry);
        console2.log("SenateSeatRegistry:", deployment.senateSeatRegistry);
        console2.log("TreasuryVault:", deployment.treasuryVault);
        console2.log("BudgetEnvelopeRegistry:", deployment.budgetEnvelopeRegistry);
        console2.log("OfficeRegistry:", deployment.officeRegistry);
        console2.log("OfficePermissionPolicy:", deployment.officePermissionPolicy);
        console2.log("TreasurySpendingPolicy:", deployment.treasurySpendingPolicy);
        console2.log("PayoutQueue:", deployment.payoutQueue);
        console2.log("OfficeExecutor:", deployment.officeExecutor);
        console2.logBytes32(deployment.financeOfficeId);
        console2.logBytes32(deployment.financeBudgetId);
        console2.log("Demo Congress Cycle ID:", deployment.congressCycleId);
        console2.log("Demo Congress Voting Start:", deployment.congressVotingStart);
        console2.log("Demo Congress Voting End:", deployment.congressVotingEnd);
        console2.log("Finance Office Admin:", deployment.financeOfficeAdmin);
        console2.log("Finance Clerk:", deployment.financeClerk);
        console2.log("Treasury Prefund Wei:", deployment.treasuryPrefundWei);
        console2.log("Merit Reserve Minted:", deployment.meritReserveMinted);
    }
}
