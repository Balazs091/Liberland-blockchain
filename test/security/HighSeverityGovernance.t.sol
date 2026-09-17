// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ReferendaTest} from "../apps/Referenda.t.sol";
import {ICongressElectionPolicy} from "../../contracts/interfaces/ICongressElectionPolicy.sol";
import {ReferendumTypes} from "../../contracts/types/ReferendumTypes.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {MockModule} from "../../contracts/mocks/MockModule.sol";

contract MetadataImpersonatingPolicy {
    address private immutable original;

    constructor(address original_) {
        original = original_;
    }

    fallback(bytes calldata input) external returns (bytes memory) {
        if (msg.sig == ICongressElectionPolicy.isEligibleCandidate.selector) return abi.encode(false);
        (bool ok, bytes memory data) = original.staticcall(input);
        require(ok);
        return data;
    }
}

contract HighSeverityGovernanceTest is ReferendaTest {
    function test_Security_ElectionPolicyMetadataCannotBuyOrdinaryApproval() public {
        MetadataImpersonatingPolicy changed = new MetadataImpersonatingPolicy(address(congressElectionPolicy));
        congressAuthority.setMember(WALLET_THREE, true);
        ReferendumTypes.CongressElectionPolicyProposal memory proposal = ReferendumTypes.CongressElectionPolicyProposal({
            proposalMetadataHash: keccak256("security.metadata"),
            proposalId: keccak256("security.policy"),
            newPolicy: address(changed),
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + MINIMUM_VOTING_DURATION),
            adoptionDelay: STANDARD_ADOPTION_DELAY
        });
        vm.prank(WALLET_THREE);
        bytes32 id = referendumApp.createCongressElectionPolicyReferendum(proposal);
        assertTrue(referendumRegistry.getReferendum(id).requiresSupermajority);
        assertEq(referendumRegistry.getReferendum(id).electorateHeadcountSnapshot, 3);
        vm.prank(WALLET_THREE);
        referendumApp.castVote(id, ReferendumTypes.VoteOption.For);
        vm.warp(proposal.endTime);
        referendumApp.finalizeReferendum(id);
        ReferendumTypes.ReferendumResult memory result = referendumRegistry.getReferendumResult(id);
        assertFalse(result.passed);
        assertEq(result.headcountQuorumRequired, 2);
        assertEq(result.enactmentActionId, bytes32(0));
        assertEq(kernel.getModule(KernelModuleIds.CONGRESS_ELECTION_POLICY), address(congressElectionPolicy));
    }

    function test_Security_DeferredReferendumWriterRejectsPartialRollCreation() public {
        _deployFoundation();
        _deployReferendumSystem();
        MockModule setup = new MockModule(keccak256("genesis.writer"));
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(setup));
        _registerCitizen(PERSON_ONE_ID, WALLET_ONE, 12_000);
        _registerCitizen(PERSON_TWO_ID, WALLET_TWO, 12_000);
        vm.roll(block.number + 1);
        ReferendumTypes.ModuleGovernanceProposal memory proposal = _defaultModuleGovernanceProposal(
            "partial", "partial-id", KernelModuleIds.CONGRESS_ELECTION_POLICY, address(setup), false
        );
        vm.prank(WALLET_ONE);
        vm.expectRevert();
        referendumApp.createCitizenModuleGovernanceReferendum(proposal);
        _registerCitizen(PERSON_THREE_ID, WALLET_THREE, 12_000);
        vm.roll(block.number + 1);
        kernel.bootstrapSetModule(KernelModuleIds.REFERENDUM_REGISTRY_AUTHORITY, address(referendumApp));
        vm.prank(WALLET_ONE);
        bytes32 id = referendumApp.createCitizenModuleGovernanceReferendum(proposal);
        assertEq(referendumRegistry.getReferendum(id).electorateHeadcountSnapshot, 3);
    }
}
