// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SessionAcknowledgment
 * @dev Handles session attendance acknowledgment for COMMITMENT_FEE bookings
 *
 * Features:
 * - Simple acknowledgment by mentor with booking identifier
 * - Time-window validation for acknowledgment
 * - Integration with BookingManager for state updates
 *
 * This contract implements a simple acknowledgment system where mentors
 * confirm session attendance using the booking ID.
 */
contract SessionAcknowledgment is AccessControl, ReentrancyGuard {
    /// @notice Role identifier for booking managers
    bytes32 public constant BOOKING_MANAGER_ROLE = keccak256("BOOKING_MANAGER_ROLE");

    /// @notice Acknowledgment state for each booking
    struct AckStatus {
        bool acknowledged;       // Whether mentor has acknowledged
        uint256 expiryTime;     // When acknowledgment expires (session + 1 hour)
        address mentee;         // Mentee address
        address mentor;         // Mentor address
    }

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
    error SessionNotStarted();
    error WindowExpired();
    error NotTheMentor();
    error NotAuthorized();
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
     * @dev Initializes acknowledgment for a booking
     * @param bookingId Booking identifier
     * @param sessionTime Session timestamp
     * @param mentee Mentee address
     * @param mentor Mentor address
     */
    function initializeAcknowledgment(
        uint256 bookingId,
        uint256 sessionTime,
        address mentee,
        address mentor
    ) external onlyRole(BOOKING_MANAGER_ROLE) {
        AckStatus storage ack = acknowledgments[bookingId];
        if (ack.mentor != address(0)) revert AlreadyAcknowledged(); // Already initialized

        ack.mentee = mentee;
        ack.mentor = mentor;
        ack.expiryTime = sessionTime + 1 hours;
    }

    /**
     * @dev Acknowledges session attendance
     * @param bookingId Booking identifier
     */
    function acknowledgeSession(
        uint256 bookingId
    ) external nonReentrant {
        AckStatus storage ack = acknowledgments[bookingId];
        if (ack.mentor == address(0)) revert NotAuthorized();
        if (ack.acknowledged) revert AlreadyAcknowledged();
        if (block.timestamp > ack.expiryTime) revert WindowExpired();
        if (msg.sender != ack.mentor) revert NotTheMentor();

        // Mark as acknowledged
        ack.acknowledged = true;

        // Update booking state via BookingManager
        _updateBookingState(bookingId, true);

        emit SessionAcknowledged(bookingId, msg.sender, true);
    }

    /**
     * @dev Records no-show after acknowledgment window expires
     * @param bookingId Booking identifier
     */
    function recordNoShow(uint256 bookingId) external {
        AckStatus storage ack = acknowledgments[bookingId];
        if (ack.mentor == address(0)) revert NotAuthorized();
        if (ack.acknowledged) revert AlreadyAcknowledged();
        if (block.timestamp <= ack.expiryTime) revert WindowExpired();

        // Update booking state via BookingManager
        _updateBookingState(bookingId, false);

        emit NoShowRecorded(bookingId, block.timestamp);
    }

    /**
     * @dev Checks if acknowledgment is valid
     * @param bookingId Booking identifier
     * @return bool True if acknowledgment is valid
     */
    function isAcknowledgmentValid(uint256 bookingId) external view returns (bool) {
        AckStatus storage ack = acknowledgments[bookingId];
        return ack.mentor != address(0) && !ack.acknowledged && block.timestamp <= ack.expiryTime;
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
     * @dev Gets acknowledgment status for a booking
     * @param bookingId Booking identifier
     * @return AckStatus The acknowledgment status
     */
    function getAckStatus(uint256 bookingId) external view returns (AckStatus memory) {
        return acknowledgments[bookingId];
    }

    /**
     * @dev Checks if acknowledgment window has expired
     * @param bookingId Booking identifier
     * @return bool True if expired
     */
    function isAcknowledgmentExpired(uint256 bookingId) external view returns (bool) {
        AckStatus storage ack = acknowledgments[bookingId];
        return ack.mentor != address(0) && block.timestamp > ack.expiryTime;
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
        if (ack.mentor == address(0)) revert NotAuthorized();
        if (ack.mentor != mentor) revert MentorMismatch();

        ack.acknowledged = true;

        _updateBookingState(bookingId, attended);

        emit SessionAcknowledged(bookingId, mentor, attended);
    }
}
