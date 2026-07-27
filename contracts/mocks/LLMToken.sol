// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {LLMTokenConstants} from "../libraries/LLMTokenConstants.sol";

/// @title LLMToken
/// @notice Demo-only merit token with open minting for frontend testing, bounded by the production LLM hard cap.
contract LLMToken is ERC20Capped {
    error ZeroAmount();

    event DemoMeritsMinted(address indexed to, uint256 amount, address indexed mintedBy);

    constructor() ERC20("Liberland Merit", "LLM") ERC20Capped(LLMTokenConstants.MAX_SUPPLY) {}

    function decimals() public pure override returns (uint8) {
        return LLMTokenConstants.DECIMALS;
    }

    function mint(address to, uint256 amount) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        _mint(to, amount);
        emit DemoMeritsMinted(to, amount, msg.sender);
    }
}
