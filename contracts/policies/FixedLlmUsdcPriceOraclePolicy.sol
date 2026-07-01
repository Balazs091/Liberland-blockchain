// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILLMPriceOraclePolicy} from "../interfaces/ILLMPriceOraclePolicy.sol";

/// @title FixedLlmUsdcPriceOraclePolicy
/// @notice Conservative v1 oracle policy with a fixed USDC value per LLM stake unit.
contract FixedLlmUsdcPriceOraclePolicy is ILLMPriceOraclePolicy {
    error InvalidAsset(address assetAddress);
    error InvalidPrice(uint256 assetUnitsPerLlm);

    /// @dev One whole LLM expressed in the 18-decimal stake units the registry stores. `_assetUnitsPerLlm` prices
    ///      one *whole* LLM, so every conversion normalizes by this unit to keep collateral valuation coherent with
    ///      the wei-scaled stake registry.
    uint256 private constant LLM_UNIT = 1e18;

    address private immutable _asset;
    uint256 private immutable _assetUnitsPerLlm;

    /// @param assetAddress The USDC token address.
    /// @param assetUnitsPerLlm_ USDC smallest units per one LLM stake unit.
    constructor(address assetAddress, uint256 assetUnitsPerLlm_) {
        if (assetAddress == address(0) || assetAddress.code.length == 0) {
            revert InvalidAsset(assetAddress);
        }
        if (assetUnitsPerLlm_ == 0) {
            revert InvalidPrice(assetUnitsPerLlm_);
        }

        _asset = assetAddress;
        _assetUnitsPerLlm = assetUnitsPerLlm_;
    }

    /// @inheritdoc ILLMPriceOraclePolicy
    function asset() external view returns (address assetAddress) {
        return _asset;
    }

    /// @notice Returns the USDC smallest units assigned to one LLM stake unit.
    /// @return amount The fixed USDC quote.
    function assetUnitsPerLlm() external view returns (uint256 amount) {
        return _assetUnitsPerLlm;
    }

    /// @inheritdoc ILLMPriceOraclePolicy
    function quoteLlmToAsset(uint256 llmStakeAmount) external view returns (uint256 assetAmount) {
        // Floors the collateral valuation (protocol-favorable).
        return Math.mulDiv(llmStakeAmount, _assetUnitsPerLlm, LLM_UNIT);
    }

    /// @inheritdoc ILLMPriceOraclePolicy
    function quoteAssetToLlm(uint256 assetAmount) external view returns (uint256 llmStakeAmount) {
        // Rounds the seized/required stake up (protocol-favorable).
        return Math.mulDiv(assetAmount, LLM_UNIT, _assetUnitsPerLlm, Math.Rounding.Ceil);
    }
}
