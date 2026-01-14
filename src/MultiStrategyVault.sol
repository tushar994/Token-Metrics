// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IStrategy.sol";

/**
 * @title MultiStrategyVault
 * @notice An ERC-4626 compliant vault that accepts USDC deposits and will support multiple underlying strategies
 * @dev This is Step 1 implementation - basic vault functionality. Multi-strategy routing will be added in Step 2.
 */
contract MultiStrategyVault is ERC4626, AccessControl, Pausable {
    // Roles
    bytes32 public constant STRATEGY_MANAGER_ROLE =
        keccak256("STRATEGY_MANAGER_ROLE");

    // State variables
    uint256 public totalAssetsInStrategies;

    // Strategy debt tracking: strategy address => current debt
    mapping(address => uint256) public strategyDebt;

    // Events
    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event DebtUpdated(
        address indexed strategy,
        uint256 currentDebt,
        uint256 newDebt
    );
    event StrategyReported(
        address indexed strategy,
        uint256 gain,
        uint256 loss,
        uint256 currentDebt
    );

    /**
     * @notice Constructor initializes the vault with USDC as the underlying asset
     * @param _asset Address of the USDC token contract
     */
    constructor(
        IERC20 _asset
    ) ERC4626(_asset) ERC20("Multi-Strategy Vault Shares", "msVault") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGY_MANAGER_ROLE, msg.sender);
    }

    /**
     * @notice Deposits assets into the vault and mints shares to receiver
     * @param assets Amount of USDC to deposit
     * @param receiver Address to receive the vault shares
     * @return shares Amount of shares minted
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override whenNotPaused returns (uint256 shares) {
        shares = super.deposit(assets, receiver);
        emit Deposited(receiver, assets, shares);
    }

    /**
     * @notice Mints exact amount of shares to receiver
     * @param shares Amount of shares to mint
     * @param receiver Address to receive the vault shares
     * @return assets Amount of USDC deposited
     */
    function mint(
        uint256 shares,
        address receiver
    ) public virtual override whenNotPaused returns (uint256 assets) {
        assets = super.mint(shares, receiver);
        emit Deposited(receiver, assets, shares);
    }

    /**
     * @notice Withdraws assets from the vault by burning shares
     * @param assets Amount of USDC to withdraw
     * @param receiver Address to receive the USDC
     * @param owner Address that owns the shares
     * @return shares Amount of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256 shares) {
        shares = super.withdraw(assets, receiver, owner);
        emit Withdrawn(owner, assets, shares);
    }

    /**
     * @notice Redeems shares for assets
     * @param shares Amount of shares to burn
     * @param receiver Address to receive the USDC
     * @param owner Address that owns the shares
     * @return assets Amount of USDC withdrawn
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256 assets) {
        assets = super.redeem(shares, receiver, owner);
        emit Withdrawn(owner, assets, shares);
    }

    /**
     * @notice Returns the total assets managed by the vault
     * @dev Returns the sum of vault's idle balance and assets deployed to strategies
     * @return Total USDC value managed by the vault
     */
    function totalAssets() public view virtual override returns (uint256) {
        return
            IERC20(asset()).balanceOf(address(this)) + totalAssetsInStrategies;
    }

    /**
     * @notice Pauses the vault, preventing deposits and mints
     * @dev Only callable by admin
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the vault, allowing deposits and mints
     * @dev Only callable by admin
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Updates the debt allocation for a strategy
     * @dev Simplified version of Yearn's update_debt. Either deposits to or withdraws from strategy.
     * @param strategy Address of the strategy to update
     * @param targetDebt The desired debt amount for the strategy
     */
    function updateDebt(
        address strategy,
        uint256 targetDebt
    ) external onlyRole(STRATEGY_MANAGER_ROLE) {
        require(strategy != address(0), "Invalid strategy");
        require(
            IStrategy(strategy).asset() == asset(),
            "Strategy asset mismatch"
        );

        uint256 currentDebt = strategyDebt[strategy];
        require(targetDebt != currentDebt, "Target debt equals current debt");

        if (targetDebt > currentDebt) {
            // Increase debt - deposit to strategy
            uint256 assetsToDeposit = targetDebt - currentDebt;

            // Check if vault has enough idle assets
            uint256 idleAssets = IERC20(asset()).balanceOf(address(this));
            require(idleAssets >= assetsToDeposit, "Insufficient idle assets");

            // Check strategy's max deposit
            uint256 maxDeposit = IStrategy(strategy).maxDeposit(address(this));
            require(
                maxDeposit >= assetsToDeposit,
                "Strategy cannot accept deposit"
            );

            // Approve and deposit to strategy
            IERC20(asset()).approve(strategy, assetsToDeposit);
            uint256 sharesMinted = IStrategy(strategy).deposit(
                assetsToDeposit,
                address(this)
            );
            require(sharesMinted > 0, "Deposit failed");

            // Reset approval
            IERC20(asset()).approve(strategy, 0);

            // Update debt tracking
            strategyDebt[strategy] = targetDebt;
            totalAssetsInStrategies += assetsToDeposit;
        } else {
            // Decrease debt - withdraw from strategy
            uint256 assetsToWithdraw = currentDebt - targetDebt;

            // Check if strategy has enough to withdraw
            uint256 maxRedeem = IStrategy(strategy).maxRedeem(address(this));
            uint256 maxWithdraw = IStrategy(strategy).convertToAssets(
                maxRedeem
            );
            require(
                maxWithdraw >= assetsToWithdraw,
                "Cannot withdraw requested amount"
            );

            // Calculate shares needed
            uint256 sharesToRedeem = IStrategy(strategy).previewWithdraw(
                assetsToWithdraw
            );

            // Withdraw from strategy
            uint256 assetsReceived = IStrategy(strategy).redeem(
                sharesToRedeem,
                address(this),
                address(this)
            );
            require(assetsReceived >= assetsToWithdraw, "Withdrawal failed");

            // Update debt tracking
            strategyDebt[strategy] = targetDebt;
            totalAssetsInStrategies -= assetsToWithdraw;
        }

        emit DebtUpdated(strategy, currentDebt, targetDebt);
    }

    /**
     * @notice Updates the vault's accounting based on a strategy's current performance
     * @dev Simplified version of Yearn's process_report without fees or profit locking
     * @param strategy Address of the strategy to report on
     * @return gain The amount of profit generated (if any)
     * @return loss The amount of loss incurred (if any)
     */
    function updateStrategyPerformance(
        address strategy
    )
        external
        onlyRole(STRATEGY_MANAGER_ROLE)
        returns (uint256 gain, uint256 loss)
    {
        require(strategy != address(0), "Invalid strategy");
        require(strategyDebt[strategy] > 0, "Strategy has no debt");

        // Get the current debt (what we think the strategy should have)
        uint256 currentDebt = strategyDebt[strategy];

        // Get strategy's actual position value
        // The vault's shares in the strategy
        uint256 strategyShares = IStrategy(strategy).balanceOf(address(this));
        // Convert shares to assets to see what our position is worth
        uint256 strategyTotalAssets = IStrategy(strategy).convertToAssets(
            strategyShares
        );

        // Calculate gain or loss
        if (strategyTotalAssets > currentDebt) {
            // Strategy has generated profit
            gain = strategyTotalAssets - currentDebt;
            loss = 0;

            // Update the strategy's debt to reflect the gain
            strategyDebt[strategy] = strategyTotalAssets;
            // Increase total assets in strategies
            totalAssetsInStrategies += gain;
        } else if (strategyTotalAssets < currentDebt) {
            // Strategy has incurred a loss
            gain = 0;
            loss = currentDebt - strategyTotalAssets;

            // Update the strategy's debt to reflect the loss
            strategyDebt[strategy] = strategyTotalAssets;
            // Decrease total assets in strategies
            totalAssetsInStrategies -= loss;
        } else {
            // No change in value
            gain = 0;
            loss = 0;
        }

        emit StrategyReported(strategy, gain, loss, strategyDebt[strategy]);
    }
}
