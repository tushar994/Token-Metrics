// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IStrategy.sol";

/**
 * @title HoldingStrategy
 * @notice A simple strategy that holds funds without investing them.
 */
contract HoldingStrategy is ERC4626, IStrategy {
    constructor(
        IERC20 _asset
    ) ERC4626(_asset) ERC20("Holding Strategy", "HOLD") {}

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
