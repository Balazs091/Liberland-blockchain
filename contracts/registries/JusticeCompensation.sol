// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {KernelModule} from "../base/KernelModule.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IJusticeCompensation} from "../interfaces/IJusticeCompensation.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {LLMTokenConstants} from "../libraries/LLMTokenConstants.sol";

/// @title JusticeCompensation
/// @notice Stable escrow for voluntarily exposed liquid LLM, exact final awards and funded restoration.
/// @dev Existing wallets, political stake, loans and canonical staking backing are never debited. There are no
///      pre-decision reservations: final awards consume a lot's available funds in execution order. Consent binds
///      one immutable deposit, terms and expiry, so later deposits cannot replenish an older award's collateral.
contract JusticeCompensation is IJusticeCompensation, KernelModule, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 private immutable _token;
    IIdentityRegistry private immutable _identityRegistry;
    mapping(bytes32 lotId => ExposureLot lot) private _lots;
    mapping(bytes32 awardId => AwardRecord record) private _awards;
    mapping(bytes32 personId => uint256 amount) private _claimable;
    uint256 private _totalLiabilities;

    /// @param kernelAddress Canonical governance kernel.
    /// @param tokenAddress The reviewed 18-decimal Liberland Merit token.
    /// @param identityRegistryAddress Identity ledger required for new exposure and justice writes.
    constructor(address kernelAddress, address tokenAddress, address identityRegistryAddress)
        KernelModule(kernelAddress)
    {
        if (tokenAddress.code.length == 0 || identityRegistryAddress.code.length == 0) {
            revert InvalidConfiguration(address(0));
        }
        if (IERC20Metadata(tokenAddress).decimals() != LLMTokenConstants.DECIMALS) {
            revert InvalidConfiguration(tokenAddress);
        }
        if (IIdentityRegistry(identityRegistryAddress).kernel() != kernelAddress) {
            revert InvalidConfiguration(identityRegistryAddress);
        }
        _token = IERC20(tokenAddress);
        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
    }

    /// @inheritdoc IJusticeCompensation
    function token() external view returns (address) {
        return address(_token);
    }

    /// @inheritdoc IJusticeCompensation
    function identityRegistry() external view returns (address) {
        return address(_identityRegistry);
    }

    /// @inheritdoc IJusticeCompensation
    function getLot(bytes32 lotId) external view returns (ExposureLot memory) {
        return _lots[lotId];
    }

    /// @inheritdoc IJusticeCompensation
    function getAward(bytes32 awardId) external view returns (AwardRecord memory) {
        return _awards[awardId];
    }

    /// @inheritdoc IJusticeCompensation
    function claimableOf(bytes32 personId) external view returns (uint256) {
        return _claimable[personId];
    }

    /// @inheritdoc IJusticeCompensation
    function totalLiabilities() external view returns (uint256) {
        return _totalLiabilities;
    }

    /// @inheritdoc IJusticeCompensation
    function deposit(bytes32 lotId, uint128 amount, bytes32 termsHash, uint48 exposureEndsAt) external nonReentrant {
        _requireCurrent();
        _requireAmount(amount);
        bytes32 personId = _activePerson(msg.sender);
        if (lotId == bytes32(0) || _lots[lotId].personId != bytes32(0) || termsHash == bytes32(0)) {
            revert InvalidLot(lotId);
        }
        if (exposureEndsAt <= block.timestamp) revert InvalidExposureEnd(exposureEndsAt);
        uint48 depositedBlock = SafeCast.toUint48(block.number);
        _pull(msg.sender, amount);
        _lots[lotId] = ExposureLot(personId, termsHash, amount, amount, depositedBlock, exposureEndsAt);
        _totalLiabilities += amount;
        _requireBacking();
        emit ExposureDeposited(lotId, personId, msg.sender, amount, termsHash, depositedBlock, exposureEndsAt);
    }

    /// @inheritdoc IJusticeCompensation
    function refund(bytes32 lotId) external nonReentrant {
        ExposureLot storage lot = _lots[lotId];
        bytes32 personId = _activePerson(msg.sender);
        if (lot.personId != personId) revert InvalidLot(lotId);
        if (block.timestamp < lot.exposureEndsAt) revert ExposureNotEnded(lotId, lot.exposureEndsAt);
        uint128 amount = lot.remainingAmount;
        _requireAmount(amount);
        lot.remainingAmount = 0;
        _totalLiabilities -= amount;
        _pay(msg.sender, amount);
        emit ExposureRefunded(lotId, personId, msg.sender, amount);
    }

    /// @inheritdoc IJusticeCompensation
    function award(
        bytes32 awardId,
        bytes32 lotId,
        bytes32 subject,
        bytes32 beneficiary,
        uint128 amount,
        uint48 cutoffBlock,
        bytes32 termsHash
    ) external nonReentrant {
        _requireJustice();
        _requireAmount(amount);
        if (awardId == bytes32(0) || _awards[awardId].lotId != bytes32(0)) revert InvalidAward(awardId);
        ExposureLot storage lot = _lots[lotId];
        if (subject == bytes32(0) || lot.personId != subject) revert InvalidLot(lotId);
        if (beneficiary == subject || !_identityRegistry.identityExists(beneficiary)) {
            revert InvalidAwardParties(subject, beneficiary);
        }
        if (block.timestamp >= lot.exposureEndsAt) revert ExposureEnded(lotId);
        if (cutoffBlock < lot.depositedBlock || cutoffBlock >= block.number) {
            revert InvalidCutoff(lot.depositedBlock, cutoffBlock, block.number);
        }
        if (termsHash != lot.termsHash) revert TermsMismatch(lot.termsHash, termsHash);
        if (amount > lot.remainingAmount) revert InsufficientLotBalance(lotId, lot.remainingAmount, amount);
        _requireBacking();
        lot.remainingAmount -= amount;
        _awards[awardId] = AwardRecord(lotId, subject, beneficiary, amount, 0, 0, cutoffBlock);
        _claimable[beneficiary] += amount;
        emit CompensationAwarded(awardId, lotId, beneficiary, subject, amount, cutoffBlock);
    }

    /// @inheritdoc IJusticeCompensation
    function fundRestoration(bytes32 awardId, uint128 amount) external nonReentrant {
        _requireCurrent();
        _requireAmount(amount);
        AwardRecord storage record = _existingAward(awardId);
        uint128 unfunded = record.amount - record.restoredAmount - record.restorationFunding;
        if (amount > unfunded) revert InvalidAmount(amount);
        _pull(msg.sender, amount);
        record.restorationFunding += amount;
        _totalLiabilities += amount;
        _requireBacking();
        emit RestorationFunded(awardId, msg.sender, amount);
    }

    /// @inheritdoc IJusticeCompensation
    function restore(bytes32 awardId, uint128 amount) external nonReentrant {
        _requireJustice();
        _requireAmount(amount);
        AwardRecord storage record = _existingAward(awardId);
        if (amount > record.restorationFunding) {
            revert InsufficientRestorationFunding(awardId, record.restorationFunding, amount);
        }
        _requireBacking();
        record.restorationFunding -= amount;
        record.restoredAmount += amount;
        _claimable[record.subject] += amount;
        emit CompensationRestored(awardId, record.subject, amount);
    }

    /// @inheritdoc IJusticeCompensation
    function claim() external nonReentrant {
        bytes32 personId = _activePerson(msg.sender);
        uint256 amount = _claimable[personId];
        _requireAmount(amount);
        delete _claimable[personId];
        _totalLiabilities -= amount;
        _pay(msg.sender, amount);
        emit CompensationClaimed(personId, msg.sender, amount);
    }

    function _existingAward(bytes32 awardId) private view returns (AwardRecord storage record) {
        record = _awards[awardId];
        if (record.lotId == bytes32(0)) revert InvalidAward(awardId);
    }

    function _requireCurrent() private view {
        if (
            _kernel.getModule(KernelModuleIds.JUSTICE_COMPENSATION) != address(this)
                || _kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY) != address(_identityRegistry)
        ) revert InactiveCompensation();
    }

    function _requireJustice() private view {
        _requireCurrent();
        if (msg.sender != _kernel.getModule(KernelModuleIds.JUSTICE_APP)) {
            revert UnauthorizedJusticeCaller(msg.sender);
        }
    }

    /// @dev Exits remain available from a retired escrow. Resolve the current identity ledger so a revoked old
    ///      wallet cannot regain access after an explicitly migrated identity registry; stable person IDs must be
    ///      preserved by that migration. No citizenship, membership or political-eligibility condition gates exits.
    function _activePerson(address wallet) private view returns (bytes32 personId) {
        IIdentityRegistry identity = IIdentityRegistry(_kernel.getModule(KernelModuleIds.IDENTITY_REGISTRY));
        personId = identity.resolveWalletToPersonId(wallet);
        if (
            personId == bytes32(0) || !identity.hasActiveWalletLink(wallet)
                || identity.activeWalletOf(personId) != wallet
        ) {
            revert UnauthorizedWallet(wallet);
        }
    }

    function _requireAmount(uint256 amount) private pure {
        if (amount == 0) revert InvalidAmount(amount);
    }

    function _pull(address from, uint256 amount) private {
        uint256 beforeBalance = _token.balanceOf(address(this));
        _token.safeTransferFrom(from, address(this), amount);
        uint256 received = _token.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert UnexpectedTokenAmount(amount, received);
    }

    function _pay(address recipient, uint256 amount) private {
        uint256 beforeBalance = _token.balanceOf(recipient);
        _token.safeTransfer(recipient, amount);
        uint256 received = _token.balanceOf(recipient) - beforeBalance;
        if (received != amount) revert UnexpectedTokenAmount(amount, received);
        _requireBacking();
    }

    function _requireBacking() private view {
        uint256 balance = _token.balanceOf(address(this));
        if (balance < _totalLiabilities) revert InsufficientBacking(balance, _totalLiabilities);
    }
}
