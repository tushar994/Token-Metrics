// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @notice A simple ERC20 token that simulates USDC for testing purposes
 * @dev Uses 6 decimals to match real USDC
 */
contract MockUSDC is ERC20 {
    /**
     * @notice Constructor sets up the token with name and symbol
     */
    constructor() ERC20("Mock USDC", "USDC") {}

    /**
     * @notice Returns 6 decimals to match real USDC
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Allows anyone to mint tokens for testing
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint (in 6 decimal format)
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
