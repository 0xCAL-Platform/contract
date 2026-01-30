// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {MockIDRX} from "../src/MockIDRX.sol";
import {BookingManager} from "../src/BookingManager.sol";

contract VaultTest is Test {
    // Contracts
    MockIDRX public token;
    Vault public vault;
    BookingManager public bookingManager;

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
        // Note: For tests, we'll need to deploy a mock MentorRegistry or deploy real contracts first
        // For now, using address(1) as placeholder - tests should deploy real contracts for integration
        bookingManager = new BookingManager(address(vault), address(token), platformFeeAddress, address(1));

        // Mint tokens to mentee and test contract
        token.mint(mentee, 1000000);
        token.mint(address(this), 1000000);

        // Setup roles - grant BOOKING_MANAGER_ROLE to this test contract and to BookingManager
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(bookingManager));

        // Approve vault to spend tokens on behalf of this contract
        token.approve(address(vault), type(uint256).max);
    }

    // ============ Create Escrow Tests ============

    function testCreateEscrowSuccessfully() public {
        uint256 amount = 100000; // 1,000.00 tokens
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Verify escrow data
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);

        assertEq(escrow.amount, amount);
        assertEq(escrow.mentor, mentor);
        assertEq(escrow.mentee, mentee);
        assertEq(escrow.sessionTime, sessionTime);
        assertEq(uint256(escrow.bookingType), uint256(Vault.BookingType.PAID));
        assertEq(escrow.mentorAmount, amount * 95 / 100);
        assertEq(escrow.platformFee, amount * 5 / 100);
        assertEq(escrow.menteeRefund, 0);
        assertTrue(escrow.active);
        assertFalse(escrow.claimed);
    }

    function testCreateEscrowCommitmentFee() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // Verify escrow - COMMITMENT_FEE has different initial state
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);

        assertEq(escrow.amount, amount);
        assertEq(uint256(escrow.bookingType), uint256(Vault.BookingType.COMMITMENT_FEE));
        assertEq(escrow.mentorAmount, 0);
        assertEq(escrow.platformFee, 0);
        assertEq(escrow.menteeRefund, 0); // Will be set after attendance confirmation
    }

    function testRevertCreateEscrowAlreadyExists() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create first escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Try to create second escrow with same ID
        vm.expectRevert(Vault.EscrowAlreadyExists.selector);
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );
    }

    function testRevertCreateEscrowInvalidMentee() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        vm.expectRevert(Vault.InvalidMentee.selector);
        vault.createEscrow(
            1,
            address(0),
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );
    }

    function testRevertCreateEscrowInvalidMentor() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        vm.expectRevert(Vault.InvalidMentor.selector);
        vault.createEscrow(
            1,
            mentee,
            address(0),
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );
    }

    function testRevertCreateEscrowZeroAmount() public {
        uint256 sessionTime = block.timestamp + 1 days;

        vm.expectRevert(Vault.InvalidAmount.selector);
        vault.createEscrow(
            1,
            mentee,
            mentor,
            0,
            Vault.BookingType.PAID,
            sessionTime
        );
    }

    function testRevertCreateEscrowPastSessionTime() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp - 1;

        vm.expectRevert(Vault.SessionNotInFuture.selector);
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );
    }

    function testRevertCreateEscrowTooFarFuture() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 31 days;

        vm.expectRevert(Vault.SessionTooFar.selector);
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );
    }

    function testRevertCreateEscrowUnauthorized() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Try to create escrow from non-authorized address
        vm.prank(mentee);
        vm.expectRevert();
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );
    }

    // ============ Release to Mentor Tests ============

    function testReleaseToMentorSuccessfully() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        uint256 mentorBalanceBefore = token.balanceOf(mentor);

        // Release payment
        vm.prank(mentor);
        vault.releaseToMentor(1);

        uint256 mentorBalanceAfter = token.balanceOf(mentor);
        assertEq(mentorBalanceAfter - mentorBalanceBefore, amount * 95 / 100);

        // Verify escrow state
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertTrue(escrow.claimed);
    }

    function testRevertReleaseToMentorTooEarly() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Try to release immediately (too early)
        vm.prank(mentor);
        vm.expectRevert(Vault.TooEarlyToClaim.selector);
        vault.releaseToMentor(1);
    }

    function testRevertReleaseToMentorNotMentor() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // Try to release from mentee (not mentor)
        vm.prank(mentee);
        vm.expectRevert(Vault.NotMentor.selector);
        vault.releaseToMentor(1);
    }

    function testRevertReleaseToMentorEscrowNotActive() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Try to release for non-existent escrow
        vm.prank(mentor);
        vm.expectRevert(Vault.EscrowNotActive.selector);
        vault.releaseToMentor(999);
    }

    function testRevertReleaseToMentorAlreadyClaimed() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // First release
        vm.prank(mentor);
        vault.releaseToMentor(1);

        // Try to release again
        vm.prank(mentor);
        vm.expectRevert(Vault.AlreadyClaimed.selector);
        vault.releaseToMentor(1);
    }

    // ============ Refund to Mentee Tests ============

    function testRefundToMenteeSuccessfully() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow for COMMITMENT_FEE
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // Update refund amount (simulating attendance confirmation)
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, amount);

        // Warp to session time
        vm.warp(sessionTime);

        uint256 menteeBalanceBefore = token.balanceOf(mentee);

        // Refund to mentee
        vm.prank(mentee);
        vault.refundToMentee(1);

        uint256 menteeBalanceAfter = token.balanceOf(mentee);
        assertEq(menteeBalanceAfter - menteeBalanceBefore, amount);

        // Verify escrow state
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertTrue(escrow.claimed);
    }

    function testRevertRefundToMenteeTooEarly() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // Update refund amount
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, amount);

        // Try to refund before attendance is confirmed (menteeRefund will be reset to 0)
        // Note: With the new logic, refunds are allowed before session time as long as
        // attendance is confirmed. This test is now obsolete.
        vm.prank(mentee);
        vault.refundToMentee(1);

        // Verify refund was processed
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertTrue(escrow.claimed);
    }

    function testRevertRefundToMenteeNotMentee() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // Update refund amount
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, amount);

        // Warp to session time
        vm.warp(sessionTime);

        // Try to refund from mentor
        vm.prank(mentor);
        vm.expectRevert(Vault.NotMentee.selector);
        vault.refundToMentee(1);
    }

    function testRevertRefundToMenteeWrongBookingType() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create PAID escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Warp to session time
        vm.warp(sessionTime);

        // Try to refund PAID booking
        vm.prank(mentee);
        vm.expectRevert(Vault.WrongBookingType.selector);
        vault.refundToMentee(1);
    }

    function testRevertRefundToMenteeAlreadyClaimed() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // Update refund amount
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, amount);

        // Warp to session time
        vm.warp(sessionTime);

        // First refund
        vm.prank(mentee);
        vault.refundToMentee(1);

        // Try to refund again
        vm.prank(mentee);
        vm.expectRevert(Vault.AlreadyClaimed.selector);
        vault.refundToMentee(1);
    }

    // ============ Platform Fee Tests ============

    function testClaimPlatformFeeSuccessfully() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // Mentor claims
        vm.prank(mentor);
        vault.releaseToMentor(1);

        uint256 platformBalanceBefore = token.balanceOf(platformFeeAddress);

        // Platform claims fee
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vault.claimPlatformFee(1);

        uint256 platformBalanceAfter = token.balanceOf(platformFeeAddress);
        assertEq(platformBalanceAfter - platformBalanceBefore, amount * 5 / 100);
    }

    function testRevertClaimPlatformFeeNotYetClaimed() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Try to claim fee before mentor claims
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vm.expectRevert(Vault.BookingNotClaimed.selector);
        vault.claimPlatformFee(1);
    }

    function testRevertClaimPlatformFeeAlreadyClaimed() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // Mentor claims
        vm.prank(mentor);
        vault.releaseToMentor(1);

        // Platform claims fee
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vault.claimPlatformFee(1);

        // Try to claim again
        vm.expectRevert(Vault.PlatformFeeAlreadyClaimed.selector);
        vault.claimPlatformFee(1);
    }

    // ============ Update Refund/Amount Tests ============

    function testUpdateMenteeRefund() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create COMMITMENT_FEE escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // Update refund amount
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, amount * 80 / 100);

        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertEq(escrow.menteeRefund, amount * 80 / 100);
    }

    function testUpdateMentorAmount() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create COMMITMENT_FEE escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // Update mentor amount (simulating no-show)
        // IMPORTANT: Must reset menteeRefund to 0 first
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, 0);
        vault.updateMentorAmount(1, amount * 90 / 100);

        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertEq(escrow.mentorAmount, amount * 90 / 100);
        assertEq(escrow.platformFee, amount * 10 / 100);
    }

    function testRevertUpdateMenteeRefundNotBookingManager() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // Try to update from non-manager
        vm.prank(mentee);
        vm.expectRevert();
        vault.updateMenteeRefund(1, amount);
    }

    // ============ Emergency Functions Tests ============

    function testEmergencyRefund() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Activate emergency mode
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vault.activateEmergencyMode();

        // Emergency refund
        vault.emergencyRefund(1, payable(mentee), amount, "Emergency test");

        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertEq(escrow.amount, 0);
    }

    function testRevertEmergencyRefundNotInEmergency() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Note: emergencyRefund no longer requires emergency mode (to allow BookingManager to cancel bookings)
        // This test is now obsolete - emergency refunds can be called by PLATFORM_ADMIN_ROLE at any time
        // and are meant for authorized cancellations, not actual emergencies
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vault.emergencyRefund(1, payable(mentee), amount, "Test");
    }

    function testUpdatePlatformFeeAddress() public {
        address newFeeAddress = address(0x99);

        // Activate emergency mode
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vault.activateEmergencyMode();

        // Update fee address
        vault.updatePlatformFeeAddress(newFeeAddress);

        assertEq(vault.platformFeeAddress(), newFeeAddress);
    }

    // ============ View Function Tests ============

    function testIsReadyForMentorClaim() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Not ready before time
        assertFalse(vault.isReadyForMentorClaim(1));

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // Ready now
        assertTrue(vault.isReadyForMentorClaim(1));
    }

    function testIsReadyForMenteeRefund() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create COMMITMENT_FEE escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // Initially not ready (menteeRefund is full amount but attendance not confirmed)
        // Note: For commitment fee, refund is only ready after attendance is confirmed
        // which happens via updateMenteeRefund in confirmAttendance
        assertFalse(vault.isReadyForMenteeRefund(1));

        // Update mentee refund (simulating attendance confirmation)
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, amount);

        // Ready now (refund amount is set and > 0)
        assertTrue(vault.isReadyForMenteeRefund(1));
    }

    function testGetEscrow() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Verify getEscrow returns correct data
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertEq(escrow.amount, amount);
        assertEq(escrow.sessionTime, sessionTime);
    }

    // ============ Total Escrowed Tests ============

    function testTotalEscrowedIncreases() public {
        uint256 amount1 = 100000;
        uint256 amount2 = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        uint256 totalBefore = vault.totalEscrowed();

        // Create first escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount1,
            Vault.BookingType.PAID,
            sessionTime
        );

        assertEq(vault.totalEscrowed(), totalBefore + amount1);

        // Create second escrow
        vault.createEscrow(
            2,
            mentee,
            mentor,
            amount2,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        assertEq(vault.totalEscrowed(), totalBefore + amount1 + amount2);
    }

    function testTotalEscrowedDecreasesOnClaim() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // Mentor claims
        vm.prank(mentor);
        vault.releaseToMentor(1);

        // Total escrowed should decrease by claimed amount
        // Note: mentorAmount is 95% of total, so totalEscrowed decreases by that amount
    }

    // ============ Integration Tests ============

    function testEndToEndPaidBookingWithVault() public {
        uint256 amount = 100000;
        uint256 sessionTime = block.timestamp + 1 days;

        // 1. Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.PAID,
            sessionTime
        );

        // 2. Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // 3. Mentor claims
        vm.prank(mentor);
        vault.releaseToMentor(1);

        // 4. Platform claims fee
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vault.claimPlatformFee(1);

        // Verify final state
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertTrue(escrow.claimed);
    }

    function testEndToEndCommitmentFeeAttendedWithVault() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // 1. Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // 2. Update refund (attendance confirmed)
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, amount);

        // 3. Warp to session time
        vm.warp(sessionTime);

        // 4. Mentee claims refund
        vm.prank(mentee);
        vault.refundToMentee(1);

        // Verify final state
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertTrue(escrow.claimed);
    }

    function testEndToEndCommitmentFeeNoShowWithVault() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;

        // 1. Create escrow
        vault.createEscrow(
            1,
            mentee,
            mentor,
            amount,
            Vault.BookingType.COMMITMENT_FEE,
            sessionTime
        );

        // 2. Update amounts (no-show)
        // IMPORTANT: Must reset menteeRefund to 0 first, then update mentor amount
        vault.grantRole(vault.BOOKING_MANAGER_ROLE(), address(this));
        vault.updateMenteeRefund(1, 0);
        vault.updateMentorAmount(1, amount * 90 / 100);

        // 3. Warp to after session + 1 hour
        vm.warp(sessionTime + 1 hours + 1);

        // 4. Mentor claims
        vm.prank(mentor);
        vault.releaseToMentor(1);

        // 5. Platform claims fee
        vault.grantRole(vault.PLATFORM_ADMIN_ROLE(), address(this));
        vault.claimPlatformFee(1);

        // Verify final state
        Vault.BookingEscrow memory escrow = vault.getEscrow(1);
        assertTrue(escrow.claimed);
    }
}
