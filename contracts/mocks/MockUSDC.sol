// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice Test-only USDC-like token with six decimals and open minting.
contract MockUSDC is ERC20 {
    error ZeroAmount();

    event MockUSDCMinted(address indexed to, uint256 amount, address indexed mintedBy);

    constructor() ERC20("Mock USD Coin", "USDC") {}

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mints mock USDC for tests and demos.
    /// @param to The receiving account.
    /// @param amount The amount to mint.
    function mint(address to, uint256 amount) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        _mint(to, amount);
        emit MockUSDCMinted(to, amount, msg.sender);
    }
}
