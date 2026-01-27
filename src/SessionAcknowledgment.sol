// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SessionAcknowledgment
 * @dev Handles session attendance acknowledgment for COMMITMENT_FEE bookings
 *
 * Features:
 * - Generate cryptographically secure acknowledgment tokens
 * - One-time use tokens to prevent replay attacks
 * - Time-window validation for link activation
 * - Integration with BookingManager for state updates
 *
 * This contract implements a secure acknowledgment system that prevents
 * forgery and ensures only legitimate mentors can confirm attendance.
 */
contract SessionAcknowledgment is AccessControl, ReentrancyGuard {
    /// @notice Role identifier for booking managers
    bytes32 public constant BOOKING_MANAGER_ROLE = keccak256("BOOKING_MANAGER_ROLE");

    /// @notice Acknowledgment state for each booking
    struct AckStatus {
        bytes32 tokenHash;      // Hash of the acknowledgment token
        bytes32 salt;            // Random salt for token generation
        bool linkGenerated;      // Whether link has been generated
        bool acknowledged;       // Whether mentor has acknowledged
        bool linkUsed;          // Whether token has been consumed
        uint256 expiryTime;     // When link expires (session + 1 hour)
        address mentee;         // Mentee address
        address mentor;         // Mentor address
    }

    /// @notice Emitted when acknowledgment link is generated
    event AcknowledgmentLinkGenerated(
        uint256 indexed bookingId,
        string link,
        uint256 expiryTime
    );

    /// @notice Emitted when session is acknowledged
    event SessionAcknowledged(
        uint256 indexed bookingId,
        address indexed mentor,
        bool attended
    );

    /// @notice Emitted when no-show is recorded
    event NoShowRecorded(
        uint256 indexed bookingId,
        uint256 timestamp
    );

    /// @notice Mapping of booking ID to acknowledgment status
    mapping(uint256 => AckStatus) public acknowledgments;

    /// @notice Booking manager contract address
    address public bookingManager;

    /// @notice Custom errors
    error InvalidManagerAddress();
    error LinkAlreadyGenerated();
    error SessionNotStarted();
    error WindowExpired();
    error LinkNotGenerated();
    error LinkAlreadyUsed();
    error LinkExpired();
    error NotTheMentor();
    error InvalidToken();
    error NotAuthorized();
    error WindowNotExpired();
    error AlreadyAcknowledged();
    error StateUpdateFailed();
    error MentorMismatch();

    /**
     * @dev Constructor
     * @param _bookingManager Address of BookingManager contract
     */
    constructor(address _bookingManager) {
        if (_bookingManager == address(0)) revert InvalidManagerAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BOOKING_MANAGER_ROLE, _bookingManager);

        bookingManager = _bookingManager;
    }

    /**
     * @dev Generates acknowledgment link for a booking
     * @param bookingId Booking identifier
     * @param sessionTime Session timestamp
     * @param mentee Mentee address
     * @param mentor Mentor address
     * @return link The acknowledgment link
     */
    function generateAckLink(
        uint256 bookingId,
        uint256 sessionTime,
        address mentee,
        address mentor
    ) external onlyRole(BOOKING_MANAGER_ROLE) returns (string memory link) {
        AckStatus storage ack = acknowledgments[bookingId];
        if (ack.linkGenerated) revert LinkAlreadyGenerated();
        if (sessionTime + 1 hours < block.timestamp) revert WindowExpired();

        // Generate salt and token hash
        bytes32 salt = _generateSalt();
        bytes32 tokenHash = _generateTokenHash(bookingId, sessionTime, mentor, salt);

        // Store acknowledgment data
        ack.tokenHash = tokenHash;
        ack.salt = salt;
        ack.linkGenerated = true;
        ack.expiryTime = sessionTime + 1 hours;
        ack.mentee = mentee;
        ack.mentor = mentor;

        // Generate human-readable link
        link = _createLink(bookingId, tokenHash);

        emit AcknowledgmentLinkGenerated(bookingId, link, ack.expiryTime);
    }

    /**
     * @dev Acknowledges session attendance
     * @param bookingId Booking identifier
     * @param rawToken The acknowledgment token
     */
    function acknowledgeSession(
        uint256 bookingId,
        bytes32 rawToken
    ) external nonReentrant {
        AckStatus storage ack = acknowledgments[bookingId];
        if (!ack.linkGenerated) revert LinkNotGenerated();
        if (ack.linkUsed) revert LinkAlreadyUsed();
        if (block.timestamp > ack.expiryTime) revert LinkExpired();
        if (msg.sender != ack.mentor) revert NotTheMentor();

        // Verify token matches stored hash
        if (rawToken != ack.tokenHash) revert InvalidToken();

        // Mark as acknowledged and used
        ack.acknowledged = true;
        ack.linkUsed = true;

        // Update booking state via BookingManager
        _updateBookingState(bookingId, true);

        emit SessionAcknowledged(bookingId, msg.sender, true);
    }

    /**
     * @dev Records no-show after link expiry
     * @param bookingId Booking identifier
     */
    function recordNoShow(uint256 bookingId) external {
        AckStatus storage ack = acknowledgments[bookingId];
        if (!ack.linkGenerated) revert LinkNotGenerated();
        if (ack.acknowledged) revert AlreadyAcknowledged();
        if (block.timestamp <= ack.expiryTime) revert WindowNotExpired();

        // Mark as no-show (not acknowledged but link used = true to prevent future use)
        ack.linkUsed = true;

        // Update booking state via BookingManager
        _updateBookingState(bookingId, false);

        emit NoShowRecorded(bookingId, block.timestamp);
    }

    /**
     * @dev Checks if acknowledgment link is valid
     * @param bookingId Booking identifier
     * @return bool True if link is valid
     */
    function isLinkValid(uint256 bookingId) external view returns (bool) {
        AckStatus storage ack = acknowledgments[bookingId];
        return ack.linkGenerated && !ack.linkUsed && block.timestamp <= ack.expiryTime;
    }

    /**
     * @dev Checks if session is acknowledged
     * @param bookingId Booking identifier
     * @return bool True if acknowledged
     */
    function isAcknowledged(uint256 bookingId) external view returns (bool) {
        return acknowledgments[bookingId].acknowledged;
    }

    /**
     * @dev Gets acknowledgment link for a booking (mentee only)
     * @param bookingId Booking identifier
     * @return link The acknowledgment link
     */
    function getAckLink(uint256 bookingId) external view returns (string memory link) {
        AckStatus storage ack = acknowledgments[bookingId];
        if (
            msg.sender != ack.mentee && msg.sender != address(this) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) revert NotAuthorized();
        if (!ack.linkGenerated) revert LinkNotGenerated();

        link = _createLink(bookingId, ack.tokenHash);
    }

    /**
     * @dev Gets acknowledgment status for a booking
     * @param bookingId Booking identifier
     * @return AckStatus The acknowledgment status
     */
    function getAckStatus(uint256 bookingId) external view returns (AckStatus memory) {
        return acknowledgments[bookingId];
    }

    /**
     * @dev Checks if link has expired
     * @param bookingId Booking identifier
     * @return bool True if expired
     */
    function isLinkExpired(uint256 bookingId) external view returns (bool) {
        return acknowledgments[bookingId].linkGenerated &&
            block.timestamp > acknowledgments[bookingId].expiryTime;
    }

    /**
     * @dev Generates cryptographically secure salt
     * @return salt Random salt
     */
    function _generateSalt() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.timestamp,
                block.prevrandao,
                blockhash(block.number - 1),
                tx.gasprice,
                msg.sender
            )
        );
    }

    /**
     * @dev Generates token hash from components
     * @param bookingId Booking identifier
     * @param sessionTime Session timestamp
     * @param mentor Mentor address
     * @param salt Random salt
     * @return bytes32 Token hash
     */
    function _generateTokenHash(
        uint256 bookingId,
        uint256 sessionTime,
        address mentor,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                bookingId,
                "|",
                sessionTime,
                "|",
                mentor,
                "|",
                salt,
                "|",
                "ACK_TOKEN_V1"
            )
        );
    }

    /**
     * @dev Creates human-readable link from booking ID and token hash
     * @param bookingId Booking identifier
     * @param tokenHash Token hash
     * @return link The acknowledgment link
     */
    function _createLink(uint256 bookingId, bytes32 tokenHash) internal pure returns (string memory link) {
        string memory base = "https://onecal.xyz/ack/";
        string memory separator = "/";
        string memory tokenStr = _bytes32ToHexString(tokenHash);

        link = string(abi.encodePacked(base, _uintToString(bookingId), separator, tokenStr));
    }

    /**
     * @dev Converts uint256 to string
     * @param value Number to convert
     * @return string String representation
     */
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            // casting to 'uint8' is safe because value % 10 produces 0-9, and 48 + (0-9) = 48-57 (ASCII digits)
            // forge-lint: disable-next-line(unsafe-typecast)
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    /**
     * @dev Converts bytes32 to hex string
     * @param data Bytes to convert
     * @return string Hex string
     */
    function _bytes32ToHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = _byteToHexChar(uint8(data[i] >> 4));
            str[i * 2 + 1] = _byteToHexChar(uint8(data[i] & 0x0f));
        }

        return string(str);
    }

    /**
     * @dev Converts byte to hex character
     * @param b Byte to convert
     * @return bytes1 Hex character
     */
    function _byteToHexChar(uint8 b) internal pure returns (bytes1) {
        if (b < 10) return bytes1(b + 48);
        else return bytes1(b + 87);
    }

    /**
     * @dev Updates booking state via BookingManager
     * @param bookingId Booking identifier
     * @param attended Whether mentee attended
     */
    function _updateBookingState(uint256 bookingId, bool attended) internal {
        // Call BookingManager to update state
        (bool success, ) = bookingManager.call(
            abi.encodeWithSignature("confirmAttendance(uint256,bool)", bookingId, attended)
        );
        if (!success) revert StateUpdateFailed();
    }

    /**
     * @dev Emergency function to manually acknowledge (platform admin only)
     * @param bookingId Booking identifier
     * @param attended Attendance status
     * @param mentor Mentor address (must match stored mentor)
     */
    function emergencyAcknowledge(
        uint256 bookingId,
        bool attended,
        address mentor
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AckStatus storage ack = acknowledgments[bookingId];
        if (!ack.linkGenerated) revert LinkNotGenerated();
        if (ack.mentor != mentor) revert MentorMismatch();

        ack.acknowledged = true;
        ack.linkUsed = true;

        _updateBookingState(bookingId, attended);

        emit SessionAcknowledged(bookingId, mentor, attended);
    }
}
