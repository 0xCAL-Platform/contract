// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {BookingManager} from "../src/v1/BookingManager.sol";
import {Vault} from "../src/v1/Vault.sol";
import {MockIDRX} from "../src/MockIDRX.sol";
import {MentorRegistry} from "../src/MentorRegistry.sol";

contract SimplifiedBookingTest is Test {
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
        // Setup addresses
        admin = address(this);
        mentee = address(0x11);
        mentor = address(0x21);
        platformFeeAddress = address(0xFF);

        // Deploy contracts
        token = new MockIDRX();
        vault = new Vault(address(token), platformFeeAddress);
        mentorRegistry = new MentorRegistry();
        bookingManager = new BookingManager(
            address(vault),
            address(token),
            platformFeeAddress,
            address(mentorRegistry)
        );

        // Grant roles
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(bookingManager));

        // Add mentor to registry
        vm.prank(mentor);
        mentorRegistry.registerMentor("testmentor", mentor);

        // Mint tokens
        token.mint(mentee, 1000000);
        token.mint(admin, 1000000);

        // Approve booking manager to spend tokens
        token.approve(address(bookingManager), type(uint256).max);
    }

    function testCreateCommitmentFeeBooking() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Mentee must approve booking manager first
        vm.prank(mentee);
        token.approve(address(bookingManager), amount);

        // Create booking (must be called from mentee)
        vm.prank(mentee);
        uint256 bookingId = bookingManager.createBooking(
            mentor,
            sessionTime,
            amount
        );

        assertEq(bookingId, 1);

        // Verify booking data
        BookingManager.Booking memory booking = bookingManager.getBooking(bookingId);
        assertEq(booking.id, 1);
        assertEq(booking.mentee, mentee);
        assertEq(booking.mentor, mentor);
        assertEq(booking.sessionTime, sessionTime);
        assertEq(booking.amount, amount);
        assertEq(uint256(booking.status), uint256(BookingManager.BookingStatus.Confirmed));
        assertFalse(booking.attendanceConfirmed);
    }

    function testCommitmentFeeBookingCreatesEscrow() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Mentee must approve booking manager first
        vm.prank(mentee);
        token.approve(address(bookingManager), amount);

        // Create booking (must be called from mentee)
        vm.prank(mentee);
        bookingManager.createBooking(
            mentor,
            sessionTime,
            amount
        );

        // Check escrow in vault
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertEq(escrow.amount, amount);
        assertEq(escrow.mentor, mentor);
        assertEq(escrow.mentee, mentee);
        assertEq(escrow.mentorAmount, 0);
        assertEq(escrow.platformFee, 0);
        assertEq(escrow.menteeRefund, 0);
        assertTrue(escrow.active);
        assertFalse(escrow.claimed);
    }

    function testUpdateMenteeRefundAfterAttendance() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Mentee must approve booking manager first
        vm.prank(mentee);
        token.approve(address(bookingManager), amount);

        // Create booking (must be called from mentee)
        vm.prank(mentee);
        bookingManager.createBooking(
            mentor,
            sessionTime,
            amount
        );

        // Update refund amount (simulating attendance confirmation)
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, amount);

        // Check updated escrow
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertEq(escrow.menteeRefund, amount);
    }

    function testUpdateMentorAmountAfterNoShow() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Mentee must approve booking manager first
        vm.prank(mentee);
        token.approve(address(bookingManager), amount);

        // Create booking (must be called from mentee)
        vm.prank(mentee);
        bookingManager.createBooking(
            mentor,
            sessionTime,
            amount
        );

        // Update mentor amount (simulating no-show)
        // IMPORTANT: Must reset menteeRefund to 0 first
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, 0);
        vault.updateMentorAmount(1, amount * 90 / 100);

        // Check updated escrow
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertEq(escrow.mentorAmount, amount * 90 / 100);
        assertEq(escrow.platformFee, amount * 10 / 100);
    }
}
