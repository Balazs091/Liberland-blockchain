// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {DecisionApp} from "../../contracts/apps/DecisionApp.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IDecisionApp} from "../../contracts/interfaces/IDecisionApp.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {LLMToken} from "../../contracts/mocks/LLMToken.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {MockUSDC} from "../../contracts/mocks/MockUSDC.sol";
import {CongressCandidateRegistry} from "../../contracts/registries/CongressCandidateRegistry.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {OfficeRegistry} from "../../contracts/registries/OfficeRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {DecisionTypes} from "../../contracts/types/DecisionTypes.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

/// @title Milestone9DecisionsTest
/// @notice Covers bounded Congress and ministry decisions for ERC20 movement, clerk decisions, and LLM staking.
contract Milestone9DecisionsTest is Test {
    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    bytes32 internal constant RECIPIENT_PERSON_ID = bytes32(uint256(100));

    address internal constant CONGRESS_MEMBER_ONE = address(0xA11CE);
    address internal constant CONGRESS_MEMBER_TWO = address(0xB0B);
    address internal constant CONGRESS_MEMBER_THREE = address(0xCAFE);
    address internal constant CONGRESS_RUNNER_UP = address(0xD00D);
    address internal constant CONGRESS_SOURCE = address(0xC010);
    address internal constant MINISTER_OF_FINANCE = address(0xF1A0);
    address internal constant FINANCE_CLERK = address(0xF1A1);
    address internal constant TREASURY_RECIPIENT = address(0xBEEF);

    ConstitutionKernel internal kernel;
    MockModule internal congressAuthority;
    MockModule internal identityAuthority;
    MockModule internal officeAuthority;
    MockModule internal stakeAuthority;
    CongressCandidateRegistry internal congressCandidateRegistry;
    IdentityRegistry internal identityRegistry;
    OfficeRegistry internal officeRegistry;
    StakeRegistry internal stakeRegistry;
    LLMToken internal llmToken;
    MockUSDC internal usdc;
    DecisionApp internal decisionApp;

    function setUp() public {
        kernel = new ConstitutionKernel(address(this));
        congressAuthority = new MockModule(keccak256("decision.congress-authority"));
        identityAuthority = new MockModule(keccak256("decision.identity-authority"));
        officeAuthority = new MockModule(keccak256("decision.office-authority"));
        stakeAuthority = new MockModule(keccak256("decision.stake-authority"));

        congressCandidateRegistry = new CongressCandidateRegistry(address(kernel));
        identityRegistry = new IdentityRegistry(address(kernel));
        officeRegistry = new OfficeRegistry(address(kernel));
        stakeRegistry = new StakeRegistry(address(kernel));
        llmToken = new LLMToken();
        usdc = new MockUSDC();
        decisionApp = new DecisionApp(
            address(congressCandidateRegistry),
            address(identityRegistry),
            address(officeRegistry),
            address(stakeRegistry),
            address(llmToken)
        );

        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY_AUTHORITY, address(congressAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(identityAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.OFFICE_REGISTRY_AUTHORITY, address(officeAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_REGISTRY_AUTHORITY, address(stakeAuthority));
        kernel.bootstrapSetModule(KernelModuleIds.STAKE_DEPOSIT_AUTHORITY, address(decisionApp));
        kernel.bootstrapSetModule(KernelModuleIds.DECISION_APP, address(decisionApp));

        _registerIdentity(RECIPIENT_PERSON_ID, TREASURY_RECIPIENT);
        _registerOffice(FINANCE_OFFICE_ID, OfficeTypes.OfficeKind.MinistryOfFinance, "Ministry of Finance");
        _seedCongressTerm(1);
    }

    function test_CongressDecision_TransfersERC20AfterMajoritySupport() public {
        bytes32 decisionId = keccak256("decision.congress.usdc-ministry-budget");
        uint256 amount = 250_000e6;
        usdc.mint(CONGRESS_SOURCE, amount);

        vm.prank(CONGRESS_MEMBER_ONE);
        decisionApp.createCongressTokenTransferDecision(
            decisionId,
            CONGRESS_SOURCE,
            address(usdc),
            MINISTER_OF_FINANCE,
            amount,
            keccak256("budget-to-finance"),
            "ipfs://budget-to-finance"
        );

        DecisionTypes.DecisionRecord memory prepared = decisionApp.getDecision(decisionId);
        assertEq(uint256(prepared.scope), uint256(DecisionTypes.DecisionScope.Congress));
        assertEq(uint256(prepared.action), uint256(DecisionTypes.DecisionAction.ERC20Transfer));
        assertEq(prepared.supportCount, 1);
        assertEq(prepared.supportRequired, 2);
        assertTrue(decisionApp.hasCongressSupported(decisionId, CONGRESS_MEMBER_ONE));

        vm.expectRevert(abi.encodeWithSelector(IDecisionApp.CongressDecisionNotApproved.selector, decisionId, 1, 2));
        decisionApp.executeCongressDecision(decisionId);

        vm.prank(CONGRESS_MEMBER_TWO);
        decisionApp.supportCongressDecision(decisionId);

        vm.prank(CONGRESS_SOURCE);
        usdc.approve(address(decisionApp), amount);

        decisionApp.executeCongressDecision(decisionId);

        assertEq(usdc.balanceOf(MINISTER_OF_FINANCE), amount);
        DecisionTypes.DecisionRecord memory executed = decisionApp.getDecision(decisionId);
        assertEq(uint256(executed.status), uint256(DecisionTypes.DecisionStatus.Executed));
        assertEq(executed.executedBy, address(this));
    }

    function test_CongressDecision_CannotBeApprovedByLaterCongressTerm() public {
        bytes32 decisionId = keccak256("decision.congress.stale");
        uint256 amount = 100_000e6;
        usdc.mint(CONGRESS_SOURCE, amount);

        vm.prank(CONGRESS_MEMBER_ONE);
        decisionApp.createCongressTokenTransferDecision(
            decisionId,
            CONGRESS_SOURCE,
            address(usdc),
            MINISTER_OF_FINANCE,
            amount,
            keccak256("stale-budget"),
            "ipfs://stale-budget"
        );

        _seedCongressTerm(2);

        vm.prank(CONGRESS_MEMBER_ONE);
        vm.expectRevert(abi.encodeWithSelector(IDecisionApp.CongressDecisionTermChanged.selector, decisionId, 1, 2));
        decisionApp.supportCongressDecision(decisionId);
    }

    function test_CongressDecision_RegistersNewOfficeAfterMajoritySupport() public {
        bytes32 decisionId = keccak256("decision.congress.new-land-office");
        bytes32 newOfficeId = keccak256("office.land-registry.west");
        address newOfficeAdmin = address(0x0FF1);

        vm.prank(CONGRESS_MEMBER_ONE);
        decisionApp.createCongressRegisterOfficeDecision(
            decisionId,
            newOfficeId,
            OfficeTypes.OfficeKind.LandRegistryOffice,
            "Western Land Registry Office",
            newOfficeAdmin,
            keccak256("new-land-office"),
            "ipfs://new-land-office"
        );

        DecisionTypes.DecisionRecord memory prepared = decisionApp.getDecision(decisionId);
        assertEq(uint256(prepared.scope), uint256(DecisionTypes.DecisionScope.Congress));
        assertEq(uint256(prepared.action), uint256(DecisionTypes.DecisionAction.RegisterOffice));
        assertEq(prepared.officeId, newOfficeId);
        assertEq(prepared.recipient, newOfficeAdmin);
        assertEq(uint256(prepared.officeKind), uint256(OfficeTypes.OfficeKind.LandRegistryOffice));
        assertEq(prepared.supportCount, 1);
        assertEq(prepared.supportRequired, 2);

        // Majority not yet reached.
        vm.expectRevert(abi.encodeWithSelector(IDecisionApp.CongressDecisionNotApproved.selector, decisionId, 1, 2));
        decisionApp.executeCongressDecision(decisionId);

        vm.prank(CONGRESS_MEMBER_TWO);
        decisionApp.supportCongressDecision(decisionId);

        decisionApp.executeCongressDecision(decisionId);

        OfficeTypes.OfficeRecord memory office = officeRegistry.getOfficeRecord(newOfficeId);
        assertEq(office.officeId, newOfficeId);
        assertEq(uint256(office.kind), uint256(OfficeTypes.OfficeKind.LandRegistryOffice));
        assertEq(office.admin, newOfficeAdmin);
        assertTrue(office.active);
        assertEq(office.name, "Western Land Registry Office");
        assertEq(uint256(officeRegistry.roleOf(newOfficeId, newOfficeAdmin)), uint256(OfficeTypes.OfficeRole.Admin));

        DecisionTypes.DecisionRecord memory executed = decisionApp.getDecision(decisionId);
        assertEq(uint256(executed.status), uint256(DecisionTypes.DecisionStatus.Executed));
    }

    function test_CongressRegisterOffice_RevertsForNonCongressMember() public {
        vm.prank(CONGRESS_SOURCE);
        vm.expectRevert(abi.encodeWithSelector(IDecisionApp.NotActiveCongressMember.selector, CONGRESS_SOURCE));
        decisionApp.createCongressRegisterOfficeDecision(
            keccak256("decision.congress.unauthorized-office"),
            keccak256("office.unauthorized"),
            OfficeTypes.OfficeKind.CompanyRegistryOffice,
            "Rogue Office",
            address(0x0FF2),
            keccak256("rogue-office"),
            "ipfs://rogue-office"
        );
    }

    function test_CongressRegisterOffice_RevertsWhenOfficeAlreadyExists() public {
        vm.prank(CONGRESS_MEMBER_ONE);
        vm.expectRevert(abi.encodeWithSelector(IDecisionApp.OfficeAlreadyRegistered.selector, FINANCE_OFFICE_ID));
        decisionApp.createCongressRegisterOfficeDecision(
            keccak256("decision.congress.duplicate-office"),
            FINANCE_OFFICE_ID,
            OfficeTypes.OfficeKind.MinistryOfFinance,
            "Duplicate Finance Office",
            address(0x0FF3),
            keccak256("duplicate-office"),
            "ipfs://duplicate-office"
        );
    }

    function test_MinistryDecision_AddsClerkAndClerkPreparesTokenTransfer() public {
        bytes32 clerkDecisionId = keccak256("decision.ministry.add-clerk");

        vm.prank(MINISTER_OF_FINANCE);
        decisionApp.prepareMinistryClerkDecision(
            FINANCE_OFFICE_ID,
            clerkDecisionId,
            FINANCE_CLERK,
            true,
            keccak256("add-finance-clerk"),
            "ipfs://add-finance-clerk"
        );

        vm.prank(FINANCE_CLERK);
        vm.expectRevert(
            abi.encodeWithSelector(IDecisionApp.NotMinistrySigner.selector, FINANCE_OFFICE_ID, FINANCE_CLERK)
        );
        decisionApp.executeMinistryDecision(clerkDecisionId);

        vm.prank(MINISTER_OF_FINANCE);
        decisionApp.executeMinistryDecision(clerkDecisionId);
        assertEq(
            uint256(officeRegistry.roleOf(FINANCE_OFFICE_ID, FINANCE_CLERK)), uint256(OfficeTypes.OfficeRole.Clerk)
        );

        bytes32 transferDecisionId = keccak256("decision.ministry.usdc-transfer");
        uint256 amount = 75_000e6;
        usdc.mint(MINISTER_OF_FINANCE, amount);

        vm.prank(FINANCE_CLERK);
        decisionApp.prepareMinistryTokenTransferDecision(
            FINANCE_OFFICE_ID,
            transferDecisionId,
            address(usdc),
            TREASURY_RECIPIENT,
            amount,
            keccak256("clerk-prepared-transfer"),
            "ipfs://clerk-prepared-transfer"
        );

        DecisionTypes.DecisionRecord memory prepared = decisionApp.getDecision(transferDecisionId);
        assertEq(prepared.preparedBy, FINANCE_CLERK);
        assertEq(prepared.source, MINISTER_OF_FINANCE);

        vm.prank(MINISTER_OF_FINANCE);
        usdc.approve(address(decisionApp), amount);

        vm.prank(MINISTER_OF_FINANCE);
        decisionApp.executeMinistryDecision(transferDecisionId);

        assertEq(usdc.balanceOf(TREASURY_RECIPIENT), amount);
        assertEq(usdc.balanceOf(MINISTER_OF_FINANCE), 0);
    }

    function test_MinistryDecision_TransfersAndStakesLLMForRecipientPerson() public {
        bytes32 decisionId = keccak256("decision.ministry.llm-stake");
        uint256 amount = 1_250;
        llmToken.mint(MINISTER_OF_FINANCE, amount);

        vm.prank(MINISTER_OF_FINANCE);
        decisionApp.prepareMinistryLlmStakeDecision(
            FINANCE_OFFICE_ID,
            decisionId,
            RECIPIENT_PERSON_ID,
            amount,
            keccak256("stake-recipient-llm"),
            "ipfs://stake-recipient-llm"
        );

        vm.prank(MINISTER_OF_FINANCE);
        llmToken.approve(address(decisionApp), amount);

        vm.prank(MINISTER_OF_FINANCE);
        decisionApp.executeMinistryDecision(decisionId);

        assertEq(stakeRegistry.activeStakeOf(RECIPIENT_PERSON_ID), amount);
        assertEq(llmToken.balanceOf(address(decisionApp)), amount);
        assertEq(llmToken.balanceOf(MINISTER_OF_FINANCE), 0);
    }

    function _seedCongressTerm(uint256 cycleId) internal {
        uint64 nominationStart = uint64(block.timestamp);
        ElectionTypes.CongressCycleInput memory cycleInput = ElectionTypes.CongressCycleInput({
            nominationStart: nominationStart,
            votingStart: nominationStart + 1,
            votingEnd: nominationStart + 2,
            seatCount: 3,
            runnerUpCount: 1,
            maxCandidateCount: 4,
            policyReference: keccak256(abi.encode("decision.test.policy", cycleId))
        });

        address[] memory rankedCandidates = new address[](4);
        rankedCandidates[0] = CONGRESS_MEMBER_ONE;
        rankedCandidates[1] = CONGRESS_MEMBER_TWO;
        rankedCandidates[2] = CONGRESS_MEMBER_THREE;
        rankedCandidates[3] = CONGRESS_RUNNER_UP;

        int256[] memory rankedVoteTotals = new int256[](4);

        vm.startPrank(address(congressAuthority));
        congressCandidateRegistry.createCycle(cycleId, cycleInput);
        congressCandidateRegistry.registerCandidate(
            cycleId, CONGRESS_MEMBER_ONE, bytes32(uint256(1)), keccak256("candidate-one"), "ipfs://candidate-one"
        );
        congressCandidateRegistry.registerCandidate(
            cycleId, CONGRESS_MEMBER_TWO, bytes32(uint256(2)), keccak256("candidate-two"), "ipfs://candidate-two"
        );
        congressCandidateRegistry.registerCandidate(
            cycleId, CONGRESS_MEMBER_THREE, bytes32(uint256(3)), keccak256("candidate-three"), "ipfs://candidate-three"
        );
        congressCandidateRegistry.registerCandidate(
            cycleId,
            CONGRESS_RUNNER_UP,
            bytes32(uint256(4)),
            keccak256("candidate-runner-up"),
            "ipfs://candidate-runner-up"
        );
        congressCandidateRegistry.finalizeCycle(
            cycleId,
            ElectionTypes.CongressFinalizationInput({
                rankedCandidates: rankedCandidates,
                rankedVoteTotals: rankedVoteTotals,
                electedCount: 3,
                runnerUpCount: 1
            })
        );
        vm.stopPrank();
    }

    function _registerIdentity(bytes32 personId, address wallet) internal {
        vm.startPrank(address(identityAuthority));
        identityRegistry.setIdentityRecord(personId, _defaultIdentityInput());
        identityRegistry.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
        vm.stopPrank();
    }

    function _registerOffice(bytes32 officeId, OfficeTypes.OfficeKind kind, string memory name) internal {
        vm.prank(address(officeAuthority));
        officeRegistry.registerOffice(officeId, kind, name, MINISTER_OF_FINANCE);
    }

    function _defaultIdentityInput() internal pure returns (IdentityTypes.IdentityRecordInput memory input) {
        return IdentityTypes.IdentityRecordInput({
            metadataHash: keccak256("decision.identity"),
            metadataURI: "ipfs://decision-identity",
            verificationStatus: IdentityTypes.VerificationStatus.Verified,
            citizenshipStatus: IdentityTypes.CitizenshipStatus.Citizen,
            ageClass: IdentityTypes.AgeClass.Adult,
            correctionFlag: false,
            finalSuspension: false
        });
    }
}
