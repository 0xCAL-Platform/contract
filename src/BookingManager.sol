// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Vault} from "./Vault.sol";

/**
 * @title IMentorRegistry
 * @dev Interface for MentorRegistry contract
 */
interface IMentorRegistry {
    function getMentorByAddress(
        address _mentorAddress
    )
        external
        view
        returns (string memory username, address mentorAddr, bool exists);
}

/**
 * @title BookingManager
 * @dev Core booking management contract with meta-transaction support
 *
 * Features:
 * - Create PAID and COMMITMENT_FEE bookings
 * - Session state management
 * - Integration with MentorRegistry for mentor validation
 * - Integration with Vault for escrow management
 * - Meta-transaction support for gasless booking creation
 * - Session acknowledgment tracking
 *
 * This contract orchestrates the entire booking lifecycle and integrates
 * with MentorRegistry and Vault contracts.
 */
contract BookingManager is ReentrancyGuard, AccessControl, EIP712 {
    using SafeERC20 for IERC20;

    /// @notice Role identifier for platform administrators
    bytes32 public constant PLATFORM_ADMIN_ROLE =
        keccak256("PLATFORM_ADMIN_ROLE");

    /// @notice Booking status enum
    enum BookingStatus {
        Created, // Booking created but not confirmed
        Confirmed, // Booking confirmed by mentee
        InProgress, // Session in progress
        Completed, // Session completed
        Cancelled, // Booking cancelled
        NoShow // Mentee no-showed
    }

    /// @notice Booking data structure
    struct Booking {
        uint256 id; // Unique booking ID
        address mentee; // Mentee address
        address mentor; // Mentor address
        uint256 sessionTime; // Session timestamp
        uint256 amount; // Payment amount
        BookingStatus status; // Current status
        Vault.BookingType bookingType; // Type of booking
        bool attendanceConfirmed; // Whether attendance was confirmed
        bool createdByRelayer; // Whether created via meta-transaction
        uint256 createdAt; // Creation timestamp
    }

    /// @notice Meta-transaction request structure
    struct ForwardRequest {
        address from; // Signer address
        address to; // Contract address
        uint256 value; // Ether value
        uint256 gas; // Gas limit
        uint256 nonce; // Nonce for replay protection
        uint256 deadline; // Deadline for signature
        bytes data; // Call data
    }

    /// @notice Emitted when a booking is created
    event BookingCreated(
        uint256 indexed bookingId,
        address indexed mentee,
        address indexed mentor,
        uint256 sessionTime,
        Vault.BookingType bookingType,
        uint256 amount
    );

    /// @notice Emitted when booking status is updated
    event BookingStatusUpdated(
        uint256 indexed bookingId,
        BookingStatus oldStatus,
        BookingStatus newStatus
    );

    /// @notice Emitted when attendance is confirmed
    event AttendanceConfirmed(
        uint256 indexed bookingId,
        bool attended,
        address indexed confirmer
    );

    /// @notice Emitted when mentor payment is released
    event MentorPaymentReleased(
        uint256 indexed bookingId,
        address indexed mentor,
        uint256 amount
    );

    /// @notice Emitted when mentee refund is processed
    event MenteeRefundProcessed(
        uint256 indexed bookingId,
        address indexed mentee,
        uint256 amount
    );

    /// @notice Emitted when booking is cancelled
    event BookingCancelled(
        uint256 indexed bookingId,
        address indexed canceller,
        uint256 refundAmount
    );

    /// @notice Emitted when cancellation penalty is applied
    event CancellationPenaltyApplied(
        uint256 indexed bookingId,
        uint256 mentorAmount,
        uint256 platformAmount
    );

    /// @notice Mapping of booking ID to Booking data
    mapping(uint256 => Booking) public bookings;

    /// @notice Mapping of user address to nonce for meta-transactions
    mapping(address => uint256) public nonces;

    /// @notice Next available booking ID
    uint256 public nextBookingId = 1;

    /// @notice Vault contract instance
    Vault public immutable VAULT;

    /// @notice Payment token address
    IERC20 public immutable PAYMENT_TOKEN;

    /// @notice Platform fee address
    address public immutable PLATFORM_FEE_ADDRESS;

    /// @notice MentorRegistry contract address
    address public immutable MENTOR_REGISTRY;

    /// @notice Custom errors
    error InvalidVaultAddress();
    error InvalidPaymentTokenAddress();
    error InvalidPlatformFeeAddress();
    error InvalidSignature();
    error InvalidRequest();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidMentee();
    error InvalidMentor();
    error InvalidAmount();
    error SessionNotInFuture();
    error SessionTooFar();
    error Unauthorized();
    error BookingIsCancelled();
    error WrongBookingType();
    error NotMentor();
    error InvalidStatus();
    error TooEarlyToClaim();
    error NotMentee();
    error AttendanceNotConfirmed();
    error OnlyMenteeCanCancel();
    error CannotCancel();
    error TooLateToCancel();
    error InvalidStatusForInProgress();
    error StateUpdateFailed();

    /**
     * @dev Constructor
     * @param _vault Address of Vault contract
     * @param _paymentToken Address of payment token
     * @param _platformFeeAddress Platform fee address
     * @param _mentorRegistry Address of MentorRegistry contract
     */
    constructor(
        address _vault,
        address _paymentToken,
        address _platformFeeAddress,
        address _mentorRegistry
    ) EIP712("BookingManager", "1") {
        if (_vault == address(0)) revert InvalidVaultAddress();
        if (_paymentToken == address(0)) revert InvalidPaymentTokenAddress();
        if (_platformFeeAddress == address(0))
            revert InvalidPlatformFeeAddress();
        if (_mentorRegistry == address(0)) revert InvalidPlatformFeeAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PLATFORM_ADMIN_ROLE, msg.sender);

        VAULT = Vault(_vault);
        PAYMENT_TOKEN = IERC20(_paymentToken);
        PLATFORM_FEE_ADDRESS = _platformFeeAddress;
        MENTOR_REGISTRY = _mentorRegistry;
    }

    /**
     * @dev Creates a new booking (direct call)
     * @param mentor Mentor address
     * @param sessionTime Session timestamp
     * @param amount Payment amount
     * @param bookingType Type of booking
     * @return bookingId The ID of the created booking
     */
    function createBooking(
        address mentor,
        uint256 sessionTime,
        uint256 amount,
        Vault.BookingType bookingType
    ) external nonReentrant returns (uint256 bookingId) {
        return
            _createBooking(
                msg.sender,
                mentor,
                sessionTime,
                amount,
                bookingType,
                false
            );
    }

    /**
     * @dev Creates a new booking via meta-transaction (relayer)
     * @param req Forward request structure
     * @param signature Signature from mentee
     * @return bookingId The ID of the created booking
     */
    function createBookingByRelayer(
        ForwardRequest calldata req,
        bytes calldata signature
    ) external nonReentrant returns (uint256 bookingId) {
        // Verify signature
        if (
            !SignatureChecker.isValidSignatureNow(
                req.from,
                _hashTypedDataV4(_hashForwardRequest(req)),
                signature
            )
        ) revert InvalidSignature();

        // Verify nonce and deadline
        if (req.from != req.to) revert InvalidRequest();
        if (block.timestamp > req.deadline) revert SignatureExpired();
        if (nonces[req.from] != req.nonce) revert InvalidNonce();

        // Increment nonce
        nonces[req.from]++;

        // Decode function call from data
        (
            address mentor,
            uint256 sessionTime,
            uint256 amount,
            Vault.BookingType bookingType
        ) = abi.decode(
                req.data[4:],
                (address, uint256, uint256, Vault.BookingType)
            );

        return
            _createBooking(
                req.from,
                mentor,
                sessionTime,
                amount,
                bookingType,
                true
            );
    }

    /**
     * @dev Internal function to create booking
     * @param mentee Mentee address
     * @param mentor Mentor address
     * @param sessionTime Session timestamp
     * @param amount Payment amount
     * @param bookingType Type of booking
     * @param createdByRelayer Whether created via relayer
     * @return bookingId The ID of the created booking
     */
    function _createBooking(
        address mentee,
        address mentor,
        uint256 sessionTime,
        uint256 amount,
        Vault.BookingType bookingType,
        bool createdByRelayer
    ) internal returns (uint256 bookingId) {
        if (mentee == address(0)) revert InvalidMentee();
        if (mentor == address(0)) revert InvalidMentor();
        if (amount == 0) revert InvalidAmount();
        if (sessionTime <= block.timestamp) revert SessionNotInFuture();
        if (sessionTime > block.timestamp + 14 days) revert SessionTooFar();

        // Validate mentor exists in MentorRegistry
        (, , bool exists) = IMentorRegistry(MENTOR_REGISTRY).getMentorByAddress(
            mentor
        );
        if (!exists) revert NotMentor();

        // Get new booking ID
        bookingId = nextBookingId++;
        uint256 currentId = bookingId;

        // Transfer tokens from mentee to this contract
        PAYMENT_TOKEN.safeTransferFrom(mentee, address(this), amount);

        // Approve vault to spend tokens
        PAYMENT_TOKEN.approve(address(VAULT), amount);

        // Create escrow in Vault
        VAULT.createEscrow(
            currentId,
            mentee,
            mentor,
            amount,
            bookingType,
            sessionTime
        );

        // Store booking data
        bookings[currentId] = Booking({
            id: currentId,
            mentee: mentee,
            mentor: mentor,
            sessionTime: sessionTime,
            amount: amount,
            status: BookingStatus.Confirmed,
            bookingType: bookingType,
            attendanceConfirmed: false,
            createdByRelayer: createdByRelayer,
            createdAt: block.timestamp
        });

        emit BookingCreated(
            currentId,
            mentee,
            mentor,
            sessionTime,
            bookingType,
            amount
        );
        emit BookingStatusUpdated(
            currentId,
            BookingStatus.Created,
            BookingStatus.Confirmed
        );
    }

    /**
     * @dev Confirms session attendance (for COMMITMENT_FEE bookings)
     * @param bookingId Booking identifier
     * @param attended Whether mentee attended
     */
    function confirmAttendance(uint256 bookingId, bool attended) external {
        if (
            msg.sender != address(VAULT) &&
            !hasRole(PLATFORM_ADMIN_ROLE, msg.sender)
        ) revert Unauthorized();

        Booking storage booking = bookings[bookingId];
        if (booking.status == BookingStatus.Cancelled)
            revert BookingIsCancelled();
        if (booking.bookingType != Vault.BookingType.COMMITMENT_FEE)
            revert WrongBookingType();

        booking.attendanceConfirmed = attended;

        if (attended) {
            // Update mentee refund to 100% in vault
            VAULT.updateMenteeRefund(bookingId, booking.amount);

            emit AttendanceConfirmed(bookingId, true, msg.sender);
        } else {
            // Update mentor amount to 90% in vault
            uint256 mentorAmount = (booking.amount * 90) / 100;
            // Reset mentee refund to 0 for no-show
            VAULT.updateMenteeRefund(bookingId, 0);
            VAULT.updateMentorAmount(bookingId, mentorAmount);

            booking.status = BookingStatus.NoShow;

            emit AttendanceConfirmed(bookingId, false, msg.sender);
            emit BookingStatusUpdated(
                bookingId,
                BookingStatus.Confirmed,
                BookingStatus.NoShow
            );
        }
    }

    /**
     * @dev Processes mentor payment claim
     * @param bookingId Booking identifier
     */
    function claimMentorPayment(uint256 bookingId) external nonReentrant {
        Booking storage booking = bookings[bookingId];
        if (msg.sender != booking.mentor) revert NotMentor();
        if (
            booking.status != BookingStatus.Completed &&
            booking.status != BookingStatus.NoShow &&
            booking.status != BookingStatus.Confirmed
        ) revert InvalidStatus();

        // Call vault release
        VAULT.releaseToMentor(bookingId);

        // Only update status to Completed if not already Completed or NoShow
        if (booking.status == BookingStatus.Confirmed) {
            BookingStatus oldStatus = booking.status;
            booking.status = BookingStatus.Completed;
            emit BookingStatusUpdated(bookingId, oldStatus, booking.status);
        }

        emit MentorPaymentReleased(bookingId, booking.mentor, booking.amount);
    }

    /**
     * @dev Processes mentee refund claim
     * @param bookingId Booking identifier
     */
    function claimMenteeRefund(uint256 bookingId) external nonReentrant {
        Booking storage booking = bookings[bookingId];
        if (msg.sender != booking.mentee) revert NotMentee();
        if (booking.bookingType != Vault.BookingType.COMMITMENT_FEE)
            revert WrongBookingType();
        if (!booking.attendanceConfirmed) revert AttendanceNotConfirmed();

        // Call vault refund
        VAULT.refundToMentee(bookingId);

        // Update status to Completed
        BookingStatus oldStatus = booking.status;
        booking.status = BookingStatus.Completed;
        emit BookingStatusUpdated(bookingId, oldStatus, booking.status);

        emit MenteeRefundProcessed(bookingId, booking.mentee, booking.amount);
    }

    /**
     * @dev Cancels a booking before session
     * @param bookingId Booking identifier
     */
    function cancelBooking(uint256 bookingId) external nonReentrant {
        Booking storage booking = bookings[bookingId];
        if (msg.sender != booking.mentee) revert OnlyMenteeCanCancel();
        if (booking.status != BookingStatus.Confirmed) revert CannotCancel();
        if (block.timestamp >= booking.sessionTime) revert TooLateToCancel();

        booking.status = BookingStatus.Cancelled;

        // Calculate refund based on cancellation timing
        uint256 timeUntilSession = booking.sessionTime - block.timestamp;
        uint256 menteeRefund;
        uint256 mentorPenalty;
        uint256 platformPenalty;

        if (timeUntilSession > 1 days) {
            // No punishment - full refund
            menteeRefund = booking.amount;
            mentorPenalty = 0;
            platformPenalty = 0;
        } else {
            // Late cancellation (within 1 day) - apply punishment
            menteeRefund = (booking.amount * 80) / 100;
            mentorPenalty = (booking.amount * 15) / 100;
            platformPenalty = (booking.amount * 5) / 100;
        }

        // Refund mentee
        VAULT.cancelBookingRefund(
            bookingId,
            payable(booking.mentee),
            menteeRefund
        );

        // If there's a penalty, distribute it
        if (mentorPenalty > 0) {
            VAULT.distributeCancellationPenalty(
                bookingId,
                mentorPenalty,
                platformPenalty
            );
        }

        emit BookingCancelled(bookingId, booking.mentee, menteeRefund);
        if (mentorPenalty > 0) {
            emit CancellationPenaltyApplied(
                bookingId,
                mentorPenalty,
                platformPenalty
            );
        }
    }

    /**
     * @dev Marks booking as in progress (called at session time)
     * @param bookingId Booking identifier
     */
    function markInProgress(uint256 bookingId) external {
        if (!hasRole(PLATFORM_ADMIN_ROLE, msg.sender)) revert Unauthorized();

        Booking storage booking = bookings[bookingId];
        if (booking.status != BookingStatus.Confirmed)
            revert InvalidStatusForInProgress();

        booking.status = BookingStatus.InProgress;
        emit BookingStatusUpdated(
            bookingId,
            BookingStatus.Confirmed,
            BookingStatus.InProgress
        );
    }

    /**
     * @dev Gets booking details
     * @param bookingId Booking identifier
     * @return Booking The booking data
     */
    function getBooking(
        uint256 bookingId
    ) external view returns (Booking memory) {
        return bookings[bookingId];
    }

    /**
     * @dev Gets current nonce for an address
     * @param user User address
     * @return nonce Current nonce
     */
    function getNonce(address user) external view returns (uint256) {
        return nonces[user];
    }

    /**
     * @dev Hashes forward request for EIP-712 signature
     * @param req Forward request
     * @return bytes32 Hash
     */
    function _hashForwardRequest(
        ForwardRequest calldata req
    ) internal pure returns (bytes32) {
        return
            keccak256(
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

    /**
     * @dev Verifies forward request signature
     * @param req Forward request
     * @param signature Signature
     * @return bool True if signature is valid
     */
    function verifyForwardRequest(
        ForwardRequest calldata req,
        bytes calldata signature
    ) external view returns (bool) {
        return
            SignatureChecker.isValidSignatureNow(
                req.from,
                _hashTypedDataV4(_hashForwardRequest(req)),
                signature
            );
    }

    /**
     * @dev Updates booking status manually (emergency only)
     * @param bookingId Booking identifier
     * @param newStatus New status
     */
    function emergencyUpdateStatus(
        uint256 bookingId,
        BookingStatus newStatus
    ) external onlyRole(PLATFORM_ADMIN_ROLE) {
        Booking storage booking = bookings[bookingId];
        BookingStatus oldStatus = booking.status;
        booking.status = newStatus;

        emit BookingStatusUpdated(bookingId, oldStatus, newStatus);
    }
}
