// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IConstitutionKernel} from "../interfaces/IConstitutionKernel.sol";
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

    uint256 public constant RAY = 1e27;
    uint256 public constant HEALTH_FACTOR_SCALE = 1e18;
    uint256 public constant BPS = 10_000;
    // 5,000 whole LLM in the registry's 18-decimal stake units — matches MINIMUM_CITIZEN_STAKE so lending can never
    // pull a citizen below their retained citizenship floor.
    uint256 public constant MINIMUM_RETAINED_STAKE = 5_000 * 1e18;

    uint256 private constant VIRTUAL_ASSETS = 1_000_000;
    uint256 private constant VIRTUAL_SHARES = 1_000_000;

    IConstitutionKernel private immutable _kernel;
    IERC20 private immutable _usdc;
    IIdentityRegistry private immutable _identityRegistry;
    IStakeRegistry private immutable _stakeRegistry;
    IStakeLienRegistry private immutable _stakeLienRegistry;
    ILLMPriceOraclePolicy private immutable _priceOraclePolicy;
    IInterestRatePolicy private immutable _interestRatePolicy;
    uint8 private immutable _shareDecimals;
    uint256 private immutable _borrowCap;

    uint256 private _totalBorrows;
    uint256 private _totalReserves;
    uint256 private _borrowIndex;
    uint64 private _lastAccrualTimestamp;

    mapping(bytes32 personId => uint256 debtPrincipal) private _accountDebtPrincipal;
    mapping(bytes32 personId => uint256 accountBorrowIndex) private _accountBorrowIndexes;

    /// @param kernelAddress The canonical kernel registry address.
    /// @param usdcAddress The USDC token address.
    /// @param identityRegistryAddress The identity registry address.
    /// @param stakeRegistryAddress The stake registry address.
    /// @param stakeLienRegistryAddress The stake lien registry address.
    /// @param priceOraclePolicyAddress The LLM/USDC oracle policy address.
    /// @param interestRatePolicyAddress The utilization-rate policy address.
    /// @param borrowCap_ Maximum total USDC borrows for this v1 pool.
    constructor(
        address kernelAddress,
        address usdcAddress,
        address identityRegistryAddress,
        address stakeRegistryAddress,
        address stakeLienRegistryAddress,
        address priceOraclePolicyAddress,
        address interestRatePolicyAddress,
        uint256 borrowCap_
    ) ERC20("Liberland USDC Lending Share", "llUSDC") {
        _requireContract(kernelAddress);
        _requireContract(usdcAddress);
        _requireContract(identityRegistryAddress);
        _requireContract(stakeRegistryAddress);
        _requireContract(stakeLienRegistryAddress);
        _requireContract(priceOraclePolicyAddress);
        _requireContract(interestRatePolicyAddress);
        if (borrowCap_ == 0) {
            revert InvalidBorrowCap(borrowCap_);
        }

        ILLMPriceOraclePolicy oraclePolicy = ILLMPriceOraclePolicy(priceOraclePolicyAddress);
        if (oraclePolicy.asset() != usdcAddress) {
            revert InvalidToken(usdcAddress);
        }

        IStakeLienRegistry lienRegistry = IStakeLienRegistry(stakeLienRegistryAddress);
        if (lienRegistry.minimumRetainedStake() != MINIMUM_RETAINED_STAKE) {
            revert InvalidRegistry(stakeLienRegistryAddress);
        }

        _kernel = IConstitutionKernel(kernelAddress);
        _usdc = IERC20(usdcAddress);
        _identityRegistry = IIdentityRegistry(identityRegistryAddress);
        _stakeRegistry = IStakeRegistry(stakeRegistryAddress);
        _stakeLienRegistry = lienRegistry;
        _priceOraclePolicy = oraclePolicy;
        _interestRatePolicy = IInterestRatePolicy(interestRatePolicyAddress);
        _shareDecimals = IERC20Metadata(usdcAddress).decimals();
        _borrowCap = borrowCap_;
        _borrowIndex = RAY;
        _lastAccrualTimestamp = uint64(block.timestamp);
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
        return address(_priceOraclePolicy);
    }

    /// @notice Returns the configured interest-rate policy.
    /// @return policyAddress The interest-rate policy address.
    function interestRatePolicy() external view returns (address policyAddress) {
        return address(_interestRatePolicy);
    }

    /// @notice Returns the configured total borrow cap.
    /// @return amount The USDC borrow cap.
    function borrowCap() external view returns (uint256 amount) {
        return _borrowCap;
    }

    /// @notice Returns stored total borrows before preview interest.
    /// @return amount The stored total borrow amount.
    function totalBorrows() external view returns (uint256 amount) {
        return _totalBorrows;
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
        uint256 grossAssets = cash + _totalBorrows;
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
        uint256 managedAssets = totalManagedAssets();
        if (managedAssets == 0 || _totalBorrows == 0) {
            return 0;
        }
        if (_totalBorrows >= managedAssets) {
            return RAY;
        }

        return Math.mulDiv(_totalBorrows, RAY, managedAssets);
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function ratePreview() external view returns (LendingTypes.RatePreview memory preview) {
        preview.utilizationRay = utilizationRate();
        preview.borrowRatePerSecondRay = _interestRatePolicy.borrowRatePerSecond(preview.utilizationRay);
        preview.supplyRatePerSecondRay =
            _interestRatePolicy.supplyRatePerSecond(preview.utilizationRay, _riskParameters().reserveFactorBps);
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function currentDebtOf(bytes32 personId) public view returns (uint256 amount) {
        return _debtAtIndex(personId, _previewBorrowIndex());
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function maxBorrowable(bytes32 personId) external view returns (uint256 amount) {
        uint256 maxDebt = _maxDebtForPerson(personId);
        uint256 debt = currentDebtOf(personId);
        if (maxDebt <= debt) {
            return 0;
        }

        uint256 availableByCollateral = maxDebt - debt;
        uint256 availableByCap = _totalBorrows >= _borrowCap ? 0 : _borrowCap - _totalBorrows;
        uint256 liquidity = availableLiquidity();

        amount = availableByCollateral;
        if (availableByCap < amount) {
            amount = availableByCap;
        }
        if (liquidity < amount) {
            amount = liquidity;
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

        emit USDCWithdrawn(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function borrow(uint256 amount) external nonReentrant {
        _requireAmount(amount);
        _accrueInterest();

        bytes32 personId = _requireActivePerson(msg.sender);
        StakeTypes.StakeRecord memory stakeRecord = _stakeRegistry.getStakeRecord(personId);

        uint256 debt = _storedDebtOf(personId);
        uint256 newDebt = debt + amount;
        uint256 maxDebt = _maxDebtForRecord(stakeRecord);
        if (newDebt > maxDebt) {
            revert BorrowWouldBreachLtv(personId, newDebt, maxDebt);
        }

        uint256 newTotalBorrows = _totalBorrows + amount;
        if (newTotalBorrows > _borrowCap) {
            revert BorrowCapExceeded(newTotalBorrows, _borrowCap);
        }

        uint256 liquidity = availableLiquidity();
        if (liquidity < amount) {
            revert InsufficientLiquidity(liquidity, amount);
        }

        _totalBorrows = newTotalBorrows;
        _setDebt(personId, newDebt);

        uint256 lienedStake = _syncLienTo(personId, _surplusStakeForRecord(stakeRecord));
        _usdc.safeTransfer(msg.sender, amount);

        emit USDCBorrowed(msg.sender, personId, amount, newDebt, lienedStake, uint64(block.timestamp));
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function repay(uint256 amount) external nonReentrant returns (uint256 repaidAmount) {
        _requireAmount(amount);
        _accrueInterest();

        bytes32 personId = _requireActivePerson(msg.sender);
        uint256 debt = _storedDebtOf(personId);
        if (debt == 0) {
            revert NoDebt(personId);
        }

        repaidAmount = amount > debt ? debt : amount;
        _pullUsdc(msg.sender, repaidAmount);

        uint256 newDebt = debt - repaidAmount;
        _totalBorrows -= repaidAmount;
        _setDebt(personId, newDebt);

        uint256 releasedLien = 0;
        if (newDebt == 0) {
            releasedLien = _stakeLienRegistry.lienedStakeOf(personId);
            if (releasedLien != 0) {
                _stakeLienRegistry.decreaseLien(personId, releasedLien);
            }
        }

        emit USDCRepaid(msg.sender, personId, repaidAmount, newDebt, releasedLien, uint64(block.timestamp));
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

        uint256 healthFactor = _healthFactor(borrowerPersonId, debt);
        if (healthFactor >= HEALTH_FACTOR_SCALE) {
            revert LiquidationNotAllowed(borrowerPersonId, healthFactor);
        }

        repaidAmount = repayAmount > debt ? debt : repayAmount;
        uint256 repaymentWithBonus =
            Math.mulDiv(repaidAmount, BPS + _riskParameters().liquidationBonusBps, BPS, Math.Rounding.Ceil);
        seizedStake = _priceOraclePolicy.quoteAssetToLlm(repaymentWithBonus);

        StakeTypes.StakeRecord memory stakeRecord = _stakeRegistry.getStakeRecord(borrowerPersonId);
        uint256 seizableStake = _surplusStakeForRecord(stakeRecord);
        if (seizedStake > seizableStake) {
            revert InsufficientLiquidationCollateral(borrowerPersonId, seizableStake, seizedStake);
        }

        _pullUsdc(msg.sender, repaidAmount);

        uint256 newDebt = debt - repaidAmount;
        _totalBorrows -= repaidAmount;
        _setDebt(borrowerPersonId, newDebt);

        uint256 targetLien = newDebt == 0 ? 0 : seizableStake - seizedStake;
        _syncLienTo(borrowerPersonId, targetLien);
        _stakeRegistry.transferActiveStake(borrowerPersonId, liquidatorPersonId, seizedStake);

        emit StakeBackedPositionLiquidated(
            msg.sender,
            borrowerPersonId,
            liquidatorPersonId,
            repaidAmount,
            seizedStake,
            newDebt,
            uint64(block.timestamp)
        );
    }

    /// @inheritdoc IUSDCLendingPoolApp
    function claimProtocolReserves(uint256 amount) external nonReentrant {
        _requireAmount(amount);
        _accrueInterest();

        if (_totalReserves < amount) {
            revert InsufficientProtocolReserves(_totalReserves, amount);
        }

        _totalReserves -= amount;
        address treasury = _kernel.getModule(KernelModuleIds.TREASURY_VAULT);
        _usdc.safeTransfer(treasury, amount);

        emit ProtocolReservesClaimed(treasury, amount, uint64(block.timestamp));
    }

    function _accrueInterest() private {
        uint64 currentTimestamp = uint64(block.timestamp);
        uint256 elapsed = currentTimestamp - _lastAccrualTimestamp;
        if (elapsed == 0) {
            return;
        }

        _lastAccrualTimestamp = currentTimestamp;
        if (_totalBorrows == 0) {
            return;
        }

        uint256 borrowRateRay = _interestRatePolicy.borrowRatePerSecond(utilizationRate());
        uint256 interestFactorRay = borrowRateRay * elapsed;
        uint256 interestAccrued = Math.mulDiv(_totalBorrows, interestFactorRay, RAY);
        uint256 protocolReservesAccrued = Math.mulDiv(interestAccrued, _riskParameters().reserveFactorBps, BPS);

        _totalBorrows += interestAccrued;
        _totalReserves += protocolReservesAccrued;
        _borrowIndex += Math.mulDiv(_borrowIndex, interestFactorRay, RAY);

        emit InterestAccrued(
            interestAccrued, protocolReservesAccrued, _totalBorrows, _totalReserves, _borrowIndex, currentTimestamp
        );
    }

    function _previewBorrowIndex() private view returns (uint256 indexRay) {
        uint256 elapsed = block.timestamp - _lastAccrualTimestamp;
        if (elapsed == 0 || _totalBorrows == 0) {
            return _borrowIndex;
        }

        uint256 borrowRateRay = _interestRatePolicy.borrowRatePerSecond(utilizationRate());
        return _borrowIndex + Math.mulDiv(_borrowIndex, borrowRateRay * elapsed, RAY);
    }

    function _storedDebtOf(bytes32 personId) private view returns (uint256 amount) {
        return _debtAtIndex(personId, _borrowIndex);
    }

    function _debtAtIndex(bytes32 personId, uint256 indexRay) private view returns (uint256 amount) {
        uint256 principal = _accountDebtPrincipal[personId];
        if (principal == 0) {
            return 0;
        }

        return Math.mulDiv(principal, indexRay, _accountBorrowIndexes[personId]);
    }

    function _setDebt(bytes32 personId, uint256 newDebt) private {
        if (newDebt == 0) {
            delete _accountDebtPrincipal[personId];
            delete _accountBorrowIndexes[personId];
            return;
        }

        _accountDebtPrincipal[personId] = newDebt;
        _accountBorrowIndexes[personId] = _borrowIndex;
    }

    function _maxDebtForPerson(bytes32 personId) private view returns (uint256 amount) {
        return _maxDebtForRecord(_stakeRegistry.getStakeRecord(personId));
    }

    function _maxDebtForRecord(StakeTypes.StakeRecord memory stakeRecord) private view returns (uint256 amount) {
        return Math.mulDiv(
            _priceOraclePolicy.quoteLlmToAsset(_surplusStakeForRecord(stakeRecord)), _riskParameters().maxLtvBps, BPS
        );
    }

    function _healthFactor(bytes32 personId, uint256 debt) private view returns (uint256 healthFactor) {
        if (debt == 0) {
            return type(uint256).max;
        }

        StakeTypes.StakeRecord memory stakeRecord = _stakeRegistry.getStakeRecord(personId);
        uint256 liquidationValue = Math.mulDiv(
            _priceOraclePolicy.quoteLlmToAsset(_surplusStakeForRecord(stakeRecord)),
            _riskParameters().liquidationThresholdBps,
            BPS
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

    function _surplusStakeForRecord(StakeTypes.StakeRecord memory stakeRecord) private pure returns (uint256 amount) {
        uint256 retainedStake = _retainedStakeFloor(stakeRecord.protectedStakeFloor);
        if (stakeRecord.activeStake <= retainedStake) {
            return 0;
        }

        return stakeRecord.activeStake - retainedStake;
    }

    function _retainedStakeFloor(uint256 protectedStakeFloor) private pure returns (uint256 amount) {
        return protectedStakeFloor > MINIMUM_RETAINED_STAKE ? protectedStakeFloor : MINIMUM_RETAINED_STAKE;
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
