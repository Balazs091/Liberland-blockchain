// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

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
import {GovernanceTypes} from "../contracts/types/GovernanceTypes.sol";
import {OfficeTypes} from "../contracts/types/OfficeTypes.sol";

contract Deploy is Script {
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000;
    uint256 internal constant MINIMUM_CANDIDATE_STAKE = 6_000;
    uint256 internal constant CANDIDATE_BOND_REQUIREMENT = 6_000;
    uint64 internal constant UNSTAKE_COOLDOWN = 7 days;
    uint64 internal constant MINIMUM_REFERENDUM_VOTING_DURATION = 3 days;
    uint256 internal constant CITIZEN_QUORUM = 10_000;
    uint256 internal constant CONGRESS_QUORUM = 8_000;
    uint256 internal constant CITIZEN_PROPOSAL_BOND = 6_000;
    uint256 internal constant CONSTITUTIONAL_FOR_VOTER_QUORUM = 2;
    uint16 internal constant CONSTITUTIONAL_FOR_STAKE_BPS = 5_000;
    uint32 internal constant CONGRESS_SEAT_COUNT = 2;
    uint32 internal constant CONGRESS_RUNNER_UP_COUNT = 2;
    uint32 internal constant CONGRESS_MAX_CANDIDATE_COUNT = 8;
    uint64 internal constant MINIMUM_NOMINATION_DURATION = 2 days;
    uint64 internal constant MINIMUM_ELECTION_VOTING_DURATION = 3 days;
    uint64 internal constant MAX_SCHEDULE_LEAD_TIME = 14 days;
    uint64 internal constant ELECTION_CYCLE_DURATION = 90 days;
    uint32 internal constant SENATE_CANCELLATION_THRESHOLD = 2;
    uint256 internal constant PUBLIC_VETO_THRESHOLD = 2;
    uint256 internal constant FINANCE_CLERK_OPERATIONS_LIMIT = 3 ether;
    uint256 internal constant FINANCE_CLERK_SALARY_LIMIT = 2 ether;

    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    bytes32 internal constant IDENTITY_OFFICE_ID = keccak256("office.identity");
    bytes32 internal constant LAND_OFFICE_ID = keccak256("office.land");

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

    struct Deployment {
        address deployer;
        address kernel;
        address timelock;
        address router;
        address identityAuthority;
        address stakeAuthority;
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
        address financeOfficeAdmin;
        address identityOfficeAdmin;
        address landOfficeAdmin;
    }

    function run() external returns (Deployment memory deployment) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        _financeOfficeAdmin = vm.envOr("FINANCE_ADMIN", deployer);
        _identityOfficeAdmin = vm.envOr("IDENTITY_ADMIN", deployer);
        _landOfficeAdmin = vm.envOr("LAND_ADMIN", deployer);

        vm.startBroadcast(deployerPrivateKey);
        _deployCore(deployer);
        _deployRegistries();
        _deployPoliciesAndApps(deployer);
        _registerModules();
        _configureOriginAuthorities();
        _bootstrapOffices();
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
        _identityAuthority = new MockModule(keccak256("sepolia.identity-authority"));
        _stakeAuthority = new MockModule(keccak256("sepolia.stake-authority"));

        (bytes32[] memory moduleIds, address[] memory moduleAddresses) = _allocateModuleBatch(4);
        _setModuleBatchEntry(moduleIds, moduleAddresses, 0, KernelModuleIds.GOVERNANCE_ROUTER, address(_router));
        _setModuleBatchEntry(moduleIds, moduleAddresses, 1, KernelModuleIds.ACTION_TIMELOCK, address(_timelock));
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 2, KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_identityAuthority)
        );
        _setModuleBatchEntry(
            moduleIds, moduleAddresses, 3, KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(_stakeAuthority)
        );
        _kernel.bootstrapSetModules(moduleIds, moduleAddresses);
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

    function _deployPoliciesAndApps(address deployer) internal {
        _citizenEligibilityPolicy =
            new CitizenEligibilityPolicy(address(_identityRegistry), address(_stakeRegistry), MINIMUM_CITIZEN_STAKE);
        _unstakingPolicy = new UnstakingPolicy(address(_stakeRegistry), UNSTAKE_COOLDOWN);
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

    function _registerModules() internal {
        (bytes32[] memory moduleIds, address[] memory moduleAddresses) = _allocateModuleBatch(32);
        uint256 index;

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

        _kernel.bootstrapSetModules(moduleIds, moduleAddresses);
    }

    function _configureOriginAuthorities() internal {
        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Referendum, address(_referendumApp));
        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Senate, address(_senateApp));
        _router.configureOriginAuthority(GovernanceTypes.ActionOrigin.Office, address(_officeExecutor));
    }

    function _bootstrapOffices() internal {
        _officeExecutor.bootstrapCreateOffice(
            FINANCE_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "Ministry of Finance", _financeOfficeAdmin
        );
        _officeExecutor.bootstrapCreateOffice(
            IDENTITY_OFFICE_ID, OfficeTypes.OfficeKind.IdentityOffice, "Identity Office", _identityOfficeAdmin
        );
        _officeExecutor.bootstrapCreateOffice(
            LAND_OFFICE_ID, OfficeTypes.OfficeKind.LandRegistryOffice, "Land Registry Office", _landOfficeAdmin
        );
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

    function _snapshot(address deployer) internal view returns (Deployment memory deployment) {
        deployment.deployer = deployer;
        deployment.kernel = address(_kernel);
        deployment.timelock = address(_timelock);
        deployment.router = address(_router);
        deployment.identityAuthority = address(_identityAuthority);
        deployment.stakeAuthority = address(_stakeAuthority);
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
        deployment.financeOfficeAdmin = _financeOfficeAdmin;
        deployment.identityOfficeAdmin = _identityOfficeAdmin;
        deployment.landOfficeAdmin = _landOfficeAdmin;
    }

    function _writeDeploymentJson(Deployment memory deployment) internal {
        string memory deploymentKey = "deployment";

        vm.serializeUint(deploymentKey, "chainId", block.chainid);
        vm.serializeAddress(deploymentKey, "deployer", deployment.deployer);
        vm.serializeAddress(deploymentKey, "constitutionKernel", deployment.kernel);
        vm.serializeAddress(deploymentKey, "actionTimelock", deployment.timelock);
        vm.serializeAddress(deploymentKey, "governanceRouter", deployment.router);
        vm.serializeAddress(deploymentKey, "identityAuthority", deployment.identityAuthority);
        vm.serializeAddress(deploymentKey, "stakeAuthority", deployment.stakeAuthority);
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
        vm.serializeAddress(deploymentKey, "financeOfficeAdmin", deployment.financeOfficeAdmin);
        vm.serializeAddress(deploymentKey, "identityOfficeAdmin", deployment.identityOfficeAdmin);
        string memory json = vm.serializeAddress(deploymentKey, "landOfficeAdmin", deployment.landOfficeAdmin);

        string memory path = string.concat(vm.projectRoot(), "/deployments/sepolia.json");
        vm.writeJson(json, path);
    }

    function _logDeployment(Deployment memory deployment) internal view {
        console2.log("Deployer:", deployment.deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("ConstitutionKernel:", deployment.kernel);
        console2.log("ActionTimelock:", deployment.timelock);
        console2.log("GovernanceRouter:", deployment.router);
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
        console2.log("Finance Office Admin:", deployment.financeOfficeAdmin);
        console2.logBytes32(deployment.identityOfficeId);
        console2.log("Identity Office Admin:", deployment.identityOfficeAdmin);
        console2.logBytes32(deployment.landOfficeId);
        console2.log("Land Office Admin:", deployment.landOfficeAdmin);
    }
}
