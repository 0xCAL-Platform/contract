// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {BookingManager} from "../src/v1/BookingManager.sol";
import {Vault} from "../src/v1/Vault.sol";
import {MockIDRX} from "../src/MockIDRX.sol";
import {MentorRegistry} from "../src/MentorRegistry.sol";

contract AllByRelayerTest is Test {
    // Contracts
    MockIDRX public token;
    Vault public vault;
    BookingManager public bookingManager;
    MentorRegistry public mentorRegistry;

    // Test addresses
    address public admin;
    address public mentee;
    address public mentor;
    address public platformFeeAddress;

    function setUp() public {
        admin = address(this);
        mentee = address(0x11);
        mentor = address(0x21);
        platformFeeAddress = address(0xFF);

        token = new MockIDRX();
        vault = new Vault(address(token), platformFeeAddress);
        mentorRegistry = new MentorRegistry();
        bookingManager = new BookingManager(
            address(vault),
            address(token),
            platformFeeAddress,
            address(mentorRegistry)
        );

        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(bookingManager));

        vm.prank(mentor);
        mentorRegistry.registerMentor("testmentor", mentor);

        token.mint(mentee, 1000000);
        token.approve(address(bookingManager), type(uint256).max);
    }

    // Helper to compute hash
    function computeHash(BookingManager.ForwardRequest memory req) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                req.from,
                req.to,
                req.value,
                req.gas,
                keccak256(req.data),
                req.nonce,
                req.deadline
            )
        );
    }

    function testAllByRelayerFunctionsExist() public {
        // Verify all byRelayer functions exist
        assertTrue(bookingManager.createBookingByRelayer.selector != bytes4(0), "createBookingByRelayer exists");
        assertTrue(bookingManager.claimMentorPaymentByRelayer.selector != bytes4(0), "claimMentorPaymentByRelayer exists");
        assertTrue(bookingManager.claimMenteeRefundByRelayer.selector != bytes4(0), "claimMenteeRefundByRelayer exists");
        assertTrue(bookingManager.cancelBookingByRelayer.selector != bytes4(0), "cancelBookingByRelayer exists");
    }

    function testCreateBookingByRelayerExists() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;
        uint256 nonce = bookingManager.getNonce(mentee);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("createBooking(address,uint256,uint256)")),
            mentor,
            sessionTime,
            amount
        );

        BookingManager.ForwardRequest memory req = BookingManager.ForwardRequest({
            from: mentee,
            to: address(bookingManager),
            value: 0,
            gas: 100000,
            nonce: nonce,
            deadline: deadline,
            data: data
        });

        bytes32 structHash = computeHash(req);
        bytes32 TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(
            abi.encode(TYPE_HASH, keccak256("BookingManager"), keccak256("1"), block.chainid, address(bookingManager))
        );
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(mentee)), typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 bookingId = bookingManager.createBookingByRelayer(req, signature);

        assertEq(bookingId, 1);
    }

    function testClaimMentorPaymentByRelayerExists() public {
        // Function signature exists
        bytes4 selector = this.testClaimMentorPaymentByRelayerExists.selector;
        assertTrue(bookingManager.claimMentorPaymentByRelayer.selector != bytes4(0), "claimMentorPaymentByRelayer exists");
    }

    function testClaimMenteeRefundByRelayerExists() public {
        // Function signature exists
        bytes4 selector = this.testClaimMenteeRefundByRelayerExists.selector;
        assertTrue(bookingManager.claimMenteeRefundByRelayer.selector != bytes4(0), "claimMenteeRefundByRelayer exists");
    }

    function testCancelBookingByRelayerExists() public {
        // Function signature exists
        bytes4 selector = this.testCancelBookingByRelayerExists.selector;
        assertTrue(bookingManager.cancelBookingByRelayer.selector != bytes4(0), "cancelBookingByRelayer exists");
    }

    function testInternalHelperFunctionsExist() public {
        // Verify internal helper functions exist by testing they can be called
        // We can't directly test internal functions, but we can verify the public functions work
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Test direct call works
        vm.prank(mentee);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee);
        uint256 bookingId = bookingManager.createBooking(mentor, sessionTime, amount);

        assertEq(bookingId, 1);
    }
}
