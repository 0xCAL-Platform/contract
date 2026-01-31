// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract BookingManager is ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    enum Status { Confirmed, NoShow, Completed }

    struct Booking {
        address mentee;
        address mentor;
        uint256 amount;
        uint256 sessionTime;
        Status status;
        bool attended;
        bool claimed;
    }

    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        uint256 deadline;
        bytes data;
    }

    bytes32 private constant TYPEHASH = keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint256 deadline,bytes data)");

    mapping(uint256 => Booking) public bookings;
    mapping(address => uint256) public nonces;
    uint256 public nextBookingId = 1;

    IERC20 public immutable PAYMENT_TOKEN;
    address public immutable OWNER;

    constructor(address _token) EIP712("BookingManager", "1") {
        PAYMENT_TOKEN = IERC20(_token);
        OWNER = msg.sender;
    }

    // --- INTERNAL LOGIC (The Core Engine) ---
    function _createBooking(address mentee, address mentor, uint256 time, uint256 amt) internal returns (uint256 id) {
        id = nextBookingId++;
        PAYMENT_TOKEN.safeTransferFrom(mentee, address(this), amt);
        bookings[id] = Booking(mentee, mentor, amt, time, Status.Confirmed, false, false);
    }

    function _acknowledge(address mentor, uint256 id, bool attended) internal {
        Booking storage b = bookings[id];
        require(mentor == b.mentor, "Not mentor");
        b.attended = attended;
        if (!attended) b.status = Status.NoShow;
    }

    function _claim(address caller, uint256 id) internal {
        Booking storage b = bookings[id];
        require(!b.claimed, "Claimed");
        b.claimed = true;
        b.status = Status.Completed;

        if (b.attended) {
            require(caller == b.mentee, "Not mentee");
            PAYMENT_TOKEN.safeTransfer(b.mentee, b.amount);
        } else {
            require(caller == b.mentor, "Not mentor");
            uint256 mShare = (b.amount * 90) / 100;
            PAYMENT_TOKEN.safeTransfer(b.mentor, mShare);
            PAYMENT_TOKEN.safeTransfer(OWNER, b.amount - mShare);
        }
    }

    // --- BY RELAYER WRAPPERS ---
    function createBookingByRelayer(ForwardRequest calldata req, bytes calldata sig) external {
        _verify(req, sig);
        (address mentor, uint256 time, uint256 amt) = abi.decode(req.data[4:], (address, uint256, uint256));
        _createBooking(req.from, mentor, time, amt);
    }

    function acknowledgeByRelayer(ForwardRequest calldata req, bytes calldata sig) external {
        _verify(req, sig);
        (uint256 id, bool attended) = abi.decode(req.data[4:], (uint256, bool));
        _acknowledge(req.from, id, attended);
    }

    function claimFundsByRelayer(ForwardRequest calldata req, bytes calldata sig) external {
        _verify(req, sig);
        uint256 id = abi.decode(req.data[4:], (uint256));
        _claim(req.from, id);
    }

    function _verify(ForwardRequest calldata req, bytes calldata sig) internal {
        require(nonces[req.from] == req.nonce, "Nonce");
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(TYPEHASH, req.from, req.to, req.value, req.gas, keccak256(req.data), req.nonce, req.deadline)));
        require(SignatureChecker.isValidSignatureNow(req.from, digest, sig), "Sig");
        nonces[req.from]++;
    }
}
