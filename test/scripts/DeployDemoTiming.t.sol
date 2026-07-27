// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {DeployDemo} from "../../scripts/DeployDemo.s.sol";

contract DeployDemoTimingHarness is DeployDemo {
    function nextDemoCongressVotingEnd(uint64 currentTimestamp) external pure returns (uint64 votingEnd) {
        return _nextDemoCongressVotingEnd(currentTimestamp);
    }
}

contract DeployDemoTimingTest is Test {
    DeployDemoTimingHarness internal harness;

    function setUp() public {
        harness = new DeployDemoTimingHarness();
    }

    function test_DemoCongressEndIsAlwaysAnchoredTo1700Utc() public view {
        _assertAnchored(5 days + 16 hours);
        _assertAnchored(5 days + 17 hours);
        _assertAnchored(5 days + 18 hours);
    }

    function _assertAnchored(uint64 currentTimestamp) private view {
        uint64 votingEnd = harness.nextDemoCongressVotingEnd(currentTimestamp);
        uint64 remaining = votingEnd - currentTimestamp;

        assertEq(votingEnd % 1 days, 17 hours);
        assertGe(remaining, 1 days);
        assertLe(remaining, 2 days);
    }
}
