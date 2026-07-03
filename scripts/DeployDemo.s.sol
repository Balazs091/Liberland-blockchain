// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {CabinetApp} from "../contracts/apps/CabinetApp.sol";
import {CompanyRegistryApp} from "../contracts/apps/CompanyRegistryApp.sol";
import {CongressElectionApp} from "../contracts/apps/CongressElectionApp.sol";
import {DecisionApp} from "../contracts/apps/DecisionApp.sol";
import {HeadOfStateApp} from "../contracts/apps/HeadOfStateApp.sol";
import {IdentityApp} from "../contracts/apps/IdentityApp.sol";
import {LandRegistryApp} from "../contracts/apps/LandRegistryApp.sol";
import {MinistryTreasury} from "../contracts/apps/MinistryTreasury.sol";
import {OfficeExecutor} from "../contracts/apps/OfficeExecutor.sol";
import {PayoutQueue} from "../contracts/apps/PayoutQueue.sol";
import {PublicVetoApp} from "../contracts/apps/PublicVetoApp.sol";
import {ReferendumApp} from "../contracts/apps/ReferendumApp.sol";
import {SenateApp} from "../contracts/apps/SenateApp.sol";
import {TreasuryVault} from "../contracts/apps/TreasuryVault.sol";
import {USDCLendingPoolApp} from "../contracts/apps/USDCLendingPoolApp.sol";
import {ActionTimelock} from "../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../contracts/core/GovernanceRouter.sol";
import {KernelModuleIds} from "../contracts/libraries/KernelModuleIds.sol";
import {ITreasurySpendingPolicy} from "../contracts/interfaces/ITreasurySpendingPolicy.sol";
import {DemoCitizenGateway} from "../contracts/mocks/DemoCitizenGateway.sol";
import {DemoSetupAuthority} from "../contracts/mocks/DemoSetupAuthority.sol";
import {LLMToken} from "../contracts/mocks/LLMToken.sol";
import {MockUSDC} from "../contracts/mocks/MockUSDC.sol";
import {CandidateEligibilityPolicy} from "../contracts/policies/CandidateEligibilityPolicy.sol";
import {CitizenEligibilityPolicy} from "../contracts/policies/CitizenEligibilityPolicy.sol";
import {CongressElectionPolicy} from "../contracts/policies/CongressElectionPolicy.sol";
import {FixedLlmUsdcPriceOraclePolicy} from "../contracts/policies/FixedLlmUsdcPriceOraclePolicy.sol";
import {KinkedInterestRatePolicy} from "../contracts/policies/KinkedInterestRatePolicy.sol";
import {LendingRiskParameterPolicy} from "../contracts/policies/LendingRiskParameterPolicy.sol";
import {OfficePermissionPolicy} from "../contracts/policies/OfficePermissionPolicy.sol";
import {ReferendumPolicy} from "../contracts/policies/ReferendumPolicy.sol";
import {SenatePowersPolicy} from "../contracts/policies/SenatePowersPolicy.sol";
import {TreasurySpendingPolicy} from "../contracts/policies/TreasurySpendingPolicy.sol";
import {UnstakingPolicy} from "../contracts/policies/UnstakingPolicy.sol";
import {VotingPowerPolicy} from "../contracts/policies/VotingPowerPolicy.sol";
import {BudgetEnvelopeRegistry} from "../contracts/registries/BudgetEnvelopeRegistry.sol";
import {CongressCandidateRegistry} from "../contracts/registries/CongressCandidateRegistry.sol";
import {CompanyRegistry} from "../contracts/registries/CompanyRegistry.sol";
import {ExecutiveRegistry} from "../contracts/registries/ExecutiveRegistry.sol";
import {IdentityRegistry} from "../contracts/registries/IdentityRegistry.sol";
import {LandRegistry} from "../contracts/registries/LandRegistry.sol";
import {LegislationRegistry} from "../contracts/registries/LegislationRegistry.sol";
import {OfficeRegistry} from "../contracts/registries/OfficeRegistry.sol";
import {PresidentRegistry} from "../contracts/registries/PresidentRegistry.sol";
import {ReferendumRegistry} from "../contracts/registries/ReferendumRegistry.sol";
import {SenateSeatRegistry} from "../contracts/registries/SenateSeatRegistry.sol";
import {StakeLienRegistry} from "../contracts/registries/StakeLienRegistry.sol";
import {StakeRegistry} from "../contracts/registries/StakeRegistry.sol";
import {ElectionTypes} from "../contracts/types/ElectionTypes.sol";
import {GovernanceTypes} from "../contracts/types/GovernanceTypes.sol";
import {LegislationTypes} from "../contracts/types/LegislationTypes.sol";
import {OfficeTypes} from "../contracts/types/OfficeTypes.sol";
import {ReferendumTypes} from "../contracts/types/ReferendumTypes.sol";
import {TreasuryTypes} from "../contracts/types/TreasuryTypes.sol";

contract DeployDemo is Script {
    // One whole LLM in base units. LLM uses the standard 18 ERC20 decimals, so every LLM-denominated amount
    // (stakes, bonds, and the stake-derived voting-power quorums and ballot weights) is written as whole LLM * ONE_LLM.
    // ONE_LLM_SIGNED is the same unit for signed Congress ballot allocations (which may be negative).
    uint256 internal constant ONE_LLM = 10 ** 18;
    int256 internal constant ONE_LLM_SIGNED = 10 ** 18;
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000 * ONE_LLM;
    uint256 internal constant MINIMUM_CANDIDATE_STAKE = 6_000 * ONE_LLM;
    uint256 internal constant CANDIDATE_BOND_REQUIREMENT = 6_000 * ONE_LLM;
    uint64 internal constant WELFARE_PERIOD = 30 days;
    // 1064 bps (10.64%/yr): with the 30-day compounding unstake portion, twelve 30-day unstakes release ~10.00% of
    // the original stake over 360 days (each release is annualRate * 30/365 of the current, shrinking balance).
    uint16 internal constant ANNUAL_UNSTAKE_RATE_BPS = 1_064;
    uint64 internal constant STANDARD_ADOPTION_DELAY = 7 days;
    uint256 internal constant CITIZEN_QUORUM = 10_000 * ONE_LLM;
    uint256 internal constant CONGRESS_QUORUM = 8_000 * ONE_LLM;
    uint256 internal constant CITIZEN_PROPOSAL_BOND = 6_000 * ONE_LLM;
    uint256 internal constant CONSTITUTIONAL_FOR_VOTER_QUORUM = 2;
    uint16 internal constant CONSTITUTIONAL_FOR_STAKE_BPS = 6_500;
    uint32 internal constant CONGRESS_SEAT_COUNT = 2;
    uint32 internal constant CONGRESS_RUNNER_UP_COUNT = 2;
    uint32 internal constant CONGRESS_MAX_CANDIDATE_COUNT = 8;
    uint64 internal constant MINIMUM_NOMINATION_DURATION = 1 days;
    uint64 internal constant MINIMUM_ELECTION_VOTING_DURATION = 2 days;
    uint64 internal constant MAX_SCHEDULE_LEAD_TIME = 3 days;
    uint64 internal constant ELECTION_CYCLE_DURATION = 3 days;
    uint32 internal constant SENATE_CANCELLATION_THRESHOLD = 2;
    uint64 internal constant DISBURSEMENT_SUSPENSION_PERIOD = 30 days;
    uint256 internal constant PUBLIC_VETO_THRESHOLD = 2;
    // One whole USDC in base units (USDC uses 6 decimals).
    uint256 internal constant ONE_USDC = 10 ** 6;
    uint256 internal constant FINANCE_CLERK_LLM_OPERATIONS_LIMIT = 3_000 * ONE_LLM;
    uint256 internal constant FINANCE_CLERK_LLM_SALARY_LIMIT = 2_000 * ONE_LLM;
    uint256 internal constant FINANCE_CLERK_USDC_OPERATIONS_LIMIT = 3_000 * ONE_USDC;
    uint256 internal constant FINANCE_CLERK_USDC_SALARY_LIMIT = 2_000 * ONE_USDC;
    uint256 internal constant DEMO_OPERATIONS_BUDGET_AMOUNT = 1_000 * ONE_USDC;
    // Launch lending config: 1 LLM = 2 USDC manual oracle, kinked rates (2% base, +8% to the 80% kink, +100% to
    // full), 25% LTV / 35% liquidation threshold / 10% bonus / 15% reserve, unlimited per-person cap (0).
    uint256 internal constant LAUNCH_LLM_USDC_PRICE = 2 * ONE_USDC;
    uint256 internal constant LENDING_BORROW_CAP = 1_000_000 * ONE_USDC;
    uint64 internal constant IDENTITY_MIGRATION_DELAY = 2 days;
    uint64 internal constant PRESIDENT_TERM = 5 * 365 days;

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
    bytes32 internal constant COMPANY_REGISTRY_OFFICE_ID = keccak256("office.company-registry");
    bytes32 internal constant DEMO_FINANCE_BUDGET_ID = keccak256("demo.budget.finance.operations");
    uint256 internal constant DEMO_CONGRESS_CYCLE_ID = 1;

    ConstitutionKernel internal _kernel;
    ActionTimelock internal _timelock;
    GovernanceRouter internal _router;
    IdentityRegistry internal _identityRegistry;
    StakeRegistry internal _stakeRegistry;
    LegislationRegistry internal _legislationRegistry;
    ReferendumRegistry internal _referendumRegistry;
    CongressCandidateRegistry internal _congressCandidateRegistry;
    SenateSeatRegistry internal _senateSeatRegistry;
    LandRegistry internal _landRegistry;
    CompanyRegistry internal _companyRegistry;
    TreasuryVault internal _treasuryVault;
    BudgetEnvelopeRegistry internal _budgetEnvelopeRegistry;
    OfficeRegistry internal _officeRegistry;
    PresidentRegistry internal _presidentRegistry;
    ExecutiveRegistry internal _executiveRegistry;
    DemoSetupAuthority internal _demoAuthority;
    DemoCitizenGateway internal _demoCitizenGateway;
    LLMToken internal _llmToken;
    MockUSDC internal _usdcToken;
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
    DecisionApp internal _decisionApp;
    HeadOfStateApp internal _headOfStateApp;
    CabinetApp internal _cabinetApp;
    IdentityApp internal _identityApp;
    LandRegistryApp internal _landRegistryApp;
    CompanyRegistryApp internal _companyRegistryApp;
    PayoutQueue internal _payoutQueue;
    OfficeExecutor internal _officeExecutor;
    StakeLienRegistry internal _stakeLienRegistry;
    FixedLlmUsdcPriceOraclePolicy internal _llmUsdcOracle;
    KinkedInterestRatePolicy internal _lendingInterestRatePolicy;
    LendingRiskParameterPolicy internal _lendingRiskPolicy;
    USDCLendingPoolApp internal _lendingPool;
    MinistryTreasury internal _ministryTreasury;

    address internal _financeOfficeAdmin;
    address internal _identityOfficeAdmin;
    address internal _landOfficeAdmin;
    address internal _companyRegistryOfficeAdmin;
    address internal _financeClerk;
    uint256 internal _treasuryPrefundUsdc;
    uint256 internal _treasuryPrefundLlm;

    struct Deployment {
        address deployer;
        address kernel;
        address timelock;
        address router;
        address demoAuthority;
        address demoCitizenGateway;
        address llmToken;
        address usdcToken;
        address stakeLienRegistry;
        address llmUsdcOracle;
        address lendingInterestRatePolicy;
        address lendingRiskPolicy;
        address lendingPool;
        address ministryTreasury;
        address identityRegistry;
        address stakeRegistry;
        address legislationRegistry;
        address referendumRegistry;
        address congressCandidateRegistry;
        address senateSeatRegistry;
        address landRegistry;
        address companyRegistry;
        address treasuryVault;
        address budgetEnvelopeRegistry;
        address officeRegistry;
        address presidentRegistry;
        address executiveRegistry;
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
        address decisionApp;
        address headOfStateApp;
        address cabinetApp;
        address identityApp;
        address landRegistryApp;
        address companyRegistryApp;
        address payoutQueue;
        address officeExecutor;
        bytes32 financeOfficeId;
        bytes32 identityOfficeId;
        bytes32 landOfficeId;
        bytes32 companyRegistryOfficeId;
        bytes32 financeBudgetId;
        uint256 congressCycleId;
        uint64 congressNominationStart;
        uint64 congressVotingStart;
        uint64 congressVotingEnd;
        address financeOfficeAdmin;
        address identityOfficeAdmin;
        address landOfficeAdmin;
        address companyRegistryOfficeAdmin;
        address financeClerk;
        uint256 treasuryPrefundUsdc;
        uint256 treasuryPrefundLlm;
        uint256 meritReserveMinted;
    }

    function run() external returns (Deployment memory deployment) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        _financeOfficeAdmin = vm.envOr("FINANCE_ADMIN", deployer);
        _identityOfficeAdmin = vm.envOr("IDENTITY_ADMIN", address(0xB0B));
        _landOfficeAdmin = vm.envOr("LAND_ADMIN", address(0xCAFE));
        _companyRegistryOfficeAdmin = vm.envOr("COMPANY_REGISTRY_ADMIN", deployer);
        _financeClerk = vm.envOr("FINANCE_CLERK", address(0xD00D));
        _treasuryPrefundUsdc = vm.envOr("TREASURY_PREFUND_USDC", uint256(0));
        _treasuryPrefundLlm = vm.envOr("TREASURY_PREFUND_LLM", uint256(0));

        vm.startBroadcast(deployerPrivateKey);

        _deployCore(deployer);
        _deployRegistries();
        _deployDemoAuthority(deployer);
        _deployPoliciesAndApps(deployer);
        _registerBootstrapModules();
        _seedDemoState(deployer);
        _switchToFinalDemoWiring();
        _prefundTreasury();
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
        _timelock = new ActionTimelock(address(_kernel), _timelockDelayConfig());
        _router = new GovernanceRouter(address(_kernel), deployer);

        (bytes32[] memory moduleIds, address[] memory moduleAddresses) = _allocateModuleBatch(2);
        _setModuleBatchEntry(moduleIds, moduleAddresses, 0, KernelModuleIds.GOVERNANCE_ROUTER, address(_router));
        _setModuleBatchEntry(moduleIds, moduleAddresses, 1, KernelModuleIds.ACTION_TIMELOCK, address(_timelock));
        _kernel.bootstrapSetModules(moduleIds, moduleAddresses);
    }

    function _deployRegistries() internal {
        _identityRegistry = new IdentityRegistry(address(_kernel));
        _stakeRegistry = new StakeRegistry(address(_kernel));
        _legislationRegistry = new LegislationRegistry(address(_kernel));
        _referendumRegistry = new ReferendumRegistry(address(_kernel));
        _congressCandidateRegistry = new CongressCandidateRegistry(address(_kernel));
        _senateSeatRegistry = new SenateSeatRegistry(address(_kernel));
        _landRegistry = new LandRegistry(address(_kernel));
        _companyRegistry = new CompanyRegistry(address(_kernel));
        _treasuryVault = new TreasuryVault(address(_kernel));
        _budgetEnvelopeRegistry = new BudgetEnvelopeRegistry(address(_kernel));
        _officeRegistry = new OfficeRegistry(address(_kernel));
        _presidentRegistry = new PresidentRegistry(address(_kernel));
        _executiveRegistry = new ExecutiveRegistry(address(_kernel));
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
        _usdcToken = new MockUSDC();
        _citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(_identityRegistry), address(_stakeRegistry), MINIMUM_CITIZEN_STAKE);
        _unstakingPolicy = new UnstakingPolicy(address(_stakeRegistry), WELFARE_PERIOD, ANNUAL_UNSTAKE_RATE_BPS);
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
            address(_llmToken),
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
        _senatePowersPolicy = new SenatePowersPolicy(SENATE_CANCELLATION_THRESHOLD, DISBURSEMENT_SUSPENSION_PERIOD);
        _senateApp = new SenateApp(
            address(_identityRegistry),
            address(_senateSeatRegistry),
            address(_senatePowersPolicy),
            address(_presidentRegistry),
            address(_router),
            address(_timelock),
            address(_referendumApp)
        );
        _publicVetoApp =
            new PublicVetoApp(address(_legislationRegistry), address(_citizenEligibilityPolicy), PUBLIC_VETO_THRESHOLD);
        _decisionApp = new DecisionApp(
            address(_congressCandidateRegistry),
            address(_identityRegistry),
            address(_officeRegistry),
            address(_stakeRegistry),
            address(_llmToken)
        );
        _headOfStateApp = new HeadOfStateApp(address(_presidentRegistry), address(_senateSeatRegistry));
        _cabinetApp = new CabinetApp(
            address(_executiveRegistry),
            address(_congressCandidateRegistry),
            address(_citizenEligibilityPolicy),
            FINANCE_OFFICE_ID,
            address(_officeRegistry)
        );
        _officePermissionPolicy = new OfficePermissionPolicy();
        _treasurySpendingPolicy = new TreasurySpendingPolicy(FINANCE_OFFICE_ID, _treasurySpendingAssetLimits());
        _identityApp = new IdentityApp(
            address(_identityRegistry), address(_officeRegistry), IDENTITY_OFFICE_ID, IDENTITY_MIGRATION_DELAY
        );
        _landRegistryApp = new LandRegistryApp(
            address(_landRegistry), address(_officeRegistry), address(_officePermissionPolicy), LAND_OFFICE_ID
        );
        _companyRegistryApp = new CompanyRegistryApp(
            address(_companyRegistry),
            address(_officeRegistry),
            address(_officePermissionPolicy),
            COMPANY_REGISTRY_OFFICE_ID
        );
        _payoutQueue = new PayoutQueue(address(_kernel), address(_budgetEnvelopeRegistry));
        _officeExecutor = new OfficeExecutor(
            address(_officeRegistry),
            address(_officePermissionPolicy),
            address(_treasurySpendingPolicy),
            address(_payoutQueue),
            address(_router),
            deployer
        );

        // Stake-backed lending stack (ERC20 money) plus the office-keyed ministry treasury. The lien registry
        // sources its retained-stake floor live from the citizenship policy, so no floor amount is passed here.
        _stakeLienRegistry = new StakeLienRegistry(address(_kernel));
        _llmUsdcOracle = new FixedLlmUsdcPriceOraclePolicy(address(_usdcToken), LAUNCH_LLM_USDC_PRICE);
        _lendingInterestRatePolicy = new KinkedInterestRatePolicy(200, 800, 10_000, 8e26);
        _lendingRiskPolicy = new LendingRiskParameterPolicy(2_500, 3_500, 1_000, 1_500, 0);
        _lendingPool = new USDCLendingPoolApp(
            address(_kernel),
            address(_usdcToken),
            address(_identityRegistry),
            address(_stakeRegistry),
            address(_stakeLienRegistry),
            address(_lendingInterestRatePolicy),
            LENDING_BORROW_CAP
        );
        _ministryTreasury = new MinistryTreasury(address(_kernel));
    }

    function _registerBootstrapModules() internal {
        (bytes32[] memory moduleIds, address[] memory moduleAddresses) = _allocateModuleBatch(54);
        uint256 index;

        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_demoAuthority)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(_demoAuthority)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(_demoAuthority)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(_demoAuthority)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(_demoAuthority)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY,
            address(_demoAuthority)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY,
            address(_demoAuthority)
        );

        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.IDENTITY_REGISTRY, address(_identityRegistry)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.STAKE_REGISTRY, address(_stakeRegistry)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.LEGISLATION_REGISTRY, address(_legislationRegistry)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.REFERENDUM_REGISTRY, address(_referendumRegistry)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY,
            address(_congressCandidateRegistry)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.SENATE_SEAT_REGISTRY, address(_senateSeatRegistry)
        );
        _setModuleBatchEntry(moduleIds, moduleAddresses, index++, KernelModuleIds.LAND_REGISTRY, address(_landRegistry));
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.COMPANY_REGISTRY, address(_companyRegistry)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.TREASURY_VAULT, address(_treasuryVault)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.BUDGET_ENVELOPE_REGISTRY,
            address(_budgetEnvelopeRegistry)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.OFFICE_REGISTRY, address(_officeRegistry)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.PRESIDENT_REGISTRY, address(_presidentRegistry)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.EXECUTIVE_REGISTRY, address(_executiveRegistry)
        );

        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY,
            address(_citizenEligibilityPolicy)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.UNSTAKING_POLICY, address(_unstakingPolicy)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.VOTING_POWER_POLICY, address(_votingPowerPolicy)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.CANDIDATE_ELIGIBILITY_POLICY,
            address(_candidateEligibilityPolicy)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.CONGRESS_ELECTION_POLICY,
            address(_congressElectionPolicy)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.REFERENDUM_POLICY, address(_referendumPolicy)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.SENATE_POWERS_POLICY, address(_senatePowersPolicy)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.OFFICE_PERMISSION_POLICY,
            address(_officePermissionPolicy)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.TREASURY_SPENDING_POLICY,
            address(_treasurySpendingPolicy)
        );

        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.CONGRESS_ELECTION_APP, address(_congressElectionApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.REFERENDUM_APP, address(_referendumApp)
        );
        _setModuleBatchEntry(moduleIds, moduleAddresses, index++, KernelModuleIds.SENATE_APP, address(_senateApp));
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.PUBLIC_VETO_APP, address(_publicVetoApp)
        );
        _setModuleBatchEntry(moduleIds, moduleAddresses, index++, KernelModuleIds.DECISION_APP, address(_decisionApp));
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.HEAD_OF_STATE_APP, address(_headOfStateApp)
        );
        _setModuleBatchEntry(moduleIds, moduleAddresses, index++, KernelModuleIds.CABINET_APP, address(_cabinetApp));
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.LAND_REGISTRY_APP, address(_landRegistryApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.COMPANY_REGISTRY_APP, address(_companyRegistryApp)
        );
        _setModuleBatchEntry(moduleIds, moduleAddresses, index++, KernelModuleIds.PAYOUT_QUEUE, address(_payoutQueue));
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.OFFICE_EXECUTOR, address(_officeExecutor)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY, address(_senateApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.LEGISLATION_REPEAL_AUTHORITY, address(_publicVetoApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.STAKE_DEPOSIT_AUTHORITY, address(_decisionApp)
        );
        // Standing President-registry authority (fixes the post-genesis freeze): the HeadOfStateApp is the sole
        // live writer of the President registry after genesis and is not repointed by _switchToFinalDemoWiring.
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.PRESIDENT_REGISTRY_AUTHORITY, address(_headOfStateApp)
        );
        // Standing Executive-registry authority: the CabinetApp is the sole live writer of the Executive registry
        // (Prime Minister + Cabinet) after genesis and is not repointed by _switchToFinalDemoWiring.
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.EXECUTIVE_REGISTRY_AUTHORITY, address(_cabinetApp)
        );

        // Lending stack: the pool is its own stake-lien and liquidation authority; oracle/interest/risk policies are
        // governed replaceable modules resolved live by the pool.
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.STAKE_LIEN_REGISTRY, address(_stakeLienRegistry)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY, address(_lendingPool)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY, address(_lendingPool)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY, address(_llmUsdcOracle)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.USDC_INTEREST_RATE_POLICY,
            address(_lendingInterestRatePolicy)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.LENDING_RISK_PARAMETER_POLICY,
            address(_lendingRiskPolicy)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.USDC_LENDING_POOL_APP, address(_lendingPool)
        );

        // Ministry treasury: office-keyed ERC20 funds, funded by Congress decision (DecisionApp is the authority).
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.MINISTRY_TREASURY, address(_ministryTreasury)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.MINISTRY_TREASURY_FUNDING_AUTHORITY,
            address(_decisionApp)
        );

        _kernel.bootstrapSetModules(moduleIds, moduleAddresses);
    }

    function _seedDemoState(address deployer) internal {
        address walletTwo = address(0xB0B);
        address walletThree = address(0xCAFE);
        address walletFour = address(0xD00D);

        _demoAuthority.seedCitizen(
            DEMO_PERSON_ONE, deployer, 20_000 * ONE_LLM, "ipfs://demo/citizen-one.json", keccak256("demo-citizen-one")
        );
        _demoAuthority.seedCitizen(
            DEMO_PERSON_TWO, walletTwo, 7_500 * ONE_LLM, "ipfs://demo/citizen-two.json", keccak256("demo-citizen-two")
        );
        _demoAuthority.seedCitizen(
            DEMO_PERSON_THREE,
            walletThree,
            12_000 * ONE_LLM,
            "ipfs://demo/citizen-three.json",
            keccak256("demo-citizen-three")
        );
        _demoAuthority.seedCitizen(
            DEMO_PERSON_FOUR,
            walletFour,
            5_500 * ONE_LLM,
            "ipfs://demo/citizen-four.json",
            keccak256("demo-citizen-four")
        );
        _demoAuthority.setProtectedStakeFloor(DEMO_PERSON_ONE, 5_000 * ONE_LLM);
        uint64 presidentTermStart = uint64(block.timestamp);
        _presidentRegistry.setPresident(
            deployer,
            DEMO_PERSON_ONE,
            keccak256("demo-president-mandate"),
            presidentTermStart,
            presidentTermStart + PRESIDENT_TERM
        );
        _seedCongressElection(deployer, walletTwo, walletThree, walletFour);

        _demoAuthority.seedLegislation(
            ORDINARY_MEASURE_ID,
            LegislationTypes.LegislationRecordInput({
                tier: LegislationTypes.LegislationTier.Law,
                textHash: keccak256("demo-law-ordinary"),
                proposerReference: DEMO_PERSON_ONE,
                enactedByReferendumId: keccak256("demo-law-ordinary-referendum"),
                amendsMeasureId: bytes32(0)
            })
        );
        _demoAuthority.seedLegislation(
            CONSTITUTIONAL_MEASURE_ID,
            LegislationTypes.LegislationRecordInput({
                tier: LegislationTypes.LegislationTier.ConstitutionalOrInternationalTreaty,
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
                legislationTier: LegislationTypes.LegislationTier.Law,
                targetModule: bytes32(0),
                proposedModuleAddress: address(0),
                registerNewModule: false,
                proposerReference: DEMO_PERSON_ONE,
                startTime: uint64(block.timestamp - 1 days),
                endTime: uint64(block.timestamp + 6 days),
                adoptionDelay: STANDARD_ADOPTION_DELAY,
                electorateHeadcountSnapshot: 0,
                electorateVotingPowerSnapshot: 0,
                requiresSupermajority: false
            })
        );
        _demoAuthority.seedReferendumVote(
            ACTIVE_REFERENDUM_ID, deployer, ReferendumTypes.VoteOption.For, 20_000 * ONE_LLM
        );
        _demoAuthority.seedReferendumVote(
            ACTIVE_REFERENDUM_ID, walletThree, ReferendumTypes.VoteOption.Against, 12_000 * ONE_LLM
        );

        _demoAuthority.seedReferendum(
            FINALIZED_REFERENDUM_ID,
            ReferendumTypes.ReferendumRecordInput({
                referendumClass: ReferendumTypes.ReferendumClass.Legislation,
                proposalOrigin: ReferendumTypes.ProposalOrigin.Citizen,
                proposalMetadataHash: keccak256("demo-finalized-referendum"),
                proposedMeasureId: DEFEATED_MEASURE_ID,
                amendsMeasureId: bytes32(0),
                legislationTextHash: keccak256("demo-defeated-law-text"),
                legislationTier: LegislationTypes.LegislationTier.Law,
                targetModule: bytes32(0),
                proposedModuleAddress: address(0),
                registerNewModule: false,
                proposerReference: DEMO_PERSON_TWO,
                startTime: uint64(block.timestamp - 10 days),
                endTime: uint64(block.timestamp - 5 days),
                adoptionDelay: STANDARD_ADOPTION_DELAY,
                electorateHeadcountSnapshot: 0,
                electorateVotingPowerSnapshot: 0,
                requiresSupermajority: false
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
        _demoAuthority.seedOffice(
            COMPANY_REGISTRY_OFFICE_ID,
            OfficeTypes.OfficeKind.CompanyRegistryOffice,
            "Company Registry Office",
            _companyRegistryOfficeAdmin
        );
        _demoAuthority.seedClerk(FINANCE_OFFICE_ID, _financeClerk, true);

        _demoAuthority.seedBudget(
            DEMO_FINANCE_BUDGET_ID,
            TreasuryTypes.BudgetEnvelopeInput({
                officeId: FINANCE_OFFICE_ID,
                disbursementType: TreasuryTypes.DisbursementType.Operations,
                asset: address(_usdcToken),
                allocatedAmount: DEMO_OPERATIONS_BUDGET_AMOUNT,
                startsAt: uint64(block.timestamp - 1 hours),
                endsAt: uint64(block.timestamp + 30 days),
                policyReference: _treasurySpendingPolicy.computePolicyReference(
                    FINANCE_OFFICE_ID,
                    OfficeTypes.OfficeRole.Admin,
                    TreasuryTypes.DisbursementType.Operations,
                    address(_usdcToken),
                    DEMO_OPERATIONS_BUDGET_AMOUNT
                )
            })
        );

        _senateApp.bootstrapAssignSeat(0, deployer);
        _senateApp.bootstrapAssignSeat(1, walletThree);

        _publicVetoApp.castPublicVeto(ORDINARY_MEASURE_ID);
        _llmToken.mint(address(_demoCitizenGateway), 45_000 * ONE_LLM);
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

        _seedCongressBallot(
            deployer, walletThree, 12_000 * ONE_LLM_SIGNED, deployer, 8_000 * ONE_LLM_SIGNED, 20_000 * ONE_LLM
        );
        _seedCongressBallot(walletTwo, walletTwo, 7_500 * ONE_LLM_SIGNED, 7_500 * ONE_LLM);
        _seedCongressBallot(
            walletThree, deployer, 8_000 * ONE_LLM_SIGNED, walletTwo, 4_000 * ONE_LLM_SIGNED, 12_000 * ONE_LLM
        );
        _seedCongressBallot(walletFour, walletFour, 5_500 * ONE_LLM_SIGNED, 5_500 * ONE_LLM);
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
        (bytes32[] memory moduleIds, address[] memory moduleAddresses) = _allocateModuleBatch(10);
        // Standing identity authority: the governed IdentityApp replaces the demo gateway as the sole live
        // mutator of the identity registry. The gateway remains the stake authority and user staking gateway;
        // post-genesis identity lifecycle (onboarding, renunciation, wallet migration) now flows through offices.
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 0, KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_identityApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 1, KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(_demoCitizenGateway)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 2, KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(_timelock)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 3, KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(_referendumApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 4, KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(_timelock)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 5, KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY, address(_payoutQueue)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 6, KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(_officeExecutor)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            7,
            KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY,
            address(_congressElectionApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 8, KernelModuleIds.LAND_REGISTRY_AUTHORITY, address(_landRegistryApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 9, KernelModuleIds.COMPANY_REGISTRY_AUTHORITY, address(_companyRegistryApp)
        );
        _kernel.bootstrapSetModules(moduleIds, moduleAddresses);

        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, address(_referendumApp));
        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Senate, address(_senateApp));
        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Office, address(_officeExecutor));
    }

    function _allocateModuleBatch(uint256 length)
        internal
        pure
        returns (bytes32[] memory moduleIds, address[] memory moduleAddresses)
    {
        moduleIds = new bytes32[](length);
        moduleAddresses = new address[](length);
    }

    function _setModuleBatchEntry(
        bytes32[] memory moduleIds,
        address[] memory moduleAddresses,
        uint256 index,
        bytes32 moduleId,
        address moduleAddress
    ) internal pure {
        moduleIds[index] = moduleId;
        moduleAddresses[index] = moduleAddress;
    }

    function _timelockDelayConfig() internal pure returns (GovernanceTypes.TimelockDelayConfig memory config) {
        config = GovernanceTypes.TimelockDelayConfig({
            moduleGovernanceDelay: 2 days,
            treasuryBudgetApprovalDelay: 1 days,
            legislationEnactmentDelay: 1 days,
            treasuryDisbursementDelay: 2 days,
            defaultExecutionWindow: 7 days
        });
    }

    function _treasurySpendingAssetLimits()
        internal
        view
        returns (ITreasurySpendingPolicy.AssetSpendingLimit[] memory assetLimits)
    {
        assetLimits = new ITreasurySpendingPolicy.AssetSpendingLimit[](2);
        assetLimits[0] = ITreasurySpendingPolicy.AssetSpendingLimit({
            asset: address(_llmToken),
            clerkOperationsLimit: FINANCE_CLERK_LLM_OPERATIONS_LIMIT,
            clerkSalaryLimit: FINANCE_CLERK_LLM_SALARY_LIMIT
        });
        assetLimits[1] = ITreasurySpendingPolicy.AssetSpendingLimit({
            asset: address(_usdcToken),
            clerkOperationsLimit: FINANCE_CLERK_USDC_OPERATIONS_LIMIT,
            clerkSalaryLimit: FINANCE_CLERK_USDC_SALARY_LIMIT
        });
    }

    /// @dev Demo money is ERC20 only: the vault is always funded with enough USDC to cover the seeded demo budget,
    ///      plus any optional env-configured USDC/LLM top-ups. Native ETH is gas-only and never treasury money.
    function _prefundTreasury() internal {
        _usdcToken.mint(address(_treasuryVault), DEMO_OPERATIONS_BUDGET_AMOUNT + _treasuryPrefundUsdc);
        if (_treasuryPrefundLlm != 0) {
            _llmToken.mint(address(_treasuryVault), _treasuryPrefundLlm);
        }
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
        deployment.usdcToken = address(_usdcToken);
        deployment.stakeLienRegistry = address(_stakeLienRegistry);
        deployment.llmUsdcOracle = address(_llmUsdcOracle);
        deployment.lendingInterestRatePolicy = address(_lendingInterestRatePolicy);
        deployment.lendingRiskPolicy = address(_lendingRiskPolicy);
        deployment.lendingPool = address(_lendingPool);
        deployment.ministryTreasury = address(_ministryTreasury);
        deployment.identityRegistry = address(_identityRegistry);
        deployment.stakeRegistry = address(_stakeRegistry);
        deployment.legislationRegistry = address(_legislationRegistry);
        deployment.referendumRegistry = address(_referendumRegistry);
        deployment.congressCandidateRegistry = address(_congressCandidateRegistry);
        deployment.senateSeatRegistry = address(_senateSeatRegistry);
        deployment.landRegistry = address(_landRegistry);
        deployment.companyRegistry = address(_companyRegistry);
        deployment.treasuryVault = address(_treasuryVault);
        deployment.budgetEnvelopeRegistry = address(_budgetEnvelopeRegistry);
        deployment.officeRegistry = address(_officeRegistry);
        deployment.presidentRegistry = address(_presidentRegistry);
        deployment.executiveRegistry = address(_executiveRegistry);
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
        deployment.decisionApp = address(_decisionApp);
        deployment.headOfStateApp = address(_headOfStateApp);
        deployment.cabinetApp = address(_cabinetApp);
        deployment.identityApp = address(_identityApp);
        deployment.landRegistryApp = address(_landRegistryApp);
        deployment.companyRegistryApp = address(_companyRegistryApp);
        deployment.payoutQueue = address(_payoutQueue);
        deployment.officeExecutor = address(_officeExecutor);
        deployment.financeOfficeId = FINANCE_OFFICE_ID;
        deployment.identityOfficeId = IDENTITY_OFFICE_ID;
        deployment.landOfficeId = LAND_OFFICE_ID;
        deployment.companyRegistryOfficeId = COMPANY_REGISTRY_OFFICE_ID;
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
        deployment.companyRegistryOfficeAdmin = _companyRegistryOfficeAdmin;
        deployment.financeClerk = _financeClerk;
        deployment.treasuryPrefundUsdc = DEMO_OPERATIONS_BUDGET_AMOUNT + _treasuryPrefundUsdc;
        deployment.treasuryPrefundLlm = _treasuryPrefundLlm;
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
        vm.serializeAddress(deploymentKey, "landRegistry", deployment.landRegistry);
        vm.serializeAddress(deploymentKey, "companyRegistry", deployment.companyRegistry);
        vm.serializeAddress(deploymentKey, "treasuryVault", deployment.treasuryVault);
        vm.serializeAddress(deploymentKey, "budgetEnvelopeRegistry", deployment.budgetEnvelopeRegistry);
        vm.serializeAddress(deploymentKey, "officeRegistry", deployment.officeRegistry);
        vm.serializeAddress(deploymentKey, "presidentRegistry", deployment.presidentRegistry);
        vm.serializeAddress(deploymentKey, "executiveRegistry", deployment.executiveRegistry);
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
        vm.serializeAddress(deploymentKey, "decisionApp", deployment.decisionApp);
        vm.serializeAddress(deploymentKey, "headOfStateApp", deployment.headOfStateApp);
        vm.serializeAddress(deploymentKey, "cabinetApp", deployment.cabinetApp);
        vm.serializeAddress(deploymentKey, "identityApp", deployment.identityApp);
        vm.serializeAddress(deploymentKey, "landRegistryApp", deployment.landRegistryApp);
        vm.serializeAddress(deploymentKey, "companyRegistryApp", deployment.companyRegistryApp);
        vm.serializeAddress(deploymentKey, "payoutQueue", deployment.payoutQueue);
        vm.serializeAddress(deploymentKey, "officeExecutor", deployment.officeExecutor);
        vm.serializeBytes32(deploymentKey, "financeOfficeId", deployment.financeOfficeId);
        vm.serializeBytes32(deploymentKey, "identityOfficeId", deployment.identityOfficeId);
        vm.serializeBytes32(deploymentKey, "landOfficeId", deployment.landOfficeId);
        vm.serializeBytes32(deploymentKey, "companyRegistryOfficeId", deployment.companyRegistryOfficeId);
        vm.serializeBytes32(deploymentKey, "financeBudgetId", deployment.financeBudgetId);
        vm.serializeUint(deploymentKey, "congressCycleId", deployment.congressCycleId);
        vm.serializeUint(deploymentKey, "congressNominationStart", deployment.congressNominationStart);
        vm.serializeUint(deploymentKey, "congressVotingStart", deployment.congressVotingStart);
        vm.serializeUint(deploymentKey, "congressVotingEnd", deployment.congressVotingEnd);
        vm.serializeAddress(deploymentKey, "financeOfficeAdmin", deployment.financeOfficeAdmin);
        vm.serializeAddress(deploymentKey, "identityOfficeAdmin", deployment.identityOfficeAdmin);
        vm.serializeAddress(deploymentKey, "landOfficeAdmin", deployment.landOfficeAdmin);
        vm.serializeAddress(deploymentKey, "companyRegistryOfficeAdmin", deployment.companyRegistryOfficeAdmin);
        vm.serializeAddress(deploymentKey, "financeClerk", deployment.financeClerk);
        vm.serializeAddress(deploymentKey, "usdcToken", deployment.usdcToken);
        vm.serializeAddress(deploymentKey, "stakeLienRegistry", deployment.stakeLienRegistry);
        vm.serializeAddress(deploymentKey, "llmUsdcOracle", deployment.llmUsdcOracle);
        vm.serializeAddress(deploymentKey, "lendingInterestRatePolicy", deployment.lendingInterestRatePolicy);
        vm.serializeAddress(deploymentKey, "lendingRiskPolicy", deployment.lendingRiskPolicy);
        vm.serializeAddress(deploymentKey, "lendingPool", deployment.lendingPool);
        vm.serializeAddress(deploymentKey, "ministryTreasury", deployment.ministryTreasury);
        vm.serializeUint(deploymentKey, "treasuryPrefundUsdc", deployment.treasuryPrefundUsdc);
        vm.serializeUint(deploymentKey, "treasuryPrefundLlm", deployment.treasuryPrefundLlm);
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
        console2.log("USDCToken:", deployment.usdcToken);
        console2.log("StakeLienRegistry:", deployment.stakeLienRegistry);
        console2.log("LLMUSDCOracle:", deployment.llmUsdcOracle);
        console2.log("LendingInterestRatePolicy:", deployment.lendingInterestRatePolicy);
        console2.log("LendingRiskPolicy:", deployment.lendingRiskPolicy);
        console2.log("USDCLendingPool:", deployment.lendingPool);
        console2.log("MinistryTreasury:", deployment.ministryTreasury);
        console2.log("IdentityRegistry:", deployment.identityRegistry);
        console2.log("StakeRegistry:", deployment.stakeRegistry);
        console2.log("LegislationRegistry:", deployment.legislationRegistry);
        console2.log("ReferendumRegistry:", deployment.referendumRegistry);
        console2.log("CongressCandidateRegistry:", deployment.congressCandidateRegistry);
        console2.log("SenateSeatRegistry:", deployment.senateSeatRegistry);
        console2.log("LandRegistry:", deployment.landRegistry);
        console2.log("CompanyRegistry:", deployment.companyRegistry);
        console2.log("TreasuryVault:", deployment.treasuryVault);
        console2.log("BudgetEnvelopeRegistry:", deployment.budgetEnvelopeRegistry);
        console2.log("OfficeRegistry:", deployment.officeRegistry);
        console2.log("PresidentRegistry:", deployment.presidentRegistry);
        console2.log("ExecutiveRegistry:", deployment.executiveRegistry);
        console2.log("OfficePermissionPolicy:", deployment.officePermissionPolicy);
        console2.log("TreasurySpendingPolicy:", deployment.treasurySpendingPolicy);
        console2.log("DecisionApp:", deployment.decisionApp);
        console2.log("HeadOfStateApp:", deployment.headOfStateApp);
        console2.log("CabinetApp:", deployment.cabinetApp);
        console2.log("IdentityApp:", deployment.identityApp);
        console2.log("LandRegistryApp:", deployment.landRegistryApp);
        console2.log("CompanyRegistryApp:", deployment.companyRegistryApp);
        console2.log("PayoutQueue:", deployment.payoutQueue);
        console2.log("OfficeExecutor:", deployment.officeExecutor);
        console2.logBytes32(deployment.financeOfficeId);
        console2.logBytes32(deployment.identityOfficeId);
        console2.logBytes32(deployment.landOfficeId);
        console2.logBytes32(deployment.companyRegistryOfficeId);
        console2.logBytes32(deployment.financeBudgetId);
        console2.log("Demo Congress Cycle ID:", deployment.congressCycleId);
        console2.log("Demo Congress Voting Start:", deployment.congressVotingStart);
        console2.log("Demo Congress Voting End:", deployment.congressVotingEnd);
        console2.log("Finance Office Admin:", deployment.financeOfficeAdmin);
        console2.log("Identity Office Admin:", deployment.identityOfficeAdmin);
        console2.log("Land Office Admin:", deployment.landOfficeAdmin);
        console2.log("Company Registry Office Admin:", deployment.companyRegistryOfficeAdmin);
        console2.log("Finance Clerk:", deployment.financeClerk);
        console2.log("Treasury Prefund USDC:", deployment.treasuryPrefundUsdc);
        console2.log("Treasury Prefund LLM:", deployment.treasuryPrefundLlm);
        console2.log("Merit Reserve Minted:", deployment.meritReserveMinted);
    }
}
