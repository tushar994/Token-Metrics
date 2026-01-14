// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IStrategy.sol";

interface ICoreWriter {
    function sendRawAction(bytes calldata data) external;
}

interface IBridge {
    function deposit(uint256 amount, uint32 destinationDex) external;
}

/**
 * @title CoreWriterStrategy
 * @notice ERC4626 vault strategy for Core blockchain with action execution capabilities
 */
contract CoreWriterStrategy is ERC4626, AccessControl, IStrategy {
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    address public immutable CORE_WRITER;

    // Custom errors
    error ZeroAmount();
    error InsufficientBalance();
    error TransferFailed();

    // Events
    event TokenSentToLayer1(
        address indexed token,
        uint256 amount,
        uint256 tokenIndex
    );
    event CoreActionExecuted(bytes1 versionByte, uint32 actionId);
    event USDCTransferredToBridge(uint256 amount);

    // Constants
    address public constant BRIDGE_ADDRESS =
        0x6B9E773128f453f5c2C60935Ee2DE2CBc5390A24;

    constructor(
        IERC20 _asset,
        address _coreWriter
    ) ERC4626(_asset) ERC20("CoreWriter Strategy", "CORE") {
        require(_coreWriter != address(0), "CoreWriter cannot be zero address");
        CORE_WRITER = _coreWriter;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
    }

    /**
     * @notice Send action to Core blockchain via CoreWriter
     * @param versionByte Version byte for the action
     * @param actionId 32-bit action identifier
     * @param encodedAction ABI-encoded action data
     */
    function sendCoreWriterAction(
        bytes1 versionByte,
        uint32 actionId,
        bytes calldata encodedAction
    ) external onlyRole(EXECUTOR_ROLE) {
        ICoreWriter(CORE_WRITER).sendRawAction(
            abi.encodePacked(
                versionByte,
                bytes1(uint8(actionId >> 16)),
                bytes1(uint8(actionId >> 8)),
                bytes1(uint8(actionId)),
                encodedAction
            )
        );

        emit CoreActionExecuted(versionByte, actionId);
    }

    /**
     * @notice Send ERC20 tokens to Hypercore Layer1
     * @param token Address of the ERC20 token to send
     * @param amount Amount of tokens to send
     * @param tokenIndex Token index on Core (determines system address)
     */
    function sendTokenToLayer1(
        address token,
        uint256 amount,
        uint256 tokenIndex
    ) external onlyRole(EXECUTOR_ROLE) {
        if (amount == 0) revert ZeroAmount();

        // Calculate system address: 0x20 + zeros + token index in big-endian
        // Example: tokenIndex 200 (0xc8) => 0x20000000000000000000000000000000000000c8
        address systemAddress = address(
            uint160(0x2000000000000000000000000000000000000000) |
                uint160(tokenIndex)
        );

        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));

        if (amount > balance) revert InsufficientBalance();

        // Transfer to system address
        tokenContract.transfer(systemAddress, amount);

        emit TokenSentToLayer1(token, amount, tokenIndex);
    }

    /**
     * @notice Transfer USDC to bridge contract
     * @param amount Amount of USDC to transfer
     */
    function transferUSDC(uint256 amount) external onlyRole(EXECUTOR_ROLE) {
        if (amount == 0) revert ZeroAmount();

        IERC20 usdc = IERC20(asset());
        uint256 balance = usdc.balanceOf(address(this));

        if (amount > balance) revert InsufficientBalance();

        // Approve bridge to spend USDC
        usdc.approve(BRIDGE_ADDRESS, amount);

        // Deposit to bridge with destinationDex as uint32.max
        IBridge(BRIDGE_ADDRESS).deposit(amount, type(uint32).max);

        emit USDCTransferredToBridge(amount);
    }

    // IStrategy interface overrides
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
