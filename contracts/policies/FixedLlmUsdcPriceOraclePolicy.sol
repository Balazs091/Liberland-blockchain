// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILLMPriceOraclePolicy} from "../interfaces/ILLMPriceOraclePolicy.sol";

/// @title FixedLlmUsdcPriceOraclePolicy
/// @notice Conservative v1 oracle policy with a fixed USDC value per LLM stake unit.
contract FixedLlmUsdcPriceOraclePolicy is ILLMPriceOraclePolicy {
    error InvalidAsset(address assetAddress);
    error InvalidPrice(uint256 assetUnitsPerLlm);

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
        return llmStakeAmount * _assetUnitsPerLlm;
    }

    /// @inheritdoc ILLMPriceOraclePolicy
    function quoteAssetToLlm(uint256 assetAmount) external view returns (uint256 llmStakeAmount) {
        return Math.ceilDiv(assetAmount, _assetUnitsPerLlm);
    }
}
