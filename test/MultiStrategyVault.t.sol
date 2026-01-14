// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MultiStrategyVault.sol";
import "../src/MockUSDC.sol";

contract MultiStrategyVaultTest is Test {
    MultiStrategyVault public vault;
    MockUSDC public usdc;

    address public alice = address(0x1);
    address public bob = address(0x2);

    // Constants for testing
    uint256 constant INITIAL_MINT = 10_000 * 1e6; // 10,000 USDC (6 decimals)
    uint256 constant DEPOSIT_AMOUNT = 1_000 * 1e6; // 1,000 USDC

    function setUp() public {
        // Deploy contracts
        usdc = new MockUSDC();
        vault = new MultiStrategyVault(IERC20(address(usdc)));

        // Mint USDC to test users
        usdc.mint(alice, INITIAL_MINT);
        usdc.mint(bob, INITIAL_MINT);

        // Approve vault to spend USDC
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            BASIC DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_Success() public {
        vm.startPrank(alice);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 usdcBefore = usdc.balanceOf(alice);

        // Deposit USDC
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);

        // Verify shares minted (should be 1:1 for first deposit)
        assertEq(
            shares,
            DEPOSIT_AMOUNT,
            "Shares should equal deposit amount for first deposit"
        );
        assertEq(
            vault.balanceOf(alice),
            sharesBefore + shares,
            "Alice should receive shares"
        );

        // Verify USDC transferred
        assertEq(
            usdc.balanceOf(alice),
            usdcBefore - DEPOSIT_AMOUNT,
            "USDC should be transferred from Alice"
        );
        assertEq(
            usdc.balanceOf(address(vault)),
            DEPOSIT_AMOUNT,
            "Vault should receive USDC"
        );

        vm.stopPrank();
    }

    function test_Deposit_EmitsEvent() public {
        vm.startPrank(alice);

        // Expect Deposited event
        vm.expectEmit(true, false, false, true);
        emit MultiStrategyVault.Deposited(
            alice,
            DEPOSIT_AMOUNT,
            DEPOSIT_AMOUNT
        );

        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.stopPrank();
    }

    function test_Deposit_MultipleUsers() public {
        // Alice deposits
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(DEPOSIT_AMOUNT, alice);

        // Bob deposits
        vm.prank(bob);
        uint256 bobShares = vault.deposit(DEPOSIT_AMOUNT, bob);

        // Both should receive equal shares for equal deposits
        assertEq(
            aliceShares,
            bobShares,
            "Equal deposits should yield equal shares"
        );
        assertEq(
            vault.totalAssets(),
            DEPOSIT_AMOUNT * 2,
            "Total assets should be sum of deposits"
        );
    }

    function test_Mint_Success() public {
        vm.startPrank(alice);

        uint256 sharesToMint = 500 * 1e6;
        uint256 assets = vault.mint(sharesToMint, alice);

        assertEq(
            vault.balanceOf(alice),
            sharesToMint,
            "Alice should have minted shares"
        );
        assertEq(
            assets,
            sharesToMint,
            "Assets should equal shares for first mint"
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Withdraw_Success() public {
        // Alice deposits first
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Alice requests redemption for half her shares
        uint256 sharesToRedeem = DEPOSIT_AMOUNT / 2;

        vm.startPrank(alice);
        uint256 usdcBefore = usdc.balanceOf(alice);

        // Request redeem (should fulfill immediately since vault has assets)
        uint256 requestId = vault.requestRedeem(sharesToRedeem, alice);

        // requestId 0 means immediate fulfillment
        assertEq(requestId, 0, "Should fulfill immediately");

        // Verify USDC returned
        assertEq(
            usdc.balanceOf(alice),
            usdcBefore + sharesToRedeem,
            "Alice should receive USDC"
        );

        vm.stopPrank();
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.startPrank(alice);

        uint256 sharesToRedeem = DEPOSIT_AMOUNT / 2;

        // Expect Withdrawn event (immediate fulfillment)
        vm.expectEmit(true, false, false, true);
        emit MultiStrategyVault.Withdrawn(
            alice,
            sharesToRedeem,
            sharesToRedeem
        );

        vault.requestRedeem(sharesToRedeem, alice);

        vm.stopPrank();
    }

    function test_Redeem_Success() public {
        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);

        // Alice redeems all shares via requestRedeem
        vm.startPrank(alice);
        uint256 usdcBefore = usdc.balanceOf(alice);
        uint256 requestId = vault.requestRedeem(shares, alice);

        // Should fulfill immediately
        assertEq(requestId, 0, "Should fulfill immediately");

        assertEq(
            usdc.balanceOf(alice),
            usdcBefore + DEPOSIT_AMOUNT,
            "Alice should receive USDC"
        );
        assertEq(vault.balanceOf(alice), 0, "Alice should have no shares left");

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            TOTAL ASSETS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TotalAssets_Empty() public {
        assertEq(
            vault.totalAssets(),
            0,
            "Empty vault should have 0 total assets"
        );
    }

    function test_TotalAssets_AfterDeposit() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        assertEq(
            vault.totalAssets(),
            DEPOSIT_AMOUNT,
            "Total assets should equal deposit"
        );
    }

    function test_TotalAssets_AfterMultipleDeposits() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(bob);
        vault.deposit(DEPOSIT_AMOUNT * 2, bob);

        assertEq(
            vault.totalAssets(),
            DEPOSIT_AMOUNT * 3,
            "Total assets should be sum of all deposits"
        );
    }

    function test_TotalAssets_AfterWithdrawal() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(alice);
        vault.requestRedeem(DEPOSIT_AMOUNT / 2, alice);

        assertEq(
            vault.totalAssets(),
            DEPOSIT_AMOUNT / 2,
            "Total assets should decrease after withdrawal"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            SHARE PRICING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SharePrice_InitialDeposit() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);

        // First deposit should be 1:1
        assertEq(shares, DEPOSIT_AMOUNT, "Initial share price should be 1:1");
    }

    function test_ConvertToShares() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 assets = 100 * 1e6;
        uint256 shares = vault.convertToShares(assets);

        assertEq(shares, assets, "Conversion should be 1:1 with no yield");
    }

    function test_ConvertToAssets() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = 100 * 1e6;
        uint256 assets = vault.convertToAssets(shares);

        assertEq(assets, shares, "Conversion should be 1:1 with no yield");
    }

    /*//////////////////////////////////////////////////////////////
                            PREVIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_PreviewDeposit() public {
        uint256 assets = 100 * 1e6;
        uint256 expectedShares = vault.previewDeposit(assets);

        vm.prank(alice);
        uint256 actualShares = vault.deposit(assets, alice);

        assertEq(
            actualShares,
            expectedShares,
            "Preview should match actual deposit"
        );
    }

    function test_PreviewMint() public {
        uint256 shares = 100 * 1e6;
        uint256 expectedAssets = vault.previewMint(shares);

        vm.prank(alice);
        uint256 actualAssets = vault.mint(shares, alice);

        assertEq(
            actualAssets,
            expectedAssets,
            "Preview should match actual mint"
        );
    }

    function test_PreviewWithdraw() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 assets = 100 * 1e6;
        uint256 expectedShares = vault.previewWithdraw(assets);

        vm.startPrank(alice);
        uint256 balanceBefore = usdc.balanceOf(alice);
        vault.requestRedeem(expectedShares, alice);
        uint256 actualAssets = usdc.balanceOf(alice) - balanceBefore;

        assertEq(actualAssets, assets, "Actual assets should match expected");
        vm.stopPrank();
    }

    function test_PreviewRedeem() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = 100 * 1e6;
        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.startPrank(alice);
        uint256 balanceBefore = usdc.balanceOf(alice);
        vault.requestRedeem(shares, alice);
        uint256 actualAssets = usdc.balanceOf(alice) - balanceBefore;

        assertEq(
            actualAssets,
            expectedAssets,
            "Preview should match actual redeem"
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            MAX FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_MaxDeposit() public {
        uint256 maxDeposit = vault.maxDeposit(alice);
        assertEq(
            maxDeposit,
            type(uint256).max,
            "Max deposit should be unlimited"
        );
    }

    function test_MaxMint() public {
        uint256 maxMint = vault.maxMint(alice);
        assertEq(maxMint, type(uint256).max, "Max mint should be unlimited");
    }

    function test_MaxWithdraw() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 maxWithdraw = vault.maxWithdraw(alice);
        assertEq(
            maxWithdraw,
            DEPOSIT_AMOUNT,
            "Max withdraw should equal deposited amount"
        );
    }

    function test_MaxRedeem() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 maxRedeem = vault.maxRedeem(alice);
        assertEq(maxRedeem, shares, "Max redeem should equal share balance");
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_Zero_Allowed() public {
        // ERC4626 standard allows zero deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(0, alice);

        assertEq(shares, 0, "Zero deposit should return zero shares");
        assertEq(vault.balanceOf(alice), 0, "Alice should have no shares");
    }

    function test_Withdraw_InsufficientBalance_Reverts() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(DEPOSIT_AMOUNT * 2, alice, alice);
    }

    function test_Withdraw_WithoutApproval_Reverts() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Bob tries to withdraw Alice's funds without approval
        vm.prank(bob);
        vm.expectRevert();
        vault.withdraw(DEPOSIT_AMOUNT, bob, alice);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Deposit(uint256 amount) public {
        // Bound amount to reasonable range
        amount = bound(amount, 1, INITIAL_MINT);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        assertEq(vault.balanceOf(alice), shares, "Shares should be minted");
        assertEq(
            vault.totalAssets(),
            amount,
            "Total assets should match deposit"
        );
    }

    function testFuzz_DepositAndWithdraw(
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        depositAmount = bound(depositAmount, 1, INITIAL_MINT);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Convert withdraw amount to shares
        uint256 sharesToRedeem = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        vault.requestRedeem(sharesToRedeem, alice);

        assertEq(
            vault.totalAssets(),
            depositAmount - withdrawAmount,
            "Total assets should decrease"
        );
    }
}
