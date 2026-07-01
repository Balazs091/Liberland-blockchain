// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IInterestRatePolicy} from "../interfaces/IInterestRatePolicy.sol";

/// @title KinkedInterestRatePolicy
/// @notice Utilization-based interest policy with a steep slope after the target utilization.
contract KinkedInterestRatePolicy is IInterestRatePolicy {
    uint256 private constant RAY = 1e27;
    uint256 private constant BPS = 10_000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    error InvalidAnnualRateBps(uint256 annualRateBps);
    error InvalidKink(uint256 kinkRay);
    error InvalidReserveFactor(uint16 reserveFactorBps);
    error InvalidUtilization(uint256 utilizationRay);

    uint256 private immutable _baseRatePerSecondRay;
    uint256 private immutable _slope1PerSecondRay;
    uint256 private immutable _slope2PerSecondRay;
    uint256 private immutable _kinkRay;

    /// @param baseAnnualRateBps Base borrow APR in basis points.
    /// @param slope1AnnualRateBps Added borrow APR at the kink, in basis points.
    /// @param slope2AnnualRateBps Added borrow APR from kink to full utilization, in basis points.
    /// @param kinkRay_ Target utilization scaled by 1e27.
    constructor(uint256 baseAnnualRateBps, uint256 slope1AnnualRateBps, uint256 slope2AnnualRateBps, uint256 kinkRay_) {
        if (baseAnnualRateBps > BPS || slope1AnnualRateBps > BPS * 5 || slope2AnnualRateBps > BPS * 20) {
            revert InvalidAnnualRateBps(baseAnnualRateBps);
        }
        if (kinkRay_ == 0 || kinkRay_ >= RAY) {
            revert InvalidKink(kinkRay_);
        }

        _baseRatePerSecondRay = _annualBpsToPerSecondRay(baseAnnualRateBps);
        _slope1PerSecondRay = _annualBpsToPerSecondRay(slope1AnnualRateBps);
        _slope2PerSecondRay = _annualBpsToPerSecondRay(slope2AnnualRateBps);
        _kinkRay = kinkRay_;
    }

    /// @inheritdoc IInterestRatePolicy
    function ray() external pure returns (uint256 ray_) {
        return RAY;
    }

    /// @notice Returns the configured target utilization.
    /// @return utilizationRay The kink utilization scaled by 1e27.
    function kinkRay() external view returns (uint256 utilizationRay) {
        return _kinkRay;
    }

    /// @inheritdoc IInterestRatePolicy
    function borrowRatePerSecond(uint256 utilizationRay) public view returns (uint256 rateRay) {
        if (utilizationRay > RAY) {
            revert InvalidUtilization(utilizationRay);
        }

        if (utilizationRay <= _kinkRay) {
            return _baseRatePerSecondRay + Math.mulDiv(_slope1PerSecondRay, utilizationRay, _kinkRay);
        }

        uint256 excessUtilization = utilizationRay - _kinkRay;
        uint256 excessRange = RAY - _kinkRay;

        return
            _baseRatePerSecondRay + _slope1PerSecondRay
                + Math.mulDiv(_slope2PerSecondRay, excessUtilization, excessRange);
    }

    /// @inheritdoc IInterestRatePolicy
    function supplyRatePerSecond(uint256 utilizationRay, uint16 reserveFactorBps)
        external
        view
        returns (uint256 rateRay)
    {
        if (reserveFactorBps > BPS) {
            revert InvalidReserveFactor(reserveFactorBps);
        }

        uint256 borrowRateRay = borrowRatePerSecond(utilizationRay);
        uint256 lenderShareBps = BPS - reserveFactorBps;
        return Math.mulDiv(Math.mulDiv(borrowRateRay, utilizationRay, RAY), lenderShareBps, BPS);
    }

    function _annualBpsToPerSecondRay(uint256 annualRateBps) private pure returns (uint256 rateRay) {
        return Math.mulDiv(annualRateBps, RAY, BPS * SECONDS_PER_YEAR);
    }
}
