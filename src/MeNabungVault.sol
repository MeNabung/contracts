// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IAdapter.sol";

/**
 * @title MeNabungVault
 * @notice Main vault that splits deposits across multiple yield strategies
 * @dev AI recommends allocations, vault executes the splits automatically
 */
contract MeNabungVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    IERC20 public immutable idrx;
    
    // Strategy adapters
    IAdapter public thetanutsAdapter;  // Options vault
    IAdapter public aerodromeAdapter;  // LP positions
    IAdapter public stakingAdapter;    // Native staking

    // User data
    struct UserPosition {
        uint256 totalDeposited;
        uint256 optionsAllocation;    // Percentage (0-100)
        uint256 lpAllocation;         // Percentage (0-100)
        uint256 stakingAllocation;    // Percentage (0-100)
        uint256 lastUpdateTime;
    }
    
    mapping(address => UserPosition) public positions;
    
    // ============ Events ============
    
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event StrategySet(address indexed user, uint256 options, uint256 lp, uint256 staking);
    event Rebalanced(address indexed user);
    event PartialRebalance(
        address indexed user,
        address indexed fromAdapter,
        address indexed toAdapter,
        uint256 amount
    );

    // ============ Constructor ============

    constructor(
        address _idrx,
        address _thetanutsAdapter,
        address _aerodromeAdapter,
        address _stakingAdapter
    ) Ownable(msg.sender) {
        idrx = IERC20(_idrx);
        thetanutsAdapter = IAdapter(_thetanutsAdapter);
        aerodromeAdapter = IAdapter(_aerodromeAdapter);
        stakingAdapter = IAdapter(_stakingAdapter);
    }

    // ============ External Functions ============

    /**
     * @notice Deposit IDRX and automatically split according to strategy
     * @param amount Amount of IDRX to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        
        UserPosition storage pos = positions[msg.sender];
        
        // If no strategy set, use default balanced (40/40/20)
        if (pos.optionsAllocation == 0 && pos.lpAllocation == 0 && pos.stakingAllocation == 0) {
            pos.optionsAllocation = 40;
            pos.lpAllocation = 40;
            pos.stakingAllocation = 20;
        }
        
        // Transfer IDRX from user
        idrx.safeTransferFrom(msg.sender, address(this), amount);
        pos.totalDeposited += amount;
        pos.lastUpdateTime = block.timestamp;
        
        // Split and deposit to adapters
        _splitAndDeposit(amount, pos);
        
        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Set strategy allocation percentages
     * @param optionsPercent Percentage for Thetanuts options (0-100)
     * @param lpPercent Percentage for Aerodrome LP (0-100)
     * @param stakingPercent Percentage for staking (0-100)
     */
    function setStrategy(
        uint256 optionsPercent,
        uint256 lpPercent,
        uint256 stakingPercent
    ) external {
        require(
            optionsPercent + lpPercent + stakingPercent == 100,
            "Allocations must sum to 100"
        );
        
        UserPosition storage pos = positions[msg.sender];
        pos.optionsAllocation = optionsPercent;
        pos.lpAllocation = lpPercent;
        pos.stakingAllocation = stakingPercent;
        
        emit StrategySet(msg.sender, optionsPercent, lpPercent, stakingPercent);
    }

    /**
     * @notice Withdraw all positions proportionally
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        UserPosition storage pos = positions[msg.sender];
        require(pos.totalDeposited >= amount, "Insufficient balance");
        
        uint256 totalBalance = getUserTotalBalance(msg.sender);
        require(totalBalance >= amount, "Insufficient total balance");
        
        // Calculate proportional withdrawals from each adapter
        uint256 optionsBalance = thetanutsAdapter.getBalance();
        uint256 lpBalance = aerodromeAdapter.getBalance();
        uint256 stakingBalance = stakingAdapter.getBalance();
        
        if (optionsBalance > 0) {
            uint256 optionsWithdraw = (amount * pos.optionsAllocation) / 100;
            if (optionsWithdraw > 0) {
                thetanutsAdapter.withdraw(optionsWithdraw);
            }
        }
        
        if (lpBalance > 0) {
            uint256 lpWithdraw = (amount * pos.lpAllocation) / 100;
            if (lpWithdraw > 0) {
                aerodromeAdapter.withdraw(lpWithdraw);
            }
        }
        
        if (stakingBalance > 0) {
            uint256 stakingWithdraw = (amount * pos.stakingAllocation) / 100;
            if (stakingWithdraw > 0) {
                stakingAdapter.withdraw(stakingWithdraw);
            }
        }
        
        pos.totalDeposited -= amount;
        idrx.safeTransfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Rebalance positions to match current strategy
     */
    function rebalance() external nonReentrant {
        UserPosition storage pos = positions[msg.sender];
        require(pos.totalDeposited > 0, "No position to rebalance");

        // Withdraw all from adapters
        uint256 optionsBalance = thetanutsAdapter.getBalance();
        uint256 lpBalance = aerodromeAdapter.getBalance();
        uint256 stakingBalance = stakingAdapter.getBalance();

        if (optionsBalance > 0) thetanutsAdapter.withdraw(optionsBalance);
        if (lpBalance > 0) aerodromeAdapter.withdraw(lpBalance);
        if (stakingBalance > 0) stakingAdapter.withdraw(stakingBalance);

        uint256 totalToRebalance = optionsBalance + lpBalance + stakingBalance;

        // Re-split according to current strategy
        _splitAndDeposit(totalToRebalance, pos);

        emit Rebalanced(msg.sender);
    }

    /**
     * @notice Partially rebalance by moving funds between two specific strategies
     * @dev This is used by the AI rebalancing agent to optimize yields
     * @param fromAdapter The adapter to withdraw from
     * @param toAdapter The adapter to deposit into
     * @param amount The amount to move
     */
    function rebalancePartial(
        address fromAdapter,
        address toAdapter,
        uint256 amount
    ) external nonReentrant {
        UserPosition storage pos = positions[msg.sender];
        require(pos.totalDeposited > 0, "No position to rebalance");
        require(fromAdapter != toAdapter, "Same adapter");
        require(amount > 0, "Amount must be > 0");

        // Validate adapters
        require(
            fromAdapter == address(thetanutsAdapter) ||
            fromAdapter == address(aerodromeAdapter) ||
            fromAdapter == address(stakingAdapter),
            "Invalid from adapter"
        );
        require(
            toAdapter == address(thetanutsAdapter) ||
            toAdapter == address(aerodromeAdapter) ||
            toAdapter == address(stakingAdapter),
            "Invalid to adapter"
        );

        // Withdraw from source adapter
        IAdapter(fromAdapter).withdraw(amount);

        // Approve and deposit to target adapter
        idrx.approve(toAdapter, amount);
        IAdapter(toAdapter).deposit(amount);

        // Update allocation percentages based on actual amounts
        _updateAllocationsAfterPartialRebalance(pos, fromAdapter, toAdapter, amount);

        pos.lastUpdateTime = block.timestamp;

        emit PartialRebalance(msg.sender, fromAdapter, toAdapter, amount);
    }

    /**
     * @notice Rebalance with a new strategy in one transaction
     * @dev Combines setStrategy and rebalance for gas efficiency
     * @param optionsPercent New options allocation percentage
     * @param lpPercent New LP allocation percentage
     * @param stakingPercent New staking allocation percentage
     */
    function rebalanceWithNewStrategy(
        uint256 optionsPercent,
        uint256 lpPercent,
        uint256 stakingPercent
    ) external nonReentrant {
        require(
            optionsPercent + lpPercent + stakingPercent == 100,
            "Allocations must sum to 100"
        );

        UserPosition storage pos = positions[msg.sender];
        require(pos.totalDeposited > 0, "No position to rebalance");

        // Update strategy
        pos.optionsAllocation = optionsPercent;
        pos.lpAllocation = lpPercent;
        pos.stakingAllocation = stakingPercent;

        // Withdraw all from adapters
        uint256 optionsBalance = thetanutsAdapter.getBalance();
        uint256 lpBalance = aerodromeAdapter.getBalance();
        uint256 stakingBalance = stakingAdapter.getBalance();

        if (optionsBalance > 0) thetanutsAdapter.withdraw(optionsBalance);
        if (lpBalance > 0) aerodromeAdapter.withdraw(lpBalance);
        if (stakingBalance > 0) stakingAdapter.withdraw(stakingBalance);

        uint256 totalToRebalance = optionsBalance + lpBalance + stakingBalance;

        // Re-split according to new strategy
        _splitAndDeposit(totalToRebalance, pos);

        pos.lastUpdateTime = block.timestamp;

        emit StrategySet(msg.sender, optionsPercent, lpPercent, stakingPercent);
        emit Rebalanced(msg.sender);
    }

    // ============ View Functions ============

    /**
     * @notice Get user's total balance across all strategies
     * @param user User address
     * @return Total balance in IDRX terms
     */
    function getUserTotalBalance(address user) public view returns (uint256) {
        UserPosition memory pos = positions[user];
        if (pos.totalDeposited == 0) return 0;
        
        // Sum balances from all adapters (simplified - in production would be more accurate)
        return thetanutsAdapter.getBalance() + 
               aerodromeAdapter.getBalance() + 
               stakingAdapter.getBalance();
    }

    /**
     * @notice Get user's position details
     * @param user User address
     * @return totalDeposited Total amount deposited
     * @return optionsAlloc Options allocation percentage
     * @return lpAlloc LP allocation percentage  
     * @return stakingAlloc Staking allocation percentage
     */
    function getUserPosition(address user) external view returns (
        uint256 totalDeposited,
        uint256 optionsAlloc,
        uint256 lpAlloc,
        uint256 stakingAlloc
    ) {
        UserPosition memory pos = positions[user];
        return (
            pos.totalDeposited,
            pos.optionsAllocation,
            pos.lpAllocation,
            pos.stakingAllocation
        );
    }

    /**
     * @notice Get breakdown of user's positions by strategy
     * @param user User address
     * @return optionsValue Value in options strategy
     * @return lpValue Value in LP strategy
     * @return stakingValue Value in staking strategy
     */
    function getPositionBreakdown(address user) external view returns (
        uint256 optionsValue,
        uint256 lpValue,
        uint256 stakingValue
    ) {
        UserPosition memory pos = positions[user];
        if (pos.totalDeposited == 0) return (0, 0, 0);
        
        // Return adapter balances (simplified)
        return (
            thetanutsAdapter.getBalance(),
            aerodromeAdapter.getBalance(),
            stakingAdapter.getBalance()
        );
    }

    // ============ Internal Functions ============

    function _splitAndDeposit(uint256 amount, UserPosition memory pos) internal {
        uint256 optionsAmount = (amount * pos.optionsAllocation) / 100;
        uint256 lpAmount = (amount * pos.lpAllocation) / 100;
        uint256 stakingAmount = amount - optionsAmount - lpAmount; // Remainder to staking

        // Approve and deposit to each adapter
        if (optionsAmount > 0) {
            idrx.approve(address(thetanutsAdapter), optionsAmount);
            thetanutsAdapter.deposit(optionsAmount);
        }

        if (lpAmount > 0) {
            idrx.approve(address(aerodromeAdapter), lpAmount);
            aerodromeAdapter.deposit(lpAmount);
        }

        if (stakingAmount > 0) {
            idrx.approve(address(stakingAdapter), stakingAmount);
            stakingAdapter.deposit(stakingAmount);
        }
    }

    /**
     * @notice Update user allocation percentages after a partial rebalance
     * @dev Recalculates percentages based on new adapter balances
     */
    function _updateAllocationsAfterPartialRebalance(
        UserPosition storage pos,
        address fromAdapter,
        address toAdapter,
        uint256 amount
    ) internal {
        // Get total balance across all adapters
        uint256 optionsBalance = thetanutsAdapter.getBalance();
        uint256 lpBalance = aerodromeAdapter.getBalance();
        uint256 stakingBalance = stakingAdapter.getBalance();
        uint256 totalBalance = optionsBalance + lpBalance + stakingBalance;

        if (totalBalance == 0) return;

        // Calculate new percentages based on actual balances
        pos.optionsAllocation = (optionsBalance * 100) / totalBalance;
        pos.lpAllocation = (lpBalance * 100) / totalBalance;
        // Ensure percentages sum to 100 by assigning remainder to staking
        pos.stakingAllocation = 100 - pos.optionsAllocation - pos.lpAllocation;
    }

    // ============ Admin Functions ============

    function updateAdapters(
        address _thetanuts,
        address _aerodrome,
        address _staking
    ) external onlyOwner {
        if (_thetanuts != address(0)) thetanutsAdapter = IAdapter(_thetanuts);
        if (_aerodrome != address(0)) aerodromeAdapter = IAdapter(_aerodrome);
        if (_staking != address(0)) stakingAdapter = IAdapter(_staking);
    }
}
