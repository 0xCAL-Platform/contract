// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {BookingManager} from "../src/v1/BookingManager.sol";
import {Vault} from "../src/v1/Vault.sol";
import {MockIDRX} from "../src/MockIDRX.sol";
import {MentorRegistry} from "../src/MentorRegistry.sol";

contract MetaTransactionTest is Test {
    // Helper to compute the same hash as BookingManager's _hashForwardRequest
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
    // Contracts
    MockIDRX public token;
    Vault public vault;
    BookingManager public bookingManager;
    MentorRegistry public mentorRegistry;

    // Test addresses
    address public admin;
    address public mentee;
    address public mentor;
    address public relayer;
    address public platformFeeAddress;

    // EIP-712 helper - matches BookingManager's implementation
    bytes32 public constant FORWARD_REQUEST_TYPEHASH =
        keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,bytes32 dataHash,uint256 nonce,uint256 deadline)");

    function setUp() public {
        // Setup addresses
        admin = address(this);
        mentee = address(0x11);
        mentor = address(0x21);
        relayer = address(0x31);
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

        // Approve booking manager to spend tokens
        token.approve(address(bookingManager), type(uint256).max);
    }

    function testCreateBookingByRelayer() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;
        uint256 nonce = bookingManager.getNonce(mentee);
        uint256 deadline = block.timestamp + 1 hours;

        // Prepare function call
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("createBooking(address,uint256,uint256)")),
            mentor,
            sessionTime,
            amount
        );

        // Create forward request
        BookingManager.ForwardRequest memory req = BookingManager.ForwardRequest({
            from: mentee,
            to: address(bookingManager),
            value: 0,
            gas: 100000,
            nonce: nonce,
            deadline: deadline,
            data: data
        });

        // Compute hash matching BookingManager's _hashForwardRequest
        bytes32 structHash = computeHash(req);

        // Get domain separator from contract
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("BookingManager"),
                keccak256("1"),
                block.chainid,
                address(bookingManager)
            )
        );

        // Compute typed data hash
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(mentee)), typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature works with contract before testing
        assertTrue(bookingManager.verifyForwardRequest(req, signature), "Signature should be valid");

        // Execute via relayer
        uint256 bookingId = bookingManager.createBookingByRelayer(req, signature);

        assertEq(bookingId, 1);

        // Verify booking data
        BookingManager.Booking memory booking = bookingManager.getBooking(bookingId);
        assertEq(booking.mentee, mentee);
        assertEq(booking.mentor, mentor);
        assertEq(booking.amount, amount);
        assertTrue(booking.createdByRelayer);

        // Verify nonce was incremented
        assertEq(bookingManager.getNonce(mentee), nonce + 1);
    }

    function testRevertCreateBookingByRelayerWrongDeadline() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;
        uint256 nonce = bookingManager.getNonce(mentee);
        uint256 deadline = block.timestamp - 1; // Expired

        // Prepare function call
        bytes memory data = abi.encodeWithSelector(
            bookingManager.createBooking.selector,
            mentor,
            sessionTime,
            amount
        );

        // Create forward request
        BookingManager.ForwardRequest memory req = BookingManager.ForwardRequest({
            from: mentee,
            to: address(bookingManager),
            value: 0,
            gas: 100000,
            nonce: nonce,
            deadline: deadline,
            data: data
        });

        // Compute hash matching BookingManager's _hashForwardRequest
        bytes32 structHash = computeHash(req);

        // Get domain separator from contract
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("BookingManager"),
                keccak256("1"),
                block.chainid,
                address(bookingManager)
            )
        );

        // Compute typed data hash
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(mentee)), typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Try to execute via relayer - should revert with SignatureExpired
        vm.expectRevert(BookingManager.SignatureExpired.selector);
        bookingManager.createBookingByRelayer(req, signature);
    }

    function testRevertCreateBookingByRelayerWrongTo() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;
        uint256 nonce = bookingManager.getNonce(mentee);
        uint256 deadline = block.timestamp + 1 hours;

        // Prepare function call
        bytes memory data = abi.encodeWithSelector(
            bookingManager.createBooking.selector,
            mentor,
            sessionTime,
            amount
        );

        // Create forward request with WRONG 'to' address
        BookingManager.ForwardRequest memory req = BookingManager.ForwardRequest({
            from: mentee,
            to: address(0x9999), // Wrong address!
            value: 0,
            gas: 100000,
            nonce: nonce,
            deadline: deadline,
            data: data
        });

        // Compute hash matching BookingManager's _hashForwardRequest
        bytes32 structHash = computeHash(req);

        // Get domain separator from contract
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("BookingManager"),
                keccak256("1"),
                block.chainid,
                address(bookingManager)
            )
        );

        // Compute typed data hash
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(mentee)), typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Try to execute via relayer - should revert with InvalidRequest
        vm.expectRevert(BookingManager.InvalidRequest.selector);
        bookingManager.createBookingByRelayer(req, signature);
    }

    function testRevertCreateBookingByRelayerInvalidNonce() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;
        uint256 nonce = bookingManager.getNonce(mentee);
        uint256 deadline = block.timestamp + 1 hours;

        // Prepare function call
        bytes memory data = abi.encodeWithSelector(
            bookingManager.createBooking.selector,
            mentor,
            sessionTime,
            amount
        );

        // Create forward request with WRONG nonce
        BookingManager.ForwardRequest memory req = BookingManager.ForwardRequest({
            from: mentee,
            to: address(bookingManager),
            value: 0,
            gas: 100000,
            nonce: nonce + 999, // Wrong nonce!
            deadline: deadline,
            data: data
        });

        // Compute hash matching BookingManager's _hashForwardRequest
        bytes32 structHash = computeHash(req);

        // Get domain separator from contract
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("BookingManager"),
                keccak256("1"),
                block.chainid,
                address(bookingManager)
            )
        );

        // Compute typed data hash
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(mentee)), typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Try to execute via relayer - should revert with InvalidNonce
        vm.expectRevert(BookingManager.InvalidNonce.selector);
        bookingManager.createBookingByRelayer(req, signature);
    }

    function testRevertCreateBookingByRelayerInvalidSignature() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;
        uint256 nonce = bookingManager.getNonce(mentee);
        uint256 deadline = block.timestamp + 1 hours;

        // Prepare function call
        bytes memory data = abi.encodeWithSelector(
            bookingManager.createBooking.selector,
            mentor,
            sessionTime,
            amount
        );

        // Create forward request
        BookingManager.ForwardRequest memory req = BookingManager.ForwardRequest({
            from: mentee,
            to: address(bookingManager),
            value: 0,
            gas: 100000,
            nonce: nonce,
            deadline: deadline,
            data: data
        });

        // Sign with WRONG private key (mentee instead of wrong address)
        bytes32 dataHash = keccak256(data);
        bytes32 structHash = keccak256(
            abi.encode(
                FORWARD_REQUEST_TYPEHASH,
                req.from,
                req.to,
                req.value,
                req.gas,
                dataHash,
                req.nonce,
                req.deadline
            )
        );
        bytes32 DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("BookingManager"),
                keccak256("1"),
                block.chainid,
                address(bookingManager)
            )
        );
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // Sign with a different address
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(mentor)), typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Try to execute via relayer - should revert with InvalidSignature
        vm.expectRevert(BookingManager.InvalidSignature.selector);
        bookingManager.createBookingByRelayer(req, signature);
    }

    function testReuseNonceReverts() public {
        uint256 amount = 50000;
        uint256 sessionTime = block.timestamp + 1 days;
        uint256 nonce = bookingManager.getNonce(mentee);
        uint256 deadline = block.timestamp + 1 hours;

        // Prepare function call
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("createBooking(address,uint256,uint256)")),
            mentor,
            sessionTime,
            amount
        );

        // Create forward request
        BookingManager.ForwardRequest memory req = BookingManager.ForwardRequest({
            from: mentee,
            to: address(bookingManager),
            value: 0,
            gas: 100000,
            nonce: nonce,
            deadline: deadline,
            data: data
        });

        // Compute hash matching BookingManager's _hashForwardRequest
        bytes32 structHash = computeHash(req);

        // Get domain separator from contract
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("BookingManager"),
                keccak256("1"),
                block.chainid,
                address(bookingManager)
            )
        );

        // Compute typed data hash
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(mentee)), typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature works with contract before testing
        assertTrue(bookingManager.verifyForwardRequest(req, signature), "Signature should be valid");

        // First call succeeds
        bookingManager.createBookingByRelayer(req, signature);

        // Second call with same nonce should fail
        vm.expectRevert(BookingManager.InvalidNonce.selector);
        bookingManager.createBookingByRelayer(req, signature);
    }
}
