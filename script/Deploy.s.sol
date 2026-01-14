// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MultiStrategyVault.sol";
import "../src/strategies/CoreWriterStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployScript is Script {
    // USDC on Core blockchain
    address constant USDC_ADDRESS = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;

    // CoreWriter contract address
    address constant CORE_WRITER_ADDRESS =
        0x3333333333333333333333333333333333333333;

    // Deposit amounts (in USDC decimals - 6)
    uint256 constant INITIAL_DEPOSIT = 30 * 1e6; // 30 USDC
    uint256 constant STRATEGY_ALLOCATION = 20 * 1e6; // 20 USDC to strategy

    function run() external {
        // Get private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying with address:", deployer);
        console.log(
            "USDC balance:",
            IERC20(USDC_ADDRESS).balanceOf(deployer) / 1e6,
            "USDC"
        );

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy MultiStrategyVault
        console.log("\n1. Deploying MultiStrategyVault...");
        MultiStrategyVault vault = new MultiStrategyVault(IERC20(USDC_ADDRESS));
        console.log("MultiStrategyVault deployed at:", address(vault));

        // 2. Deploy CoreWriterStrategy
        console.log("\n2. Deploying CoreWriterStrategy...");
        CoreWriterStrategy strategy = new CoreWriterStrategy(
            IERC20(USDC_ADDRESS),
            CORE_WRITER_ADDRESS
        );
        console.log("CoreWriterStrategy deployed at:", address(strategy));

        // 3. Grant executor role to deployer
        console.log("\n3. Granting executor role...");
        strategy.grantRole(strategy.EXECUTOR_ROLE(), deployer);
        console.log("Executor role granted to:", deployer);

        // 4. Approve and deposit 30 USDC into vault
        console.log("\n4. Depositing 30 USDC into vault...");
        IERC20(USDC_ADDRESS).approve(address(vault), INITIAL_DEPOSIT);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, deployer);
        console.log("Deposited 30 USDC, received shares:", shares);

        // 5. Set CoreWriterStrategy allocation limit to 100%
        console.log("\n5. Configuring strategy (100% max allocation)...");
        vault.setStrategyConfig(address(strategy), 10000); // 100%
        console.log("Strategy configured with 100% max allocation");

        // 6. Allocate 20 USDC to CoreWriterStrategy
        console.log("\n6. Allocating 20 USDC to strategy...");
        vault.updateDebt(address(strategy), STRATEGY_ALLOCATION);
        console.log("Allocated 20 USDC to strategy");
        console.log(
            "Strategy USDC balance:",
            IERC20(USDC_ADDRESS).balanceOf(address(strategy)) / 1e6,
            "USDC"
        );

        // 7. Call transferUSDC on CoreWriterStrategy
        console.log("\n7. Transferring USDC to bridge...");
        uint256 strategyBalance = IERC20(USDC_ADDRESS).balanceOf(
            address(strategy)
        );
        strategy.transferUSDC(strategyBalance);
        console.log("Transferred", strategyBalance / 1e6, "USDC to bridge");

        // 8. Call sendCoreWriterAction (action 2 - deposit into vault)
        console.log("\n8. Sending Core action (deposit into vault)...");
        bytes memory actionData = abi.encode(
            0xdfc24b077bc1425AD1DEA75bCB6f8158E10Df303,
            true,
            15000000
        );
        strategy.sendCoreWriterAction(bytes1(0x01), uint32(2), actionData);
        console.log("Core action sent: Deposit into vault");

        vm.stopBroadcast();

        // // Print deployment summary
        console.log("\n========================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("MultiStrategyVault:", address(vault));
        console.log("CoreWriterStrategy:", address(strategy));
        console.log("Initial deposit: 30 USDC");
        console.log("Strategy allocation: 20 USDC");
        console.log("Strategy max allocation: 100%");
        console.log("========================================");
    }
}
