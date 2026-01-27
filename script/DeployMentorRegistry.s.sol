// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MentorRegistry} from "../src/MentorRegistry.sol";

contract DeployMentorRegistry is Script {
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
        console.log("Deploying MentorRegistry Contract");
        console.log("===========================================");
        console.log();

        // Deploy MentorRegistry
        console.log("Deploying MentorRegistry...");
        MentorRegistry mentorRegistry = new MentorRegistry();
        console.log("   MentorRegistry deployed at:", address(mentorRegistry));
        console.log();

        // Verify deployment
        console.log("Verifying deployment...");
        console.log("   TypeHash ADDRESS_UPDATE_TYPEHASH:", vm.toString(mentorRegistry.ADDRESS_UPDATE_TYPEHASH()));
        console.log("   TypeHash MENTOR_REGISTER_TYPEHASH:", vm.toString(mentorRegistry.MENTOR_REGISTER_TYPEHASH()));
        console.log();

        // Output deployment summary
        console.log("===========================================");
        console.log("Deployment Summary");
        console.log("===========================================");
        console.log();
        console.log("Contract Address:");
        console.log("  MentorRegistry:  ", address(mentorRegistry));
        console.log();
        console.log("Deployer Address: ", msg.sender);
        console.log();

        // Save deployment info
        console.log("===========================================");
        console.log("Next Steps");
        console.log("===========================================");
        console.log();
        console.log("1. Update frontend configuration:");
        console.log("   Update CONTRACT_ADDRESSES.MENTOR_REGISTRY in platform/lib/contracts.ts");
        console.log("   to:", vm.toString(address(mentorRegistry)));
        console.log();
        console.log("2. Verify contract on Etherscan:");
        console.log("   forge verify-contract", vm.toString(address(mentorRegistry)), "MentorRegistry");
        console.log();
        console.log("3. Test the contract:");
        console.log("   forge test --match-contract MentorRegistryTest");
        console.log();

        vm.stopBroadcast();
    }
}
