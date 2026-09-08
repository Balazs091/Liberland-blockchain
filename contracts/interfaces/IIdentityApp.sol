// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IdentityTypes} from "../types/IdentityTypes.sol";

/// @title IIdentityApp
/// @notice Standing governed identity authority: office-gated citizenship lifecycle, caller-initiated
///         citizenship renunciation, and timelocked, office-approved single-wallet migration.
interface IIdentityApp {
    error InvalidIdentityRegistry(address registryAddress);
    error InvalidOfficeRegistry(address registryAddress);
    error KernelMismatch(address identityKernel, address officeKernel);
    error InvalidIdentityOffice(bytes32 officeId);
    error InvalidMigrationDelay(uint64 migrationDelaySeconds);
    error UnauthorizedIdentityOfficer(address caller, bytes32 officeId);
    error NotRenounceableCitizen(address caller, bytes32 personId);
    error WalletNotLinked(address wallet);
    error InvalidNewWallet(address newWallet);
    error NewWalletAlreadyLinked(address newWallet, bytes32 personId);
    error MigrationAlreadyPending(bytes32 personId);
    error MigrationNotFound(bytes32 personId);
    error MigrationAlreadyApproved(bytes32 personId);
    error MigrationNotApproved(bytes32 personId);
    error MigrationDelayNotElapsed(bytes32 personId, uint64 readyAt);
    error MigrationOldWalletInactive(bytes32 personId, address oldWallet);
    error UnauthorizedMigrationCanceller(address caller, bytes32 personId);
    error IdentityAlreadyRegistered(bytes32 personId);
    error IdentityNotRegistered(bytes32 personId);
    error UseCivicChangeProcedure(bytes32 personId);
    error InitialWalletOnly(bytes32 personId);
    error DestinationConsentRequired(bytes32 personId);
    error StaleRequest(bytes32 expected, bytes32 supplied);
    error DistinctOfficerRequired();
    error InvalidEvidenceHash();
    error CivicChangePending(bytes32 personId);
    error CivicChangeNotReady(bytes32 personId);
    error CivicAppealNotOpen(bytes32 personId);
    error UnauthorizedCivicReviewer(address caller);
    error StaleOfficerAuthorization(address officer);

    event InitialWalletProposed(bytes32 indexed personId, address indexed wallet);
    event InitialWalletAccepted(bytes32 indexed personId, address indexed wallet);
    event MigrationConsent(bytes32 indexed personId, bytes32 indexed requestId, address indexed destination);
    event MigrationProposalBound(
        bytes32 indexed personId, bytes32 indexed requestId, uint256 nonce, bool recovery, bytes32 evidenceHash
    );
    event CivicChangeProposed(
        bytes32 indexed personId, bytes32 indexed requestId, address indexed proposer, bytes32 evidenceHash
    );
    event CivicChangeApproved(
        bytes32 indexed personId, bytes32 indexed requestId, address indexed approver, uint64 readyAt
    );
    event CivicChangeCancelled(bytes32 indexed personId, bytes32 indexed requestId, address indexed caller);
    event CivicChangeFinalized(bytes32 indexed personId, bytes32 indexed requestId);
    event CivicAppealAuthorityPinned(bytes32 indexed personId, bytes32 indexed requestId, address indexed authority);
    event CivicChangeAppealed(
        bytes32 indexed personId, bytes32 indexed requestId, bytes32 evidenceHash, uint64 deadline
    );
    event CivicAppealResolved(
        bytes32 indexed personId, bytes32 indexed requestId, bool upheld, bytes32 rulingEvidenceHash, uint64 readyAt
    );
    event CivicAppealExpired(bytes32 indexed personId, bytes32 indexed requestId);

    event CitizenshipRenounced(bytes32 indexed personId, address indexed wallet, uint64 timestamp);

    event WalletMigrationRequested(
        bytes32 indexed personId, address indexed oldWallet, address indexed newWallet, uint64 requestedAt
    );

    event WalletMigrationApproved(bytes32 indexed personId, address indexed approvedBy, uint64 approvedAt);

    event WalletMigrationFinalized(
        bytes32 indexed personId, address indexed oldWallet, address indexed newWallet, uint64 timestamp
    );

    event WalletMigrationCancelled(bytes32 indexed personId, address indexed cancelledBy, uint64 timestamp);

    /// @notice Returns the identity registry this app mutates as the standing authority.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the office registry used to resolve identity-office roles.
    /// @return registryAddress The office registry address.
    function officeRegistry() external view returns (address registryAddress);

    /// @notice Returns the kernel shared by the identity and office registries.
    /// @return kernelAddress The configured kernel address.
    function kernel() external view returns (address kernelAddress);

    /// @notice Returns the pinned identity office identifier gating management actions.
    /// @return officeId The identity office identifier.
    function identityOfficeId() external view returns (bytes32 officeId);

    /// @notice Returns the post-approval timelock delay applied before a wallet migration can finalize.
    /// @return delaySeconds The migration delay in seconds.
    function migrationDelay() external view returns (uint64 delaySeconds);

    /// @notice Onboards a new non-citizen identity. Cannot overwrite an existing record or impose final suspension.
    /// @param personId The canonical person identifier.
    /// @param input The identity fields to store.
    function registerIdentity(bytes32 personId, IdentityTypes.IdentityRecordInput calldata input) external;

    /// @notice Proposes the first active wallet for a newly onboarded identity; destination must accept separately.
    /// @param personId The canonical person identifier.
    /// @param wallet The wallet whose link is updated.
    /// @param status The new wallet link status.
    function linkWallet(bytes32 personId, address wallet, IdentityTypes.WalletLinkStatus status) external;

    /// @notice Makes the one-time onboarding citizenship grant to a verified adult. Reinstatement uses civic notice.
    /// @param personId The canonical person identifier.
    /// @param status The new citizenship status.
    function setCitizenship(bytes32 personId, IdentityTypes.CitizenshipStatus status) external;

    /// @notice Renounces the caller's own citizenship (Art IV §2.3). The office cannot block this.
    /// @dev Resolves the caller to a person with an active wallet link and current Citizen status, then sets
    ///      citizenship to None while preserving all other fields and leaving the wallet link intact.
    function renounceCitizenship() external;

    /// @notice Requests migration of the caller's single active wallet to a new, currently-unlinked wallet.
    /// @param newWallet The wallet to migrate to once approved and the timelock elapses.
    function requestWalletMigration(address newWallet) external;

    /// @notice Approves a pending wallet migration, starting the finalization timelock. Identity-office admin or clerk.
    /// @param personId The person identifier whose migration is approved.
    function approveWalletMigration(bytes32 personId, bytes32 requestId) external;

    /// @notice Accepts the initial wallet proposed by the identity office. Destination caller only.
    function acceptInitialWallet(bytes32 personId) external;

    /// @notice Corrects metadata only, without altering any civic status or wallet.
    function correctMetadata(bytes32 personId, bytes32 metadataHash, string calldata metadataURI) external;

    /// @notice Returns the chain/app/person/wallet/nonce-bound digest of the pending request.
    function walletMigrationId(bytes32 personId) external view returns (bytes32 requestId);

    /// @notice Accepts an exact pending migration or recovery. Destination caller only.
    function acceptWalletMigration(bytes32 personId, bytes32 requestId) external;

    /// @notice Admin proposes documented lost-key recovery; distinct officer, destination consent and seven days required.
    function proposeWalletRecovery(bytes32 personId, address newWallet, bytes32 evidenceHash) external;

    /// @notice Proposes a documented civic-field change, including adverse changes or reversal of final suspension.
    function proposeCivicChange(
        bytes32 personId,
        IdentityTypes.CivicStatusInput calldata proposed,
        bytes32 evidenceHash
    ) external returns (bytes32 requestId);

    /// @notice A distinct current officer approves the exact request and starts seven-day notice.
    function approveCivicChange(bytes32 personId, bytes32 requestId) external;

    /// @notice Returns the pending civic change and its evidence, officers and notice deadline.
    function getCivicChange(bytes32 personId) external view returns (IdentityTypes.CivicChangeRequest memory request);

    /// @notice Finalizes an unchanged, approved civic request after notice; callable by anyone.
    function finalizeCivicChange(bytes32 personId, bytes32 requestId) external;

    /// @notice Withdraws a pending civic change. Current identity officers only, never the affected person.
    function cancelCivicChange(bytes32 personId, bytes32 requestId) external;

    /// @notice Files the affected active wallet's one evidence-backed appeal before the seven-day notice ends.
    function appealCivicChange(bytes32 personId, bytes32 requestId, bytes32 evidenceHash) external;

    /// @notice Records the pinned review authority's exact-case ruling before the 30-day appeal deadline.
    /// @dev Upholding starts a two-day execution delay; dismissal deletes the request. No alternative status is allowed.
    function resolveCivicAppeal(bytes32 personId, bytes32 requestId, bool uphold, bytes32 rulingEvidenceHash) external;

    /// @notice Dismisses an unanswered appeal at its deadline. Permissionless; never imposes a default penalty.
    function expireCivicAppeal(bytes32 personId, bytes32 requestId) external;

    /// @notice Finalizes an approved wallet migration after the timelock elapses. Callable by anyone.
    /// @param personId The person identifier whose migration is finalized.
    function finalizeWalletMigration(bytes32 personId) external;

    /// @notice Cancels a pending wallet migration. Callable by the recorded old wallet or an identity officer.
    /// @param personId The person identifier whose migration is cancelled.
    function cancelWalletMigration(bytes32 personId) external;

    /// @notice Returns the pending migration request for a person, if any.
    /// @param personId The canonical person identifier.
    /// @return request The stored migration request, or an empty request when none is pending.
    function getWalletMigration(bytes32 personId) external view returns (IdentityTypes.MigrationRequest memory request);
}
