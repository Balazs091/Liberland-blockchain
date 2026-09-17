// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {CongressElectionFixture} from "../apps/CongressElections.t.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {ICongressElectionApp} from "../../contracts/interfaces/ICongressElectionApp.sol";
import {ICongressRankingStore} from "../../contracts/interfaces/ICongressRankingStore.sol";
import {ElectorateRegistry} from "../../contracts/registries/ElectorateRegistry.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";
import {CongressElectionPolicy} from "../../contracts/policies/CongressElectionPolicy.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

/// @notice Revision-specific liveness regressions and cold-storage transaction measurements.
contract EfficiencyAuditTest is CongressElectionFixture {
    function test_EfficiencyAudit_FinalizationIsIndependentOfNextElectorate() public {
        (uint256 cycle, ElectionTypes.CongressCycleRecord memory record) = _createCycle();
        vm.warp(record.nominationStart);
        _applyCandidate(cycle, WALLET_ONE, "candidate-one");
        _applyCandidate(cycle, WALLET_TWO, "candidate-two");
        vm.warp(record.votingEnd);
        ElectorateRegistry replacement =
            new ElectorateRegistry(address(kernel), address(identityRegistry), address(stakeRegistry));
        kernel.bootstrapSetModule(KernelModuleIds.ELECTORATE_REGISTRY, address(replacement));
        congressElectionApp.finalizeElection(cycle);
        assertEq(uint8(congressCandidateRegistry.getCycle(cycle).status), uint8(ElectionTypes.ElectionStatus.Finalized));
        assertTrue(congressElectionApp.isCongressMember(WALLET_ONE));
        assertEq(congressCandidateRegistry.latestCycleId(), cycle);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICongressElectionApp.VotingPowerElectorateMismatch.selector,
                address(votingPowerPolicy),
                address(electorateRegistry),
                address(replacement)
            )
        );
        congressElectionApp.createNextElectionCycle();
        kernel.bootstrapSetModule(KernelModuleIds.ELECTORATE_REGISTRY, address(electorateRegistry));
        assertEq(congressElectionApp.createNextElectionCycle(), cycle + 1);
        assertEq(congressCandidateRegistry.getCycleCandidateCount(cycle + 1), 2);
    }

    function test_EfficiencyAudit_FinalizationDoesNotCallReplacementElectionPolicy() public {
        (uint256 cycle, ElectionTypes.CongressCycleRecord memory record) = _createCycle();
        vm.warp(record.nominationStart);
        _applyCandidate(cycle, WALLET_ONE, "candidate-one");
        vm.warp(record.votingEnd);
        kernel.bootstrapSetModule(
            KernelModuleIds.CONGRESS_ELECTION_POLICY, address(new MockModule(keccak256("incompatible-policy")))
        );
        congressElectionApp.finalizeElection(cycle);
        assertEq(uint8(congressCandidateRegistry.getCycle(cycle).status), uint8(ElectionTypes.ElectionStatus.Finalized));
        assertTrue(congressElectionApp.isCongressMember(WALLET_ONE));
        vm.expectRevert();
        congressElectionApp.createNextElectionCycle();
    }

    function test_EfficiencyAudit_InvalidCountBatchRejectedBeforeStateChange() public {
        vm.expectRevert(abi.encodeWithSelector(ICongressElectionApp.InvalidFinalizationBatchSize.selector, 0));
        congressElectionApp.finalizeElection(1, 0);
        vm.expectRevert(abi.encodeWithSelector(ICongressElectionApp.InvalidFinalizationBatchSize.selector, 33));
        congressElectionApp.finalizeElection(1, 33);
        assertEq(congressCandidateRegistry.latestCycleId(), 0);
    }

    function testFuzz_EfficiencyAudit_BatchSizePreservesRankedOutcome(uint8 rawBatch) public {
        uint256 batch = bound(uint256(rawBatch), 1, 32);
        uint256 population = 40;
        for (uint256 i; i < population; ++i) {
            _registerCitizen(bytes32(10_000 + i), address(uint160(10_000 + i)), 6_000 + i);
        }
        vm.roll(block.number + 1);
        (uint256 cycle, ElectionTypes.CongressCycleRecord memory record) = _createCycle();
        vm.warp(record.nominationStart);
        for (uint256 i; i < population; ++i) {
            _applyCandidate(cycle, address(uint160(10_000 + i)), "batch-candidate");
        }
        vm.warp(record.votingStart);
        for (uint256 i; i < population; ++i) {
            _castFullWeightBallot(address(uint160(10_000 + i)), cycle, address(uint160(10_000 + i)));
        }
        vm.warp(record.votingEnd);
        uint256 rounds;
        while (congressCandidateRegistry.getCycle(cycle).status != ElectionTypes.ElectionStatus.Finalized) {
            ElectionTypes.FinalizationProgress memory before = _rankingProgress(cycle);
            congressElectionApp.finalizeElection(cycle, batch);
            ElectionTypes.FinalizationProgress memory after_ = _rankingProgress(cycle);
            assertLe(after_.processedCount - before.processedCount, batch);
            if (before.processedCount == population) {
                assertLe(before.remainingRanked - after_.remainingRanked, batch);
            }
            assertLe(++rounds, (population + batch - 1) / batch + 4);
        }
        assertEq(congressCandidateRegistry.getElectedCandidateAt(cycle, 0), address(10_039));
        assertEq(congressCandidateRegistry.getElectedCandidateAt(cycle, 1), address(10_038));
        assertEq(congressCandidateRegistry.getRunnerUpAt(cycle, 0), address(10_037));
        assertEq(congressCandidateRegistry.getRunnerUpAt(cycle, 1), address(10_036));
        assertEq(congressCandidateRegistry.latestCycleId(), cycle);
    }
}

/// @notice Prepares population-sized fixtures in setUp so each measured test starts a fresh EVM transaction.
/// @dev Unlike same-test count loops, this preserves correct original/current SSTORE pricing for existing heap slots.
abstract contract CongressGasFixture is CongressElectionFixture {
    uint256 internal gasCycle;

    function _prepareGasElection(uint256 population, uint32 seats, uint32 runners) internal {
        super.setUp();
        // This fixture represents many separate registration/ballot transactions; only the measured test is capped.
        vm.pauseGasMetering();
        congressElectionPolicy = new CongressElectionPolicy(
            address(candidateEligibilityPolicy),
            address(votingPowerPolicy),
            seats,
            runners,
            0,
            6000,
            2 days,
            3 days,
            14 days,
            5 days
        );
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_POLICY, address(congressElectionPolicy));
        for (uint256 i; i < population; ++i) {
            _registerCitizen(bytes32(10_000 + i), address(uint160(10_000 + i)), 6_000 + i);
        }
        vm.roll(block.number + 1);
        ElectionTypes.CongressCycleRecord memory record;
        (gasCycle, record) = _createCycle();
        // Increasing scores and application times force bubble-up inserts with four distinct stored entry fields.
        string memory metadata = _gasCandidateMetadata();
        for (uint256 i; i < population; ++i) {
            vm.warp(record.nominationStart + i);
            vm.prank(address(uint160(10_000 + i)));
            congressElectionApp.applyAsCandidate(gasCycle, keccak256(abi.encode(i)), metadata);
        }
        vm.warp(record.votingStart);
        for (uint256 i; i < population; ++i) {
            _castFullWeightBallot(address(uint160(10_000 + i)), gasCycle, address(uint160(10_000 + i)));
        }
        vm.warp(record.votingEnd);
        vm.resumeGasMetering();
    }

    function _gasCandidateMetadata() internal view virtual returns (string memory) {
        return "ipfs://gas-candidate";
    }

    function _coolCongressDependencies() internal {
        vm.cool(congressCandidateRegistry.rankingStore());
        vm.cool(address(congressCandidateRegistry));
        vm.cool(address(congressElectionApp));
        vm.cool(address(identityRegistry));
        vm.cool(address(stakeRegistry));
        vm.cool(address(kernel));
        vm.cool(address(congressElectionPolicy));
        vm.cool(address(candidateEligibilityPolicy));
        vm.cool(address(citizenEligibilityPolicy));
        vm.cool(address(votingPowerPolicy));
        vm.cool(address(electorateRegistry));
    }
}

/// @notice Cold, fresh-transaction costs for insertion into a heap with 960 already persisted candidates.
contract CongressInsertionGasAuditTest is CongressGasFixture {
    function setUp() public override {
        _prepareGasElection(1000, 2, 2);
        for (uint256 i; i < 30; ++i) {
            congressElectionApp.finalizeElection(gasCycle);
        }
        assertEq(_rankingProgress(gasCycle).processedCount, 960);
    }

    function test_EfficiencyAudit_ColdPersistedHeapDefaultBatchGas() public {
        _coolCongressDependencies();
        uint256 gasBefore = gasleft();
        (bool success,) = address(congressElectionApp).call{gas: 16_000_000}(
            abi.encodeWithSignature("finalizeElection(uint256)", gasCycle)
        );
        uint256 used = gasBefore - gasleft();
        assertTrue(success, "32 persisted-heap inserts must fit the gas cap");
        assertEq(_rankingProgress(gasCycle).processedCount, 992);
        emit log_named_uint("cold persisted 960-entry heap, 32 inserts execution gas", used);
    }

    function test_EfficiencyAudit_ColdPersistedHeapSingleCandidateGas() public {
        _coolCongressDependencies();
        uint256 gasBefore = gasleft();
        (bool success,) = address(congressElectionApp).call{gas: 1_000_000}(
            abi.encodeWithSignature("finalizeElection(uint256,uint256)", gasCycle, 1)
        );
        uint256 used = gasBefore - gasleft();
        assertTrue(success, "one persisted-heap insert must fit reduced gas cap");
        assertEq(_rankingProgress(gasCycle).processedCount, 961);
        emit log_named_uint("cold persisted 960-entry heap, one insert execution gas", used);
    }
}

/// @notice Cold, fresh-transaction revalidation when all 31 provisional outcomes lose eligibility.
contract CongressRevalidationGasAuditTest is CongressGasFixture {
    function setUp() public override {
        _prepareGasElection(64, 31, 1);
        while (_rankingProgress(gasCycle).selectedCount < 31) {
            congressElectionApp.finalizeElection(gasCycle, 1);
        }
        IdentityTypes.IdentityRecordInput memory suspended = _defaultIdentityInput();
        suspended.finalSuspension = true;
        for (uint256 i = 33; i < 64; ++i) {
            _setIdentityRecord(bytes32(10_000 + i), suspended);
        }
    }

    function test_EfficiencyAudit_ColdPersistedProvisionalDisqualificationsGas() public {
        _coolCongressDependencies();
        uint256 gasBefore = gasleft();
        (bool success,) = address(congressElectionApp).call{gas: 16_000_000}(
            abi.encodeWithSignature("finalizeElection(uint256,uint256)", gasCycle, 1)
        );
        uint256 used = gasBefore - gasleft();
        assertTrue(success, "persisted provisional revalidation must fit the gas cap");
        assertEq(_rankingProgress(gasCycle).selectedCount, 1);
        emit log_named_uint("31 cold persisted provisional disqualifications execution gas", used);
    }

    function testFuzz_EfficiencyAudit_ReverseRemovalPreservesEveryRetainedRank(uint32 excludedMask) public {
        uint256 retained;
        address[] memory expected = new address[](32);
        for (uint256 rank; rank < 31; ++rank) {
            uint256 personIndex = 63 - rank;
            if (excludedMask & (uint32(1) << rank) == 0) {
                _setIdentityRecord(bytes32(10_000 + personIndex), _defaultIdentityInput());
                expected[retained++] = address(uint160(10_000 + personIndex));
            }
        }
        congressElectionApp.finalizeElection(gasCycle, 1);
        expected[retained++] = address(10_032);
        ICongressRankingStore ranking = ICongressRankingStore(congressCandidateRegistry.rankingStore());
        assertEq(ranking.progress(gasCycle).selectedCount, retained);
        for (uint256 rank; rank < retained; ++rank) {
            (address candidate,) = ranking.selectedAt(gasCycle, rank);
            assertEq(candidate, expected[rank]);
        }
    }
}

/// @notice Cold activation cost at the registry's maximum 32 elected-plus-runner-up outcomes.
contract CongressActivationGasAuditTest is CongressGasFixture {
    function setUp() public override {
        _prepareGasElection(32, 31, 1);
    }

    function test_EfficiencyAudit_ColdMaximumOutcomeActivationGas() public {
        _coolCongressDependencies();
        uint256 gasBefore = gasleft();
        (bool success,) = address(congressElectionApp).call{gas: 16_000_000}(
            abi.encodeWithSignature("finalizeElection(uint256)", gasCycle)
        );
        uint256 used = gasBefore - gasleft();
        assertTrue(success, "maximum bounded outcome must activate within the gas cap");
        assertEq(
            uint8(congressCandidateRegistry.getCycle(gasCycle).status), uint8(ElectionTypes.ElectionStatus.Finalized)
        );
        assertEq(congressCandidateRegistry.getCurrentOfficeTerm().occupiedSeatCount, 31);
        assertEq(congressCandidateRegistry.getRunnerUpAt(gasCycle, 0), address(10_000));
        emit log_named_uint("32 cold ranked outcomes including31 seat activations execution gas", used);
    }
}

/// @notice Succession over every retained runner-up must not load their maximum-sized metadata records.
contract CongressSuccessionGasAuditTest is CongressGasFixture {
    function setUp() public override {
        _prepareGasElection(32, 1, 31);
        congressElectionApp.finalizeElection(gasCycle);
        IdentityTypes.IdentityRecordInput memory suspended = _defaultIdentityInput();
        suspended.finalSuspension = true;
        for (uint256 i = 1; i < 31; ++i) {
            _setIdentityRecord(bytes32(10_000 + i), suspended);
        }
    }

    function _gasCandidateMetadata() internal view override returns (string memory) {
        bytes memory metadata = new bytes(congressCandidateRegistry.MAX_APPLICATION_URI_LENGTH());
        for (uint256 i; i < metadata.length; i += 32) {
            assembly { mstore(add(add(metadata, 32), i), not(0)) }
        }
        return string(metadata);
    }

    function test_EfficiencyAudit_ColdSuccessionSkipsThirtyMaximumMetadataCandidatesGas() public {
        _coolCongressDependencies();
        vm.prank(address(10_031));
        uint256 gasBefore = gasleft();
        (bool success,) =
            address(congressElectionApp).call{gas: 16_000_000}(abi.encodeCall(congressElectionApp.resignSeat, ()));
        uint256 used = gasBefore - gasleft();
        assertTrue(success, "all retained runner-ups must be scannable in one bounded transaction");
        assertTrue(congressElectionApp.isCongressMember(address(10_000)));
        emit log_named_uint("31 cold maximum-metadata runner-up checks execution gas", used);
    }
}
