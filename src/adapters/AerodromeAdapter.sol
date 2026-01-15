// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IAdapter.sol";

/**
 * @title AerodromeAdapter
 * @notice Adapter for Aerodrome LP positions on Base
 * @dev Mock implementation - will integrate with real Aerodrome pools
 */
contract AerodromeAdapter is IAdapter, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable idrx;
    address public pool; // IDRX/USDC pool address
    uint256 private _balance;

    // Mock APY for demo (12% annual = ~0.033% daily)
    uint256 public constant MOCK_DAILY_YIELD_BPS = 33;

    event LiquidityAdded(uint256 amount);
    event LiquidityRemoved(uint256 amount);

    constructor(address _idrx, address _pool) Ownable(msg.sender) {
        idrx = IERC20(_idrx);
        pool = _pool;
    }

    function deposit(uint256 amount) external override {
        require(amount > 0, "Amount must be > 0");
        idrx.safeTransferFrom(msg.sender, address(this), amount);
        _balance += amount;
        emit LiquidityAdded(amount);
    }

    function withdraw(uint256 amount) external override {
        require(amount <= _balance, "Insufficient balance");
        _balance -= amount;
        idrx.safeTransfer(msg.sender, amount);
        emit LiquidityRemoved(amount);
    }

    function getBalance() external view override returns (uint256) {
        return _balance;
    }

    function token() external view override returns (address) {
        return address(idrx);
    }

    function accrueYield() external onlyOwner {
        uint256 yield = (_balance * MOCK_DAILY_YIELD_BPS) / 1_000_000;
        _balance += yield;
    }

    function setPool(address _pool) external onlyOwner {
        pool = _pool;
    }
}
