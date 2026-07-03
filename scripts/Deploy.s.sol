// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {CabinetApp} from "../contracts/apps/CabinetApp.sol";
import {CompanyRegistryApp} from "../contracts/apps/CompanyRegistryApp.sol";
import {CongressElectionApp} from "../contracts/apps/CongressElectionApp.sol";
import {HeadOfStateApp} from "../contracts/apps/HeadOfStateApp.sol";
import {IdentityApp} from "../contracts/apps/IdentityApp.sol";
import {InitialSetupAuthority} from "../contracts/apps/InitialSetupAuthority.sol";
import {LandRegistryApp} from "../contracts/apps/LandRegistryApp.sol";
import {OfficeExecutor} from "../contracts/apps/OfficeExecutor.sol";
import {PayoutQueue} from "../contracts/apps/PayoutQueue.sol";
import {PublicVetoApp} from "../contracts/apps/PublicVetoApp.sol";
import {ReferendumApp} from "../contracts/apps/ReferendumApp.sol";
import {SenateApp} from "../contracts/apps/SenateApp.sol";
import {TreasuryVault} from "../contracts/apps/TreasuryVault.sol";
import {ActionTimelock} from "../contracts/core/ActionTimelock.sol";
import {ConstitutionKernel} from "../contracts/core/ConstitutionKernel.sol";
import {GovernanceRouter} from "../contracts/core/GovernanceRouter.sol";
import {ITreasurySpendingPolicy} from "../contracts/interfaces/ITreasurySpendingPolicy.sol";
import {KernelModuleIds} from "../contracts/libraries/KernelModuleIds.sol";
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
import {CompanyRegistry} from "../contracts/registries/CompanyRegistry.sol";
import {ExecutiveRegistry} from "../contracts/registries/ExecutiveRegistry.sol";
import {IdentityRegistry} from "../contracts/registries/IdentityRegistry.sol";
import {LandRegistry} from "../contracts/registries/LandRegistry.sol";
import {LegislationRegistry} from "../contracts/registries/LegislationRegistry.sol";
import {OfficeRegistry} from "../contracts/registries/OfficeRegistry.sol";
import {PresidentRegistry} from "../contracts/registries/PresidentRegistry.sol";
import {ReferendumRegistry} from "../contracts/registries/ReferendumRegistry.sol";
import {SenateSeatRegistry} from "../contracts/registries/SenateSeatRegistry.sol";
import {StakeRegistry} from "../contracts/registries/StakeRegistry.sol";
import {GovernanceTypes} from "../contracts/types/GovernanceTypes.sol";
import {IdentityTypes} from "../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../contracts/types/OfficeTypes.sol";

contract Deploy is Script {
    // One whole LLM in base units. LLM uses the standard 18 ERC20 decimals, so every LLM-denominated amount
    // (stakes, bonds, and the stake-derived voting-power quorums) is expressed in whole LLM * ONE_LLM.
    uint256 internal constant ONE_LLM = 10 ** 18;
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000 * ONE_LLM;
    uint256 internal constant MINIMUM_CANDIDATE_STAKE = 6_000 * ONE_LLM;
    uint256 internal constant CANDIDATE_BOND_REQUIREMENT = 6_000 * ONE_LLM;
    uint64 internal constant WELFARE_PERIOD = 30 days;
    // 1064 bps (10.64%/yr): with the 30-day compounding unstake portion, twelve 30-day unstakes release ~10.00% of
    // the original stake over 360 days (each release is annualRate * 30/365 of the current, shrinking balance).
    uint16 internal constant ANNUAL_UNSTAKE_RATE_BPS = 1_064;
    uint256 internal constant CITIZEN_QUORUM = 10_000 * ONE_LLM;
    uint256 internal constant CONGRESS_QUORUM = 8_000 * ONE_LLM;
    uint256 internal constant CITIZEN_PROPOSAL_BOND = 6_000 * ONE_LLM;
    uint256 internal constant CONSTITUTIONAL_FOR_VOTER_QUORUM = 2;
    uint16 internal constant CONSTITUTIONAL_FOR_STAKE_BPS = 6_500;
    uint32 internal constant CONGRESS_SEAT_COUNT = 2;
    uint32 internal constant CONGRESS_RUNNER_UP_COUNT = 2;
    uint32 internal constant CONGRESS_MAX_CANDIDATE_COUNT = 8;
    uint64 internal constant MINIMUM_NOMINATION_DURATION = 2 days;
    uint64 internal constant MINIMUM_ELECTION_VOTING_DURATION = 3 days;
    uint64 internal constant MAX_SCHEDULE_LEAD_TIME = 14 days;
    uint64 internal constant ELECTION_CYCLE_DURATION = 90 days;
    uint32 internal constant SENATE_CANCELLATION_THRESHOLD = 2;
    uint64 internal constant DISBURSEMENT_SUSPENSION_PERIOD = 30 days;
    uint256 internal constant PUBLIC_VETO_THRESHOLD = 2;
    uint64 internal constant IDENTITY_MIGRATION_DELAY = 2 days;
    uint64 internal constant PRESIDENT_TERM = 5 * 365 days;

    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    bytes32 internal constant IDENTITY_OFFICE_ID = keccak256("office.identity");
    bytes32 internal constant LAND_OFFICE_ID = keccak256("office.land");
    bytes32 internal constant COMPANY_REGISTRY_OFFICE_ID = keccak256("office.company-registry");

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
    InitialSetupAuthority internal _initialSetupAuthority;
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
    HeadOfStateApp internal _headOfStateApp;
    CabinetApp internal _cabinetApp;
    IdentityApp internal _identityApp;
    LandRegistryApp internal _landRegistryApp;
    CompanyRegistryApp internal _companyRegistryApp;
    PayoutQueue internal _payoutQueue;
    OfficeExecutor internal _officeExecutor;

    address internal _financeOfficeAdmin;
    address internal _identityOfficeAdmin;
    address internal _landOfficeAdmin;
    address internal _companyRegistryOfficeAdmin;
    address internal _llmTokenAddress;
    ITreasurySpendingPolicy.AssetSpendingLimit[] internal _treasuryAssetLimits;
    uint256 internal _genesisCitizenCount;
    uint32 internal _genesisSenateSeatCount;
    uint32 internal _genesisCongressSeatCount;

    struct GenesisCitizen {
        bytes32 personId;
        address wallet;
        uint256 activeStake;
    }

    struct Deployment {
        address deployer;
        address llmToken;
        address kernel;
        address timelock;
        address router;
        address initialSetupAuthority;
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
        uint256 genesisCitizenCount;
        uint32 genesisSenateSeatCount;
        uint32 genesisCongressSeatCount;
        address genesisPresident;
        bytes32 genesisPresidentPersonId;
        address financeOfficeAdmin;
        address identityOfficeAdmin;
        address landOfficeAdmin;
        address companyRegistryOfficeAdmin;
    }

    function run() external returns (Deployment memory deployment) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // L9: production office admins must be explicitly configured and distinct from the deployer key, so a
        // run can never silently centralize office control on the deployer by defaulting an unset env var.
        _financeOfficeAdmin = vm.envAddress("FINANCE_ADMIN");
        _identityOfficeAdmin = vm.envAddress("IDENTITY_ADMIN");
        _landOfficeAdmin = vm.envAddress("LAND_ADMIN");
        _companyRegistryOfficeAdmin = vm.envAddress("COMPANY_REGISTRY_ADMIN");
        require(
            _financeOfficeAdmin != deployer && _identityOfficeAdmin != deployer && _landOfficeAdmin != deployer
                && _companyRegistryOfficeAdmin != deployer,
            "office admins must differ from deployer"
        );

        // System money is ERC20: LLM (governance/merit) plus the configured treasury spending assets (stablecoins
        // such as USDC/USDS). Native ETH is gas-only and has no treasury role, so both inputs are mandatory.
        _llmTokenAddress = vm.envAddress("LLM_TOKEN");
        require(_llmTokenAddress != address(0) && _llmTokenAddress.code.length != 0, "LLM_TOKEN must be a contract");
        _loadTreasuryAssetLimits();

        vm.startBroadcast(deployerPrivateKey);
        _deployCore(deployer);
        _deployRegistries();
        _deployPoliciesAndApps(deployer);
        _registerModules();
        _configureOriginAuthorities();
        _seedGenesisState();
        _assertReadyForBootstrapDisable();
        _sealAndDisableBootstrap();
        vm.stopBroadcast();

        deployment = _snapshot(deployer);

        _writeDeploymentJson(deployment);
        _logDeployment(deployment);
    }

    /// @dev Reads the governed treasury spending asset set (TREASURY_ASSET_COUNT plus indexed ADDRESS and clerk
    ///      limit entries). Every configured asset must be a deployed ERC20 with nonzero clerk limits; the policy
    ///      constructor re-validates and rejects duplicates.
    function _loadTreasuryAssetLimits() internal {
        uint256 assetCount = vm.envUint("TREASURY_ASSET_COUNT");
        require(assetCount != 0, "TREASURY_ASSET_COUNT must be at least 1");

        for (uint256 index = 0; index < assetCount; ++index) {
            address asset = vm.envAddress(_indexedGenesisKey("TREASURY_ASSET_", index, "_ADDRESS"));
            require(asset != address(0) && asset.code.length != 0, "treasury asset must be a contract");

            _treasuryAssetLimits.push(
                ITreasurySpendingPolicy.AssetSpendingLimit({
                    asset: asset,
                    clerkOperationsLimit: vm.envUint(
                        _indexedGenesisKey("TREASURY_ASSET_", index, "_CLERK_OPERATIONS_LIMIT")
                    ),
                    clerkSalaryLimit: vm.envUint(_indexedGenesisKey("TREASURY_ASSET_", index, "_CLERK_SALARY_LIMIT"))
                })
            );
        }
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

    function _deployPoliciesAndApps(address deployer) internal {
        _citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(_identityRegistry), address(_stakeRegistry), MINIMUM_CITIZEN_STAKE);
        _unstakingPolicy = new UnstakingPolicy(address(_stakeRegistry), WELFARE_PERIOD, ANNUAL_UNSTAKE_RATE_BPS);
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
        _initialSetupAuthority = new InitialSetupAuthority(
            deployer,
            address(_identityRegistry),
            address(_stakeRegistry),
            address(_congressCandidateRegistry),
            address(_congressElectionPolicy),
            address(_senateSeatRegistry),
            address(_officeRegistry)
        );
        _referendumPolicy = new ReferendumPolicy(
            address(_citizenEligibilityPolicy),
            address(_votingPowerPolicy),
            address(_congressElectionApp),
            _llmTokenAddress,
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
        _headOfStateApp = new HeadOfStateApp(address(_presidentRegistry), address(_senateSeatRegistry));
        _cabinetApp = new CabinetApp(
            address(_executiveRegistry),
            address(_congressCandidateRegistry),
            address(_citizenEligibilityPolicy),
            FINANCE_OFFICE_ID,
            address(_officeRegistry)
        );
        _officePermissionPolicy = new OfficePermissionPolicy();
        _treasurySpendingPolicy = new TreasurySpendingPolicy(FINANCE_OFFICE_ID, _treasuryAssetLimits);
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
    }

    function _registerModules() internal {
        (bytes32[] memory moduleIds, address[] memory moduleAddresses) = _allocateModuleBatch(47);
        uint256 index;

        // Standing identity authority: the IdentityApp becomes the sole live mutator of the identity registry.
        // Genesis identity seeding still runs through the InitialSetupAuthority, which the identity registry
        // accepts via its INITIAL_SETUP_AUTHORITY fallback until that authority is sealed below.
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_identityApp)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.STAKE_REGISTRY_AUTHORITY,
            address(_initialSetupAuthority)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.IDENTITY_REGISTRY, address(_identityRegistry)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.INITIAL_SETUP_AUTHORITY,
            address(_initialSetupAuthority)
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
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY,
            address(_congressElectionApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.LEGISLATION_REGISTRY_AUTHORITY, address(_timelock)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(_referendumApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.SENATE_SEAT_REGISTRY_AUTHORITY, address(_senateApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.LEGISLATION_REPEAL_AUTHORITY, address(_publicVetoApp)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.BUDGET_ENVELOPE_REGISTRY_AUTHORITY, address(_timelock)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY,
            address(_payoutQueue)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(_officeExecutor)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.LAND_REGISTRY_AUTHORITY, address(_landRegistryApp)
        );
        _setModuleBatchEntry(
            moduleIds,
            moduleAddresses,
            index++,
            KernelModuleIds.COMPANY_REGISTRY_AUTHORITY,
            address(_companyRegistryApp)
        );
        // Standing President-registry authority (fixes the post-genesis freeze that left this pointer unregistered):
        // the HeadOfStateApp becomes the sole live writer of the President registry after genesis.
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.PRESIDENT_REGISTRY_AUTHORITY, address(_headOfStateApp)
        );
        // Standing Executive-registry authority: the CabinetApp is the sole live writer of the Executive registry
        // (Prime Minister + Cabinet) after genesis. The cabinet is left empty at genesis.
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, index++, KernelModuleIds.EXECUTIVE_REGISTRY_AUTHORITY, address(_cabinetApp)
        );

        _kernel.bootstrapSetModules(moduleIds, moduleAddresses);
    }

    function _configureOriginAuthorities() internal {
        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, address(_referendumApp));
        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Senate, address(_senateApp));
        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Office, address(_officeExecutor));
    }

    function _seedGenesisState() internal {
        GenesisCitizen[] memory citizens = _seedGenesisCitizens();
        _seedGenesisSenateSeats(citizens);
        _seedGenesisCongressTerm(citizens);
        _seedGenesisPresident(citizens);
        _seedGenesisOffices();
    }

    function _seedGenesisCitizens() internal returns (GenesisCitizen[] memory citizens) {
        uint256 citizenCount = vm.envUint("GENESIS_CITIZEN_COUNT");
        require(citizenCount != 0, "missing genesis citizens");
        require(citizenCount <= type(uint32).max, "too many genesis citizens");
        _genesisCitizenCount = citizenCount;

        citizens = new GenesisCitizen[](citizenCount);
        for (uint256 index = 0; index < citizenCount; ++index) {
            GenesisCitizen memory citizen = GenesisCitizen({
                personId: vm.envBytes32(_indexedGenesisKey("GENESIS_CITIZEN_", index, "_PERSON_ID")),
                wallet: vm.envAddress(_indexedGenesisKey("GENESIS_CITIZEN_", index, "_WALLET")),
                activeStake: vm.envUint(_indexedGenesisKey("GENESIS_CITIZEN_", index, "_ACTIVE_STAKE"))
            });
            require(citizen.personId != bytes32(0), "invalid genesis person");
            require(citizen.wallet != address(0), "invalid genesis wallet");
            require(citizen.activeStake >= MINIMUM_CITIZEN_STAKE, "genesis citizen below stake");
            _requireUniqueGenesisCitizen(citizens, index, citizen);

            _initialSetupAuthority.configureCitizen(
                citizen.personId,
                citizen.wallet,
                IdentityTypes.IdentityRecordInput({
                    metadataHash: vm.envBytes32(_indexedGenesisKey("GENESIS_CITIZEN_", index, "_METADATA_HASH")),
                    metadataURI: vm.envString(_indexedGenesisKey("GENESIS_CITIZEN_", index, "_METADATA_URI")),
                    verificationStatus: IdentityTypes.VerificationStatus.Verified,
                    citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
                    ageClass: IdentityTypes.AgeClass.Adult,
                    correctionFlag: false,
                    finalSuspension: false
                }),
                citizen.activeStake
            );

            citizens[index] = citizen;
        }
    }

    function _seedGenesisSenateSeats(GenesisCitizen[] memory citizens) internal {
        uint256 senateSeatCount = vm.envUint("GENESIS_SENATE_SEAT_COUNT");
        require(senateSeatCount >= SENATE_CANCELLATION_THRESHOLD, "genesis senate below threshold");
        require(senateSeatCount <= 100, "too many genesis senate seats");
        _genesisSenateSeatCount = _requireUint32(senateSeatCount, "senate count overflow");

        uint256[] memory selectedCitizenIndexes = new uint256[](senateSeatCount);
        for (uint256 seatIndex = 0; seatIndex < senateSeatCount; ++seatIndex) {
            uint256 citizenIndex = _readGenesisCitizenIndex(
                _indexedGenesisKey("GENESIS_SENATE_SEAT_", seatIndex, "_CITIZEN_INDEX"), citizens.length
            );
            _requireUniqueGenesisCitizenIndex(selectedCitizenIndexes, seatIndex, citizenIndex);
            selectedCitizenIndexes[seatIndex] = citizenIndex;

            _initialSetupAuthority.assignSenateSeat(
                _requireUint32(seatIndex, "senate seat index overflow"), citizens[citizenIndex].wallet
            );
        }
    }

    function _seedGenesisCongressTerm(GenesisCitizen[] memory citizens) internal {
        uint256 congressMemberCount = vm.envUint("GENESIS_CONGRESS_MEMBER_COUNT");
        require(congressMemberCount >= CONGRESS_SEAT_COUNT, "genesis congress below seats");
        require(congressMemberCount <= CONGRESS_MAX_CANDIDATE_COUNT, "too many genesis congress candidates");
        _genesisCongressSeatCount = CONGRESS_SEAT_COUNT;

        address[] memory members = new address[](congressMemberCount);
        uint256[] memory selectedCitizenIndexes = new uint256[](congressMemberCount);
        for (uint256 rankIndex = 0; rankIndex < congressMemberCount; ++rankIndex) {
            uint256 citizenIndex = _readGenesisCitizenIndex(
                _indexedGenesisKey("GENESIS_CONGRESS_MEMBER_", rankIndex, "_CITIZEN_INDEX"), citizens.length
            );
            _requireUniqueGenesisCitizenIndex(selectedCitizenIndexes, rankIndex, citizenIndex);
            require(citizens[citizenIndex].activeStake >= MINIMUM_CANDIDATE_STAKE, "genesis candidate below stake");

            selectedCitizenIndexes[rankIndex] = citizenIndex;
            members[rankIndex] = citizens[citizenIndex].wallet;
        }

        _initialSetupAuthority.seedCongressTerm(members);
    }

    function _seedGenesisPresident(GenesisCitizen[] memory citizens) internal {
        uint256 citizenIndex = _readGenesisCitizenIndex("GENESIS_PRESIDENT_CITIZEN_INDEX", citizens.length);
        bytes32 mandateHash = vm.envBytes32("GENESIS_PRESIDENT_MANDATE_HASH");
        require(mandateHash != bytes32(0), "invalid president mandate");

        uint64 termStart = uint64(block.timestamp);
        _presidentRegistry.setPresident(
            citizens[citizenIndex].wallet,
            citizens[citizenIndex].personId,
            mandateHash,
            termStart,
            termStart + PRESIDENT_TERM
        );
    }

    function _seedGenesisOffices() internal {
        _initialSetupAuthority.createOffice(
            FINANCE_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "Ministry of Finance", _financeOfficeAdmin
        );
        _initialSetupAuthority.createOffice(
            IDENTITY_OFFICE_ID, OfficeTypes.OfficeKind.IdentityOffice, "Identity Office", _identityOfficeAdmin
        );
        _initialSetupAuthority.createOffice(
            LAND_OFFICE_ID, OfficeTypes.OfficeKind.LandRegistryOffice, "Land Registry Office", _landOfficeAdmin
        );
        _initialSetupAuthority.createOffice(
            COMPANY_REGISTRY_OFFICE_ID,
            OfficeTypes.OfficeKind.CompanyRegistryOffice,
            "Company Registry Office",
            _companyRegistryOfficeAdmin
        );
    }

    /// @dev Seals the one-time setup authority and only then disables the bootstrap authorities.
    function _sealAndDisableBootstrap() internal {
        _initialSetupAuthority.seal();
        // L1: never disable the bootstrap authorities while the one-time setup authority is still live. A
        // modified run that skipped or silently failed sealing would otherwise leave a standing privileged
        // backdoor into the genesis registries.
        require(_initialSetupAuthority.isSealed(), "setup authority not sealed");
        _officeExecutor.disableBootstrapAuthority();
        _router.disableBootstrapAuthority();
        _kernel.disableBootstrapAuthority();
    }

    function _assertReadyForBootstrapDisable() internal view {
        require(
            _kernel.getModule(KernelModuleIds.INITIAL_SETUP_AUTHORITY) == address(_initialSetupAuthority),
            "initial setup authority not registered"
        );

        bytes32[] memory requiredOfficeIds = new bytes32[](4);
        requiredOfficeIds[0] = FINANCE_OFFICE_ID;
        requiredOfficeIds[1] = IDENTITY_OFFICE_ID;
        requiredOfficeIds[2] = LAND_OFFICE_ID;
        requiredOfficeIds[3] = COMPANY_REGISTRY_OFFICE_ID;
        _initialSetupAuthority.assertReadyForBootstrapDisable(
            _genesisCitizenCount, _genesisSenateSeatCount, _genesisCongressSeatCount, requiredOfficeIds
        );
        require(_presidentRegistry.currentPresident() != address(0), "genesis president not set");
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

    function _readGenesisCitizenIndex(string memory key, uint256 citizenCount) internal view returns (uint256 index) {
        index = vm.envUint(key);
        require(index < citizenCount, "genesis citizen index out of bounds");
    }

    function _requireUniqueGenesisCitizen(
        GenesisCitizen[] memory citizens,
        uint256 configuredCount,
        GenesisCitizen memory citizen
    ) internal pure {
        for (uint256 index = 0; index < configuredCount; ++index) {
            require(citizens[index].personId != citizen.personId, "duplicate genesis person");
            require(citizens[index].wallet != citizen.wallet, "duplicate genesis wallet");
        }
    }

    function _requireUniqueGenesisCitizenIndex(
        uint256[] memory selectedCitizenIndexes,
        uint256 configuredCount,
        uint256 citizenIndex
    ) internal pure {
        for (uint256 index = 0; index < configuredCount; ++index) {
            require(selectedCitizenIndexes[index] != citizenIndex, "duplicate genesis citizen index");
        }
    }

    function _requireUint32(uint256 value, string memory reason) internal pure returns (uint32 castValue) {
        require(value <= type(uint32).max, reason);

        // forge-lint: disable-next-line(unsafe-typecast)
        castValue = uint32(value);
    }

    function _indexedGenesisKey(string memory prefix, uint256 index, string memory suffix)
        internal
        pure
        returns (string memory key)
    {
        key = string.concat(prefix, _uintToString(index), suffix);
    }

    function _uintToString(uint256 value) internal pure returns (string memory text) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits += 1;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;

            // forge-lint: disable-next-line(unsafe-typecast)
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }

        text = string(buffer);
    }

    function _snapshot(address deployer) internal view returns (Deployment memory deployment) {
        deployment.deployer = deployer;
        deployment.llmToken = _llmTokenAddress;
        deployment.kernel = address(_kernel);
        deployment.timelock = address(_timelock);
        deployment.router = address(_router);
        deployment.initialSetupAuthority = address(_initialSetupAuthority);
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
        deployment.genesisCitizenCount = _genesisCitizenCount;
        deployment.genesisSenateSeatCount = _genesisSenateSeatCount;
        deployment.genesisCongressSeatCount = _genesisCongressSeatCount;
        deployment.genesisPresident = _presidentRegistry.currentPresident();
        deployment.genesisPresidentPersonId = _presidentRegistry.currentPresidentPersonId();
        deployment.financeOfficeAdmin = _financeOfficeAdmin;
        deployment.identityOfficeAdmin = _identityOfficeAdmin;
        deployment.landOfficeAdmin = _landOfficeAdmin;
        deployment.companyRegistryOfficeAdmin = _companyRegistryOfficeAdmin;
    }

    function _writeDeploymentJson(Deployment memory deployment) internal {
        string memory deploymentKey = "deployment";

        vm.serializeUint(deploymentKey, "chainId", block.chainid);
        vm.serializeAddress(deploymentKey, "deployer", deployment.deployer);
        vm.serializeAddress(deploymentKey, "llmToken", deployment.llmToken);
        vm.serializeAddress(deploymentKey, "constitutionKernel", deployment.kernel);
        vm.serializeAddress(deploymentKey, "actionTimelock", deployment.timelock);
        vm.serializeAddress(deploymentKey, "governanceRouter", deployment.router);
        vm.serializeAddress(deploymentKey, "initialSetupAuthority", deployment.initialSetupAuthority);
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
        vm.serializeUint(deploymentKey, "genesisCitizenCount", deployment.genesisCitizenCount);
        vm.serializeUint(deploymentKey, "genesisSenateSeatCount", deployment.genesisSenateSeatCount);
        vm.serializeUint(deploymentKey, "genesisCongressSeatCount", deployment.genesisCongressSeatCount);
        vm.serializeAddress(deploymentKey, "genesisPresident", deployment.genesisPresident);
        vm.serializeBytes32(deploymentKey, "genesisPresidentPersonId", deployment.genesisPresidentPersonId);
        vm.serializeAddress(deploymentKey, "financeOfficeAdmin", deployment.financeOfficeAdmin);
        vm.serializeAddress(deploymentKey, "identityOfficeAdmin", deployment.identityOfficeAdmin);
        vm.serializeAddress(deploymentKey, "landOfficeAdmin", deployment.landOfficeAdmin);
        string memory json =
            vm.serializeAddress(deploymentKey, "companyRegistryOfficeAdmin", deployment.companyRegistryOfficeAdmin);

        string memory path = string.concat(vm.projectRoot(), "/deployments/sepolia.json");
        vm.writeJson(json, path);
    }

    function _logDeployment(Deployment memory deployment) internal view {
        console2.log("Deployer:", deployment.deployer);
        console2.log("LLMToken:", deployment.llmToken);
        console2.log("Chain ID:", block.chainid);
        console2.log("ConstitutionKernel:", deployment.kernel);
        console2.log("ActionTimelock:", deployment.timelock);
        console2.log("GovernanceRouter:", deployment.router);
        console2.log("InitialSetupAuthority:", deployment.initialSetupAuthority);
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
        console2.log("PayoutQueue:", deployment.payoutQueue);
        console2.log("HeadOfStateApp:", deployment.headOfStateApp);
        console2.log("CabinetApp:", deployment.cabinetApp);
        console2.log("IdentityApp:", deployment.identityApp);
        console2.log("LandRegistryApp:", deployment.landRegistryApp);
        console2.log("CompanyRegistryApp:", deployment.companyRegistryApp);
        console2.log("OfficeExecutor:", deployment.officeExecutor);
        console2.logBytes32(deployment.financeOfficeId);
        console2.log("Finance Office Admin:", deployment.financeOfficeAdmin);
        console2.logBytes32(deployment.identityOfficeId);
        console2.log("Identity Office Admin:", deployment.identityOfficeAdmin);
        console2.logBytes32(deployment.landOfficeId);
        console2.log("Land Office Admin:", deployment.landOfficeAdmin);
        console2.logBytes32(deployment.companyRegistryOfficeId);
        console2.log("Company Registry Office Admin:", deployment.companyRegistryOfficeAdmin);
        console2.log("Genesis Citizen Count:", deployment.genesisCitizenCount);
        console2.log("Genesis Senate Seat Count:", deployment.genesisSenateSeatCount);
        console2.log("Genesis Congress Seat Count:", deployment.genesisCongressSeatCount);
        console2.log("Genesis President:", deployment.genesisPresident);
        console2.logBytes32(deployment.genesisPresidentPersonId);
    }
}
