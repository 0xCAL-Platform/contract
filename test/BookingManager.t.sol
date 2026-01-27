// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BookingManager} from "../src/BookingManager.sol";
import {Vault} from "../src/Vault.sol";
import {MockIDRX} from "../src/MockIDRX.sol";
import {MentorRegistry} from "../src/MentorRegistry.sol";

contract BookingManagerTest is Test {
    // Contracts
    MockIDRX public token;
    Vault public vault;
    BookingManager public bookingManager;
    MentorRegistry public mentorRegistry;

    // Test addresses
    address public admin;
    address public mentee1;
    address public mentee2;
    address public mentor1;
    address public mentor2;
    address public platformFeeAddress;

    // Events
    event BookingCreated(
        uint256 indexed bookingId,
        address indexed mentee,
        address indexed mentor,
        uint256 sessionTime,
        Vault.BookingType bookingType,
        uint256 amount
    );

    event BookingStatusUpdated(
        uint256 indexed bookingId,
        BookingManager.BookingStatus oldStatus,
        BookingManager.BookingStatus newStatus
    );

    event MentorPaymentReleased(
        uint256 indexed bookingId,
        address indexed mentor,
        uint256 amount
    );

    event MenteeRefundProcessed(
        uint256 indexed bookingId,
        address indexed mentee,
        uint256 amount
    );

    function setUp() public {
        // Setup addresses
        admin = address(this);
        mentee1 = address(0x11);
        mentee2 = address(0x12);
        mentor1 = address(0x21);
        mentor2 = address(0x22);
        platformFeeAddress = address(0xFF);

        // Deploy contracts
        token = new MockIDRX();
        vault = new Vault(address(token), platformFeeAddress);
        mentorRegistry = new MentorRegistry();
        bookingManager = new BookingManager(address(vault), address(token), platformFeeAddress, address(mentorRegistry));

        // Grant BOOKING_MANAGER_ROLE to bookingManager on vault
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(bookingManager));

        // Mint tokens to mentees
        token.mint(mentee1, 1000000); // 10,000.00 tokens (2 decimals)
        token.mint(mentee2, 1000000);

        // Grant roles
        bookingManager.grantRole(bookingManager.PLATFORM_ADMIN_ROLE(), admin);
        bookingManager.grantRole(bookingManager.PLATFORM_ADMIN_ROLE(), address(this));

        // Register mentors in MentorRegistry
        vm.prank(mentor1);
        mentorRegistry.registerMentor("mentor_one", mentor1);

        vm.prank(mentor2);
        mentorRegistry.registerMentor("mentor_two", mentor2);
    }

    // ============ PAID Booking Tests ============

    function testCreatePaidBookingSuccessfully() public {
        uint256 amount = 100000; // 1,000.00 tokens
        uint256 sessionTime = block.timestamp + 1 days;

        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        uint256 bookingId = bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        assertEq(bookingId, 1);

        // Verify booking data
        BookingManager.Booking memory booking = bookingManager.getBooking(bookingId);
        assertEq(booking.id, 1);
        assertEq(booking.mentee, mentee1);
        assertEq(booking.mentor, mentor1);
        assertEq(booking.sessionTime, sessionTime);
        assertEq(booking.amount, amount);
        assertEq(uint256(booking.status), uint256(BookingManager.BookingStatus.Confirmed));
        assertEq(uint256(booking.bookingType), uint256(Vault.BookingType.PAID));
        assertFalse(booking.attendanceConfirmed);
    }

    function testPaidBookingCreatesEscrow() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        // Check escrow in vault
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertEq(escrow.amount, amount);
        assertEq(escrow.mentor, mentor1);
        assertEq(escrow.mentee, mentee1);
        assertEq(uint256(escrow.bookingType), uint256(Vault.BookingType.PAID));
        assertEq(escrow.mentorAmount, amount * 95 / 100);
        assertEq(escrow.platformFee, amount * 5 / 100);
        assertTrue(escrow.active);
        assertFalse(escrow.claimed);
    }

    function testRevertCreateBookingInvalidMentee() public {
        uint256 sessionTime = block.timestamp + 1 days;

        vm.prank(address(0));
        vm.expectRevert(BookingManager.InvalidMentee.selector);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            100000,
            Vault.BookingType.PAID
        );
    }

    function testRevertCreateBookingInvalidMentor() public {
        uint256 sessionTime = block.timestamp + 1 days;

        vm.prank(mentee1);
        token.approve(address(bookingManager), 100000);

        vm.prank(mentee1);
        vm.expectRevert(BookingManager.InvalidMentor.selector);
        bookingManager.createBooking(
            address(0),
            sessionTime,
            100000,
            Vault.BookingType.PAID
        );
    }

    function testRevertCreateBookingZeroAmount() public {
        uint256 sessionTime = block.timestamp + 1 days;

        vm.prank(mentee1);
        vm.expectRevert(BookingManager.InvalidAmount.selector);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            0,
            Vault.BookingType.PAID
        );
    }

    function testRevertCreateBookingPastSessionTime() public {
        uint256 sessionTime = block.timestamp - 1;

        vm.prank(mentee1);
        vm.expectRevert(BookingManager.SessionNotInFuture.selector);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            100000,
            Vault.BookingType.PAID
        );
    }

    function testRevertCreateBookingTooFarFuture() public {
        uint256 sessionTime = block.timestamp + 31 days;

        vm.prank(mentee1);
        vm.expectRevert(BookingManager.SessionTooFar.selector);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            100000,
            Vault.BookingType.PAID
        );
    }

    // ============ COMMITMENT_FEE Booking Tests ============

    function testCreateCommitmentFeeBookingSuccessfully() public {
        uint256 amount = 50000; // 500.00 tokens
        uint256 sessionTime = block.timestamp + 1 days;

        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        uint256 bookingId = bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.COMMITMENT_FEE
        );

        assertEq(bookingId, 1);

        // Verify booking data
        BookingManager.Booking memory booking = bookingManager.getBooking(bookingId);
        assertEq(uint256(booking.bookingType), uint256(Vault.BookingType.COMMITMENT_FEE));
    }

    function testCommitmentFeeBookingEscrowSetup() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.COMMITMENT_FEE
        );

        // Check escrow - initial state for COMMITMENT_FEE
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertEq(escrow.amount, amount);
        assertEq(escrow.mentorAmount, 0); // Not set until no-show
        assertEq(escrow.menteeRefund, 0); // Will be set after attendance confirmation
        assertEq(escrow.platformFee, 0); // Not set until no-show
    }

    // ============ Payment Claim Tests ============

    function testMentorCanClaimPaidBookingAfterTimeLock() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        uint256 mentorBalanceBefore = token.balanceOf(mentor1);

        vm.prank(mentor1);
        bookingManager.claimMentorPayment(1);

        uint256 mentorBalanceAfter = token.balanceOf(mentor1);
        assertEq(mentorBalanceAfter - mentorBalanceBefore, amount * 95 / 100);
    }

    function testRevertMentorClaimTooEarly() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        // Try to claim immediately (before session + 1 hour)
        vm.prank(mentor1);
        vm.expectRevert(Vault.TooEarlyToClaim.selector);
        bookingManager.claimMentorPayment(1);
    }

    function testRevertNonMentorClaim() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // Try to claim from mentee (not mentor)
        vm.prank(mentee1);
        vm.expectRevert(BookingManager.NotMentor.selector);
        bookingManager.claimMentorPayment(1);
    }

    function testRevertDoubleClaim() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // First claim
        vm.prank(mentor1);
        bookingManager.claimMentorPayment(1);

        // Second claim should fail
        vm.prank(mentor1);
        vm.expectRevert(Vault.AlreadyClaimed.selector);
        bookingManager.claimMentorPayment(1);
    }

    // ============ Cancellation Tests ============

    function testMenteeCanCancelBeforeSession() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 2 days; // More than 1 day before

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        uint256 menteeBalanceBefore = token.balanceOf(mentee1);

        // Cancel booking (more than 1 day before - no penalty)
        vm.prank(mentee1);
        bookingManager.cancelBooking(1);

        uint256 menteeBalanceAfter = token.balanceOf(mentee1);
        assertEq(menteeBalanceAfter - menteeBalanceBefore, amount);

        // Verify booking is cancelled
        BookingManager.Booking memory booking = bookingManager.getBooking(1);
        assertEq(uint256(booking.status), uint256(BookingManager.BookingStatus.Cancelled));
    }

    function testRevertCancelAfterSessionStart() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        // Warp to session time
        vm.warp(sessionTime);

        // Try to cancel
        vm.prank(mentee1);
        vm.expectRevert(BookingManager.TooLateToCancel.selector);
        bookingManager.cancelBooking(1);
    }

    function testRevertNonMenteeCancel() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        // Try to cancel from mentor
        vm.prank(mentor1);
        vm.expectRevert(BookingManager.OnlyMenteeCanCancel.selector);
        bookingManager.cancelBooking(1);
    }

    function testCancelEarlyNoPenalty() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 2 days; // 2 days from now

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        uint256 menteeBalanceBefore = token.balanceOf(mentee1);
        uint256 mentorBalanceBefore = token.balanceOf(mentor1);
        uint256 platformBalanceBefore = token.balanceOf(platformFeeAddress);

        // Cancel with 2 days notice (no penalty - more than 1 day)
        vm.prank(mentee1);
        bookingManager.cancelBooking(1);

        uint256 menteeBalanceAfter = token.balanceOf(mentee1);
        uint256 mentorBalanceAfter = token.balanceOf(mentor1);
        uint256 platformBalanceAfter = token.balanceOf(platformFeeAddress);

        // Mentee gets full refund
        assertEq(menteeBalanceAfter - menteeBalanceBefore, amount);
        // Mentor gets nothing
        assertEq(mentorBalanceAfter - mentorBalanceBefore, 0);
        // Platform gets nothing
        assertEq(platformBalanceAfter - platformBalanceBefore, 0);

        // Verify booking is cancelled
        BookingManager.Booking memory booking = bookingManager.getBooking(1);
        assertEq(uint256(booking.status), uint256(BookingManager.BookingStatus.Cancelled));
    }

    function testCancelLateWithPenalty() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 12 hours; // 12 hours from now (within 1 day - penalty applies)

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        uint256 menteeBalanceBefore = token.balanceOf(mentee1);
        uint256 mentorBalanceBefore = token.balanceOf(mentor1);
        uint256 platformBalanceBefore = token.balanceOf(platformFeeAddress);

        // Cancel with 12 hours notice (penalty applies - within 1 day)
        vm.prank(mentee1);
        bookingManager.cancelBooking(1);

        uint256 menteeBalanceAfter = token.balanceOf(mentee1);
        uint256 mentorBalanceAfter = token.balanceOf(mentor1);
        uint256 platformBalanceAfter = token.balanceOf(platformFeeAddress);

        // Mentee gets 80%
        assertEq(menteeBalanceAfter - menteeBalanceBefore, (amount * 80) / 100);
        // Mentor gets 15%
        assertEq(mentorBalanceAfter - mentorBalanceBefore, (amount * 15) / 100);
        // Platform gets 5%
        assertEq(platformBalanceAfter - platformBalanceBefore, (amount * 5) / 100);

        // Verify booking is cancelled
        BookingManager.Booking memory booking = bookingManager.getBooking(1);
        assertEq(uint256(booking.status), uint256(BookingManager.BookingStatus.Cancelled));
    }

    // ============ COMMITMENT_FEE Refund Tests ============

    function testMenteeCanRefundAfterAttendanceConfirmed() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.COMMITMENT_FEE
        );

        // Confirm attendance
        bookingManager.confirmAttendance(1, true);

        uint256 menteeBalanceBefore = token.balanceOf(mentee1);

        vm.prank(mentee1);
        bookingManager.claimMenteeRefund(1);

        uint256 menteeBalanceAfter = token.balanceOf(mentee1);
        assertEq(menteeBalanceAfter - menteeBalanceBefore, amount);
    }

    function testRevertRefundBeforeAttendanceConfirmed() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.COMMITMENT_FEE
        );

        // Try to refund before attendance confirmed
        vm.prank(mentee1);
        vm.expectRevert(BookingManager.AttendanceNotConfirmed.selector);
        bookingManager.claimMenteeRefund(1);
    }

    function testRevertNonMenteeRefund() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.COMMITMENT_FEE
        );

        // Confirm attendance
        bookingManager.confirmAttendance(1, true);

        // Try to refund from mentor
        vm.prank(mentor1);
        vm.expectRevert(BookingManager.NotMentee.selector);
        bookingManager.claimMenteeRefund(1);
    }

    // ============ Platform Fee Tests ============

    function testPlatformCanClaimFeeAfterMentorClaim() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // Mentor claims
        vm.prank(mentor1);
        bookingManager.claimMentorPayment(1);

        uint256 platformBalanceBefore = token.balanceOf(platformFeeAddress);

        // Platform claims fee (via vault)
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vault.claimPlatformFee(1);

        uint256 platformBalanceAfter = token.balanceOf(platformFeeAddress);
        assertEq(platformBalanceAfter - platformBalanceBefore, amount * 5 / 100);
    }

    // ============ Emergency Functions Tests ============

    function testPlatformCanUpdateStatusEmergency() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        // Emergency update status
        bookingManager.emergencyUpdateStatus(
            1,
            BookingManager.BookingStatus.Completed
        );

        BookingManager.Booking memory booking = bookingManager.getBooking(1);
        assertEq(uint256(booking.status), uint256(BookingManager.BookingStatus.Completed));
    }

    function testRevertEmergencyUpdateNonAdmin() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        // Try to update from non-admin
        vm.prank(mentee1);
        vm.expectRevert();
        bookingManager.emergencyUpdateStatus(
            1,
            BookingManager.BookingStatus.Completed
        );
    }

    // ============ View Function Tests ============

    function testGetNonce() public {
        // Initial nonce should be 0
        assertEq(bookingManager.getNonce(mentee1), 0);

        // Create booking (increments nonce)
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        assertEq(bookingManager.getNonce(mentee1), 0);
    }

    function testGetBooking() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        BookingManager.Booking memory booking = bookingManager.getBooking(1);
        assertEq(booking.id, 1);
        assertEq(booking.mentee, mentee1);
        assertEq(booking.mentor, mentor1);
    }

    // ============ Integration Tests ============

    function testEndToEndPaidBookingFlow() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // 1. Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        uint256 bookingId = bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.PAID
        );

        assertEq(bookingId, 1);

        // 2. Session occurs
        vm.warp(sessionTime);

        // 3. Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // 4. Mentor claims
        vm.prank(mentor1);
        bookingManager.claimMentorPayment(1);

        // 5. Platform claims fee (via vault)
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vault.claimPlatformFee(1);

        // Verify final state
        BookingManager.Booking memory booking = bookingManager.getBooking(1);
        assertEq(uint256(booking.status), uint256(BookingManager.BookingStatus.Completed));

        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertTrue(escrow.claimed);
    }

    function testEndToEndCommitmentFeeAttendedFlow() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // 1. Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.COMMITMENT_FEE
        );

        // 2. Session occurs
        vm.warp(sessionTime);

        // 3. Confirm attendance
        bookingManager.confirmAttendance(1, true);

        // 4. Mentee claims refund
        vm.prank(mentee1);
        bookingManager.claimMenteeRefund(1);

        // Verify final state
        BookingManager.Booking memory booking = bookingManager.getBooking(1);
        assertTrue(booking.attendanceConfirmed);
        assertEq(uint256(booking.status), uint256(BookingManager.BookingStatus.Completed));

        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertTrue(escrow.claimed);
    }

    function testEndToEndCommitmentFeeNoShowFlow() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // 1. Create booking
        vm.prank(mentee1);
        token.approve(address(bookingManager), amount);

        vm.prank(mentee1);
        bookingManager.createBooking(
            mentor1,
            sessionTime,
            amount,
            Vault.BookingType.COMMITMENT_FEE
        );

        // 2. Session occurs
        vm.warp(sessionTime);

        // 3. No attendance (no-show)
        bookingManager.confirmAttendance(1, false);

        // 4. Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // 5. Mentor claims (90%)
        vm.prank(mentor1);
        bookingManager.claimMentorPayment(1);

        // 6. Platform claims fee (10%) (via vault)
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vault.claimPlatformFee(1);

        // Verify final state
        BookingManager.Booking memory booking = bookingManager.getBooking(1);
        assertFalse(booking.attendanceConfirmed);
        assertEq(uint256(booking.status), uint256(BookingManager.BookingStatus.NoShow));

        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertTrue(escrow.claimed);
    }
}
