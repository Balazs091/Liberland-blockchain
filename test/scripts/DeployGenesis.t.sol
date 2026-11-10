// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {GovernanceTypes} from "../../contracts/types/GovernanceTypes.sol";
import {ICivicAppealReview} from "../../contracts/interfaces/ICivicAppealReview.sol";
import {ICitizenEligibilityPolicy} from "../../contracts/interfaces/ICitizenEligibilityPolicy.sol";
import {IJusticeApp} from "../../contracts/interfaces/IJusticeApp.sol";
import {IJusticeIdentityWriter} from "../../contracts/interfaces/IJusticeIdentityWriter.sol";
import {Deploy} from "../../scripts/Deploy.s.sol";
import {ITreasurySpendingPolicy} from "../../contracts/interfaces/ITreasurySpendingPolicy.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {LiberlandMerit} from "../../contracts/tokens/LiberlandMerit.sol";
import {EthereumMainnetParameters} from "../../scripts/parameters/EthereumMainnetParameters.sol";
import {MockUSDC} from "../../contracts/mocks/MockUSDC.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {JusticeTypes} from "../../contracts/types/JusticeTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";
import {ModuleUpgradePlanRegistry} from "../../contracts/registries/ModuleUpgradePlanRegistry.sol";
import {ReferendumApp} from "../../contracts/apps/ReferendumApp.sol";

contract ConfigurableCapLlmToken is ERC20 {
    uint256 public immutable cap;

    constructor(uint256 cap_) ERC20("Configured LLM", "LLM") {
        cap = cap_;
    }
}

contract DeployGenesisHarness is Deploy {
    address private _congressAuthorityBeforeGenesis;

    function validateLlmTokenForTest(address token) external {
        _llmTokenAddress = token;
        _validateLlmToken();
    }

    function validateUsdcTokenForTest(address token) external {
        _usdcTokenAddress = token;
        _validateUsdcToken();
    }

    function loadProductionTokensForTest() external returns (address llm, address usdc) {
        _loadProductionTokens();
        return (_llmTokenAddress, _usdcTokenAddress);
    }

    function deployForTest() external {
        _prepareForTest();
        _completeForTest();
    }

    function prepareJusticeForTest() external {
        _loadJusticeSettings();
        _prepareForTest();
    }

    function completeJusticeForTest() external {
        _loadJusticeSettings();
        _completeForTest();
    }

    function _prepareForTest() private {
        address deployer = address(this);

        _financeOfficeAdmin = address(0xF1A0);
        _identityOfficeAdmin = address(0x1D);
        _landOfficeAdmin = address(0x1A2D);
        _companyRegistryOfficeAdmin = address(0xC0);
        _civicReviewers = [address(0xA001), address(0xA002), address(0xA003), address(0xA004), address(0xA005)];

        // System money is ERC20: genesis wiring needs a deployed LLM token plus the treasury spending asset set.
        _llmTokenAddress = address(new LiberlandMerit(address(this), 100_000 * 1e18));
        // Local test double at the canonical address; this is not a mainnet USDC fork or code attestation.
        vm.etch(EthereumMainnetParameters.USDC_TOKEN, address(new MockUSDC()).code);
        address usdcToken = EthereumMainnetParameters.USDC_TOKEN;
        _usdcTokenAddress = usdcToken;
        _treasuryAssetLimits.push(
            ITreasurySpendingPolicy.AssetSpendingLimit({
                asset: _llmTokenAddress, clerkOperationsLimit: 3_000 * 1e18, clerkSalaryLimit: 2_000 * 1e18
            })
        );
        _treasuryAssetLimits.push(
            ITreasurySpendingPolicy.AssetSpendingLimit({
                asset: usdcToken, clerkOperationsLimit: 3_000 * 1e6, clerkSalaryLimit: 2_000 * 1e6
            })
        );

        _deployCore(deployer);
        _deployRegistries();
        _deployPoliciesAndApps(deployer);
        _registerModules();
        _configureOriginAuthorities();
        _congressAuthorityBeforeGenesis = _kernel.getModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY);
        _seedGenesisState();
        if (_justiceEnabled) _assertJusticeGenesis();
    }

    function _completeForTest() private {
        // Production completion is a separate invocation on a confirmed later block.
        vm.roll(block.number + 1);
        _loadGenesisCompletionState(address(_kernel));
        if (_justiceEnabled) _assertJusticeGenesis();
        _seedGenesisCongressTerm(_readSeededCitizens());
        _activateStandingCongressAuthority();
        _activateStandingReferendumAuthority();
        if (_justiceEnabled) _activateStandingJusticeAuthority();
        _assertReadyForBootstrapDisable();
        _sealAndDisableBootstrap();
    }

    function assertCivicReviewTopology() external view {
        address committee = _kernel.getModule(KernelModuleIds.CIVIC_APPEAL_AUTHORITY);
        require(ICivicAppealReview(committee).identityApp() == address(_identityApp), "review app binding");
        require(
            _kernel.moduleClass(KernelModuleIds.CIVIC_APPEAL_AUTHORITY) == GovernanceTypes.ModuleClass.Authority,
            "review class"
        );
        for (uint256 i; i < 5; ++i) {
            require(ICivicAppealReview(committee).reviewerAt(i) == _civicReviewers[i], "reviewer configuration");
        }
    }

    function totalIdentityCount() external view returns (uint256 count) {
        return _identityRegistry.totalIdentityCount();
    }

    function identityRecord(bytes32 personId) external view returns (IdentityTypes.IdentityRecord memory record) {
        return _identityRegistry.getIdentityRecord(personId);
    }

    function activeStakeOf(bytes32 personId) external view returns (uint256 amount) {
        return _stakeRegistry.activeStakeOf(personId);
    }

    function occupiedSenateSeatCount() external view returns (uint32 count) {
        return _senateSeatRegistry.occupiedSeatCount();
    }

    function currentCongressOccupiedSeatCount() external view returns (uint32 count) {
        return _congressCandidateRegistry.getCurrentOfficeTerm().occupiedSeatCount;
    }

    function latestCongressCycleId() external view returns (uint256 cycleId) {
        return _congressCandidateRegistry.latestCycleId();
    }

    function congressCycle(uint256 cycleId) external view returns (ElectionTypes.CongressCycleRecord memory record) {
        return _congressCandidateRegistry.getCycle(cycleId);
    }

    function currentPresident() external view returns (address president) {
        return _presidentRegistry.currentPresident();
    }

    function officeRecord(bytes32 officeId) external view returns (OfficeTypes.OfficeRecord memory record) {
        return _officeRegistry.getOfficeRecord(officeId);
    }

    function setupAuthoritySealed() external view returns (bool isSetupSealed) {
        return _initialSetupAuthority.isSealed();
    }

    function kernelBootstrapAuthority() external view returns (address authority) {
        return IConstitutionKernel(address(_kernel)).bootstrapAuthority();
    }

    function routerBootstrapAuthority() external view returns (address authority) {
        return _router.bootstrapAuthority();
    }

    function officeExecutorBootstrapAuthority() external view returns (address authority) {
        return _officeExecutor.bootstrapAuthority();
    }

    function productionStandingAuthorities()
        external
        view
        returns (address identityApp, address identityAuthority, address congressApp, address congressAuthority)
    {
        return (
            address(_identityApp),
            _kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY),
            address(_congressElectionApp),
            _kernel.getModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY)
        );
    }

    function congressAuthorityBeforeGenesis() external view returns (address authority) {
        return _congressAuthorityBeforeGenesis;
    }

    function initialSetupAuthorityForTest() external view returns (address authority) {
        return address(_initialSetupAuthority);
    }

    function snapshotForTest() external view returns (Deployment memory) {
        return _snapshot(address(this));
    }

    function productionLaunchModules()
        external
        view
        returns (address decisionApp, address lendingPool, address ministryTreasury)
    {
        return (address(_decisionApp), address(_lendingPool), address(_ministryTreasury));
    }

    function productionLandTopology() external view returns (address policy, address app, address authority) {
        return (
            _kernel.getModule(KernelModuleIds.LAND_PARTY_POLICY),
            address(_landRegistryApp),
            _kernel.getModule(KernelModuleIds.LAND_REGISTRY_AUTHORITY)
        );
    }

    function productionLendingParameters()
        external
        view
        returns (
            uint16 maxLtvBps,
            uint16 liquidationThresholdBps,
            uint16 liquidationBonusBps,
            uint16 reserveFactorBps,
            uint256 perPersonDebtCap,
            uint256 baseRatePerSecondRay,
            uint256 kinkRatePerSecondRay,
            uint256 fullRatePerSecondRay
        )
    {
        return (
            _lendingRiskPolicy.maxLtvBps(),
            _lendingRiskPolicy.liquidationThresholdBps(),
            _lendingRiskPolicy.liquidationBonusBps(),
            _lendingRiskPolicy.reserveFactorBps(),
            _lendingRiskPolicy.maxDebtPerPerson(),
            _lendingInterestRatePolicy.borrowRatePerSecond(0),
            _lendingInterestRatePolicy.borrowRatePerSecond(8e26),
            _lendingInterestRatePolicy.borrowRatePerSecond(1e27)
        );
    }
}

contract DeployGenesisTest is Test {
    bytes32 internal constant PERSON_ONE_ID = bytes32(uint256(1));
    bytes32 internal constant PERSON_TWO_ID = bytes32(uint256(2));
    bytes32 internal constant PERSON_THREE_ID = bytes32(uint256(3));
    bytes32 internal constant PERSON_FOUR_ID = bytes32(uint256(4));
    bytes32 internal constant PERSON_FIVE_ID = bytes32(uint256(5));
    bytes32 internal constant PERSON_SIX_ID = bytes32(uint256(6));
    bytes32 internal constant PERSON_SEVEN_ID = bytes32(uint256(7));
    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    bytes32 internal constant IDENTITY_OFFICE_ID = keccak256("office.identity");
    bytes32 internal constant LAND_OFFICE_ID = keccak256("office.land");
    bytes32 internal constant COMPANY_REGISTRY_OFFICE_ID = keccak256("office.company-registry");

    address internal constant WALLET_ONE = address(0xA11CE);
    address internal constant WALLET_TWO = address(0xB0B);
    address internal constant WALLET_THREE = address(0xCAFE);
    address internal constant WALLET_FOUR = address(0xD00D);
    address internal constant WALLET_FIVE = address(0xF1F7);
    address internal constant WALLET_SIX = address(0x51C);
    address internal constant WALLET_SEVEN = address(0x5E7E);

    function test_ProductionValidationRejectsWrongLlmCap() public {
        DeployGenesisHarness harness = new DeployGenesisHarness();
        ConfigurableCapLlmToken wrongCapToken = new ConfigurableCapLlmToken(69_000_000 * 1e18);

        vm.expectRevert("LLM token cap must be 70000000");
        harness.validateLlmTokenForTest(address(wrongCapToken));
    }

    function test_ProductionValidationRejectsWrongUsdcDecimals() public {
        DeployGenesisHarness harness = new DeployGenesisHarness();
        LLMToken eighteenDecimalToken = new LLMToken();

        vm.etch(EthereumMainnetParameters.USDC_TOKEN, address(eighteenDecimalToken).code);
        vm.expectRevert("USDC token must use 6 decimals");
        harness.validateUsdcTokenForTest(EthereumMainnetParameters.USDC_TOKEN);
    }

    function test_ProductionValidationRejectsSixDecimalUsdcLookalike() public {
        DeployGenesisHarness harness = new DeployGenesisHarness();
        MockUSDC lookalike = new MockUSDC();
        vm.expectRevert("USDC_TOKEN must be canonical Ethereum USDC");
        harness.validateUsdcTokenForTest(address(lookalike));
    }

    function test_ProductionTokenPreflightPinsUsdcAndRejectsInvalidConfiguration() public {
        DeployGenesisHarness harness = new DeployGenesisHarness();
        LiberlandMerit merit = new LiberlandMerit(address(this), 100_000 * 1e18);
        // Forge's environment is process-global; mutation cases run sequentially to avoid cross-test races.
        vm.setEnv("LLM_TOKEN", vm.toString(address(merit)));
        vm.setEnv("USDC_TOKEN", vm.toString(EthereumMainnetParameters.USDC_TOKEN));
        vm.etch(EthereumMainnetParameters.USDC_TOKEN, address(new MockUSDC()).code);
        (address llm, address usdc) = harness.loadProductionTokensForTest();
        assertEq(llm, address(merit));
        assertEq(usdc, EthereumMainnetParameters.USDC_TOKEN);
        vm.setEnv("USDC_TOKEN", vm.toString(address(new MockUSDC())));
        vm.expectRevert("USDC_TOKEN must be canonical Ethereum USDC");
        harness.loadProductionTokensForTest();
        vm.setEnv("USDC_TOKEN", vm.toString(EthereumMainnetParameters.USDC_TOKEN));
        vm.etch(EthereumMainnetParameters.USDC_TOKEN, hex"");
        vm.expectRevert("USDC_TOKEN must be a contract");
        harness.loadProductionTokensForTest();
    }

    function test_DeploySeedsDeterministicGenesisBeforeSeal() public {
        _setGenesisEnv();

        DeployGenesisHarness harness = new DeployGenesisHarness();
        harness.deployForTest();
        harness.assertCivicReviewTopology();

        assertEq(harness.totalIdentityCount(), 7);
        assertEq(harness.identityRecord(PERSON_ONE_ID).metadataHash, keccak256("genesis-citizen-one"));
        assertEq(
            uint256(harness.identityRecord(PERSON_TWO_ID).citizenshipStatus),
            uint256(IdentityTypes.CitizenshipStatus.Citizen)
        );
        assertEq(harness.activeStakeOf(PERSON_THREE_ID), 12_000 * 1e18);

        assertEq(harness.occupiedSenateSeatCount(), 2);
        assertEq(harness.currentCongressOccupiedSeatCount(), 7);
        assertEq(harness.latestCongressCycleId(), 2);

        ElectionTypes.CongressCycleRecord memory continuityCycle = harness.congressCycle(2);
        assertEq(uint256(continuityCycle.status), uint256(ElectionTypes.ElectionStatus.CandidateRegistration));
        assertEq(continuityCycle.candidateCount, 7);
        assertEq(continuityCycle.votingPowerSnapshotBlock, block.number - 1);
        assertEq(continuityCycle.seatCount, 7);
        assertEq(continuityCycle.votingEnd % 1 days, 17 hours);
        assertEq(continuityCycle.votingEnd, ((block.timestamp / 1 days) + 30) * 1 days + 17 hours);
        assertEq(harness.currentPresident(), WALLET_ONE);

        assertEq(harness.officeRecord(FINANCE_OFFICE_ID).admin, address(0xF1A0));
        assertEq(harness.officeRecord(IDENTITY_OFFICE_ID).admin, address(0x1D));
        assertEq(harness.officeRecord(LAND_OFFICE_ID).admin, address(0x1A2D));
        assertEq(harness.officeRecord(COMPANY_REGISTRY_OFFICE_ID).admin, address(0xC0));

        assertTrue(harness.setupAuthoritySealed());
        assertEq(harness.kernelBootstrapAuthority(), address(0));
        assertEq(harness.routerBootstrapAuthority(), address(0));
        assertEq(harness.officeExecutorBootstrapAuthority(), address(0));
        assertEq(harness.congressAuthorityBeforeGenesis(), harness.initialSetupAuthorityForTest());

        (address identityApp, address identityAuthority, address congressApp, address congressAuthority) =
            harness.productionStandingAuthorities();
        assertEq(identityAuthority, identityApp);
        assertEq(congressAuthority, congressApp);
        assertFalse(harness.snapshotForTest().justice.enabled);

        (address decisionApp, address lendingPool, address ministryTreasury) = harness.productionLaunchModules();
        assertTrue(decisionApp.code.length != 0);
        assertTrue(lendingPool.code.length != 0);
        assertTrue(ministryTreasury.code.length != 0);

        (address landPartyPolicy, address landApp, address landAuthority) = harness.productionLandTopology();
        assertTrue(landPartyPolicy.code.length != 0);
        assertEq(landAuthority, landApp);

        _assertProductionLendingParameters(harness);
        _assertProductionUpgradeTopology(harness);
        // Both profiles share process-global environment keys, so rehearse them sequentially in this test.
        _assertJusticeGenesisProfile();
    }

    function _assertProductionUpgradeTopology(DeployGenesisHarness harness) private {
        Deploy.Deployment memory deployment = harness.snapshotForTest();
        IConstitutionKernel kernel = IConstitutionKernel(deployment.kernel);
        ModuleUpgradePlanRegistry plans = ModuleUpgradePlanRegistry(deployment.moduleUpgradePlanRegistry);
        assertEq(kernel.getModule(KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY), address(plans));
        assertEq(plans.kernel(), address(kernel));
        assertEq(
            uint256(kernel.moduleClass(KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY)),
            uint256(GovernanceTypes.ModuleClass.State)
        );
        assertTrue(deployment.referendumProposalValidator.code.length != 0);
        assertEq(deployment.referendumProposalValidator, ReferendumApp(deployment.referendumApp).proposalValidator());

        // Plan publication remains permissionless after sealing; it grants no pointer-changing authority.
        ModuleUpgradePlanRegistry replacement = new ModuleUpgradePlanRegistry(address(kernel));
        GovernanceTypes.ModuleUpdate[] memory updates = new GovernanceTypes.ModuleUpdate[](1);
        updates[0] = GovernanceTypes.ModuleUpdate(
            KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY,
            address(plans),
            address(replacement),
            address(replacement).codehash
        );
        vm.prank(address(0xC111));
        bytes32 planId = plans.publishPlan(updates, keccak256("synthetic production upgrade review evidence"));
        assertTrue(plans.planExists(planId));
        assertEq(kernel.getModule(KernelModuleIds.MODULE_UPGRADE_PLAN_REGISTRY), address(plans));
    }

    function _assertJusticeGenesisProfile() private {
        _setEnv("JUSTICE_ENABLED", "true");
        _setEnv("GENESIS_CITIZEN_COUNT", "9");
        _setCitizenEnv(7, bytes32(uint256(8)), address(0x8888), 8_000 * 1e18, keccak256("genesis-justice-eight"));
        _setCitizenEnv(8, bytes32(uint256(9)), address(0x9999), 8_000 * 1e18, keccak256("genesis-justice-nine"));

        bytes32 rulesHash = keccak256("synthetic justice charter");
        uint256 termEnd = block.timestamp + 120 days;
        _setEnv("JUSTICE_RULES_HASH", vm.toString(rulesHash));
        _setEnv("JUSTICE_TERM_END_TIMESTAMP", vm.toString(termEnd));
        _setEnv("JUSTICE_MAX_RESTRICTION_SECONDS", vm.toString(uint256(90 days)));
        _setEnv("JUSTICE_ALLOWED_RIGHTS_MASK", "31");
        _setEnv("JUSTICE_ADMISSION_ROSTER", _roster(2, 3, 4));
        _setEnv("JUSTICE_ANNULMENT_ROSTER", _roster(1, 5, 6));
        _setEnv("JUSTICE_ANNULMENT_REVIEW_ROSTER", _roster(7, 8, 9));
        _setEnv("JUSTICE_COUNCIL_ROSTER", _roster(1, 2, 3));
        _setEnv("JUSTICE_PANEL_ROSTER", _roster(4, 5, 6));

        DeployGenesisHarness harness = new DeployGenesisHarness();
        harness.prepareJusticeForTest();
        Deploy.Deployment memory prepared = harness.snapshotForTest();
        Deploy.JusticeDeployment memory justice = prepared.justice;
        IConstitutionKernel kernel = IConstitutionKernel(prepared.kernel);
        assertTrue(justice.enabled);
        assertEq(justice.charter.rulesHash, rulesHash);
        assertEq(justice.charter.termEndsAt, termEnd);
        assertNotEq(justice.rostersHash, bytes32(0));
        assertEq(prepared.identityApp, address(0));
        assertEq(prepared.civicAppealReview, address(0));
        assertEq(kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY), prepared.initialSetupAuthority);
        assertFalse(IJusticeApp(justice.app).isCurrent());

        _setEnv("JUSTICE_ENABLED", "false");
        vm.expectRevert("prepared justice profile mismatch");
        harness.completeJusticeForTest();
        _setEnv("JUSTICE_ENABLED", "true");
        _setEnv("JUSTICE_PANEL_ROSTER", _roster(4, 5, 7));
        vm.expectRevert("justice roster mismatch");
        harness.completeJusticeForTest();
        _setEnv("JUSTICE_PANEL_ROSTER", _roster(4, 5, 6));
        _setEnv("JUSTICE_TERM_END_TIMESTAMP", vm.toString(termEnd + 1 days));
        vm.expectRevert("justice charter mismatch or expired");
        harness.completeJusticeForTest();
        _setEnv("JUSTICE_TERM_END_TIMESTAMP", vm.toString(termEnd));

        harness.completeJusticeForTest();
        _setEnv("JUSTICE_ENABLED", "false");
        _setEnv("GENESIS_CITIZEN_COUNT", "7");
        assertTrue(IJusticeApp(justice.app).isCurrent());
        assertEq(kernel.getModule(KernelModuleIds.JUSTICE_APP), justice.app);
        assertEq(kernel.getModule(KernelModuleIds.IDENTITY_WRITER), justice.app);
        assertEq(kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY), justice.identityWriter);
        assertEq(kernel.getModule(KernelModuleIds.MEMBERSHIP_REGISTRY), justice.membershipRegistry);
        assertEq(kernel.getModule(KernelModuleIds.JUSTICE_DECISIONS), justice.decisions);
        assertEq(kernel.getModule(KernelModuleIds.JUSTICE_COMPENSATION), justice.compensation);
        assertEq(
            ICitizenEligibilityPolicy(prepared.citizenEligibilityPolicy).membershipRegistry(),
            justice.membershipRegistry
        );
        assertEq(harness.totalIdentityCount(), 9);
        assertEq(harness.currentCongressOccupiedSeatCount(), 7);
        assertTrue(harness.setupAuthoritySealed());
        assertEq(harness.kernelBootstrapAuthority(), address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConstitutionKernel.ModuleNotRegistered.selector, KernelModuleIds.CIVIC_APPEAL_AUTHORITY
            )
        );
        kernel.getModule(KernelModuleIds.CIVIC_APPEAL_AUTHORITY);

        vm.prank(WALLET_SEVEN);
        IJusticeIdentityWriter(justice.identityWriter).renounceCitizenship();
        assertEq(
            uint256(harness.identityRecord(PERSON_SEVEN_ID).citizenshipStatus),
            uint256(IdentityTypes.CitizenshipStatus.None)
        );
        assertEq(harness.activeStakeOf(PERSON_SEVEN_ID), 10_000 * 1e18);
    }

    function _roster(uint256 a, uint256 b, uint256 c) private pure returns (string memory) {
        return string.concat(vm.toString(bytes32(a)), ",", vm.toString(bytes32(b)), ",", vm.toString(bytes32(c)));
    }

    function _assertProductionLendingParameters(DeployGenesisHarness harness) private view {
        (
            uint16 maxLtvBps,
            uint16 liquidationThresholdBps,
            uint16 liquidationBonusBps,
            uint16 reserveFactorBps,
            uint256 perPersonDebtCap,
            uint256 baseRatePerSecondRay,
            uint256 kinkRatePerSecondRay,
            uint256 fullRatePerSecondRay
        ) = harness.productionLendingParameters();
        assertEq(maxLtvBps, 3_000);
        assertEq(liquidationThresholdBps, 4_000);
        assertEq(liquidationBonusBps, 1_500);
        assertEq(reserveFactorBps, 1_500);
        assertEq(perPersonDebtCap, 100_000 * 1e6);
        assertEq(baseRatePerSecondRay, uint256(500) * 1e27 / (10_000 * 365 days));
        assertEq(kinkRatePerSecondRay, uint256(1_300) * 1e27 / (10_000 * 365 days));
        assertEq(fullRatePerSecondRay, uint256(11_300) * 1e27 / (10_000 * 365 days));
    }

    function _setGenesisEnv() private {
        _setEnv("GENESIS_CITIZEN_COUNT", "7");
        // LLM uses standard 18 decimals; genesis stakes are base units (whole LLM * 1e18).
        _setCitizenEnv(0, PERSON_ONE_ID, WALLET_ONE, 20_000 * 1e18, keccak256("genesis-citizen-one"));
        _setCitizenEnv(1, PERSON_TWO_ID, WALLET_TWO, 7_500 * 1e18, keccak256("genesis-citizen-two"));
        _setCitizenEnv(2, PERSON_THREE_ID, WALLET_THREE, 12_000 * 1e18, keccak256("genesis-citizen-three"));
        _setCitizenEnv(3, PERSON_FOUR_ID, WALLET_FOUR, 6_000 * 1e18, keccak256("genesis-citizen-four"));
        _setCitizenEnv(4, PERSON_FIVE_ID, WALLET_FIVE, 8_000 * 1e18, keccak256("genesis-citizen-five"));
        _setCitizenEnv(5, PERSON_SIX_ID, WALLET_SIX, 9_000 * 1e18, keccak256("genesis-citizen-six"));
        _setCitizenEnv(6, PERSON_SEVEN_ID, WALLET_SEVEN, 10_000 * 1e18, keccak256("genesis-citizen-seven"));

        _setEnv("GENESIS_SENATE_SEAT_COUNT", "2");
        _setEnv("GENESIS_SENATE_SEAT_0_CITIZEN_INDEX", "0");
        _setEnv("GENESIS_SENATE_SEAT_1_CITIZEN_INDEX", "2");

        _setEnv("GENESIS_CONGRESS_MEMBER_COUNT", "7");
        _setEnv("GENESIS_CONGRESS_MEMBER_0_CITIZEN_INDEX", "0");
        _setEnv("GENESIS_CONGRESS_MEMBER_1_CITIZEN_INDEX", "2");
        _setEnv("GENESIS_CONGRESS_MEMBER_2_CITIZEN_INDEX", "1");
        _setEnv("GENESIS_CONGRESS_MEMBER_3_CITIZEN_INDEX", "3");
        _setEnv("GENESIS_CONGRESS_MEMBER_4_CITIZEN_INDEX", "4");
        _setEnv("GENESIS_CONGRESS_MEMBER_5_CITIZEN_INDEX", "5");
        _setEnv("GENESIS_CONGRESS_MEMBER_6_CITIZEN_INDEX", "6");
        _setEnv(
            "GENESIS_CONGRESS_CYCLE_END_TIMESTAMP", vm.toString(((block.timestamp / 1 days) + 30) * 1 days + 17 hours)
        );

        _setEnv("GENESIS_PRESIDENT_CITIZEN_INDEX", "0");
        _setEnv("GENESIS_PRESIDENT_MANDATE_HASH", vm.toString(keccak256("genesis-president-mandate")));
    }

    function _setCitizenEnv(uint256 index, bytes32 personId, address wallet, uint256 activeStake, bytes32 metadataHash)
        private
    {
        string memory prefix = string.concat("GENESIS_CITIZEN_", vm.toString(index));
        _setEnv(string.concat(prefix, "_PERSON_ID"), vm.toString(personId));
        _setEnv(string.concat(prefix, "_WALLET"), vm.toString(wallet));
        _setEnv(string.concat(prefix, "_ACTIVE_STAKE"), vm.toString(activeStake));
        _setEnv(string.concat(prefix, "_METADATA_HASH"), vm.toString(metadataHash));
        _setEnv(string.concat(prefix, "_METADATA_URI"), string.concat("ipfs://genesis/citizen-", vm.toString(index)));
    }

    function _setEnv(string memory key, string memory value) private {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv(key, value);
    }
}
