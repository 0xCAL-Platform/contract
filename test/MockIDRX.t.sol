// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockIDRX} from "../src/MockIDRX.sol";

contract MockIDRXTest is Test {
    MockIDRX public token;
    address public owner = address(0x1);
    address public minter = address(0x2);
    address public pauser = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);

    function setUp() public {
        vm.startPrank(owner);
        token = new MockIDRX();

        // Grant roles
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.PAUSER_ROLE(), pauser);

        vm.stopPrank();

        // Mint tokens to users for testing
        vm.startPrank(minter);
        token.mint(user1, 1000);
        token.mint(user2, 500);
        vm.stopPrank();
    }

    function test_Decimals() public {
        assertEq(token.decimals(), 2);
    }

    function test_Name() public {
        assertEq(token.name(), "Mock IDRX");
    }

    function test_Symbol() public {
        assertEq(token.symbol(), "mIDRX");
    }

    function test_Balance() public {
        assertEq(token.balanceOf(user1), 1000);
        assertEq(token.balanceOf(user2), 500);
    }

    function test_Transfer() public {
        vm.startPrank(user1);
        bool success = token.transfer(user2, 100);
        assertTrue(success);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 900);
        assertEq(token.balanceOf(user2), 600);
    }

    function test_Mint() public {
        vm.startPrank(minter);
        token.mint(user1, 500);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 1500);
        assertEq(token.totalSupply(), 2000);
    }

    function test_Burn() public {
        vm.startPrank(user1);
        token.burn(100);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 900);
        assertEq(token.totalSupply(), 1400);
    }

    function test_Pause() public {
        vm.startPrank(pauser);
        token.pause();
        vm.stopPrank();

        vm.startPrank(user1);
        // Transfer should revert when paused
        try token.transfer(user2, 100) {
            assertTrue(false, "Expected revert but transfer succeeded");
        } catch Error(string memory reason) {
            assertTrue(true, "Transfer reverted as expected");
        } catch {
            assertTrue(true, "Transfer reverted as expected");
        }
        vm.stopPrank();
    }

    function test_Unpause() public {
        // First pause
        vm.startPrank(pauser);
        token.pause();
        token.unpause();
        vm.stopPrank();

        // Should be able to transfer now
        vm.startPrank(user1);
        bool success = token.transfer(user2, 100);
        assertTrue(success);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 900);
        assertEq(token.balanceOf(user2), 600);
    }

    function test_Permit() public {
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address signer = vm.addr(privateKey);

        // Grant allowance to signer
        vm.startPrank(minter);
        token.mint(signer, 1000);
        vm.stopPrank();

        // Create permit signature
        uint256 nonce = token.nonces(signer);
        uint256 deadline = block.timestamp + 1000;

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 permitHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                user1,
                500,
                nonce,
                deadline
            )
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, permitHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        // Use permit
        vm.startPrank(signer);
        token.permit(signer, user1, 500, deadline, v, r, s);
        vm.stopPrank();

        assertEq(token.allowance(signer, user1), 500);
    }

    function test_RoleBasedAccess() public {
        // Non-minter cannot mint
        vm.startPrank(user1);
        vm.expectRevert();
        token.mint(user1, 100);
        vm.stopPrank();

        // Minter can mint
        vm.startPrank(minter);
        token.mint(user1, 100);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 1100);
    }
}
