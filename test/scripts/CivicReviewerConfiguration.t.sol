// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {DeploymentScriptBase} from "../../scripts/DeploymentScriptBase.sol";

contract CivicReviewerConfigurationHarness is DeploymentScriptBase {
    function validate(address[5] memory reviewers, address deployer, address[4] memory admins) external {
        _civicReviewers = reviewers;
        _validateCivicReviewers(deployer, admins);
    }
}

contract CivicReviewerConfigurationTest is Test {
    function test_IndependentReviewerConfigurationAccepted() public {
        new CivicReviewerConfigurationHarness().validate(_reviewers(), address(9), _admins());
    }

    function testFuzz_ReviewerCannotBeZeroDuplicateDeployerOrOfficeAdmin(uint8 index, uint8 conflict) public {
        index = uint8(bound(index, 0, 4));
        conflict = uint8(bound(conflict, 0, 6));
        address[5] memory reviewers = _reviewers();
        address[4] memory admins = _admins();
        address invalid = conflict == 0
            ? address(0)
            : conflict == 1 ? reviewers[(uint256(index) + 1) % 5] : conflict == 2 ? address(9) : admins[conflict - 3];
        reviewers[index] = invalid;
        CivicReviewerConfigurationHarness harness = new CivicReviewerConfigurationHarness();
        vm.expectRevert(abi.encodeWithSelector(DeploymentScriptBase.InvalidCivicReviewer.selector, invalid));
        harness.validate(reviewers, address(9), admins);
    }

    function _reviewers() private pure returns (address[5] memory) {
        return [address(1), address(2), address(3), address(4), address(5)];
    }

    function _admins() private pure returns (address[4] memory) {
        return [address(10), address(11), address(12), address(13)];
    }
}
