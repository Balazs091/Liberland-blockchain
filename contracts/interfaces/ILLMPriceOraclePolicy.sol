// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title ILLMPriceOraclePolicy
/// @notice Policy interface for converting LLM stake units and a borrow asset.
interface ILLMPriceOraclePolicy {
    /// @notice Returns the borrow asset valued by this oracle policy.
    /// @return assetAddress The ERC20 asset address.
    function asset() external view returns (address assetAddress);

    /// @notice Quotes LLM stake units into the borrow asset's smallest units.
    /// @param llmStakeAmount The active LLM stake units to value.
    /// @return assetAmount The corresponding asset amount.
    function quoteLlmToAsset(uint256 llmStakeAmount) external view returns (uint256 assetAmount);

    /// @notice Quotes borrow asset units into LLM stake units, rounding up.
    /// @param assetAmount The borrow asset amount to convert.
    /// @return llmStakeAmount The corresponding active LLM stake units.
    function quoteAssetToLlm(uint256 assetAmount) external view returns (uint256 llmStakeAmount);
}
