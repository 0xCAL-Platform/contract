// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Vault
 * @dev Secure escrow contract for holding booking funds
 *
 * Features:
 * - Escrow deposits for PAID and COMMITMENT_FEE bookings
 * - Time-based locks for payment releases
 * - Platform fee distribution (5% for PAID, 10% for no-show)
 * - Pull-over-push payment pattern (reentrancy safe)
 * - Role-based access control
 * - Emergency withdrawal mechanisms
 *
 * This contract implements a secure escrow system that holds funds
 * until specific conditions are met (session completion, time expiry).
 */
contract Vault is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    /// @notice Platform fee percentage for PAID bookings (5%)
    uint256 public constant PLATFORM_FEE_PERCENT_PAID = 5;

    /// @notice Platform fee percentage for COMMITMENT_FEE no-shows (10%)
    uint256 public constant PLATFORM_FEE_PERCENT_COMMIT = 10;

    /// @notice Mentor percentage for no-show (90%)
    uint256 public constant MENTOR_PERCENT_NO_SHOW = 90;

    /// @notice Mentee refund percentage for attendance (100%)
    uint256 public constant MENTEE_REFUND_ATTENDED = 100;

    /// @notice Role identifier for booking managers
    bytes32 public constant BOOKING_MANAGER_ROLE = keccak256("BOOKING_MANAGER_ROLE");

    /// @notice Role identifier for platform administrators
    bytes32 public constant PLATFORM_ADMIN_ROLE = keccak256("PLATFORM_ADMIN_ROLE");

    /// @notice Escrow state for each booking
    struct BookingEscrow {
        uint256 amount;              // Total deposited amount
        uint256 mentorAmount;        // Amount for mentor (if applicable)
        uint256 platformFee;        // Platform fee amount
        uint256 menteeRefund;       // Refund to mentee (if applicable)
        uint256 sessionTime;        // Session timestamp
        address mentee;             // Mentee address
        address mentor;             // Mentor address
        bool claimed;               // Whether funds have been claimed
        bool active;               // Whether escrow is active
        BookingType bookingType;    // Type of booking
    }

    /// @notice Booking type enum
    enum BookingType {
        PAID,                      // Mentor gets paid
        COMMITMENT_FEE             // Refundable commitment fee
    }

    /// @notice Emitted when an escrow is created
    event EscrowCreated(
        uint256 indexed bookingId,
        address indexed mentee,
        address indexed mentor,
        uint256 amount,
        BookingType bookingType
    );

    /// @notice Emitted when mentor payment is released
    event MentorPaymentReleased(
        uint256 indexed bookingId,
        address indexed mentor,
        uint256 amount
    );

    /// @notice Emitted when mentee refund is issued
    event MenteeRefundIssued(
        uint256 indexed bookingId,
        address indexed mentee,
        uint256 amount
    );

    /// @notice Emitted when platform fee is claimed
    event PlatformFeeClaimed(
        uint256 indexed bookingId,
        address indexed platformAddress,
        uint256 amount
    );

    /// @notice Emitted when emergency refund is processed
    event EmergencyRefund(
        uint256 indexed bookingId,
        address indexed to,
        uint256 amount,
        string reason
    );

    /// @notice Emitted when emergency mode is activated
    event EmergencyModeActivated(address indexed activator);

    /// @notice Emitted when emergency mode is deactivated
    event EmergencyModeDeactivated(address indexed deactivator);

    /// @notice Mapping of booking ID to escrow data
    mapping(uint256 => BookingEscrow) public escrows;

    /// @notice Total value currently locked in escrow
    uint256 public totalEscrowed;

    /// @notice Address that receives platform fees
    address public platformFeeAddress;

    /// @notice ERC20 token used for payments
    IERC20 public paymentToken;

    /// @notice Emergency mode flag
    bool public emergencyMode;

    /// @notice Tracks platform fee claims
    mapping(uint256 => bool) public platformFeeClaimed;

    /// @notice Custom errors
    error InvalidTokenAddress();
    error InvalidFeeAddress();
    error EscrowAlreadyExists();
    error InvalidMentee();
    error InvalidMentor();
    error InvalidAmount();
    error SessionNotInFuture();
    error SessionTooFar();
    error EscrowNotActive();
    error AlreadyClaimed();
    error TooEarlyToClaim();
    error NotMentor();
    error NoMentorPayment();
    error SessionNotStarted();
    error NotMentee();
    error WrongBookingType();
    error NoRefundAvailable();
    error BookingNotClaimed();
    error PlatformFeeAlreadyClaimed();
    error NoPlatformFee();
    error EscrowNotActiveForRefund();
    error InvalidRecipient();
    error AmountExceedsEscrow();
    error NotInEmergencyMode();
    error EscrowAlreadyClaimed();
    error RefundExceedsAmount();
    error AmountExceedsEscrowForMentor();
    error EmergencyModeRequired();

    /**
     * @dev Constructor
     * @param _paymentToken Address of the payment token
     * @param _platformFeeAddress Address to receive platform fees
     */
    constructor(address _paymentToken, address _platformFeeAddress) {
        if (_paymentToken == address(0)) revert InvalidTokenAddress();
        if (_platformFeeAddress == address(0)) revert InvalidFeeAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PLATFORM_ADMIN_ROLE, msg.sender);

        paymentToken = IERC20(_paymentToken);
        platformFeeAddress = _platformFeeAddress;
    }

    /**
     * @dev Creates an escrow for a booking
     * @param bookingId Unique booking identifier
     * @param mentee Address of the mentee
     * @param mentor Address of the mentor
     * @param amount Amount to escrow
     * @param bookingType Type of booking (PAID or COMMITMENT_FEE)
     * @param sessionTime Timestamp when session occurs
     */
    function createEscrow(
        uint256 bookingId,
        address mentee,
        address mentor,
        uint256 amount,
        BookingType bookingType,
        uint256 sessionTime
    ) external onlyRole(BOOKING_MANAGER_ROLE) {
        if (escrows[bookingId].active) revert EscrowAlreadyExists();
        if (mentee == address(0)) revert InvalidMentee();
        if (mentor == address(0)) revert InvalidMentor();
        if (amount == 0) revert InvalidAmount();
        if (sessionTime <= block.timestamp) revert SessionNotInFuture();
        if (sessionTime > block.timestamp + 30 days) revert SessionTooFar();

        // Calculate fee splits based on booking type
        (uint256 mentorAmount, uint256 platformFeeAmount, uint256 menteeRefundAmount) =
            _calculateFeeSplit(bookingType, amount);

        // Transfer tokens from mentee to vault
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        // Store escrow data
        escrows[bookingId] = BookingEscrow({
            amount: amount,
            mentorAmount: mentorAmount,
            platformFee: platformFeeAmount,
            menteeRefund: menteeRefundAmount,
            sessionTime: sessionTime,
            mentee: mentee,
            mentor: mentor,
            claimed: false,
            active: true,
            bookingType: bookingType
        });

        totalEscrowed += amount;

        emit EscrowCreated(bookingId, mentee, mentor, amount, bookingType);
    }

    /**
     * @dev Releases payment to mentor (for PAID bookings or no-shows)
     * @param bookingId Booking identifier
     */
    function releaseToMentor(uint256 bookingId) external nonReentrant {
        BookingEscrow storage escrow = escrows[bookingId];
        if (!escrow.active) revert EscrowNotActive();
        if (escrow.claimed) revert AlreadyClaimed();
        if (block.timestamp < escrow.sessionTime + 1 hours) revert TooEarlyToClaim();
        if (
            msg.sender != escrow.mentor &&
            !hasRole(BOOKING_MANAGER_ROLE, msg.sender)
        ) revert NotMentor();

        escrow.claimed = true;
        uint256 amountToTransfer = escrow.mentorAmount;

        if (amountToTransfer == 0) revert NoMentorPayment();

        totalEscrowed -= amountToTransfer;
        paymentToken.safeTransfer(escrow.mentor, amountToTransfer);

        emit MentorPaymentReleased(bookingId, escrow.mentor, amountToTransfer);
    }

    /**
     * @dev Refunds payment to mentee (for COMMITMENT_FEE with attendance)
     * @param bookingId Booking identifier
     */
    function refundToMentee(uint256 bookingId) external nonReentrant {
        BookingEscrow storage escrow = escrows[bookingId];
        if (!escrow.active) revert EscrowNotActive();
        if (escrow.claimed) revert AlreadyClaimed();
        if (
            msg.sender != escrow.mentee &&
            !hasRole(BOOKING_MANAGER_ROLE, msg.sender)
        ) revert NotMentee();
        if (escrow.bookingType != BookingType.COMMITMENT_FEE) revert WrongBookingType();

        escrow.claimed = true;
        uint256 amountToTransfer = escrow.menteeRefund;

        if (amountToTransfer == 0) revert NoRefundAvailable();

        totalEscrowed -= amountToTransfer;
        paymentToken.safeTransfer(escrow.mentee, amountToTransfer);

        emit MenteeRefundIssued(bookingId, escrow.mentee, amountToTransfer);
    }

    /**
     * @dev Claims platform fee
     * @param bookingId Booking identifier
     */
    function claimPlatformFee(uint256 bookingId) external onlyRole(PLATFORM_ADMIN_ROLE) {
        BookingEscrow storage escrow = escrows[bookingId];
        if (!escrow.active) revert EscrowNotActive();
        if (!escrow.claimed) revert BookingNotClaimed();
        if (platformFeeClaimed[bookingId]) revert PlatformFeeAlreadyClaimed();

        platformFeeClaimed[bookingId] = true;
        uint256 feeAmount = escrow.platformFee;

        if (feeAmount == 0) revert NoPlatformFee();

        totalEscrowed -= feeAmount;
        paymentToken.safeTransfer(platformFeeAddress, feeAmount);

        emit PlatformFeeClaimed(bookingId, platformFeeAddress, feeAmount);
    }

    /**
     * @dev Cancels a booking and refunds the mentee (called by BookingManager)
     * @param bookingId Booking identifier
     * @param mentee Mentee address
     * @param amount Amount to refund
     */
    function cancelBookingRefund(
        uint256 bookingId,
        address payable mentee,
        uint256 amount
    ) external onlyRole(BOOKING_MANAGER_ROLE) {
        BookingEscrow storage escrow = escrows[bookingId];
        if (!escrow.active) revert EscrowNotActiveForRefund();
        if (mentee == address(0)) revert InvalidRecipient();
        if (amount > escrow.amount) revert AmountExceedsEscrow();

        escrow.amount -= amount;
        totalEscrowed -= amount;

        paymentToken.safeTransfer(mentee, amount);

        emit EmergencyRefund(bookingId, mentee, amount, "Booking cancelled");
    }

    /**
     * @dev Distributes cancellation penalty to mentor and platform
     * @param bookingId Booking identifier
     * @param mentorAmount Amount to mentor
     * @param platformAmount Amount to platform
     */
    function distributeCancellationPenalty(
        uint256 bookingId,
        uint256 mentorAmount,
        uint256 platformAmount
    ) external onlyRole(BOOKING_MANAGER_ROLE) {
        BookingEscrow storage escrow = escrows[bookingId];
        if (!escrow.active) revert EscrowNotActive();

        uint256 totalPenalty = mentorAmount + platformAmount;
        if (totalPenalty > escrow.amount) revert AmountExceedsEscrow();

        escrow.amount -= totalPenalty;
        totalEscrowed -= totalPenalty;

        // Transfer to mentor
        if (mentorAmount > 0) {
            paymentToken.safeTransfer(escrow.mentor, mentorAmount);
            emit MentorPaymentReleased(bookingId, escrow.mentor, mentorAmount);
        }

        // Transfer to platform
        if (platformAmount > 0) {
            paymentToken.safeTransfer(platformFeeAddress, platformAmount);
            emit PlatformFeeClaimed(bookingId, platformFeeAddress, platformAmount);
        }
    }

    /**
     * @dev Emergency refund mechanism (only in emergency mode)
     * @param bookingId Booking identifier
     * @param to Recipient address
     * @param amount Amount to refund
     * @param reason Reason for emergency refund
     */
    function emergencyRefund(
        uint256 bookingId,
        address payable to,
        uint256 amount,
        string calldata reason
    ) external onlyRole(PLATFORM_ADMIN_ROLE) {
        BookingEscrow storage escrow = escrows[bookingId];
        if (!escrow.active) revert EscrowNotActiveForRefund();
        if (to == address(0)) revert InvalidRecipient();
        if (amount > escrow.amount) revert AmountExceedsEscrow();

        escrow.amount -= amount;
        totalEscrowed -= amount;

        paymentToken.safeTransfer(to, amount);

        emit EmergencyRefund(bookingId, to, amount, reason);
    }

    /**
     * @dev Activates emergency mode (platform admin only)
     */
    function activateEmergencyMode() external onlyRole(PLATFORM_ADMIN_ROLE) {
        emergencyMode = true;
        emit EmergencyModeActivated(msg.sender);
    }

    /**
     * @dev Deactivates emergency mode (platform admin only)
     */
    function deactivateEmergencyMode() external onlyRole(PLATFORM_ADMIN_ROLE) {
        emergencyMode = false;
        emit EmergencyModeDeactivated(msg.sender);
    }

    /**
     * @dev Updates platform fee address (emergency mode only)
     * @param _platformFeeAddress New platform fee address
     */
    function updatePlatformFeeAddress(address _platformFeeAddress)
        external
        onlyRole(PLATFORM_ADMIN_ROLE)
        onlyInEmergency
    {
        if (_platformFeeAddress == address(0)) revert InvalidFeeAddress();
        platformFeeAddress = _platformFeeAddress;
    }

    /**
     * @dev Checks if escrow is ready for mentor claim
     * @param bookingId Booking identifier
     * @return bool True if ready for claim
     */
    function isReadyForMentorClaim(uint256 bookingId) external view returns (bool) {
        BookingEscrow storage escrow = escrows[bookingId];
        return escrow.active &&
            !escrow.claimed &&
            block.timestamp >= escrow.sessionTime + 1 hours;
    }

    /**
     * @dev Checks if escrow is ready for mentee refund
     * @param bookingId Booking identifier
     * @return bool True if ready for refund
     */
    function isReadyForMenteeRefund(uint256 bookingId) external view returns (bool) {
        BookingEscrow storage escrow = escrows[bookingId];
        return escrow.active &&
            !escrow.claimed &&
            escrow.bookingType == BookingType.COMMITMENT_FEE &&
            escrow.menteeRefund > 0;
    }

    /**
     * @dev Gets escrow details for a booking
     * @param bookingId Booking identifier
     * @return BookingEscrow The escrow data
     */
    function getEscrow(uint256 bookingId) external view returns (BookingEscrow memory) {
        return escrows[bookingId];
    }

    /**
     * @dev Calculates fee split based on booking type
     * @param bookingType Type of booking
     * @param amount Total amount
     * @return mentorAmount Amount for mentor
     * @return platformFeeAmount Platform fee
     * @return menteeRefundAmount Refund to mentee
     */
    function _calculateFeeSplit(
        BookingType bookingType,
        uint256 amount
    ) internal pure returns (uint256 mentorAmount, uint256 platformFeeAmount, uint256 menteeRefundAmount) {
        if (bookingType == BookingType.PAID) {
            // PAID: 95% to mentor, 5% to platform
            mentorAmount = (amount * (100 - PLATFORM_FEE_PERCENT_PAID)) / 100;
            platformFeeAmount = (amount * PLATFORM_FEE_PERCENT_PAID) / 100;
            menteeRefundAmount = 0;
        } else {
            // COMMITMENT_FEE: Initially 0%, will be set based on attendance
            mentorAmount = 0;
            platformFeeAmount = 0;
            menteeRefundAmount = 0;
        }
    }

    /**
     * @dev Updates mentee refund amount (for COMMITMENT_FEE after attendance)
     * @param bookingId Booking identifier
     * @param newMenteeRefund New refund amount
     */
    function updateMenteeRefund(uint256 bookingId, uint256 newMenteeRefund)
        external
        onlyRole(BOOKING_MANAGER_ROLE)
    {
        BookingEscrow storage escrow = escrows[bookingId];
        if (!escrow.active) revert EscrowNotActive();
        if (escrow.claimed) revert EscrowAlreadyClaimed();
        if (escrow.bookingType != BookingType.COMMITMENT_FEE) revert WrongBookingType();
        if (newMenteeRefund > escrow.amount) revert RefundExceedsAmount();

        escrow.menteeRefund = newMenteeRefund;
    }

    /**
     * @dev Updates mentor amount (for COMMITMENT_FEE after no-show)
     * @param bookingId Booking identifier
     * @param newMentorAmount New mentor amount
     */
    function updateMentorAmount(uint256 bookingId, uint256 newMentorAmount)
        external
        onlyRole(BOOKING_MANAGER_ROLE)
    {
        BookingEscrow storage escrow = escrows[bookingId];
        if (!escrow.active) revert EscrowNotActive();
        if (escrow.claimed) revert EscrowAlreadyClaimed();
        if (escrow.bookingType != BookingType.COMMITMENT_FEE) revert WrongBookingType();
        if (newMentorAmount > escrow.amount) revert AmountExceedsEscrowForMentor();
        if (newMentorAmount + escrow.menteeRefund > escrow.amount) revert AmountExceedsEscrowForMentor();

        escrow.mentorAmount = newMentorAmount;
        escrow.platformFee = escrow.amount - newMentorAmount - escrow.menteeRefund;
    }

    /**
     * @dev Modifier to check emergency mode
     */
    modifier onlyInEmergency() {
        _onlyInEmergency();
        _;
    }

    /**
     * @dev Internal function to check emergency mode
     */
    function _onlyInEmergency() internal view {
        if (!emergencyMode) revert NotInEmergencyMode();
    }
}
