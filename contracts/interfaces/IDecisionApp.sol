// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {DecisionTypes} from "../types/DecisionTypes.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title IDecisionApp
/// @notice Bounded Congress and ministry decision workflow for wallet-funded token movement, clerk decisions, and
///         Congress-approved creation of new government offices and ministries.
interface IDecisionApp {
    error CongressDecisionNotApproved(bytes32 decisionId, uint32 supportCount, uint32 supportRequired);
    error CongressDecisionTermChanged(bytes32 decisionId, uint256 expectedCycleId, uint256 currentCycleId);
    error DecisionAlreadyExists(bytes32 decisionId);
    error DecisionAlreadyFinalized(bytes32 decisionId);
    error DecisionNotFound(bytes32 decisionId);
    error InvalidDecisionAction(DecisionTypes.DecisionAction action);
    error InvalidDecisionAmount(uint256 amount);
    error InvalidDecisionId(bytes32 decisionId);
    error InvalidDecisionRecipient(address recipient);
    error InvalidDecisionSource(address source);
    error InvalidDecisionToken(address token);
    error InvalidIdentityReference(bytes32 personId);
    error InvalidOfficeAdmin(address admin);
    error InvalidOfficeId(bytes32 officeId);
    error InvalidOfficeKind(OfficeTypes.OfficeKind kind);
    error InvalidOfficeName();
    error OfficeAlreadyRegistered(bytes32 officeId);
    error MinistryOfficeNotFound(bytes32 officeId);
    error MinistryFundingAuthorityMismatch(address expectedAuthority, address configuredAuthority);
    error InvalidRegistry(address registryAddress);
    error InvalidToken(address tokenAddress);
    error NoActiveCongressTerm();
    error NotActiveCongressMember(address caller);
    error NotMinistrySigner(bytes32 officeId, address caller);
    error UnauthorizedDecisionPreparer(bytes32 officeId, address caller);

    event CongressDecisionPrepared(
        bytes32 indexed decisionId,
        uint256 indexed congressCycleId,
        address indexed preparedBy,
        DecisionTypes.DecisionAction action,
        uint32 supportRequired,
        bytes32 metadataHash,
        uint64 preparedAt
    );

    event CongressDecisionSupportRecorded(
        bytes32 indexed decisionId,
        address indexed member,
        uint32 supportCount,
        uint32 supportRequired,
        uint64 recordedAt
    );

    event CongressDecisionSupportRemoved(
        bytes32 indexed decisionId,
        address indexed member,
        uint32 supportCount,
        uint32 supportRequired,
        uint64 removedAt
    );

    event MinistryDecisionPrepared(
        bytes32 indexed decisionId,
        bytes32 indexed officeId,
        address indexed preparedBy,
        DecisionTypes.DecisionAction action,
        bytes32 metadataHash,
        uint64 preparedAt
    );

    event CongressRegisterOfficeDecisionPrepared(
        bytes32 indexed decisionId,
        bytes32 indexed officeId,
        address indexed preparedBy,
        OfficeTypes.OfficeKind kind,
        address admin,
        uint32 supportRequired,
        bytes32 metadataHash,
        uint64 preparedAt
    );

    event CongressFundMinistryDecisionPrepared(
        bytes32 indexed decisionId,
        bytes32 indexed officeId,
        address indexed preparedBy,
        address token,
        uint256 amount,
        uint32 supportRequired,
        bytes32 metadataHash,
        uint64 preparedAt
    );

    event DecisionExecuted(
        bytes32 indexed decisionId,
        DecisionTypes.DecisionScope indexed scope,
        DecisionTypes.DecisionAction indexed action,
        address executedBy,
        uint64 executedAt
    );

    /// @notice Returns the configured Congress candidate registry address.
    function congressCandidateRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured identity registry address.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured office registry address.
    function officeRegistry() external view returns (address registryAddress);

    /// @notice Returns the configured stake registry address.
    function stakeRegistry() external view returns (address registryAddress);

    /// @notice Returns the LLM token accepted for transfer-and-stake decisions.
    function llmToken() external view returns (address tokenAddress);

    /// @notice Returns the stored decision record.
    /// @param decisionId The decision identifier.
    function getDecision(bytes32 decisionId) external view returns (DecisionTypes.DecisionRecord memory record);

    /// @notice Returns true when a Congress member has supported a Congress decision.
    /// @param decisionId The decision identifier.
    /// @param member The Congress member wallet.
    function hasCongressSupported(bytes32 decisionId, address member) external view returns (bool supported);

    /// @notice Returns the required majority support for the current Congress term.
    function requiredCongressSupport() external view returns (uint32 supportRequired);

    /// @notice Opens a Congress decision to transfer an ERC20 from a source wallet to a recipient.
    function createCongressTokenTransferDecision(
        bytes32 decisionId,
        address source,
        address token,
        address recipient,
        uint256 amount,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external;

    /// @notice Opens a Congress decision to create a new government office or ministry. On majority approval the
    ///         office is registered with the given kind, name, and admin, letting the polity add offices after
    ///         genesis without redeploying the office bootstrap authority.
    /// @param decisionId The unique decision identifier.
    /// @param officeId The identifier of the new office to create; must not already exist.
    /// @param kind The office kind that determines the admin's operational powers.
    /// @param name The human-readable office name.
    /// @param admin The address granted the office admin role on creation.
    /// @param metadataHash The off-chain decision metadata commitment.
    /// @param metadataURI The off-chain decision metadata location.
    function createCongressRegisterOfficeDecision(
        bytes32 decisionId,
        bytes32 officeId,
        OfficeTypes.OfficeKind kind,
        string calldata name,
        address admin,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external;

    /// @notice Opens a Congress decision to fund a ministry/office balance in the MinistryTreasury. On majority
    ///         approval the source wallet's tokens are pulled and credited to the office's balance. Congress-gated
    ///         so the regular money flow is not subject to citizen-referendum friction.
    /// @param decisionId The unique decision identifier.
    /// @param officeId The office/ministry to credit; must already exist.
    /// @param source The wallet funding the ministry; must approve this app for the amount before execution.
    /// @param token The ERC20 asset to fund.
    /// @param amount The amount to fund in the asset's smallest units.
    /// @param metadataHash The off-chain decision metadata commitment.
    /// @param metadataURI The off-chain decision metadata location.
    function createCongressFundMinistryDecision(
        bytes32 decisionId,
        bytes32 officeId,
        address source,
        address token,
        uint256 amount,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external;

    /// @notice Records caller support for a Congress decision.
    function supportCongressDecision(bytes32 decisionId) external;

    /// @notice Removes caller support from a Congress decision.
    function revokeCongressDecisionSupport(bytes32 decisionId) external;

    /// @notice Executes an approved Congress decision.
    function executeCongressDecision(bytes32 decisionId) external;

    /// @notice Prepares a ministry ERC20 transfer decision. A clerk or minister may prepare it.
    function prepareMinistryTokenTransferDecision(
        bytes32 officeId,
        bytes32 decisionId,
        address token,
        address recipient,
        uint256 amount,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external;

    /// @notice Prepares a ministry LLM transfer-and-stake decision. A clerk or minister may prepare it.
    function prepareMinistryLlmStakeDecision(
        bytes32 officeId,
        bytes32 decisionId,
        bytes32 recipientPersonId,
        uint256 amount,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external;

    /// @notice Prepares a ministry clerk add/remove decision. A clerk or minister may prepare it.
    function prepareMinistryClerkDecision(
        bytes32 officeId,
        bytes32 decisionId,
        address clerk,
        bool active,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external;

    /// @notice Executes a prepared ministry decision. The minister wallet must sign the execution transaction.
    function executeMinistryDecision(bytes32 decisionId) external;
}
