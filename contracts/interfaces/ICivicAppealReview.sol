// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title ICivicAppealReview
/// @notice Fixed five-member, three-approval authority for exact civic appeals; no general executor.
interface ICivicAppealReview {
    error InvalidReviewConfiguration();
    error ReviewerNotIndependent(address reviewer);
    error InvalidAppeal(bytes32 requestId);
    error InsufficientRulingSupport(uint256 support);

    event RulingVoteCast(bytes32 indexed rulingId, bytes32 indexed requestId, address indexed reviewer, bool supported);
    event RulingExecuted(bytes32 indexed rulingId, bytes32 indexed personId, bytes32 indexed requestId, bool upheld);

    /// @notice Returns the only IdentityApp whose appeals this committee can resolve.
    function identityApp() external view returns (address app);

    /// @notice Returns one of the five immutable reviewer accounts (indices zero through four).
    function reviewerAt(uint256 index) external view returns (address reviewer);

    /// @notice Returns the chain/committee/app/person/request/outcome/evidence-bound ruling identifier.
    function rulingId(bytes32 personId, bytes32 requestId, bool uphold, bytes32 evidenceHash)
        external
        view
        returns (bytes32 id);

    /// @notice Casts or revokes the caller's approval of one exact ruling. Requires current independence.
    function castRulingVote(bytes32 personId, bytes32 requestId, bool uphold, bytes32 evidenceHash, bool support)
        external;

    /// @notice Counts currently independent, distinct reviewers supporting an open exact-case ruling.
    function rulingSupport(bytes32 personId, bytes32 requestId, bool uphold, bytes32 evidenceHash)
        external
        view
        returns (uint256 support);

    /// @notice Executes one exact ruling with three current independent approvals before the appeal deadline.
    function executeRuling(bytes32 personId, bytes32 requestId, bool uphold, bytes32 evidenceHash) external;
}
