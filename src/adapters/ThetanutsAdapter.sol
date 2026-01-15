// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IAdapter.sol";

/**
 * @title ThetanutsAdapter
 * @notice Adapter for Thetanuts Finance options vaults
 * @dev Mock implementation - will integrate with real Thetanuts V4 RFQ
 */
contract ThetanutsAdapter is IAdapter, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable idrx;
    address public vault;
    uint256 private _balance;

    // Mock APY for demo (8% annual = ~0.022% daily)
    uint256 public constant MOCK_DAILY_YIELD_BPS = 22; // 0.022% in basis points * 100

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);

    constructor(address _idrx, address _vault) Ownable(msg.sender) {
        idrx = IERC20(_idrx);
        vault = _vault;
    }

    function deposit(uint256 amount) external override {
        require(amount > 0, "Amount must be > 0");
        idrx.safeTransferFrom(msg.sender, address(this), amount);
        _balance += amount;
        emit Deposited(amount);
    }

    function withdraw(uint256 amount) external override {
        require(amount <= _balance, "Insufficient balance");
        _balance -= amount;
        idrx.safeTransfer(msg.sender, amount);
        emit Withdrawn(amount);
    }

    function getBalance() external view override returns (uint256) {
        // In production, would query Thetanuts vault for actual position value
        return _balance;
    }

    function token() external view override returns (address) {
        return address(idrx);
    }

    // Mock function to simulate yield accrual (for demo purposes)
    function accrueYield() external onlyOwner {
        uint256 yield = (_balance * MOCK_DAILY_YIELD_BPS) / 1_000_000;
        _balance += yield;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }
}
