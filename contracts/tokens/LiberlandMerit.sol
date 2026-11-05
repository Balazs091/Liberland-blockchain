// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ILLMToken} from "../interfaces/ILLMToken.sol";
import {LLMTokenConstants} from "../libraries/LLMTokenConstants.sol";

/// @title LiberlandMerit
/// @notice Non-upgradeable Liberland Merit with a fixed supply minted once at genesis.
/// @dev The approved genesis supply may be below the hard cap; any unused capacity is permanently unmintable.
///      This token has no privileged roles. Political rights and voting weight belong to protocol registries,
///      not to token balances or token-level delegation.
contract LiberlandMerit is ERC20Capped, ILLMToken {
    error ZeroGenesisSupply();

    /// @param genesisRecipient The nonzero recipient of the complete initial token supply.
    /// @param genesisSupply The fixed supply in 18-decimal base units, at most 70,000,000 LLM.
    constructor(address genesisRecipient, uint256 genesisSupply)
        ERC20("Liberland Merit", "LLM")
        ERC20Capped(LLMTokenConstants.MAX_SUPPLY)
    {
        if (genesisSupply == 0) revert ZeroGenesisSupply();
        _mint(genesisRecipient, genesisSupply);
    }

    /// @notice Returns the protocol-wide token denomination.
    /// @return tokenDecimals The number of decimal places used to display LLM balances.
    function decimals() public pure override(ERC20, IERC20Metadata) returns (uint8 tokenDecimals) {
        return LLMTokenConstants.DECIMALS;
    }

    /// @inheritdoc ILLMToken
    function cap() public view override(ERC20Capped, ILLMToken) returns (uint256 maximumSupply) {
        return super.cap();
    }
}
