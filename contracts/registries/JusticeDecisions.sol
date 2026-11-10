// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {KernelModule} from "../base/KernelModule.sol";
import {IJusticeDecisions} from "../interfaces/IJusticeDecisions.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";

/// @notice Stable decision records shared by successive justice applications.
contract JusticeDecisions is IJusticeDecisions, KernelModule {
    /// @inheritdoc IJusticeDecisions
    mapping(bytes32 decisionId => bool consumed) public used;

    /// @inheritdoc IJusticeDecisions
    mapping(bytes32 subject => mapping(bytes32 member => bool signed)) public admittedBy;

    /// @inheritdoc IJusticeDecisions
    mapping(bytes32 subject => bytes32 decisionId) public annulmentOf;

    /// @inheritdoc IJusticeDecisions
    mapping(bytes32 subject => uint256 revision) public recoveryRevisionOf;

    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IJusticeDecisions
    function consume(bytes32 decisionId) external {
        _requireApp();
        if (used[decisionId]) revert DecisionAlreadyUsed(decisionId);
        used[decisionId] = true;
    }

    /// @inheritdoc IJusticeDecisions
    function recordAdmission(bytes32 subject, bytes32[] calldata members) external {
        _requireApp();
        for (uint256 i; i < members.length; ++i) {
            admittedBy[subject][members[i]] = true;
        }
    }

    /// @inheritdoc IJusticeDecisions
    function recordAnnulment(bytes32 subject, bytes32 decisionId) external {
        _requireApp();
        bytes32 current = annulmentOf[subject];
        if (current != bytes32(0)) revert AnnulmentMismatch(bytes32(0), current);
        annulmentOf[subject] = decisionId;
    }

    /// @inheritdoc IJusticeDecisions
    function clearAnnulment(bytes32 subject, bytes32 decisionId) external {
        _requireApp();
        bytes32 current = annulmentOf[subject];
        if (current != decisionId) revert AnnulmentMismatch(decisionId, current);
        delete annulmentOf[subject];
    }

    /// @inheritdoc IJusticeDecisions
    function advanceRecovery(bytes32 subject) external {
        _requireApp();
        ++recoveryRevisionOf[subject];
    }

    function _requireApp() private view {
        if (
            !_isModuleCaller(KernelModuleIds.JUSTICE_APP, msg.sender)
                || !_isModuleCaller(KernelModuleIds.JUSTICE_DECISIONS, address(this))
        ) revert UnauthorizedJusticeApp();
    }
}
