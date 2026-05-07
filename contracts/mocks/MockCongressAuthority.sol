// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title MockCongressAuthority
/// @notice Minimal Congress-membership oracle for referendum policy tests.
contract MockCongressAuthority {
    mapping(address wallet => bool member) private _members;

    function setMember(address wallet, bool member_) external {
        _members[wallet] = member_;
    }

    function isCongressMember(address wallet) external view returns (bool member_) {
        return _members[wallet];
    }
}
