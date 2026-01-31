// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockIDRX} from "../src/MockIDRX.sol";
import {BookingManager} from "../src/BookingManager.sol";
import {MentorRegistry} from "../src/MentorRegistry.sol";

contract DeployBookingSystem is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey;
        address tokenAddress;
        bool useExistingToken = false;

        // Get private key with fallback
        try vm.envUint("PRIVATE_KEY") returns (uint256 pk) {
            deployerPrivateKey = pk;
        } catch {
            // Default to hardhat account 0
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            console.log("Warning: PRIVATE_KEY not set, using default account 0");
        }

        // Check if using existing token
        try vm.envAddress("TOKEN_ADDRESS") returns (address existingToken) {
            tokenAddress = existingToken;
            useExistingToken = true;
            console.log("Using existing token at:", vm.toString(tokenAddress));
        } catch {
            useExistingToken = false;
        }

        vm.startBroadcast(deployerPrivateKey);

        console.log("===========================================");
        console.log("Deploying OneCal Booking System");
        console.log("===========================================");
        console.log();

        MockIDRX token;

        // 1. Deploy or use existing token
        if (useExistingToken) {
            console.log("1. Using existing token at:", vm.toString(tokenAddress));
            token = MockIDRX(tokenAddress);
            console.log("   Token Name:", token.name());
            console.log("   Token Symbol:", token.symbol());
            console.log("   Token Decimals:", token.decimals());
            console.log();
        } else {
            console.log("1. Deploying MockIDRX token...");
            token = new MockIDRX();
            tokenAddress = address(token);
            console.log("   MockIDRX deployed at:", vm.toString(tokenAddress));
            console.log("   Token Name:", token.name());
            console.log("   Token Symbol:", token.symbol());
            console.log("   Token Decimals:", token.decimals());
            console.log();
        }

        // 2. Deploy BookingManager contract
        console.log("2. Deploying BookingManager contract...");
        BookingManager bookingManager = new BookingManager(tokenAddress);
        console.log("   BookingManager deployed at:", vm.toString(address(bookingManager)));
        console.log("   Payment Token:", vm.toString(address(bookingManager.PAYMENT_TOKEN())));
        console.log("   Owner:", vm.toString(address(bookingManager.OWNER())));
        console.log();

        // 3. Mint initial tokens for testing (optional, only for new token)
        bool shouldMint = false;
        if (!useExistingToken) {
            try vm.envBool("MINT_TEST_TOKENS") {
                shouldMint = vm.envBool("MINT_TEST_TOKENS");
            } catch {
                shouldMint = false;
            }

            if (shouldMint) {
                console.log("3. Minting test tokens...");
                uint256 mintAmount = 100000000; // 1,000,000.00 tokens
                token.mint(msg.sender, mintAmount);
                console.log("   Minted ", vm.toString(mintAmount), " tokens to deployer");
                console.log("   Deployer balance:", vm.toString(token.balanceOf(msg.sender)));
                console.log();
            }
        }

        // 4. Output deployment summary
        console.log("===========================================");
        console.log("Deployment Summary");
        console.log("===========================================");
        console.log();
        console.log("Contract Addresses:");
        if (!useExistingToken) {
            console.log("  MockIDRX:       ", vm.toString(tokenAddress));
        }
        console.log("  BookingManager: ", vm.toString(address(bookingManager)));
        console.log();
        console.log("Configuration:");
        console.log("  Payment Token: ", vm.toString(tokenAddress));
        console.log("  Owner:         ", vm.toString(address(bookingManager.OWNER())));
        console.log();

        // 5. Save deployment info
        console.log("===========================================");
        console.log("Next Steps");
        console.log("===========================================");
        console.log();
        console.log("1. Verify contracts on Etherscan:");
        if (!useExistingToken) {
            console.log("   forge verify-contract", vm.toString(tokenAddress), "MockIDRX");
        }
        console.log("   forge verify-contract", vm.toString(address(bookingManager)), "BookingManager --constructor-args");
        console.log(vm.toString(tokenAddress));
        console.log();
        console.log("2. Update frontend configuration with new addresses");
        console.log();
        console.log("3. Run integration tests:");
        console.log("   forge test --match-contract BookingManagerTest");
        console.log("   forge test --match-contract MetaTransactionTest");
        console.log();
        console.log("4. Deploy to testnet/mainnet with:");
        console.log("   forge script script/DeployBookingSystem.s.sol --rpc-url $RPC_URL --broadcast");
        console.log();

        vm.stopBroadcast();
    }
}
