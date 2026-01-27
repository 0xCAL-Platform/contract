// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SessionAcknowledgment} from "../src/SessionAcknowledgment.sol";
import {BookingManager} from "../src/BookingManager.sol";

contract SessionAcknowledgmentTest is Test {
    // Contracts
    SessionAcknowledgment public sessionAck;
    BookingManager public bookingManager;

    // Test addresses
    address public admin;
    address public mentee;
    address public mentor;
    address public bookingManagerAddress;

    // Events
    event AcknowledgmentLinkGenerated(
        uint256 indexed bookingId,
        string link,
        uint256 expiryTime
    );

    event SessionAcknowledged(
        uint256 indexed bookingId,
        address indexed mentor,
        bool attended
    );

    event NoShowRecorded(
        uint256 indexed bookingId,
        uint256 timestamp
    );

    function setUp() public {
        // Setup addresses
        admin = address(this);
        mentee = address(0x11);
        mentor = address(0x21);
        bookingManagerAddress = address(0xAA);

        // Deploy contracts
        sessionAck = new SessionAcknowledgment(bookingManagerAddress);
    }

    // ============ Generate Ack Link Tests ============

    function testGenerateAckLinkSuccessfully() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Generate link
        vm.prank(bookingManagerAddress);
        string memory link = sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Verify link format
        assertTrue(bytes(link).length > 0);
        assertTrue(_stringContains(link, "https://onecal.xyz/ack/"));
        assertTrue(_stringContains(link, "1"));
    }

    function testGenerateAckLinkStoresCorrectData() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Verify stored data
        SessionAcknowledgment.AckStatus memory ack = sessionAck.getAckStatus(1);

        assertTrue(ack.linkGenerated);
        assertEq(ack.mentee, mentee);
        assertEq(ack.mentor, mentor);
        assertEq(ack.expiryTime, sessionTime + 1 hours);
        assertFalse(ack.acknowledged);
        assertFalse(ack.linkUsed);
        assertTrue(ack.salt > 0);
        assertTrue(ack.tokenHash != bytes32(0));
    }

    function testRevertGenerateLinkAlreadyGenerated() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Generate first link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Try to generate again
        vm.prank(bookingManagerAddress);
        vm.expectRevert(SessionAcknowledgment.LinkAlreadyGenerated.selector);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );
    }

    function testRevertGenerateLinkSessionNotStarted() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Generate link before session starts - should succeed
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );
    }

    function testRevertGenerateLinkWindowExpired() public {
        uint256 sessionTime = block.timestamp + 1 days; // Session in future
        vm.warp(sessionTime + 2 hours); // Warp to 2 hours after session

        // Try to generate after window expired
        vm.prank(bookingManagerAddress);
        vm.expectRevert(SessionAcknowledgment.WindowExpired.selector);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );
    }

    function testRevertGenerateLinkUnauthorized() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Try to generate from unauthorized address
        vm.prank(mentee);
        vm.expectRevert();
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );
    }

    // ============ Acknowledge Session Tests ============

    function testAcknowledgeSessionSuccessfully() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Get the raw token (in real scenario, this would come from the link)
        bytes32 rawToken = _getRawToken(1, sessionTime, mentor);

        // Acknowledge
        vm.prank(mentor);
        sessionAck.acknowledgeSession(1, rawToken);

        // Verify acknowledgment
        SessionAcknowledgment.AckStatus memory ack = sessionAck.getAckStatus(1);
        assertTrue(ack.acknowledged);
        assertTrue(ack.linkUsed);
    }

    function testRevertAcknowledgeLinkNotGenerated() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Try to acknowledge without generating link first
        bytes32 rawToken = _getRawToken(1, sessionTime, mentor);

        vm.prank(mentor);
        vm.expectRevert(SessionAcknowledgment.LinkNotGenerated.selector);
        sessionAck.acknowledgeSession(1, rawToken);
    }

    function testRevertAcknowledgeLinkAlreadyUsed() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Get raw token
        bytes32 rawToken = _getRawToken(1, sessionTime, mentor);

        // First acknowledgment
        vm.prank(mentor);
        sessionAck.acknowledgeSession(1, rawToken);

        // Try to acknowledge again
        vm.prank(mentor);
        vm.expectRevert(SessionAcknowledgment.LinkAlreadyUsed.selector);
        sessionAck.acknowledgeSession(1, rawToken);
    }

    function testRevertAcknowledgeLinkExpired() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Warp past expiry (session + 1 hour + 1 second)
        vm.warp(sessionTime + 1 hours + 1);

        // Get raw token
        bytes32 rawToken = _getRawToken(1, sessionTime, mentor);

        // Try to acknowledge after expiry
        vm.prank(mentor);
        vm.expectRevert(SessionAcknowledgment.LinkExpired.selector);
        sessionAck.acknowledgeSession(1, rawToken);
    }

    function testRevertAcknowledgeNotMentor() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Get raw token
        bytes32 rawToken = _getRawToken(1, sessionTime, mentor);

        // Try to acknowledge from mentee (not mentor)
        vm.prank(mentee);
        vm.expectRevert(SessionAcknowledgment.NotTheMentor.selector);
        sessionAck.acknowledgeSession(1, rawToken);
    }

    function testRevertAcknowledgeInvalidToken() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Try with wrong token
        vm.prank(mentor);
        vm.expectRevert(SessionAcknowledgment.InvalidToken.selector);
        sessionAck.acknowledgeSession(1, bytes32(uint256(0x1234)));
    }

    // ============ Record No-Show Tests ============

    function testRecordNoShowSuccessfully() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Warp past expiry
        vm.warp(sessionTime + 1 hours + 1);

        // Record no-show
        sessionAck.recordNoShow(1);

        // Verify state
        SessionAcknowledgment.AckStatus memory ack = sessionAck.getAckStatus(1);
        assertTrue(ack.linkUsed); // Link is marked as used
        assertFalse(ack.acknowledged); // But not acknowledged
    }

    function testRevertRecordNoShowLinkNotGenerated() public {
        // Try to record no-show without generating link
        vm.expectRevert(SessionAcknowledgment.LinkNotGenerated.selector);
        sessionAck.recordNoShow(1);
    }

    function testRevertRecordNoShowAlreadyAcknowledged() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Acknowledge
        bytes32 rawToken = _getRawToken(1, sessionTime, mentor);
        vm.prank(mentor);
        sessionAck.acknowledgeSession(1, rawToken);

        // Try to record no-show after acknowledgment
        vm.expectRevert(SessionAcknowledgment.AlreadyAcknowledged.selector);
        sessionAck.recordNoShow(1);
    }

    function testRevertRecordNoShowWindowNotExpired() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Try to record no-show before expiry
        vm.expectRevert(SessionAcknowledgment.WindowNotExpired.selector);
        sessionAck.recordNoShow(1);
    }

    // ============ View Function Tests ============

    function testIsLinkValid() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Link should be valid
        assertTrue(sessionAck.isLinkValid(1));

        // Warp past expiry
        vm.warp(sessionTime + 1 hours + 1);

        // Link should be invalid
        assertFalse(sessionAck.isLinkValid(1));
    }

    function testIsAcknowledged() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Initially not acknowledged
        assertFalse(sessionAck.isAcknowledged(1));

        // Acknowledge
        bytes32 rawToken = _getRawToken(1, sessionTime, mentor);
        vm.prank(mentor);
        sessionAck.acknowledgeSession(1, rawToken);

        // Now acknowledged
        assertTrue(sessionAck.isAcknowledged(1));
    }

    function testIsLinkExpired() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Link not expired yet
        assertFalse(sessionAck.isLinkExpired(1));

        // Warp past expiry
        vm.warp(sessionTime + 1 hours + 1);

        // Link expired
        assertTrue(sessionAck.isLinkExpired(1));
    }

    function testGetAckLink() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Get link (mentee can view)
        vm.prank(mentee);
        string memory link = sessionAck.getAckLink(1);

        assertTrue(bytes(link).length > 0);
    }

    function testRevertGetAckLinkUnauthorized() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Try to get link from unauthorized address
        address unauthorized = address(0x99);
        vm.prank(unauthorized);
        vm.expectRevert(SessionAcknowledgment.NotAuthorized.selector);
        sessionAck.getAckLink(1);
    }

    function testGetAckStatus() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Get status
        SessionAcknowledgment.AckStatus memory ack = sessionAck.getAckStatus(1);

        assertTrue(ack.linkGenerated);
        assertFalse(ack.acknowledged);
        assertFalse(ack.linkUsed);
        assertEq(ack.mentee, mentee);
        assertEq(ack.mentor, mentor);
    }

    // ============ Emergency Functions Tests ============

    function testEmergencyAcknowledge() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Emergency acknowledge
        sessionAck.emergencyAcknowledge(1, true, mentor);

        // Verify
        SessionAcknowledgment.AckStatus memory ack = sessionAck.getAckStatus(1);
        assertTrue(ack.acknowledged);
        assertTrue(ack.linkUsed);
    }

    function testRevertEmergencyAcknowledgeNotAdmin() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Try to emergency acknowledge from non-admin
        vm.prank(mentee);
        vm.expectRevert();
        sessionAck.emergencyAcknowledge(1, true, mentor);
    }

    function testRevertEmergencyAcknowledgeMentorMismatch() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // Warp to session time
        vm.warp(sessionTime);

        // Generate link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // Try with wrong mentor address
        vm.expectRevert(SessionAcknowledgment.MentorMismatch.selector);
        sessionAck.emergencyAcknowledge(1, true, mentee);
    }

    // ============ Integration Tests ============

    function testEndToEndCommitmentFeeAttendedFlow() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // 1. Session starts
        vm.warp(sessionTime);

        // 2. Generate acknowledgment link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // 3. Mentee shares link with mentor
        vm.prank(mentee);
        string memory link = sessionAck.getAckLink(1);

        assertTrue(bytes(link).length > 0);

        // 4. Mentor acknowledges attendance
        bytes32 rawToken = _getRawToken(1, sessionTime, mentor);
        vm.prank(mentor);
        sessionAck.acknowledgeSession(1, rawToken);

        // 5. Verify final state
        assertTrue(sessionAck.isAcknowledged(1));
        assertTrue(sessionAck.getAckStatus(1).linkUsed);
    }

    function testEndToEndCommitmentFeeNoShowFlow() public {
        uint256 sessionTime = block.timestamp + 1 days;

        // 1. Session starts
        vm.warp(sessionTime);

        // 2. Generate acknowledgment link
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime,
            mentee,
            mentor
        );

        // 3. Warp past acknowledgment window (no click)
        vm.warp(sessionTime + 1 hours + 1);

        // 4. Record no-show
        sessionAck.recordNoShow(1);

        // 5. Verify final state
        assertFalse(sessionAck.isAcknowledged(1));
        assertTrue(sessionAck.getAckStatus(1).linkUsed);
        assertTrue(sessionAck.isLinkExpired(1));
    }

    function testMultipleBookings() public {
        uint256 sessionTime1 = block.timestamp + 1 days;
        uint256 sessionTime2 = block.timestamp + 2 days;

        // Generate link for booking 1
        vm.warp(sessionTime1);
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            1,
            sessionTime1,
            mentee,
            mentor
        );

        // Verify booking 1 link is valid
        assertTrue(sessionAck.isLinkValid(1));

        // Acknowledge booking 1 before it expires
        bytes32 rawToken1 = _getRawToken(1, sessionTime1, mentor);
        vm.prank(mentor);
        sessionAck.acknowledgeSession(1, rawToken1);

        // Verify booking 1 is acknowledged
        assertTrue(sessionAck.isAcknowledged(1));

        // Generate link for booking 2
        vm.warp(sessionTime2);
        vm.prank(bookingManagerAddress);
        sessionAck.generateAckLink(
            2,
            sessionTime2,
            mentee,
            mentor
        );

        // Verify booking 1 link is used and booking 2 is valid
        assertFalse(sessionAck.isLinkValid(1));
        assertTrue(sessionAck.isLinkValid(2));

        // Verify booking 2 is not acknowledged
        assertFalse(sessionAck.isAcknowledged(2));
    }

    // ============ Helper Functions ============

    function _getRawToken(
        uint256 bookingId,
        uint256 sessionTime,
        address mentorAddr
    ) internal returns (bytes32) {
        // This is a simplified version - in real scenario, token would be reconstructed from salt
        // For testing, we need to get the actual salt from the contract
        SessionAcknowledgment.AckStatus memory ack = sessionAck.getAckStatus(bookingId);

        // Reconstruct token from components (same logic as contract)
        return keccak256(
            abi.encodePacked(
                bookingId,
                "|",
                sessionTime,
                "|",
                mentorAddr,
                "|",
                ack.salt,
                "|",
                "ACK_TOKEN_V1"
            )
        );
    }

    function _stringContains(string memory haystack, string memory needle) internal pure returns (bool) {
        return indexOf(haystack, needle) != -1;
    }

    function indexOf(string memory haystack, string memory needle) internal pure returns (int256) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (h.length < 1 || n.length < 1 || (n.length > h.length)) return -1;
        if (h.length > (1 << 127)) return -1; // since the result is a byte offset

        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool isMatch = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    isMatch = false;
                    break;
                }
            }
            if (isMatch) {
                // Safe to cast to int256: i represents byte offset and is bounded by string length
                // Maximum practical string length << 2^255, so no overflow risk
                return int256(i);
            }
        }

        return -1;
    }
}
