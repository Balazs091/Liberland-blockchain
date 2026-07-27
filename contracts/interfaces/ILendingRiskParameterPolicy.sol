// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title ILendingRiskParameterPolicy
/// @notice Replaceable risk-parameter source for the stake-backed lending pool. Splitting these out of the pool lets
///         governance retune them on a live pool by repointing the policy module, without redeploying the pool and
///         losing its deposits, debt, and interest state.
interface ILendingRiskParameterPolicy {
    /// @param maxLtvBps Maximum loan-to-value at borrow time, in basis points.
    /// @param liquidationThresholdBps Collateral value fraction that must cover debt before liquidation, in bps.
    /// @param liquidationBonusBps Bonus paid to a liquidator on the repaid amount, in bps.
    /// @param reserveFactorBps Share of accrued borrow interest routed to protocol reserves, in bps.
    /// @param maxDebtPerPerson Per-person borrow ceiling in the borrow asset's smallest units; 0 means unlimited.
    struct RiskParameters {
        uint16 maxLtvBps;
        uint16 liquidationThresholdBps;
        uint16 liquidationBonusBps;
        uint16 reserveFactorBps;
        uint256 maxDebtPerPerson;
    }

    /// @notice Returns all lending risk parameters in one read.
    /// @return parameters The current risk parameters.
    function riskParameters() external view returns (RiskParameters memory parameters);

    /// @notice Returns the maximum borrow-time loan-to-value, in basis points.
    /// @return bps The max LTV.
    function maxLtvBps() external view returns (uint16 bps);

    /// @notice Returns the liquidation threshold, in basis points.
    /// @return bps The liquidation threshold.
    function liquidationThresholdBps() external view returns (uint16 bps);

    /// @notice Returns the liquidation bonus, in basis points.
    /// @return bps The liquidation bonus.
    function liquidationBonusBps() external view returns (uint16 bps);

    /// @notice Returns the protocol reserve factor, in basis points.
    /// @return bps The reserve factor.
    function reserveFactorBps() external view returns (uint16 bps);

    /// @notice Returns the per-person borrow ceiling in the borrow asset's smallest units (0 = unlimited).
    /// @return amount The per-person debt cap.
    function maxDebtPerPerson() external view returns (uint256 amount);
}
