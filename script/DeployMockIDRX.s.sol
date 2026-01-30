// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockIDRX} from "../src/MockIDRX.sol";

contract DeployMockIDRX is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the MockIDRX contract
        MockIDRX mockIdrx = new MockIDRX();

        // Optional: Mint initial supply to deployer
        // mockIDRX.mint(msg.sender, 1000000); // 1,000,000 tokens (with 2 decimals)

        vm.stopBroadcast();

        console.log("MockIDRX deployed at:", address(mockIdrx));
        console.log("Token Name:", mockIdrx.name());
        console.log("Token Symbol:", mockIdrx.symbol());
        console.log("Token Decimals:", mockIdrx.decimals());
    }
}
