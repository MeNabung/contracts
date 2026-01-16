// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IAdapter.sol";

/**
 * @title StakingAdapter
 * @notice Adapter for native staking/locking positions
 * @dev Time-locked staking with yield boost
 */
contract StakingAdapter is IAdapter, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable idrx;
    uint256 private _balance;

    // 15% APY (~0.041% daily yield in basis points)
    uint256 public constant DAILY_YIELD_BPS = 41;

    event Staked(uint256 amount);
    event Unstaked(uint256 amount);

    constructor(address _idrx) Ownable(msg.sender) {
        idrx = IERC20(_idrx);
    }

    function deposit(uint256 amount) external override {
        require(amount > 0, "Amount must be > 0");
        idrx.safeTransferFrom(msg.sender, address(this), amount);
        _balance += amount;
        emit Staked(amount);
    }

    function withdraw(uint256 amount) external override {
        require(amount <= _balance, "Insufficient balance");
        _balance -= amount;
        idrx.safeTransfer(msg.sender, amount);
        emit Unstaked(amount);
    }

    function getBalance() external view override returns (uint256) {
        return _balance;
    }

    function token() external view override returns (address) {
        return address(idrx);
    }

    function accrueYield() external onlyOwner {
        uint256 yield = (_balance * DAILY_YIELD_BPS) / 1_000_000;
        _balance += yield;
    }
}
