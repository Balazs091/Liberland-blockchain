// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IInterestRatePolicy} from "../interfaces/IInterestRatePolicy.sol";
import {ILendingRiskParameterPolicy} from "../interfaces/ILendingRiskParameterPolicy.sol";
import {ILLMPriceOraclePolicy} from "../interfaces/ILLMPriceOraclePolicy.sol";
import {IStakeLienRegistry} from "../interfaces/IStakeLienRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IUSDCLendingPoolApp} from "../interfaces/IUSDCLendingPoolApp.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {LendingTypes} from "../types/LendingTypes.sol";
import {StakeTypes} from "../types/StakeTypes.sol";

/// @title USDCLendingPoolApp
/// @notice USDC lending app backed by active LLM stake above the retained citizenship floor.
contract USDCLendingPoolApp is ERC20, ReentrancyGuard, IUSDCLendingPoolApp {
    using SafeERC20 for IERC20;

    struct RepaymentQuote {
        uint256 amount;
        uint256 scaledDebt;
        uint256 remainingDebt;
    }

    uint256 public constant RAY = 1e27;
    uint256 public constant HEALTH_FACTOR_SCALE = 1e18;
    uint256 public constant BPS = 10_000;

    uint256 private constant VIRTUAL_ASSETS = 1_000_000;
    uint256 private constant VIRTUAL_SHARES = 1_000_000;

    IConstitutionKernel private immutable _kernel;
    IERC20 private immutable _usdc;
    IIdentityRegistry private immutable _identityRegistry;
    IStakeRegistry private immutable _stakeRegistry;
    IStakeLienRegistry private immutable _stakeLienRegistry;
    uint8 private immutable _shareDecimals;
    uint256 private immutable _borrowCap;

    uint256 private _totalScaledDebt;
    uint256 private _totalReserves;
    uint256 private _borrowIndex;
    uint64 private _lastAccrualTimestamp;
    uint64 private _rateCheckpointTimestamp;
    uint256 private _rateCheckpointIndex;
    uint256 private _effectiveBorrowRateRay;
    uint256 private _effectiveSupplyRateRay;
    uint256 private _reserveAccrualRemainder;
    uint16 private _effectiveReserveFactorBps;
    bool private _accrualConfigurationInitialized;

    mapping(bytes32 personId => uint256 scaledDebt) private _accountScaledDebt;

    /// @param kernelAddress The canonical kernel registry address.
    /// @param usdcAddress The USDC token address.
    /// @param identityRegistryAddress The identity registry address.
    /// @param stakeRegistryAddress The stake registry address.
    /// @param stakeLienRegistryAddress The stake lien registry address.
    /// @param borrowCap_ Maximum total USDC borrows for this v1 pool.
    /// @dev The LLM/USDC price oracle is resolved live from the kernel (`LLM_USDC_PRICE_ORACLE_POLICY`), not fixed
    ///      at construction, so governance can move from the launch manual oracle to a Uniswap V4 TWAP oracle by
    ///      repointing that module without redeploying this pool. Every resolution re-checks that the oracle prices
    ///      this pool's own USDC (`_priceOracle`), so a mis-scaled or wrong-asset oracle can never be used. The current
    ///      citizenship floor applies when a lien begins and is snapshotted until that lien is cleared, so a later
    ///      floor increase cannot retroactively freeze liquidation.
    constructor(
        address kernelAddress,
        address usdcAddress,
        address identityRegistryAddress,
        address stakeRegistryAddress,
        address stakeLienRegistryAddress,
        uint256 borrowCap_
    ) ERC20("Liberland USDC Lending Share", "llUSDC") {
        _requireContract(kernelAddress);
        _requireContract(usdcAddress);
        _requireContract(identityRegistryAddress);
        _requireContract(stakeRegistryAddress);
        _requireContract(stakeLienRegistryAddress);
        if (borrowCap_ == 0) {
            revert InvalidBorrowCap(borrowCap_);
        }

        _kernel = IConstitutionKernel(kernelAddress);
        _usdc = IERC20(usdcAddress);
        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _stakeLienRegistry = IStakeLienRegistry(stakeLienRegistryAddress);
        _shareDecimals = IERC20Metadata(usdcAddress).decimals();
        _borrowCap = borrowCap_;
        _borrowIndex = RAY;
        _lastAccrualTimestamp = uint64(block.timestamp);
        _rateCheckpointTimestamp = uint64(block.timestamp);
        _rateCheckpointIndex = RAY;
    }

    /// @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _shareDecimals;
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function usdc() external view returns (address tokenAddress) {
        return address(_usdc);
    }

    /// @notice Returns the configured identity registry.
    /// @return registryAddress The identity registry address.
    function identityRegistry() external view returns (address registryAddress) {
        return address(_identityRegistry);
    }

    /// @notice Returns the configured stake registry.
    /// @return registryAddress The stake registry address.
    function stakeRegistry() external view returns (address registryAddress) {
        return address(_stakeRegistry);
    }

    /// @notice Returns the configured stake lien registry.
    /// @return registryAddress The stake lien registry address.
    function stakeLienRegistry() external view returns (address registryAddress) {
        return address(_stakeLienRegistry);
    }

    /// @notice Returns the configured price oracle policy.
    /// @return policyAddress The price oracle policy address.
    function priceOraclePolicy() external view returns (address policyAddress) {
        return _kernel.getModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY);
    }

    /// @notice Returns the configured interest-rate policy.
    /// @return policyAddress The interest-rate policy address.
    function interestRatePolicy() external view returns (address policyAddress) {
        return address(_interestRatePolicy());
    }

    /// @notice Returns the configured total borrow cap.
    /// @return amount The USDC borrow cap.
    function borrowCap() external view returns (uint256 amount) {
        return _borrowCap;
    }

    /// @notice Returns stored total borrows before preview interest.
    /// @return amount The stored total borrow amount.
    function totalBorrows() external view returns (uint256 amount) {
        return _storedTotalBorrows();
    }

    /// @notice Returns stored protocol reserves.
    /// @return amount The stored protocol reserve amount.
    function totalReserves() external view returns (uint256 amount) {
        return _totalReserves;
    }

    /// @notice Returns the global borrow index.
    /// @return indexRay The borrow index scaled by 1e27.
    function borrowIndex() external view returns (uint256 indexRay) {
        return _borrowIndex;
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function totalManagedAssets() public view returns (uint256 amount) {
        uint256 cash = _usdc.balanceOf(address(this));
        uint256 grossAssets = cash + _storedTotalBorrows();
        if (grossAssets <= _totalReserves) {
            return 0;
        }

        return grossAssets - _totalReserves;
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function availableLiquidity() public view returns (uint256 amount) {
        uint256 cash = _usdc.balanceOf(address(this));
        if (cash <= _totalReserves) {
            return 0;
        }

        return cash - _totalReserves;
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function utilizationRate() public view returns (uint256 utilizationRay) {
        uint256 storedBorrows = _storedTotalBorrows();
        uint256 managedAssets = totalManagedAssets();
        if (managedAssets == 0 || storedBorrows == 0) {
            return 0;
        }
        if (storedBorrows >= managedAssets) {
            return RAY;
        }

        return Math.mulDiv(storedBorrows, RAY, managedAssets);
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function ratePreview() external view returns (LendingTypes.RatePreview memory preview) {
        preview.utilizationRay = utilizationRate();
        if (_accrualConfigurationInitialized) {
            preview.borrowRatePerSecondRay = _effectiveBorrowRateRay;
            preview.supplyRatePerSecondRay = _effectiveSupplyRateRay;
            return preview;
        }

        IInterestRatePolicy interestPolicy = _interestRatePolicy();
        preview.borrowRatePerSecondRay = interestPolicy.borrowRatePerSecond(preview.utilizationRay);
        preview.supplyRatePerSecondRay =
            interestPolicy.supplyRatePerSecond(preview.utilizationRay, _riskParameters().reserveFactorBps);
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function currentDebtOf(bytes32 personId) public view returns (uint256 amount) {
        return _debtAtIndex(_accountScaledDebt[personId], _previewBorrowIndex());
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function maxBorrowable(bytes32 personId) external view returns (uint256 amount) {
        uint256 maxDebt = _maxDebtForPerson(personId);
        uint256 debt = currentDebtOf(personId);
        if (maxDebt <= debt) {
            return 0;
        }

        uint256 availableByCollateral = maxDebt - debt;
        uint256 storedBorrows = _storedTotalBorrows();
        uint256 availableByCap = storedBorrows >= _borrowCap ? 0 : _borrowCap - storedBorrows;
        uint256 liquidity = availableLiquidity();

        amount = availableByCollateral;
        if (availableByCap < amount) {
            amount = availableByCap;
        }
        if (liquidity < amount) {
            amount = liquidity;
        }

        uint256 perPersonCap = _riskParameters().maxDebtPerPerson;
        if (perPersonCap != 0) {
            uint256 availableByPersonCap = perPersonCap > debt ? perPersonCap - debt : 0;
            if (availableByPersonCap < amount) {
                amount = availableByPersonCap;
            }
        }
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function healthFactorOf(bytes32 personId) public view returns (uint256 healthFactor) {
        uint256 debt = currentDebtOf(personId);
        return _healthFactor(personId, debt);
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function accrueInterest() external {
        _accrueInterest();
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        _requireAmount(assets);
        _requireReceiver(receiver);
        _accrueInterest();

        uint256 managedAssets = totalManagedAssets();
        shares = _convertToShares(assets, managedAssets, Math.Rounding.Floor);
        if (shares == 0) {
            revert ZeroShares();
        }

        _pullUsdc(msg.sender, assets);
        _mint(receiver, shares);
        _checkpointAccrualConfiguration(true);

        emit USDCDeposited(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function withdraw(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        _requireAmount(assets);
        _requireReceiver(receiver);
        _accrueInterest();

        uint256 liquidity = availableLiquidity();
        if (liquidity < assets) {
            revert InsufficientLiquidity(liquidity, assets);
        }

        shares = _convertToShares(assets, totalManagedAssets(), Math.Rounding.Ceil);
        if (shares == 0) {
            revert ZeroShares();
        }
        uint256 senderShares = balanceOf(msg.sender);
        if (senderShares < shares) {
            revert InsufficientShares(msg.sender, senderShares, shares);
        }

        _burn(msg.sender, shares);
        _usdc.safeTransfer(receiver, assets);
        _checkpointAccrualConfiguration(true);

        emit USDCWithdrawn(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function borrow(uint256 amount) external nonReentrant {
        _requireAmount(amount);
        _accrueInterest();

        bytes32 personId = _requireActivePerson(msg.sender);
        if (!ICitizenEligibilityPolicy(_kernel.getModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY))
                .isCitizenInGoodStanding(msg.sender)) {
            revert BorrowerNotEligible(personId);
        }
        StakeTypes.StakeRecord memory stakeRecord = _stakeRegistry.getStakeRecord(personId);

        // Resolve the governed risk params once for this call (LTV + per-person cap read the same struct).
        ILendingRiskParameterPolicy.RiskParameters memory riskParams = _riskParameters();
        uint256 scaledDebtIncrease = Math.mulDiv(amount, RAY, _borrowIndex, Math.Rounding.Ceil);
        uint256 newScaledDebt = _accountScaledDebt[personId] + scaledDebtIncrease;
        uint256 newDebt = _debtAtIndex(newScaledDebt, _borrowIndex);
        uint256 maxDebt = _maxDebtForRecord(personId, stakeRecord, _priceOracle(), riskParams.maxLtvBps);
        if (newDebt > maxDebt) {
            revert BorrowWouldBreachLtv(personId, newDebt, maxDebt);
        }

        // Per-person concentration cap (0 = unlimited): bounds a single borrower's debt regardless of stake size,
        // so no one position can grow past what liquidators can absorb (the Aave/CRV concentration lesson).
        uint256 perPersonCap = riskParams.maxDebtPerPerson;
        if (perPersonCap != 0 && newDebt > perPersonCap) {
            revert BorrowExceedsPerPersonCap(personId, newDebt, perPersonCap);
        }

        uint256 newTotalScaledDebt = _totalScaledDebt + scaledDebtIncrease;
        uint256 newTotalBorrows = _debtAtIndex(newTotalScaledDebt, _borrowIndex);
        if (newTotalBorrows > _borrowCap) {
            revert BorrowCapExceeded(newTotalBorrows, _borrowCap);
        }

        uint256 liquidity = availableLiquidity();
        if (liquidity < amount) {
            revert InsufficientLiquidity(liquidity, amount);
        }

        _setScaledDebt(personId, newScaledDebt);

        uint256 lienedStake = _syncLienTo(personId, _surplusStakeForRecord(personId, stakeRecord));
        _usdc.safeTransfer(msg.sender, amount);
        _checkpointAccrualConfiguration(true);

        emit USDCBorrowed(msg.sender, personId, amount, newDebt, lienedStake, uint64(block.timestamp));
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function repay(uint256 amount) external nonReentrant returns (uint256 repaidAmount) {
        bytes32 personId = _requireActivePerson(msg.sender);
        return _repay(msg.sender, personId, amount);
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function repayFor(bytes32 personId, uint256 amount) external nonReentrant returns (uint256 repaidAmount) {
        if (personId == bytes32(0) || !_identityRegistry.identityExists(personId)) {
            revert InvalidBorrowerPersonId(personId);
        }
        return _repay(msg.sender, personId, amount);
    }

    function _repay(address payer, bytes32 personId, uint256 amount) private returns (uint256 repaidAmount) {
        _requireAmount(amount);
        _accrueInterest();

        uint256 debt = _storedDebtOf(personId);
        if (debt == 0) {
            revert NoDebt(personId);
        }

        RepaymentQuote memory quote = _repaymentQuote(personId, amount, debt);
        repaidAmount = quote.amount;
        _pullUsdc(payer, repaidAmount);

        _setScaledDebt(personId, quote.scaledDebt);

        uint256 releasedLien = 0;
        if (quote.remainingDebt == 0) {
            releasedLien = _stakeLienRegistry.lienedStakeOf(personId);
            if (releasedLien != 0) {
                _stakeLienRegistry.decreaseLien(personId, releasedLien);
            }
        }
        _checkpointAccrualConfiguration(true);

        emit USDCRepaid(payer, personId, repaidAmount, quote.remainingDebt, releasedLien, uint64(block.timestamp));
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function liquidate(bytes32 borrowerPersonId, uint256 repayAmount)
        external
        nonReentrant
        returns (uint256 repaidAmount, uint256 seizedStake)
    {
        _requireAmount(repayAmount);
        _accrueInterest();

        bytes32 liquidatorPersonId = _requireActivePerson(msg.sender);
        if (
            borrowerPersonId == bytes32(0) || borrowerPersonId == liquidatorPersonId
                || !_identityRegistry.identityExists(borrowerPersonId)
        ) {
            revert InvalidLiquidationTarget(borrowerPersonId, liquidatorPersonId);
        }

        uint256 debt = _storedDebtOf(borrowerPersonId);
        if (debt == 0) {
            revert NoDebt(borrowerPersonId);
        }

        // Resolve the governed risk params and oracle once (health threshold, bonus, and seizure quote share them).
        ILendingRiskParameterPolicy.RiskParameters memory riskParams = _riskParameters();
        ILLMPriceOraclePolicy oracle = _priceOracle();

        uint256 healthFactor = _healthFactor(borrowerPersonId, debt, oracle, riskParams.liquidationThresholdBps);
        if (healthFactor >= HEALTH_FACTOR_SCALE) {
            revert LiquidationNotAllowed(borrowerPersonId, healthFactor);
        }

        RepaymentQuote memory quote = _repaymentQuote(borrowerPersonId, repayAmount, debt);
        repaidAmount = quote.amount;
        uint256 repaymentWithBonus =
            Math.mulDiv(repaidAmount, BPS + riskParams.liquidationBonusBps, BPS, Math.Rounding.Ceil);
        seizedStake = oracle.quoteAssetToLlm(repaymentWithBonus);

        StakeTypes.StakeRecord memory stakeRecord = _stakeRegistry.getStakeRecord(borrowerPersonId);
        uint256 seizableStake = _surplusStakeForRecord(borrowerPersonId, stakeRecord);
        if (seizedStake > seizableStake) {
            revert InsufficientLiquidationCollateral(borrowerPersonId, seizableStake, seizedStake);
        }

        _pullUsdc(msg.sender, repaidAmount);

        _setScaledDebt(borrowerPersonId, quote.scaledDebt);

        uint256 targetLien = quote.remainingDebt == 0 ? 0 : seizableStake - seizedStake;
        _syncLienTo(borrowerPersonId, targetLien);
        _stakeRegistry.transferActiveStake(borrowerPersonId, liquidatorPersonId, seizedStake);
        _checkpointAccrualConfiguration(true);

        emit StakeBackedPositionLiquidated(
            msg.sender,
            borrowerPersonId,
            liquidatorPersonId,
            repaidAmount,
            seizedStake,
            quote.remainingDebt,
            uint64(block.timestamp)
        );
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function absorbBadDebt(bytes32 borrowerPersonId)
        external
        nonReentrant
        returns (uint256 writtenOffDebt, uint256 coveredByReserves, uint256 supplierShortfall)
    {
        _accrueInterest();

        uint256 debt = _storedDebtOf(borrowerPersonId);
        if (debt == 0) {
            revert NoDebt(borrowerPersonId);
        }

        // Bad debt exists once no liquidator can make the smallest scaled-debt reduction. This accepts nonzero
        // collateral dust that cannot satisfy the exact rounded-up seizure required by `liquidate`, including the
        // case where one asset unit is too small to change a heavily accrued scaled balance.
        StakeTypes.StakeRecord memory stakeRecord = _stakeRegistry.getStakeRecord(borrowerPersonId);
        uint256 seizableStake = _surplusStakeForRecord(borrowerPersonId, stakeRecord);
        ILendingRiskParameterPolicy.RiskParameters memory riskParams = _riskParameters();
        ILLMPriceOraclePolicy oracle = _priceOracle();
        uint256 minimumEffectiveRepayment = _minimumEffectiveRepayment(borrowerPersonId, debt);
        uint256 minimumRepaymentWithBonus =
            Math.mulDiv(minimumEffectiveRepayment, BPS + riskParams.liquidationBonusBps, BPS, Math.Rounding.Ceil);
        uint256 minimumSeizableStake = oracle.quoteAssetToLlm(minimumRepaymentWithBonus);
        if (seizableStake >= minimumSeizableStake) {
            revert PositionNotBadDebt(borrowerPersonId, seizableStake);
        }

        uint256 totalBorrowsBefore = _storedTotalBorrows();
        _setScaledDebt(borrowerPersonId, 0);
        writtenOffDebt = totalBorrowsBefore - _storedTotalBorrows();
        // Protocol reserves are first-loss capital and absorb the write-off before suppliers. Any remainder lowers
        // the LP share value; governance restores it by a referendum-approved treasury disbursement to this pool
        // (a plain USDC transfer in raises cash and share value), keeping bad debt off the supplier base.
        coveredByReserves = writtenOffDebt <= _totalReserves ? writtenOffDebt : _totalReserves;
        supplierShortfall = writtenOffDebt - coveredByReserves;

        _totalReserves -= coveredByReserves;

        uint256 residualLien = _stakeLienRegistry.lienedStakeOf(borrowerPersonId);
        if (residualLien != 0) {
            _stakeLienRegistry.decreaseLien(borrowerPersonId, residualLien);
        }
        _checkpointAccrualConfiguration(true);

        emit BadDebtAbsorbed(
            msg.sender, borrowerPersonId, writtenOffDebt, coveredByReserves, supplierShortfall, uint64(block.timestamp)
        );
    }

    function _accrueInterest() private {
        uint64 currentTimestamp = uint64(block.timestamp);
        if (!_accrualConfigurationInitialized) {
            _lastAccrualTimestamp = currentTimestamp;
            _checkpointAccrualConfiguration(true);
            return;
        }

        uint256 elapsed = currentTimestamp - _lastAccrualTimestamp;
        if (elapsed == 0) {
            _checkpointAccrualConfiguration(false);
            return;
        }
        _lastAccrualTimestamp = currentTimestamp;
        if (_totalScaledDebt == 0) {
            _checkpointAccrualConfiguration(false);
            return;
        }

        uint256 totalBorrowsBefore = _storedTotalBorrows();
        _borrowIndex = _borrowIndexAt(currentTimestamp);
        uint256 totalBorrowsAfter = _storedTotalBorrows();
        uint256 interestAccrued = totalBorrowsAfter - totalBorrowsBefore;
        uint256 protocolReservesAccrued = _accrueProtocolReserves(interestAccrued);
        _totalReserves += protocolReservesAccrued;

        emit InterestAccrued(
            interestAccrued, protocolReservesAccrued, totalBorrowsAfter, _totalReserves, _borrowIndex, currentTimestamp
        );
        _checkpointAccrualConfiguration(false);
    }

    function _previewBorrowIndex() private view returns (uint256 indexRay) {
        if (!_accrualConfigurationInitialized || _totalScaledDebt == 0 || block.timestamp == _lastAccrualTimestamp) {
            return _borrowIndex;
        }

        return _borrowIndexAt(uint64(block.timestamp));
    }

    function _borrowIndexAt(uint64 timestamp) private view returns (uint256 indexRay) {
        uint256 elapsed = timestamp - _rateCheckpointTimestamp;
        uint256 growthFactorRay = _rayPow(RAY + _effectiveBorrowRateRay, elapsed);
        return Math.mulDiv(_rateCheckpointIndex, growthFactorRay, RAY);
    }

    function _storedTotalBorrows() private view returns (uint256 amount) {
        return _debtAtIndex(_totalScaledDebt, _borrowIndex);
    }

    function _storedDebtOf(bytes32 personId) private view returns (uint256 amount) {
        return _debtAtIndex(_accountScaledDebt[personId], _borrowIndex);
    }

    function _debtAtIndex(uint256 scaledDebt, uint256 indexRay) private pure returns (uint256 amount) {
        if (scaledDebt == 0) {
            return 0;
        }

        return Math.mulDiv(scaledDebt, indexRay, RAY, Math.Rounding.Ceil);
    }

    function _setScaledDebt(bytes32 personId, uint256 newScaledDebt) private {
        uint256 oldScaledDebt = _accountScaledDebt[personId];
        if (newScaledDebt > oldScaledDebt) {
            _totalScaledDebt += newScaledDebt - oldScaledDebt;
        } else {
            _totalScaledDebt -= oldScaledDebt - newScaledDebt;
        }

        if (newScaledDebt == 0) {
            delete _accountScaledDebt[personId];
        } else {
            _accountScaledDebt[personId] = newScaledDebt;
        }
    }

    function _repaymentQuote(bytes32 personId, uint256 maximumAmount, uint256 currentDebt)
        private
        view
        returns (RepaymentQuote memory quote)
    {
        uint256 currentScaledDebt = _accountScaledDebt[personId];
        if (maximumAmount >= currentDebt) {
            quote.amount = currentDebt;
            return quote;
        }

        uint256 targetDebt = currentDebt - maximumAmount;
        quote.scaledDebt = Math.mulDiv(targetDebt, RAY, _borrowIndex, Math.Rounding.Ceil);
        quote.remainingDebt = _debtAtIndex(quote.scaledDebt, _borrowIndex);
        quote.amount = currentDebt - quote.remainingDebt;
        if (quote.scaledDebt >= currentScaledDebt || quote.amount == 0) {
            revert InvalidAmount(0);
        }
    }

    function _minimumEffectiveRepayment(bytes32 personId, uint256 currentDebt) private view returns (uint256 amount) {
        uint256 currentScaledDebt = _accountScaledDebt[personId];
        return currentDebt - _debtAtIndex(currentScaledDebt - 1, _borrowIndex);
    }

    function _accrueProtocolReserves(uint256 interestAccrued) private returns (uint256 amount) {
        amount = Math.mulDiv(interestAccrued, _effectiveReserveFactorBps, BPS);
        uint256 accumulatedRemainder =
            _reserveAccrualRemainder + mulmod(interestAccrued, _effectiveReserveFactorBps, BPS);
        amount += accumulatedRemainder / BPS;
        _reserveAccrualRemainder = accumulatedRemainder % BPS;
    }

    function _checkpointAccrualConfiguration(bool forceNewInterval) private {
        uint16 reserveFactorBps = _riskParameters().reserveFactorBps;
        uint256 utilizationRay = utilizationRate();
        IInterestRatePolicy interestPolicy = _interestRatePolicy();
        uint256 borrowRateRay = interestPolicy.borrowRatePerSecond(utilizationRay);
        uint256 supplyRateRay = interestPolicy.supplyRatePerSecond(utilizationRay, reserveFactorBps);
        if (
            !_accrualConfigurationInitialized || forceNewInterval || borrowRateRay != _effectiveBorrowRateRay
                || reserveFactorBps != _effectiveReserveFactorBps
        ) {
            _accrualConfigurationInitialized = true;
            _rateCheckpointTimestamp = uint64(block.timestamp);
            _rateCheckpointIndex = _borrowIndex;
            _effectiveBorrowRateRay = borrowRateRay;
            _effectiveReserveFactorBps = reserveFactorBps;
        }
        _effectiveSupplyRateRay = supplyRateRay;
    }

    function _rayPow(uint256 baseRay, uint256 exponent) private pure returns (uint256 resultRay) {
        resultRay = RAY;
        while (exponent != 0) {
            if (exponent & 1 != 0) {
                resultRay = Math.mulDiv(resultRay, baseRay, RAY);
            }
            exponent >>= 1;
            if (exponent != 0) {
                baseRay = Math.mulDiv(baseRay, baseRay, RAY);
            }
        }
    }

    function _maxDebtForPerson(bytes32 personId) private view returns (uint256 amount) {
        return _maxDebtForRecord(
            personId, _stakeRegistry.getStakeRecord(personId), _priceOracle(), _riskParameters().maxLtvBps
        );
    }

    /// @dev Takes the already-resolved oracle and max LTV so mutating callers resolve the governed modules once per
    ///      transaction instead of re-resolving per read.
    function _maxDebtForRecord(
        bytes32 personId,
        StakeTypes.StakeRecord memory stakeRecord,
        ILLMPriceOraclePolicy oracle,
        uint16 maxLtvBps
    ) private view returns (uint256 amount) {
        return Math.mulDiv(oracle.quoteLlmToAsset(_surplusStakeForRecord(personId, stakeRecord)), maxLtvBps, BPS);
    }

    function _healthFactor(bytes32 personId, uint256 debt) private view returns (uint256 healthFactor) {
        return _healthFactor(personId, debt, _priceOracle(), _riskParameters().liquidationThresholdBps);
    }

    /// @dev Takes the already-resolved oracle and threshold so mutating callers resolve the governed modules once.
    function _healthFactor(bytes32 personId, uint256 debt, ILLMPriceOraclePolicy oracle, uint16 liquidationThresholdBps)
        private
        view
        returns (uint256 healthFactor)
    {
        if (debt == 0) {
            return type(uint256).max;
        }

        StakeTypes.StakeRecord memory stakeRecord = _stakeRegistry.getStakeRecord(personId);
        uint256 liquidationValue = Math.mulDiv(
            oracle.quoteLlmToAsset(_surplusStakeForRecord(personId, stakeRecord)), liquidationThresholdBps, BPS
        );

        return Math.mulDiv(liquidationValue, HEALTH_FACTOR_SCALE, debt);
    }

    /// @dev Resolves the governed risk parameters live from the kernel so a module-governance repoint can retune
    ///      LTV, liquidation threshold/bonus, and reserve factor without redeploying this pool.
    function _riskParameters() private view returns (ILendingRiskParameterPolicy.RiskParameters memory parameters) {
        return
            ILendingRiskParameterPolicy(_kernel.getModule(KernelModuleIds.LENDING_RISK_PARAMETER_POLICY))
                .riskParameters();
    }

    function _interestRatePolicy() private view returns (IInterestRatePolicy policy) {
        return IInterestRatePolicy(_kernel.getModule(KernelModuleIds.USDC_INTEREST_RATE_POLICY));
    }

    /// @dev Resolves the LLM/USDC price oracle live from the kernel so governance can swap the launch manual oracle
    ///      for a Uniswap V4 TWAP oracle by repointing the module, without redeploying this pool. Re-checks on every
    ///      resolution that the oracle prices this pool's own USDC, so a wrong-asset/decimals oracle (which would
    ///      mis-scale collateral) can never drive borrow limits or health.
    function _priceOracle() private view returns (ILLMPriceOraclePolicy oracle) {
        oracle = ILLMPriceOraclePolicy(_kernel.getModule(KernelModuleIds.LLM_USDC_PRICE_ORACLE_POLICY));
        if (oracle.asset() != address(_usdc)) {
            revert InvalidToken(address(oracle));
        }
    }

    function _surplusStakeForRecord(bytes32 personId, StakeTypes.StakeRecord memory stakeRecord)
        private
        view
        returns (uint256 amount)
    {
        uint256 retainedStake = _retainedStakeFloor(personId, stakeRecord.protectedStakeFloor);
        if (stakeRecord.activeStake <= retainedStake) {
            return 0;
        }

        return stakeRecord.activeStake - retainedStake;
    }

    /// @dev The retained floor is the greater of the person's protected floor and the citizenship floor snapshotted
    ///      when their current lien began. With no lien, the lien registry returns the current policy minimum.
    function _retainedStakeFloor(bytes32 personId, uint256 protectedStakeFloor) private view returns (uint256 amount) {
        uint256 citizenshipFloor = _stakeLienRegistry.retainedStakeFloorOf(personId);
        return protectedStakeFloor > citizenshipFloor ? protectedStakeFloor : citizenshipFloor;
    }

    function _syncLienTo(bytes32 personId, uint256 targetLien) private returns (uint256 newLien) {
        uint256 currentLien = _stakeLienRegistry.lienedStakeOf(personId);
        if (targetLien > currentLien) {
            _stakeLienRegistry.increaseLien(personId, targetLien - currentLien);
        } else if (currentLien > targetLien) {
            _stakeLienRegistry.decreaseLien(personId, currentLien - targetLien);
        }

        return targetLien;
    }

    function _convertToShares(uint256 assets, uint256 managedAssets, Math.Rounding rounding)
        private
        view
        returns (uint256 shares)
    {
        return Math.mulDiv(assets, totalSupply() + VIRTUAL_SHARES, managedAssets + VIRTUAL_ASSETS, rounding);
    }

    function _pullUsdc(address from, uint256 amount) private {
        uint256 balanceBefore = _usdc.balanceOf(address(this));
        _usdc.safeTransferFrom(from, address(this), amount);
        uint256 actualAmount = _usdc.balanceOf(address(this)) - balanceBefore;
        if (actualAmount != amount) {
            revert UnexpectedAssetAmount(amount, actualAmount);
        }
    }

    function _requireActivePerson(address wallet) private view returns (bytes32 personId) {
        personId = _identityRegistry.resolveWalletToPersonId(wallet);
        IdentityTypes.WalletLink memory walletLink = _identityRegistry.getWalletLink(wallet);
        if (
            personId == bytes32(0) || walletLink.personId != personId
                || walletLink.status != IdentityTypes.WalletLinkStatus.Active
        ) {
            revert WalletNotActive(wallet);
        }
    }

    function _requireContract(address contractAddress) private view {
        if (contractAddress == address(0) || contractAddress.code.length == 0) {
            revert InvalidRegistry(contractAddress);
        }
    }

    function _requireAmount(uint256 amount) private pure {
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
    }

    function _requireReceiver(address receiver) private pure {
        if (receiver == address(0)) {
            revert InvalidReceiver(receiver);
        }
    }
}
