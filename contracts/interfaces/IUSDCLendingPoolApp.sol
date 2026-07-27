// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {LendingTypes} from "../types/LendingTypes.sol";

/// @title IUSDCLendingPoolApp
/// @notice USDC lending app backed by active LLM stake above the retained citizenship floor.
interface IUSDCLendingPoolApp {
    error BorrowCapExceeded(uint256 requestedTotalBorrows, uint256 borrowCap);
    error BorrowExceedsPerPersonCap(bytes32 personId, uint256 requestedDebt, uint256 perPersonCap);
    error BorrowerNotEligible(bytes32 personId);
    error BorrowWouldBreachLtv(bytes32 personId, uint256 requestedDebt, uint256 maxDebt);
    error InsufficientLiquidity(uint256 availableLiquidity, uint256 requestedAmount);
    error InsufficientLiquidationCollateral(bytes32 personId, uint256 seizableStake, uint256 requestedStake);
    error InsufficientShares(address owner, uint256 availableShares, uint256 requiredShares);
    error InvalidAmount(uint256 amount);
    error InvalidBorrowCap(uint256 borrowCap);
    error InvalidBorrowerPersonId(bytes32 personId);
    error InvalidLiquidationTarget(bytes32 borrowerPersonId, bytes32 liquidatorPersonId);
    error InvalidReceiver(address receiver);
    error InvalidRegistry(address registryAddress);
    error InvalidToken(address tokenAddress);
    error LiquidationNotAllowed(bytes32 personId, uint256 healthFactor);
    error NoDebt(bytes32 personId);
    error PositionNotBadDebt(bytes32 personId, uint256 seizableStake);
    error UnexpectedAssetAmount(uint256 expectedAmount, uint256 actualAmount);
    error WalletNotActive(address wallet);
    error ZeroShares();

    event USDCDeposited(address indexed supplier, address indexed receiver, uint256 assets, uint256 shares);

    event USDCWithdrawn(address indexed owner, address indexed receiver, uint256 assets, uint256 shares);

    event USDCBorrowed(
        address indexed borrower,
        bytes32 indexed personId,
        uint256 amount,
        uint256 newDebt,
        uint256 lienedStake,
        uint64 borrowedAt
    );

    event USDCRepaid(
        address indexed payer,
        bytes32 indexed personId,
        uint256 amount,
        uint256 remainingDebt,
        uint256 releasedLien,
        uint64 repaidAt
    );

    event StakeBackedPositionLiquidated(
        address indexed liquidator,
        bytes32 indexed borrowerPersonId,
        bytes32 indexed liquidatorPersonId,
        uint256 repaidAmount,
        uint256 seizedStake,
        uint256 remainingDebt,
        uint64 liquidatedAt
    );

    event InterestAccrued(
        uint256 interestAccrued,
        uint256 protocolReservesAccrued,
        uint256 totalBorrows,
        uint256 totalReserves,
        uint256 borrowIndex,
        uint64 accruedAt
    );

    event BadDebtAbsorbed(
        address indexed caller,
        bytes32 indexed borrowerPersonId,
        uint256 writtenOffDebt,
        uint256 coveredByReserves,
        uint256 supplierShortfall,
        uint64 absorbedAt
    );

    /// @notice Returns the USDC token accepted by the pool.
    /// @return tokenAddress The USDC token address.
    function usdc() external view returns (address tokenAddress);

    /// @notice Returns the current managed assets backing LP shares.
    /// @return amount Cash plus borrows minus protocol reserves.
    function totalManagedAssets() external view returns (uint256 amount);

    /// @notice Returns USDC currently available for new borrows or LP withdrawals.
    /// @return amount Available USDC excluding protocol reserves.
    function availableLiquidity() external view returns (uint256 amount);

    /// @notice Returns the current utilization scaled by 1e27.
    /// @return utilizationRay The utilization value.
    function utilizationRate() external view returns (uint256 utilizationRay);

    /// @notice Returns current borrow and supply rates.
    /// @return preview The current rate preview.
    function ratePreview() external view returns (LendingTypes.RatePreview memory preview);

    /// @notice Returns the current debt for a person identifier, including previewed interest.
    /// @param personId The canonical person identifier.
    /// @return amount The USDC debt amount.
    function currentDebtOf(bytes32 personId) external view returns (uint256 amount);

    /// @notice Returns the maximum additional USDC that a person identifier can borrow now.
    /// @param personId The canonical person identifier.
    /// @return amount The additional borrow amount available.
    function maxBorrowable(bytes32 personId) external view returns (uint256 amount);

    /// @notice Returns the liquidation health factor scaled by 1e18.
    /// @param personId The canonical person identifier.
    /// @return healthFactor The health factor, or max uint when no debt exists.
    function healthFactorOf(bytes32 personId) external view returns (uint256 healthFactor);

    /// @notice Accrues interest into the global index used by all scaled account debt.
    function accrueInterest() external;

    /// @notice Deposits USDC into the lending pool and mints LP shares.
    /// @param assets The amount of USDC to deposit.
    /// @param receiver The account receiving LP shares.
    /// @return shares The minted LP shares.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Burns LP shares and withdraws USDC from available liquidity.
    /// @param assets The USDC amount to withdraw.
    /// @param receiver The account receiving USDC.
    /// @return shares The burned LP shares.
    function withdraw(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Borrows USDC against the caller's active LLM stake above the retained floor.
    /// @param amount The USDC amount to borrow.
    function borrow(uint256 amount) external;

    /// @notice Repays the caller's USDC debt.
    /// @param amount The maximum USDC amount to repay.
    /// @return repaidAmount The actual amount repaid.
    function repay(uint256 amount) external returns (uint256 repaidAmount);

    /// @notice Repays debt for a person identifier, including when their former wallet is no longer active.
    /// @param personId The canonical borrower person identifier.
    /// @param amount The maximum USDC amount to repay.
    /// @return repaidAmount The actual amount repaid.
    function repayFor(bytes32 personId, uint256 amount) external returns (uint256 repaidAmount);

    /// @notice Repays unsafe debt and receives seized active stake as active stake for the liquidator's person ID.
    /// @param borrowerPersonId The borrower person identifier to liquidate.
    /// @param repayAmount The maximum USDC debt amount to repay.
    /// @return repaidAmount The actual USDC repaid.
    /// @return seizedStake The active LLM stake transferred to the liquidator.
    function liquidate(bytes32 borrowerPersonId, uint256 repayAmount)
        external
        returns (uint256 repaidAmount, uint256 seizedStake);

    /// @notice Writes off the unrecoverable debt of a position whose seizable collateral is fully exhausted.
    /// @dev Callable once liquidators have seized all surplus stake (only the untouchable citizenship floor remains).
    ///      Protocol reserves absorb the write-off first; any remainder lowers LP share value until governance
    ///      restores it with a treasury disbursement to this pool.
    /// @param borrowerPersonId The borrower person identifier to write off.
    /// @return writtenOffDebt The debt amount cleared.
    /// @return coveredByReserves The portion absorbed by protocol reserves.
    /// @return supplierShortfall The portion borne by suppliers until covered by the treasury.
    function absorbBadDebt(bytes32 borrowerPersonId)
        external
        returns (uint256 writtenOffDebt, uint256 coveredByReserves, uint256 supplierShortfall);
}
