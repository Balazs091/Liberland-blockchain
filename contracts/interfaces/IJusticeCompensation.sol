// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IKernelModule} from "./IKernelModule.sol";

/// @title IJusticeCompensation
/// @notice Voluntary liquid-LLM exposure, final funded awards and separately funded restoration.
interface IJusticeCompensation is IKernelModule {
    struct ExposureLot {
        bytes32 personId;
        bytes32 termsHash;
        uint128 depositedAmount;
        uint128 remainingAmount;
        uint48 depositedBlock;
        uint48 exposureEndsAt;
    }

    struct AwardRecord {
        bytes32 lotId;
        bytes32 subject;
        bytes32 beneficiary;
        uint128 amount;
        uint128 restoredAmount;
        uint128 restorationFunding;
        uint48 cutoffBlock;
    }

    error InvalidConfiguration(address value);
    error InactiveCompensation();
    error UnauthorizedJusticeCaller(address caller);
    error UnauthorizedWallet(address wallet);
    error InvalidLot(bytes32 lotId);
    error InvalidAward(bytes32 awardId);
    error InvalidAmount(uint256 amount);
    error InvalidExposureEnd(uint48 exposureEndsAt);
    error ExposureNotEnded(bytes32 lotId, uint48 exposureEndsAt);
    error ExposureEnded(bytes32 lotId);
    error InvalidCutoff(uint48 depositedBlock, uint48 cutoffBlock, uint256 currentBlock);
    error TermsMismatch(bytes32 expected, bytes32 supplied);
    error InvalidAwardParties(bytes32 subject, bytes32 beneficiary);
    error InsufficientLotBalance(bytes32 lotId, uint256 available, uint256 requested);
    error InsufficientRestorationFunding(bytes32 awardId, uint256 available, uint256 requested);
    error UnexpectedTokenAmount(uint256 expected, uint256 actual);
    error InsufficientBacking(uint256 balance, uint256 liabilities);

    event ExposureDeposited(
        bytes32 indexed lotId,
        bytes32 indexed personId,
        address indexed wallet,
        uint128 amount,
        bytes32 termsHash,
        uint48 depositedBlock,
        uint48 exposureEndsAt
    );
    event ExposureRefunded(bytes32 indexed lotId, bytes32 indexed personId, address indexed wallet, uint128 amount);
    event CompensationAwarded(
        bytes32 indexed awardId,
        bytes32 indexed lotId,
        bytes32 indexed beneficiary,
        bytes32 subject,
        uint128 amount,
        uint48 cutoffBlock
    );
    event RestorationFunded(bytes32 indexed awardId, address indexed donor, uint128 amount);
    event CompensationRestored(bytes32 indexed awardId, bytes32 indexed subject, uint128 amount);
    event CompensationClaimed(bytes32 indexed personId, address indexed wallet, uint256 amount);

    /// @notice Returns the sole escrow asset, liquid Liberland Merit.
    function token() external view returns (address);

    /// @notice Returns the identity registry pinned for new exposure and justice writes.
    function identityRegistry() external view returns (address);

    /// @notice Returns the immutable consent fields and remaining balance of a deposit lot.
    function getLot(bytes32 lotId) external view returns (ExposureLot memory);

    /// @notice Returns one final award and its independently funded restoration accounting.
    function getAward(bytes32 awardId) external view returns (AwardRecord memory);

    /// @notice Returns assigned liquid LLM claimable by the person's current active wallet.
    function claimableOf(bytes32 personId) external view returns (uint256);

    /// @notice Returns the sum of remaining lots, pull credits and allocated restoration funding.
    function totalLiabilities() external view returns (uint256);

    /// @notice Exposes only the caller's newly deposited liquid LLM under exact terms until the agreed end.
    /// @dev A lot identifier is single-use. Funding another person's stake never grants this consent.
    function deposit(bytes32 lotId, uint128 amount, bytes32 termsHash, uint48 exposureEndsAt) external;

    /// @notice Returns a lot's unawarded balance to its owner's current wallet after its agreed end.
    function refund(bytes32 lotId) external;

    /// @notice Credits one exact final award from an eligible existing lot, without moving political stake.
    /// @dev Only the canonical JusticeApp may call. The cutoff must be a completed block. Competing awards
    ///      consume available funds in execution order; this contract creates no pre-decision reservation.
    function award(
        bytes32 awardId,
        bytes32 lotId,
        bytes32 subject,
        bytes32 beneficiary,
        uint128 amount,
        uint48 cutoffBlock,
        bytes32 termsHash
    ) external;

    /// @notice Irrevocably donates liquid LLM solely to fund a potential restoration of this award.
    /// @dev Funding is capped by the unrestored award less existing funding. It grants no restoration authority
    ///      and has no donor refund; donors accept that the funds await an approved restoration.
    function fundRestoration(bytes32 awardId, uint128 amount) external;

    /// @notice Credits the original subject using only this award's allocated restoration funding.
    /// @dev Only the canonical JusticeApp may call; it must authenticate a separate exact restoration effect.
    function restore(bytes32 awardId, uint128 amount) external;

    /// @notice Pulls all assigned awards/restoration to the caller's current active identity wallet.
    function claim() external;
}
