// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {CongressElectionFixture} from "../apps/CongressElections.t.sol";
import {ElectionTypes} from "../../contracts/types/ElectionTypes.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {ICongressCandidateRegistry} from "../../contracts/interfaces/ICongressCandidateRegistry.sol";
import {CongressElectionPolicy} from "../../contracts/policies/CongressElectionPolicy.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";

contract HighSeverityCongressTest is CongressElectionFixture {
    function test_Security_ReassignedWalletCannotEraseAnotherPersonsBallotByCasting() public {
        (uint256 cycle, ElectionTypes.CongressCycleRecord memory record) = _createCycle();
        vm.warp(record.nominationStart);
        _applyAllDefaultCandidates(cycle);
        vm.warp(record.votingStart);
        _castFullWeightBallot(WALLET_ONE, cycle, WALLET_THREE);
        _setWalletLink(PERSON_ONE_ID, WALLET_ONE, IdentityTypes.WalletLinkStatus.Revoked);
        _setWalletLink(PERSON_ONE_ID, WALLET_ONE_NEW, IdentityTypes.WalletLinkStatus.Active);
        _setWalletLink(PERSON_TWO_ID, WALLET_TWO, IdentityTypes.WalletLinkStatus.Revoked);
        _setWalletLink(PERSON_TWO_ID, WALLET_ONE, IdentityTypes.WalletLinkStatus.Active);
        address[] memory candidates = _asAddressArray(WALLET_THREE);
        int256[] memory allocations = _asIntArray(_voterWeight(WALLET_ONE));
        vm.prank(WALLET_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICongressCandidateRegistry.BallotWalletOwnedByAnotherPerson.selector, cycle, WALLET_ONE, PERSON_ONE_ID
            )
        );
        congressElectionApp.castBallot(cycle, candidates, allocations);
        assertEq(congressCandidateRegistry.getCandidate(cycle, WALLET_THREE).voteTotal, 9_000);
        // Former owner can move the receipt to their new wallet; neither ballot is destroyed or doubled.
        _castFullWeightBallot(WALLET_ONE_NEW, cycle, WALLET_THREE);
        _castFullWeightBallot(WALLET_ONE, cycle, WALLET_THREE);
        assertEq(congressCandidateRegistry.getCandidate(cycle, WALLET_THREE).voteTotal, 17_000);
    }

    function test_Security_CandidateMetadataBoundRejectsGasBombAndAcceptsBoundary() public {
        (uint256 cycle, ElectionTypes.CongressCycleRecord memory record) = _createCycle();
        vm.warp(record.nominationStart);
        uint256 maximum = congressCandidateRegistry.MAX_APPLICATION_URI_LENGTH();
        vm.prank(WALLET_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(ICongressCandidateRegistry.ApplicationURITooLong.selector, 128 * 1024, maximum)
        );
        congressElectionApp.applyAsCandidate(cycle, keccak256("oversized"), string(new bytes(128 * 1024)));
        vm.prank(WALLET_ONE);
        congressElectionApp.applyAsCandidate(cycle, keccak256("maximum"), string(new bytes(maximum)));
        assertEq(bytes(congressCandidateRegistry.getCandidate(cycle, WALLET_ONE).applicationURI).length, maximum);
        vm.warp(record.votingEnd);
        vm.cool(address(congressCandidateRegistry));
        (bool ok,) = address(congressElectionApp).call{gas: 16_000_000}(
            abi.encodeWithSignature("finalizeElection(uint256)", cycle)
        );
        assertTrue(ok);
    }

    function test_Security_ProductionNineMaximumMetadataCandidatesFinalizeWithinCap() public {
        CongressElectionPolicy policy = new CongressElectionPolicy(
            address(candidateEligibilityPolicy),
            address(votingPowerPolicy),
            7,
            2,
            9,
            6_000,
            2 days,
            3 days,
            14 days,
            90 days
        );
        kernel.bootstrapSetModule(KernelModuleIds.CONGRESS_ELECTION_POLICY, address(policy));
        for (uint256 i; i < 9; i++) {
            _registerCitizen(bytes32(100 + i), address(uint160(100 + i)), 12_000);
        }
        vm.roll(block.number + 1);
        uint256 cycle = congressElectionApp.createNextElectionCycle();
        bytes memory metadata = new bytes(congressCandidateRegistry.MAX_APPLICATION_URI_LENGTH());
        for (uint256 i; i < metadata.length; i += 32) {
            assembly { mstore(add(add(metadata, 32), i), not(0)) }
        }
        for (uint256 i; i < 9; i++) {
            vm.prank(address(uint160(100 + i)));
            congressElectionApp.applyAsCandidate(cycle, keccak256(abi.encode(i)), string(metadata));
        }
        vm.warp(congressCandidateRegistry.getCycle(cycle).votingEnd);
        vm.roll(block.number + 1);
        vm.cool(address(congressCandidateRegistry));
        uint256 beforeGas = gasleft();
        (bool ok,) = address(congressElectionApp).call{gas: 16_000_000}(
            abi.encodeWithSignature("finalizeElection(uint256)", cycle)
        );
        assertTrue(ok);
        emit log_named_uint("nine maximum-size candidate records, cold finalization gas", beforeGas - gasleft());
    }
}
