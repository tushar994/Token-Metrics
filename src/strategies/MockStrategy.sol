// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IStrategy.sol";

/**
 * @title MockStrategy
 * @notice A mock strategy for testing with admin controls to simulate P&L
 */
contract MockStrategy is ERC4626, IStrategy {
    address public admin;

    event ProfitAdded(uint256 amount);
    event LossSimulated(uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    constructor(
        IERC20 _asset,
        address _admin
    ) ERC4626(_asset) ERC20("Mock Strategy", "MOCK") {
        require(_admin != address(0), "Invalid admin");
        admin = _admin;
    }

    /**
     * @notice Simulate profit by adding assets to the strategy
     * @param amount Amount of assets to add
     */
    function addProfit(uint256 amount) external onlyAdmin {
        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            msg.sender,
            address(this),
            amount
        );
        emit ProfitAdded(amount);
    }

    /**
     * @notice Simulate loss by removing assets from the strategy
     * @param amount Amount of assets to remove
     */
    function simulateLoss(uint256 amount) external onlyAdmin {
        uint256 balance = IERC20(asset()).balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");

        SafeERC20.safeTransfer(IERC20(asset()), msg.sender, amount);
        emit LossSimulated(amount);
    }

    // IStrategy overrides
    function asset()
        public
        view
        override(ERC4626, IStrategy)
        returns (address)
    {
        return super.asset();
    }

    function balanceOf(
        address owner
    ) public view override(ERC20, IERC20, IStrategy) returns (uint256) {
        return super.balanceOf(owner);
    }

    function convertToAssets(
        uint256 shares
    ) public view override(ERC4626, IStrategy) returns (uint256) {
        return super.convertToAssets(shares);
    }

    function convertToShares(
        uint256 assets
    ) public view override(ERC4626, IStrategy) returns (uint256) {
        return super.convertToShares(assets);
    }

    function previewWithdraw(
        uint256 assets
    ) public view override(ERC4626, IStrategy) returns (uint256) {
        return super.previewWithdraw(assets);
    }

    function maxDeposit(
        address receiver
    ) public view override(ERC4626, IStrategy) returns (uint256) {
        return super.maxDeposit(receiver);
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public override(ERC4626, IStrategy) returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function maxRedeem(
        address owner
    ) public view override(ERC4626, IStrategy) returns (uint256) {
        return super.maxRedeem(owner);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override(ERC4626, IStrategy) returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }
}
