// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ElectionTypes} from "../types/ElectionTypes.sol";

/// @notice Immutable storage for a derived Congress ranking; only its registry's governed writer can mutate it.
interface ICongressRankingStore {
    /// @notice Builds the bounded final outcome from a complete ranking; canonical registry revalidates every score.
    function finalizationInput(uint256 cycleId)
        external
        view
        returns (ElectionTypes.CongressFinalizationInput memory input);
    error RegistryOnly();
    error RankingNotReady();
    /// @notice Returns the fixed controlling registry, not an administrative key.
    function registry() external view returns (address);
    /// @notice Returns fixed inputs and bounded processing progress.
    function progress(uint256 cycleId) external view returns (ElectionTypes.FinalizationProgress memory);
    /// @notice Builds at most 32 entries from the controlling registry's closed candidate set. Registry authority only.
    function process(uint256 cycleId, uint256 maxCount) external;
    /// @notice Returns the highest ranked unconsidered candidate.
    function peek(uint256 cycleId) external view returns (address candidate, bytes32 personId);
    /// @notice Pops the strongest entry and optionally retains it in the bounded outcome set.
    function consider(uint256 cycleId, bool eligible) external returns (address);
    /// @notice Returns a provisional outcome candidate by index.
    function selectedAt(uint256 cycleId, uint256 index) external view returns (address candidate, bytes32 personId);
    /// @notice Removes a no-longer-eligible provisional candidate, preserving outcome order.
    function removeSelected(uint256 cycleId, uint256 index) external returns (address);
    /// @notice Returns whether a candidate failed a live eligibility check during finalization.
    function disqualified(uint256 cycleId, address candidate) external view returns (bool);
    event CongressRankingProgress(uint256 indexed cycleId, uint256 processed, uint256 total);
    event CongressCandidateConsidered(uint256 indexed cycleId, address indexed candidate, bool selected);
}
