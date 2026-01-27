// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MinimalForwarder} from "../src/MinimalForwarder.sol";

contract DeployMinimalForwarder is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey;

        // Get private key with fallback
        try vm.envUint("PRIVATE_KEY") returns (uint256 pk) {
            deployerPrivateKey = pk;
        } catch {
            // Default to hardhat account 0
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            console.log("Warning: PRIVATE_KEY not set, using default account 0");
        }

        vm.startBroadcast(deployerPrivateKey);

        console.log("===========================================");
        console.log("Deploying MinimalForwarder Contract");
        console.log("===========================================");
        console.log();

        // Deploy MinimalForwarder
        console.log("Deploying MinimalForwarder...");
        MinimalForwarder minimalForwarder = new MinimalForwarder();
        console.log("   MinimalForwarder deployed at:", address(minimalForwarder));
        console.log();

        // Verify deployment
        console.log("Verifying deployment...");
        console.log("   Domain Separator:", vm.toString(minimalForwarder.getDomainSeparator()));
        console.log("   Nonces(address(0)):", vm.toString(minimalForwarder.getNonce(address(0))));
        console.log();

        // Output deployment summary
        console.log("===========================================");
        console.log("Deployment Summary");
        console.log("===========================================");
        console.log();
        console.log("Contract Address:");
        console.log("  MinimalForwarder:  ", address(minimalForwarder));
        console.log();
        console.log("Deployer Address: ", msg.sender);
        console.log();

        // Save deployment info
        console.log("===========================================");
        console.log("Next Steps");
        console.log("===========================================");
        console.log();
        console.log("1. Update frontend configuration:");
        console.log("   Update CONTRACT_ADDRESSES.MINIMAL_FORWARDER in platform/lib/contracts.ts");
        console.log("   to:", vm.toString(address(minimalForwarder)));
        console.log();
        console.log("2. Verify contract on Etherscan:");
        console.log("   forge verify-contract", vm.toString(address(minimalForwarder)), "MinimalForwarder");
        console.log();
        console.log("3. Test the contract:");
        console.log("   forge test --match-contract MinimalForwarderTest");
        console.log();

        vm.stopBroadcast();
    }
}
