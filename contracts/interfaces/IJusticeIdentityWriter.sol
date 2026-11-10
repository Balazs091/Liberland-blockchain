// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IKernelModule} from "./IKernelModule.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";

/// @title IJusticeIdentityWriter
/// @notice Applies typed justice effects and person-authorised identity transitions to the canonical registry.
interface IJusticeIdentityWriter is IKernelModule {
    struct WalletMigrationRequest {
        address oldWallet;
        uint64 expiresAt;
        address newWallet;
        uint256 nonce;
    }

    error InvalidIdentityRegistry(address registry);
    error IdentityRegistryNotCurrent(address registry);
    error IdentityWriterNotCurrent(address writer);
    error UnauthorizedJusticeApp(address caller);
    error InvalidPersonId();
    error InvalidAdmissionEvidence();
    error UndefinedAdmissionAge();
    error IdentityCannotBeAdmitted(bytes32 personId);
    error IdentityNotCitizen(bytes32 personId);
    error IdentityNotRevoked(bytes32 personId);
    error IdentityCannotRecognizeAdulthood(bytes32 personId);
    error InactiveWallet(address wallet);
    error ActiveWalletChanged(bytes32 personId, address expected, address actual);
    error InvalidDestinationWallet(address wallet);
    error DestinationWalletAlreadyLinked(address wallet);
    error WalletMigrationExpired(uint64 expiresAt);
    error InvalidWalletMigrationRequest(bytes32 personId, bytes32 requestId);
    error WalletMigrationDestinationOnly(address caller, address expected);
    error WalletMigrationSourceOnly(address caller, address expected);

    event CitizenshipAdmitted(bytes32 indexed personId, address indexed wallet, bytes32 indexed evidenceHash);
    event CitizenshipAnnulled(bytes32 indexed personId);
    event CitizenshipRestored(bytes32 indexed personId);
    event AdulthoodRecognized(bytes32 indexed personId);
    event CitizenshipRenounced(bytes32 indexed personId, address indexed wallet);
    event WalletRecovered(bytes32 indexed personId, address indexed oldWallet, address indexed newWallet);
    event WalletMigrationRequested(
        bytes32 indexed personId,
        bytes32 indexed requestId,
        address indexed oldWallet,
        address newWallet,
        uint64 expiresAt
    );
    event WalletMigrationCancelled(bytes32 indexed personId, bytes32 indexed requestId);
    event WalletMigrationExecuted(
        bytes32 indexed personId, bytes32 indexed requestId, address indexed oldWallet, address newWallet
    );

    /// @notice Returns the immutable identity registry this writer can mutate while both are current.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Records approved citizenship for a fresh person or an eligible existing noncitizen.
    /// @dev The current JusticeApp authenticates the route, exact approved fields and destination consent.
    function executeAdmission(bytes32 personId, address wallet, bytes32 evidenceHash, IdentityTypes.AgeClass ageClass)
        external;

    /// @notice Annuls current citizenship after the current JusticeApp approves the effect.
    function executeAnnulment(bytes32 personId) external;

    /// @notice Restores revoked citizenship after the JusticeApp authenticates reversal of its live annulment.
    /// @dev Preserves verification, age, metadata, restrictions and wallet links; it is not a general re-admission.
    function executeCitizenshipRestoration(bytes32 personId) external;

    /// @notice Records an approved Verified Minor-to-Adult transition for an existing citizen or e-resident.
    /// @dev Preserves citizenship, verification, metadata, restrictions and the wallet link. The JusticeApp
    ///      authenticates the adulthood evidence and exact current-wallet consent; no birthday is inferred.
    function executeAdulthood(bytes32 personId) external;

    /// @notice Replaces an active wallet after the current JusticeApp approves recovery and verifies destination consent.
    function executeRecovery(bytes32 personId, address expectedOld, address newWallet) external;

    /// @notice Lets an active citizen renounce citizenship while retaining the existing wallet link.
    function renounceCitizenship() external;

    /// @notice Records the active wallet's consent to migrate to an unused destination before an exclusive deadline.
    /// @return requestId The exact request ID the destination must accept.
    function requestWalletMigration(address newWallet, uint64 expiresAt) external returns (bytes32 requestId);

    /// @notice Returns the stored voluntary migration and its exact request ID, or zero ID if no request is stored.
    function getWalletMigration(bytes32 personId)
        external
        view
        returns (WalletMigrationRequest memory request, bytes32 requestId);

    /// @notice Lets the named destination accept the exact request and complete the wallet change atomically.
    function acceptWalletMigration(bytes32 personId, bytes32 requestId) external;

    /// @notice Lets the currently active source wallet cancel its exact voluntary migration request.
    function cancelWalletMigration(bytes32 personId, bytes32 requestId) external;
}
