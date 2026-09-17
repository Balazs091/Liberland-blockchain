// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ICivicAppealReview} from "../interfaces/ICivicAppealReview.sol";
import {IIdentityApp} from "../interfaces/IIdentityApp.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title CivicAppealReview
/// @notice A purpose-limited 3-of-5 approval contract for one IdentityApp. No custody or arbitrary calls.
/// @dev Reviewers are immutable appointed accounts. Rotation deploys a replacement through constitutional module
///      governance; existing notices retain their original committee and always have a dismissal-on-timeout path.
contract CivicAppealReview is ICivicAppealReview {
    /// @notice Exact number of appointed review accounts.
    uint256 public constant REVIEWER_COUNT = 5;
    /// @notice Number of currently independent approvals required for the same outcome and evidence.
    uint256 public constant REQUIRED_APPROVALS = 3;

    IIdentityApp private immutable _identityApp;
    IIdentityRegistry private immutable _identityRegistry;
    IOfficeRegistry private immutable _officeRegistry;
    bytes32 private immutable _identityOfficeId;
    address[5] private _reviewers;
    mapping(address reviewer => uint8 bit) private _reviewerBits;
    mapping(bytes32 id => uint8 bitmap) private _votes;

    /// @param identityAppAddress The sole app whose appealed requests this committee may uphold or dismiss.
    /// @param reviewers Five nonzero, pairwise-distinct appointed accounts; independent custody is an operator duty.
    constructor(address identityAppAddress, address[5] memory reviewers) {
        if (identityAppAddress.code.length == 0) revert InvalidReviewConfiguration();
        _identityApp = IIdentityApp(identityAppAddress);
        _identityRegistry = IIdentityRegistry(_identityApp.identityRegistry());
        _officeRegistry = IOfficeRegistry(_identityApp.officeRegistry());
        _identityOfficeId = _identityApp.identityOfficeId();
        for (uint256 i; i < REVIEWER_COUNT; ++i) {
            address reviewer = reviewers[i];
            if (reviewer == address(0) || _reviewerBits[reviewer] != 0) revert InvalidReviewConfiguration();
            _reviewers[i] = reviewer;
            _reviewerBits[reviewer] = uint8(1 << i);
        }
    }

    /// @inheritdoc ICivicAppealReview
    function identityApp() external view returns (address app) {
        return address(_identityApp);
    }

    /// @inheritdoc ICivicAppealReview
    function reviewerAt(uint256 index) external view returns (address reviewer) {
        return _reviewers[index];
    }

    /// @inheritdoc ICivicAppealReview
    function rulingId(bytes32 personId, bytes32 requestId, bool uphold, bytes32 evidenceHash)
        public
        view
        returns (bytes32 id)
    {
        return keccak256(
            abi.encode(block.chainid, address(this), address(_identityApp), personId, requestId, uphold, evidenceHash)
        );
    }

    /// @inheritdoc ICivicAppealReview
    function castRulingVote(bytes32 personId, bytes32 requestId, bool uphold, bytes32 evidenceHash, bool support)
        external
    {
        IdentityTypes.CivicChangeRequest memory request = _requireAppeal(personId, requestId, evidenceHash);
        uint8 bit = _reviewerBits[msg.sender];
        if (bit == 0 || (support && !_isIndependent(msg.sender, personId, request))) {
            revert ReviewerNotIndependent(msg.sender);
        }
        bytes32 id = rulingId(personId, requestId, uphold, evidenceHash);
        if (support) _votes[id] |= bit;
        else _votes[id] &= ~bit;
        emit RulingVoteCast(id, requestId, msg.sender, support);
    }

    /// @inheritdoc ICivicAppealReview
    function rulingSupport(bytes32 personId, bytes32 requestId, bool uphold, bytes32 evidenceHash)
        public
        view
        returns (uint256 support)
    {
        IdentityTypes.CivicChangeRequest memory request = _requireAppeal(personId, requestId, evidenceHash);
        uint8 bitmap = _votes[rulingId(personId, requestId, uphold, evidenceHash)];
        bytes32[5] memory countedPeople;
        for (uint256 i; i < REVIEWER_COUNT; ++i) {
            address reviewer = _reviewers[i];
            if (bitmap & _reviewerBits[reviewer] == 0 || !_isIndependent(reviewer, personId, request)) continue;
            bytes32 reviewerPersonId = _identityRegistry.resolveWalletToPersonId(reviewer);
            bool duplicate;
            for (uint256 j; j < support; ++j) {
                if (reviewerPersonId != bytes32(0) && countedPeople[j] == reviewerPersonId) duplicate = true;
            }
            if (!duplicate) countedPeople[support++] = reviewerPersonId;
        }
    }

    /// @inheritdoc ICivicAppealReview
    function executeRuling(bytes32 personId, bytes32 requestId, bool uphold, bytes32 evidenceHash) external {
        uint256 support = rulingSupport(personId, requestId, uphold, evidenceHash);
        if (support < REQUIRED_APPROVALS) revert InsufficientRulingSupport(support);
        bytes32 id = rulingId(personId, requestId, uphold, evidenceHash);
        delete _votes[id];
        _identityApp.resolveCivicAppeal(personId, requestId, uphold, evidenceHash);
        emit RulingExecuted(id, personId, requestId, uphold);
    }

    function _requireAppeal(bytes32 personId, bytes32 requestId, bytes32 evidenceHash)
        private
        view
        returns (IdentityTypes.CivicChangeRequest memory request)
    {
        request = _identityApp.getCivicChange(personId);
        if (
            requestId == bytes32(0) || request.requestId != requestId || request.appealAuthority != address(this)
                || request.appealEvidenceHash == bytes32(0) || request.appealResolved
                || block.timestamp >= request.appealDeadline || evidenceHash == bytes32(0)
        ) revert InvalidAppeal(requestId);
    }

    function _isIndependent(address reviewer, bytes32 personId, IdentityTypes.CivicChangeRequest memory request)
        private
        view
        returns (bool independent)
    {
        if (
            reviewer == request.proposer || reviewer == request.approver
                || _officeRegistry.roleOf(_identityOfficeId, reviewer) != OfficeTypes.OfficeRole.None
        ) return false;
        bytes32 reviewerPersonId = _identityRegistry.resolveWalletToPersonId(reviewer);
        if (reviewerPersonId == bytes32(0)) return true;
        // Also exclude a subject/officer using another known wallet, and inactive historical reviewer wallets.
        return reviewerPersonId != personId
            && reviewerPersonId != _identityRegistry.resolveWalletToPersonId(request.proposer)
            && reviewerPersonId != _identityRegistry.resolveWalletToPersonId(request.approver)
            && _identityRegistry.activeWalletOf(reviewerPersonId) == reviewer;
    }
}
