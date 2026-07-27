// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title ILLMToken
/// @notice Minimum production interface for the externally deployed, hard-capped LLM token.
interface ILLMToken is IERC20Metadata {
    /// @notice Returns the immutable maximum token supply in base units.
    /// @return maximumSupply The token's hard cap.
    function cap() external view returns (uint256 maximumSupply);
}
