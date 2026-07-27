// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ILendingRiskParameterPolicy} from "../interfaces/ILendingRiskParameterPolicy.sol";

/// @title LendingRiskParameterPolicy
/// @notice Immutable, invariant-checked risk parameters for the stake-backed lending pool.
/// @dev Parameters are fixed at deployment; governance retunes them by deploying a new policy and repointing the
///      `policy.lending-risk-parameter` module through a module-governance referendum (constitutional double
///      threshold, per the module-governance rules). Because the pool reads these live, a repoint takes effect on
///      the next interaction — including making existing positions liquidatable if the threshold is lowered — so
///      changes must go through the timelock's review window. The constructor enforces hard bounds so that no
///      configured (or repointed) policy can set economically nonsensical values.
contract LendingRiskParameterPolicy is ILendingRiskParameterPolicy {
    uint256 internal constant BPS = 10_000;

    /// @dev Ceilings leave headroom below full utilization/collateral so liquidation seizure plus bonus stays
    ///      solvent and reserves can never starve suppliers.
    uint16 internal constant MAX_LIQUIDATION_THRESHOLD_BPS = 9_000;
    uint16 internal constant MAX_LIQUIDATION_BONUS_BPS = 2_000;
    uint16 internal constant MAX_RESERVE_FACTOR_BPS = 5_000;

    error InvalidMaxLtv(uint16 maxLtvBps);
    error InvalidLiquidationThreshold(uint16 maxLtvBps, uint16 liquidationThresholdBps);
    error InvalidLiquidationBonus(uint16 liquidationBonusBps);
    error InvalidReserveFactor(uint16 reserveFactorBps);
    error UnsafeLiquidationParameters(uint16 liquidationThresholdBps, uint16 liquidationBonusBps);

    RiskParameters private _parameters;

    /// @param maxLtvBps_ Maximum borrow-time loan-to-value, in basis points.
    /// @param liquidationThresholdBps_ Liquidation threshold, in basis points; must exceed max LTV.
    /// @param liquidationBonusBps_ Liquidation bonus, in basis points.
    /// @param reserveFactorBps_ Protocol reserve factor, in basis points.
    /// @param maxDebtPerPerson_ Per-person borrow ceiling in the borrow asset's smallest units; 0 means unlimited.
    constructor(
        uint16 maxLtvBps_,
        uint16 liquidationThresholdBps_,
        uint16 liquidationBonusBps_,
        uint16 reserveFactorBps_,
        uint256 maxDebtPerPerson_
    ) {
        if (maxLtvBps_ == 0) {
            revert InvalidMaxLtv(maxLtvBps_);
        }
        // The liquidation threshold must sit strictly above max LTV (so a fresh max-LTV borrow is not already
        // liquidatable) and below the ceiling (so seized collateral plus bonus stays within available surplus).
        if (liquidationThresholdBps_ <= maxLtvBps_ || liquidationThresholdBps_ > MAX_LIQUIDATION_THRESHOLD_BPS) {
            revert InvalidLiquidationThreshold(maxLtvBps_, liquidationThresholdBps_);
        }
        if (liquidationBonusBps_ > MAX_LIQUIDATION_BONUS_BPS) {
            revert InvalidLiquidationBonus(liquidationBonusBps_);
        }
        if (uint256(liquidationThresholdBps_) * (BPS + uint256(liquidationBonusBps_)) > BPS * BPS) {
            revert UnsafeLiquidationParameters(liquidationThresholdBps_, liquidationBonusBps_);
        }
        if (reserveFactorBps_ > MAX_RESERVE_FACTOR_BPS) {
            revert InvalidReserveFactor(reserveFactorBps_);
        }

        _parameters = RiskParameters({
            maxLtvBps: maxLtvBps_,
            liquidationThresholdBps: liquidationThresholdBps_,
            liquidationBonusBps: liquidationBonusBps_,
            reserveFactorBps: reserveFactorBps_,
            maxDebtPerPerson: maxDebtPerPerson_
        });
    }

    /// @inheritdoc ILendingRiskParameterPolicy
    function riskParameters() external view returns (RiskParameters memory parameters) {
        return _parameters;
    }

    /// @inheritdoc ILendingRiskParameterPolicy
    function maxLtvBps() external view returns (uint16 bps) {
        return _parameters.maxLtvBps;
    }

    /// @inheritdoc ILendingRiskParameterPolicy
    function liquidationThresholdBps() external view returns (uint16 bps) {
        return _parameters.liquidationThresholdBps;
    }

    /// @inheritdoc ILendingRiskParameterPolicy
    function liquidationBonusBps() external view returns (uint16 bps) {
        return _parameters.liquidationBonusBps;
    }

    /// @inheritdoc ILendingRiskParameterPolicy
    function reserveFactorBps() external view returns (uint16 bps) {
        return _parameters.reserveFactorBps;
    }

    /// @inheritdoc ILendingRiskParameterPolicy
    function maxDebtPerPerson() external view returns (uint256 amount) {
        return _parameters.maxDebtPerPerson;
    }
}
