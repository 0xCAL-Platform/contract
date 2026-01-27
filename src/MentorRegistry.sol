// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MentorRegistry is EIP712 {
    using ECDSA for bytes32;

    struct Mentor {
        string username;
        address currentAddress;
    }

    mapping(string => Mentor) public mentors;
    mapping(address => string) public mentorAddressToUsername;
    mapping(address => uint256) public nonces;

    bytes32 public constant MENTOR_REGISTER_TYPEHASH =
        keccak256(
            "MentorRegister(string username,address creatorAddress,uint256 nonce,uint256 deadline)"
        );

    bytes32 public constant ADDRESS_UPDATE_TYPEHASH =
        keccak256(
            "AddressUpdate(string username,address newAddress,uint256 nonce,uint256 deadline)"
        );

    event MentorRegistered(
        string indexed username,
        address indexed mentorAddress
    );
    event AddressUpdated(
        string indexed username,
        address indexed oldAddress,
        address indexed newAddress
    );
    event MentorRegisteredByRelayer(
        string indexed username,
        address indexed mentorAddress,
        address relayer
    );
    event AddressUpdatedByRelayer(
        string indexed username,
        address indexed oldAddress,
        address indexed newAddress,
        address relayer
    );

    error UsernameAlreadyExists();
    error AddressAlreadyExists();
    error InvalidUsernameFormat();
    error MentorDoesNotExist();
    error Unauthorized();
    error EmptyUsername();
    error InvalidSignature();
    error DeadlineExceeded();

    constructor() EIP712("MentorRegistry", "1") {}

    function registerMentor(
        string calldata _username,
        address _mentorAddress
    ) external {
        _validateNewRegistration(_username, _mentorAddress);
        _register(_username, _mentorAddress);
        emit MentorRegistered(_username, _mentorAddress);
    }

    function registerMentorByRelayer(
        string calldata _username,
        address _mentorAddress,
        uint256 _deadline,
        bytes calldata signature
    ) external {
        _validateNewRegistration(_username, _mentorAddress);

        // Verifikasi signature
        _verifySignature(
            MENTOR_REGISTER_TYPEHASH,
            _mentorAddress, // Penanda tangan harus pemilik address tersebut
            _username,
            _mentorAddress,
            _deadline,
            signature
        );

        _register(_username, _mentorAddress);
        emit MentorRegisteredByRelayer(_username, _mentorAddress, msg.sender);
    }

    function updateAddress(
        string calldata _username,
        address _newAddress
    ) external {
        Mentor storage mentor = mentors[_username];
        if (bytes(mentor.username).length == 0) revert MentorDoesNotExist();
        if (msg.sender != mentor.currentAddress) revert Unauthorized();
        if (bytes(mentorAddressToUsername[_newAddress]).length != 0)
            revert AddressAlreadyExists();

        address oldAddress = mentor.currentAddress;
        _updateMapping(_username, oldAddress, _newAddress);

        emit AddressUpdated(_username, oldAddress, _newAddress);
    }

    function updateAddressByRelayer(
        string calldata _username,
        address _newAddress,
        uint256 _deadline,
        bytes calldata signature
    ) external {
        Mentor storage mentor = mentors[_username];
        if (bytes(mentor.username).length == 0) revert MentorDoesNotExist();
        address currentMentorAddr = mentor.currentAddress;

        _verifySignature(
            ADDRESS_UPDATE_TYPEHASH,
            currentMentorAddr, // Penanda tangan harus pemegang address lama
            _username,
            _newAddress,
            _deadline,
            signature
        );

        if (bytes(mentorAddressToUsername[_newAddress]).length != 0)
            revert AddressAlreadyExists();

        address oldAddress = currentMentorAddr;
        _updateMapping(_username, oldAddress, _newAddress);

        emit AddressUpdatedByRelayer(
            _username,
            oldAddress,
            _newAddress,
            msg.sender
        );
    }

    // --- Internal Helpers ---

    function _register(
        string calldata _username,
        address _mentorAddress
    ) internal {
        mentors[_username] = Mentor({
            username: _username,
            currentAddress: _mentorAddress
        });
        mentorAddressToUsername[_mentorAddress] = _username;
    }

    function _updateMapping(
        string calldata _username,
        address _old,
        address _new
    ) internal {
        delete mentorAddressToUsername[_old];
        mentorAddressToUsername[_new] = _username;
        mentors[_username].currentAddress = _new;
    }

    function _validateNewRegistration(
        string calldata _username,
        address _addr
    ) internal view {
        if (bytes(_username).length == 0) revert EmptyUsername();
        if (!_isValidSnakeCase(_username)) revert InvalidUsernameFormat();
        if (bytes(mentors[_username].username).length != 0)
            revert UsernameAlreadyExists();
        if (bytes(mentorAddressToUsername[_addr]).length != 0)
            revert AddressAlreadyExists();
    }

    function _verifySignature(
        bytes32 _typeHash,
        address _signer,
        string calldata _username,
        address _addressValue,
        uint256 _deadline,
        bytes calldata _signature
    ) internal {
        if (block.timestamp > _deadline) revert DeadlineExceeded();

        bytes32 structHash = keccak256(
            abi.encode(
                _typeHash,
                keccak256(bytes(_username)), // KRUSIAL: String harus di-hash
                _addressValue,
                nonces[_signer],
                _deadline
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = digest.recover(_signature);

        if (recovered != _signer) revert InvalidSignature();
        nonces[_signer]++;
    }

    function _isValidSnakeCase(
        string calldata _username
    ) internal pure returns (bool) {
        bytes memory b = bytes(_username);
        if (b.length == 0 || b[0] == "_" || b[b.length - 1] == "_")
            return false;
        if (!(_isLowerCase(b[0]) || _isNumber(b[0]))) return false;

        for (uint256 i = 0; i < b.length; i++) {
            if (!(_isLowerCase(b[i]) || _isNumber(b[i]) || b[i] == "_"))
                return false;
            if (i > 0 && b[i] == "_" && b[i - 1] == "_") return false;
        }
        return true;
    }

    function _isLowerCase(bytes1 c) internal pure returns (bool) {
        return (c >= "a" && c <= "z");
    }

    function _isNumber(bytes1 c) internal pure returns (bool) {
        return (c >= "0" && c <= "9");
    }

    // View functions
    function getMentor(string calldata _username) external view returns (string memory username, address currentAddress, bool exists) {
        Mentor storage mentor = mentors[_username];
        if (bytes(mentor.username).length == 0) {
            return ("", address(0), false);
        }
        return (mentor.username, mentor.currentAddress, true);
    }

    function getMentorByAddress(address _mentorAddress) external view returns (string memory username, address mentorAddr, bool exists) {
        string storage storedUsername = mentorAddressToUsername[_mentorAddress];
        if (bytes(storedUsername).length == 0) {
            return ("", _mentorAddress, false);
        }
        return (storedUsername, _mentorAddress, true);
    }

    function getNonces(address[] calldata addresses) external view returns (uint256[] memory noncesArray) {
        noncesArray = new uint256[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            noncesArray[i] = nonces[addresses[i]];
        }
    }

    function usernameExists(string calldata _username) external view returns (bool exists) {
        Mentor storage mentor = mentors[_username];
        return bytes(mentor.username).length != 0;
    }

    function getNonce(address _user) external view returns (uint256) {
        return nonces[_user];
    }
}
