// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title LLMToken
/// @notice Demo-only merit token with open minting for frontend testing.
contract LLMToken is ERC20 {
    error ZeroAmount();

    event DemoMeritsMinted(address indexed to, uint256 amount, address indexed mintedBy);

    constructor() ERC20("Liberland Merit", "LLM") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        _mint(to, amount);
        emit DemoMeritsMinted(to, amount, msg.sender);
    }
}
