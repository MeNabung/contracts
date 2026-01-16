// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MeNabungVault.sol";
import "../src/adapters/ThetanutsAdapter.sol";
import "../src/adapters/AerodromeAdapter.sol";
import "../src/adapters/StakingAdapter.sol";

/**
 * @title Deploy
 * @notice Deployment script for MeNabung contracts on Base mainnet
 * @dev Run with: forge script script/Deploy.s.sol --rpc-url base --broadcast --verify
 */
contract Deploy is Script {
    // IDRX Token on Base Mainnet
    address constant IDRX = 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22;

    // Placeholder addresses for external protocols (mock implementations)
    // In production, these would be real Thetanuts and Aerodrome addresses
    address constant THETANUTS_VAULT = address(0); // Mock - not used in adapter
    address constant AERODROME_POOL = address(0);  // Mock - not used in adapter

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying MeNabung contracts to Base mainnet...");
        console.log("Deployer address:", deployer);
        console.log("IDRX address:", IDRX);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Staking Adapter (simplest - only needs IDRX)
        StakingAdapter stakingAdapter = new StakingAdapter(IDRX);
        console.log("StakingAdapter deployed at:", address(stakingAdapter));

        // 2. Deploy Thetanuts Adapter
        ThetanutsAdapter thetanutsAdapter = new ThetanutsAdapter(IDRX, THETANUTS_VAULT);
        console.log("ThetanutsAdapter deployed at:", address(thetanutsAdapter));

        // 3. Deploy Aerodrome Adapter
        AerodromeAdapter aerodromeAdapter = new AerodromeAdapter(IDRX, AERODROME_POOL);
        console.log("AerodromeAdapter deployed at:", address(aerodromeAdapter));

        // 4. Deploy Main Vault with all adapters
        MeNabungVault vault = new MeNabungVault(
            IDRX,
            address(thetanutsAdapter),
            address(aerodromeAdapter),
            address(stakingAdapter)
        );
        console.log("MeNabungVault deployed at:", address(vault));

        vm.stopBroadcast();

        // Output deployment summary
        console.log("");
        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Contract Addresses (save these!):");
        console.log("  IDRX:              ", IDRX);
        console.log("  StakingAdapter:    ", address(stakingAdapter));
        console.log("  ThetanutsAdapter:  ", address(thetanutsAdapter));
        console.log("  AerodromeAdapter:  ", address(aerodromeAdapter));
        console.log("  MeNabungVault:     ", address(vault));
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify contracts on BaseScan");
        console.log("2. Update frontend addresses.ts with deployed addresses");
        console.log("3. Test deposit/withdraw flow");
    }
}
