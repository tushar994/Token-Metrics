// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/strategies/CoreWriterStrategy.sol";
import "../src/MultiStrategyVault.sol";
import "../src/MockUSDC.sol";

contract MockCoreWriter {
    bytes public lastRawAction;

    function sendRawAction(bytes calldata data) external {
        lastRawAction = data;
    }
}

contract CoreWriterStrategyTest is Test {
    CoreWriterStrategy public strategy;
    MultiStrategyVault public vault;
    MockUSDC public usdc;
    MockCoreWriter public coreWriter;

    address public admin = address(this);
    address public executor = address(0x1);
    address public user1 = address(0x2);

    uint256 constant INITIAL_BALANCE = 200_000 * 1e6; // Increased for larger deposits
    uint256 constant DEPOSIT_AMOUNT = 10_000 * 1e6;

    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();
        coreWriter = new MockCoreWriter();

        // Deploy strategy
        strategy = new CoreWriterStrategy(
            IERC20(address(usdc)),
            address(coreWriter)
        );

        // Deploy vault
        vault = new MultiStrategyVault(IERC20(address(usdc)));

        // Grant executor role
        strategy.grantRole(strategy.EXECUTOR_ROLE(), executor);

        // Configure strategy in vault (50% max allocation)
        vault.setStrategyConfig(address(strategy), 5000);

        // Setup user with USDC
        usdc.mint(user1, INITIAL_BALANCE);
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
    }

    function test_SendCoreWriterAction() public {
        // Sample data from user's specification
        bytes memory data = abi.encode(
            address(0xD6642090EDE21cb1Bd6a8FBbd3861A7dbd6D3EA8),
            uint64(0),
            uint64(200000000)
        );

        // Execute action
        vm.prank(executor);
        strategy.sendCoreWriterAction(bytes1(0x01), uint32(6), data);

        // Verify action was sent to CoreWriter
        bytes memory sentAction = coreWriter.lastRawAction();
        assertTrue(sentAction.length > 0, "Action should be sent");

        // Verify action format (version + actionId + data)
        assertEq(uint8(sentAction[0]), 0x01, "Version byte should match");
    }

    function test_SendTokenToLayer1() public {
        // Mint some USDC to strategy for testing
        usdc.mint(address(strategy), 50_000 * 1e6);

        uint256 sendAmount = 1000 * 1e6;
        uint256 tokenIndex = 200; // Example token index

        // Calculate expected system address
        address expectedSystemAddress = address(
            uint160(0x2000000000000000000000000000000000000000) |
                uint160(tokenIndex)
        );

        uint256 strategyBalanceBefore = usdc.balanceOf(address(strategy));

        // Send tokens to Layer1
        vm.prank(executor);
        strategy.sendTokenToLayer1(address(usdc), sendAmount, tokenIndex);

        // Verify tokens were transferred to system address
        assertEq(
            usdc.balanceOf(expectedSystemAddress),
            sendAmount,
            "Tokens should be sent to system address"
        );

        assertEq(
            usdc.balanceOf(address(strategy)),
            strategyBalanceBefore - sendAmount,
            "Strategy balance should decrease"
        );
    }

    function test_SendTokenToLayer1_RevertsOnZeroAmount() public {
        vm.prank(executor);
        vm.expectRevert(CoreWriterStrategy.ZeroAmount.selector);
        strategy.sendTokenToLayer1(address(usdc), 0, 200);
    }

    function test_SendTokenToLayer1_RevertsOnInsufficientBalance() public {
        uint256 tooMuch = usdc.balanceOf(address(strategy)) + 1;

        vm.prank(executor);
        vm.expectRevert(CoreWriterStrategy.InsufficientBalance.selector);
        strategy.sendTokenToLayer1(address(usdc), tooMuch, 200);
    }

    function test_ProfitScenario_WithVault() public {
        // User deposits into vault
        vm.prank(user1);
        vault.deposit(20_000 * 1e6, user1); // Deposit more to have room for 50% allocation

        // Vault allocates 50% to strategy (respecting max allocation)
        vault.updateDebt(address(strategy), 10_000 * 1e6);

        // Verify strategy received funds
        uint256 strategyShares = strategy.balanceOf(address(vault));
        assertGt(strategyShares, 0, "Vault should have strategy shares");

        // Simulate profit: add 10% to strategy
        uint256 profit = (10_000 * 1e6) / 10;
        usdc.mint(address(strategy), profit);

        // Update performance to recognize profit
        (uint256 gain, uint256 loss) = vault.updateStrategyPerformance(
            address(strategy)
        );

        // Verify profit was recognized
        assertApproxEqAbs(gain, profit, 1e6, "Should recognize profit");
        assertEq(loss, 0, "Should have no loss");

        // User withdraws - should get more than deposited
        vault.updateDebt(address(strategy), 0); // Free funds

        vm.startPrank(user1);
        uint256 balanceBefore = usdc.balanceOf(user1);
        vault.requestRedeem(vault.balanceOf(user1), user1);
        vm.stopPrank();

        uint256 received = usdc.balanceOf(user1) - balanceBefore;
        assertGt(
            received,
            20_000 * 1e6,
            "User should receive more than deposited due to profit"
        );
    }

    function test_OnlyExecutorCanSendActions() public {
        bytes memory data = abi.encode(address(0), uint64(0), uint64(0));

        vm.prank(user1);
        vm.expectRevert();
        strategy.sendCoreWriterAction(bytes1(0x01), uint32(6), data);
    }

    function test_OnlyExecutorCanSendTokens() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.sendTokenToLayer1(address(usdc), 1000 * 1e6, 200);
    }
}
