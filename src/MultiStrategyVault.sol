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

    // Withdrawal request struct for EIP-7540 async redemptions
    struct WithdrawalRequest {
        uint256 shares; // Amount of shares to redeem
        address owner; // Owner of the request
        uint256 timestamp; // When request was created
        bool isPending; // Whether request is still pending
    }

    // State variables
    uint256 public totalAssetsInStrategies;

    // Strategy debt tracking: strategy address => current debt
    mapping(address => uint256) public strategyDebt;

    // EIP-7540 Async withdrawal tracking
    // owner => requestId => WithdrawalRequest
    mapping(address => mapping(uint256 => WithdrawalRequest))
        public withdrawalRequests;
    // owner => next request ID counter
    mapping(address => uint256) public nextRequestId;

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
    event WithdrawalRequested(
        address indexed owner,
        uint256 indexed requestId,
        uint256 shares
    );
    event WithdrawalClaimed(
        address indexed owner,
        uint256 indexed requestId,
        uint256 assets
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
     * @notice Withdraws are disabled - use requestRedeem() for async withdrawals
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256 shares) {
        revert("Use requestRedeem() for async withdrawals");
    }

    /**
     * @notice Redeems are disabled - use requestRedeem() for async withdrawals
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256 assets) {
        revert("Use requestRedeem() for async withdrawals");
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

    // ============ EIP-7540 Async Withdrawal Functions ============

    /**
     * @notice Request an asynchronous redemption of shares
     * @dev Burns shares immediately. If vault has idle assets, fulfills immediately. Otherwise creates pending request.
     * @param shares Amount of shares to redeem
     * @param owner Owner of the shares (must approve if not msg.sender)
     * @return requestId The ID of the withdrawal request (0 if fulfilled immediately)
     */
    function requestRedeem(
        uint256 shares,
        address owner
    ) external returns (uint256 requestId) {
        require(shares > 0, "Cannot redeem zero shares");
        require(owner != address(0), "Invalid owner");

        // Check approval if msg.sender is not the owner
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) {
                require(allowed >= shares, "Insufficient allowance");
                _approve(owner, msg.sender, allowed - shares);
            }
        }

        // Calculate assets owed at current share price
        uint256 assets = convertToAssets(shares);

        // Transfer shares to vault (keeps totalSupply correct for pending requests)
        _transfer(owner, address(this), shares);

        // Check if vault has enough idle assets
        uint256 idleAssets = IERC20(asset()).balanceOf(address(this));

        if (idleAssets >= assets) {
            // Vault has enough idle assets - fulfill immediately
            // Burn shares since we're completing the withdrawal
            _burn(address(this), shares);
            SafeERC20.safeTransfer(IERC20(asset()), owner, assets);
            emit Withdrawn(owner, assets, shares);
            return 0; // 0 indicates immediate fulfillment
        } else {
            // Not enough idle assets - create pending request
            // Shares stay in vault until claimed
            requestId = nextRequestId[owner]++;

            withdrawalRequests[owner][requestId] = WithdrawalRequest({
                shares: shares,
                owner: owner,
                timestamp: block.timestamp,
                isPending: true
            });

            emit WithdrawalRequested(owner, requestId, shares);
            return requestId;
        }
    }

    /**
     * @notice Claim a pending withdrawal request
     * @dev Can only be called by the request owner once enough assets are available
     * @param requestId The ID of the withdrawal request to claim
     * @return assets Amount of assets transferred
     */
    function claimWithdrawal(
        uint256 requestId
    ) external returns (uint256 assets) {
        WithdrawalRequest storage request = withdrawalRequests[msg.sender][
            requestId
        ];

        require(request.isPending, "Request not pending or does not exist");
        require(request.owner == msg.sender, "Not request owner");

        // Calculate assets owed
        assets = convertToAssets(request.shares);
        uint256 idleAssets = IERC20(asset()).balanceOf(address(this));

        require(idleAssets >= assets, "Insufficient idle assets");

        // Mark request as claimed
        request.isPending = false;

        // Burn the shares that were held by the vault
        _burn(address(this), request.shares);

        // Transfer assets
        SafeERC20.safeTransfer(IERC20(asset()), msg.sender, assets);

        emit WithdrawalClaimed(msg.sender, requestId, assets);
    }

    /**
     * @notice Get the amount of shares in a pending withdrawal request
     * @param owner Owner of the request
     * @param requestId ID of the request
     * @return shares Amount of shares pending
     */
    function pendingWithdrawal(
        address owner,
        uint256 requestId
    ) external view returns (uint256 shares) {
        WithdrawalRequest storage request = withdrawalRequests[owner][
            requestId
        ];
        if (request.isPending) {
            return request.shares;
        }
        return 0;
    }

    /**
     * @notice Get the amount of assets claimable for a withdrawal request
     * @param owner Owner of the request
     * @param requestId ID of the request
     * @return assets Amount of assets that can be claimed (0 if not enough idle assets)
     */
    function claimableWithdrawal(
        address owner,
        uint256 requestId
    ) external view returns (uint256 assets) {
        WithdrawalRequest storage request = withdrawalRequests[owner][
            requestId
        ];

        if (!request.isPending) {
            return 0;
        }

        assets = convertToAssets(request.shares);
        uint256 idleAssets = IERC20(asset()).balanceOf(address(this));

        // Only claimable if vault has enough idle assets
        if (idleAssets >= assets) {
            return assets;
        }
        return 0;
    }
}
