// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IKernelModule} from "./IKernelModule.sol";

/// @notice Stable replay protection and original-admission participation across justice roster changes.
interface IJusticeDecisions is IKernelModule {
    error UnauthorizedJusticeApp();
    error DecisionAlreadyUsed(bytes32 decisionId);
    error AnnulmentMismatch(bytes32 expected, bytes32 actual);

    /// @notice Reports whether a decision ID has already been executed.
    function used(bytes32 decisionId) external view returns (bool);

    /// @notice Reports whether the person signed an admission of the subject.
    function admittedBy(bytes32 subject, bytes32 member) external view returns (bool);

    /// @notice Returns the revision advanced only by completed exceptional recoveries.
    function recoveryRevisionOf(bytes32 subject) external view returns (uint256);

    /// @notice Advances the revision in the same transaction as an exceptional recovery.
    function advanceRecovery(bytes32 subject) external;

    /// @notice Returns the active recorded annulment of a person, if any.
    function annulmentOf(bytes32 subject) external view returns (bytes32);

    /// @notice Records the exact annulment when its effect is applied.
    function recordAnnulment(bytes32 subject, bytes32 decisionId) external;

    /// @notice Clears the exact annulment on execution of its reversal.
    function clearAnnulment(bytes32 subject, bytes32 decisionId) external;

    /// @notice Consumes a decision in the same transaction as its effect.
    function consume(bytes32 decisionId) external;

    /// @notice Records the Commission members who approved an admission.
    function recordAdmission(bytes32 subject, bytes32[] calldata members) external;
}
