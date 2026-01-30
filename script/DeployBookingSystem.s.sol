// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockIDRX} from "../src/MockIDRX.sol";
import {Vault} from "../src/Vault.sol";
import {BookingManager} from "../src/BookingManager.sol";
import {SessionAcknowledgment} from "../src/SessionAcknowledgment.sol";
import {MentorRegistry} from "../src/MentorRegistry.sol";

contract DeployBookingSystem is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey;
        address platformFeeAddress;
        address mentorRegistryAddress;

        // Get private key with fallback
        try vm.envUint("PRIVATE_KEY") returns (uint256 pk) {
            deployerPrivateKey = pk;
        } catch {
            // Default to hardhat account 0
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            console.log("Warning: PRIVATE_KEY not set, using default account 0");
        }

        // Get platform fee address with fallback
        try vm.envAddress("PLATFORM_FEE_ADDRESS") returns (address feeAddr) {
            platformFeeAddress = feeAddr;
        } catch {
            // Default to deployer address
            platformFeeAddress = address(uint160(uint256(deployerPrivateKey)));
            console.log("Warning: PLATFORM_FEE_ADDRESS not set, using deployer address");
        }

        // Get MentorRegistry address
        try vm.envAddress("MENTOR_REGISTRY_ADDRESS") returns (address mrAddr) {
            mentorRegistryAddress = mrAddr;
        } catch {
            revert("MENTOR_REGISTRY_ADDRESS not set. Please deploy MentorRegistry first.");
        }

        vm.startBroadcast(deployerPrivateKey);

        console.log("===========================================");
        console.log("Deploying OneCal Booking System");
        console.log("===========================================");
        console.log();

        // 1. Deploy MockIDRX token if not already deployed
        console.log("1. Deploying MockIDRX token...");
        MockIDRX token = new MockIDRX();
        console.log("   MockIDRX deployed at:", address(token));
        console.log("   Token Name:", token.name());
        console.log("   Token Symbol:", token.symbol());
        console.log("   Token Decimals:", token.decimals());
        console.log();

        // 2. Deploy Vault contract
        console.log("2. Deploying Vault contract...");
        Vault vault = new Vault(address(token), platformFeeAddress);
        console.log("   Vault deployed at:", address(vault));
        console.log("   Payment Token:", vm.toString(address(vault.paymentToken())));
        console.log("   Platform Fee Address:", vm.toString(vault.platformFeeAddress()));
        console.log("   Platform Fee (PAID):", vm.toString(vault.PLATFORM_FEE_PERCENT_PAID()));
        console.log("   Platform Fee (COMMITMENT_FEE no-show):", vm.toString(vault.PLATFORM_FEE_PERCENT_COMMIT()));
        console.log();

        // 3. Deploy BookingManager contract
        console.log("3. Deploying BookingManager contract...");
        BookingManager bookingManager = new BookingManager(
            address(vault),
            address(token),
            platformFeeAddress,
            mentorRegistryAddress
        );
        console.log("   BookingManager deployed at:", address(bookingManager));
        console.log("   Vault:", vm.toString(address(bookingManager.VAULT())));
        console.log("   Payment Token:", vm.toString(address(bookingManager.PAYMENT_TOKEN())));
        console.log("   Platform Fee Address:", vm.toString(bookingManager.PLATFORM_FEE_ADDRESS()));
        console.log("   Mentor Registry:", vm.toString(bookingManager.MENTOR_REGISTRY()));
        console.log();

        // 4. Deploy SessionAcknowledgment contract
        console.log("4. Deploying SessionAcknowledgment contract...");
        SessionAcknowledgment sessionAck = new SessionAcknowledgment(
            address(bookingManager)
        );
        console.log("   SessionAcknowledgment deployed at:", address(sessionAck));
        console.log("   Booking Manager:", vm.toString(address(sessionAck.bookingManager())));
        console.log();

        // 5. Verify contract connections
        console.log("5. Verifying contract connections...");
        bool hasManagerRole = vault.hasRole(vault.BOOKING_MANAGER_ROLE(), address(bookingManager));
        bool hasSessionAckRole = sessionAck.hasRole(sessionAck.BOOKING_MANAGER_ROLE(), address(bookingManager));
        console.log("   Vault has BOOKING_MANAGER_ROLE for BookingManager:", hasManagerRole);
        console.log("   SessionAck has BOOKING_MANAGER_ROLE for BookingManager:", hasSessionAckRole);
        console.log();

        // 6. Setup roles and permissions
        console.log("6. Setting up roles and permissions...");

        // Grant platform admin role to deployer
        bookingManager.grantRole(bookingManager.PLATFORM_ADMIN_ROLE(), msg.sender);
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), msg.sender);
        sessionAck.grantRole(sessionAck.DEFAULT_ADMIN_ROLE(), msg.sender);

        console.log("   Granted PLATFORM_ADMIN_ROLE to deployer in BookingManager");
        console.log("   Granted PLATFORM_ADMIN_ROLE to deployer in Vault");
        console.log("   Granted DEFAULT_ADMIN_ROLE to deployer in SessionAcknowledgment");
        console.log();

        // 7. Mint initial tokens for testing (optional)
        bool shouldMint = false;
        try vm.envBool("MINT_TEST_TOKENS") {
            shouldMint = vm.envBool("MINT_TEST_TOKENS");
        } catch {
            shouldMint = false;
        }

        if (shouldMint) {
            console.log("7. Minting test tokens...");
            uint256 mintAmount = 100000000; // 1,000,000.00 tokens
            token.mint(msg.sender, mintAmount);
            console.log("   Minted ", vm.toString(mintAmount), " tokens to deployer");
            console.log("   Deployer balance:", vm.toString(token.balanceOf(msg.sender)));
            console.log();
        }

        // 8. Output deployment summary
        console.log("===========================================");
        console.log("Deployment Summary");
        console.log("===========================================");
        console.log();
        console.log("Contract Addresses:");
        console.log("  MockIDRX:          ", address(token));
        console.log("  Vault:             ", address(vault));
        console.log("  BookingManager:    ", address(bookingManager));
        console.log("  SessionAck:        ", address(sessionAck));
        console.log();
        console.log("Configuration:");
        console.log("  Platform Fee Address: ", platformFeeAddress);
        console.log();
        console.log("Roles:");
        console.log("  BookingManager Admin:      ", msg.sender);
        console.log("  Vault Admin:               ", msg.sender);
        console.log("  SessionAcknowledgment Admin: ", msg.sender);
        console.log();

        // 9. Save deployment info
        console.log("===========================================");
        console.log("Next Steps");
        console.log("===========================================");
        console.log();
        console.log("1. Verify contracts on Etherscan:");
        console.log("   forge verify-contract", vm.toString(address(token)), "MockIDRX");
        console.log("   forge verify-contract", vm.toString(address(vault)), "Vault --constructor-args");
        console.log(vm.toString(address(token)), vm.toString(platformFeeAddress));
        console.log("   forge verify-contract", vm.toString(address(bookingManager)), "BookingManager --constructor-args");
        console.log(vm.toString(address(vault)), vm.toString(address(token)), vm.toString(platformFeeAddress));
        console.log("   forge verify-contract", vm.toString(address(sessionAck)), "SessionAcknowledgment --constructor-args");
        console.log(vm.toString(address(bookingManager)));
        console.log();
        console.log("2. Update frontend configuration with new addresses");
        console.log();
        console.log("3. Run integration tests:");
        console.log("   forge test --match-contract BookingManagerTest");
        console.log("   forge test --match-contract VaultTest");
        console.log("   forge test --match-contract SessionAcknowledgmentTest");
        console.log();
        console.log("4. Deploy to testnet/mainnet with:");
        console.log("   forge script script/DeployBookingSystem.s.sol --rpc-url $RPC_URL --broadcast");
        console.log();

        vm.stopBroadcast();
    }
}
