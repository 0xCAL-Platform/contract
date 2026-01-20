// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MentorRegistry
 * @dev Contract for registering and managing mentors with meta-transaction support
 *
 * Features:
 * - Username: unique, snake_case format, cannot be changed
 * - Address: can be changed by the mentor
 * - Gasless transactions via relayer (meta-transactions)
 * - EIP-712 signature verification
 */
contract MentorRegistry {
    // Struct to store mentor information
    struct Mentor {
        string username;
        address currentAddress;
    }

    // Mapping from username to Mentor info
    mapping(string => Mentor) public mentors;

    // EIP-712: Structure for typed data
    bytes32 public constant MENTOR_REGISTER_TYPEHASH =
        keccak256(
            "MentorRegister(string username,address creatorAddress,uint256 nonce,uint256 deadline)"
        );

    bytes32 public constant ADDRESS_UPDATE_TYPEHASH =
        keccak256(
            "AddressUpdate(string username,address newAddress,uint256 nonce,uint256 deadline)"
        );

    // EIP-712: Domain separator components (precomputed for gas optimization)
    bytes32 private constant _DOMAIN_TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 private constant _DOMAIN_NAME_HASH = keccak256("MentorRegistry");
    bytes32 private constant _DOMAIN_VERSION_HASH = keccak256("1");

    // Mapping from address to nonce to prevent replay attacks
    mapping(address => uint256) public nonces;

    // Events
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

    // Custom errors
    error UsernameAlreadyExists();
    error InvalidUsernameFormat();
    error MentorDoesNotExist();
    error Unauthorized();
    error EmptyUsername();
    error InvalidSignature();
    error DeadlineExceeded();
    error NonceMismatch();

    /**
     * @dev Register a new mentor (direct call)
     * @param _username Unique username in snake_case format
     * @param _mentorAddress Address of the mentor
     */
    function registerMentor(
        string calldata _username,
        address _mentorAddress
    ) external {
        // Validate username is not empty
        if (bytes(_username).length == 0) {
            revert EmptyUsername();
        }

        // Validate username format (snake_case: only lowercase, numbers, and underscores)
        if (!_isValidSnakeCase(_username)) {
            revert InvalidUsernameFormat();
        }

        // Check if username already exists
        if (bytes(mentors[_username].username).length != 0) {
            revert UsernameAlreadyExists();
        }

        // Register the mentor
        mentors[_username] = Mentor({
            username: _username,
            currentAddress: _mentorAddress
        });

        // Emit event
        emit MentorRegistered(_username, _mentorAddress);
    }

    /**
     * @dev Register a new mentor via relayer (meta-transaction)
     * @param _username Unique username in snake_case format
     * @param _mentorAddress Address of the mentor
     * @param _deadline Time until which the signature is valid
     * @param _v Recovery ID
     * @param _r ECDSA signature r value
     * @param _s ECDSA signature s value
     */
    function registerMentorByRelayer(
        string calldata _username,
        address _mentorAddress,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        // Validate username is not empty
        if (bytes(_username).length == 0) {
            revert EmptyUsername();
        }

        // Validate username format
        if (!_isValidSnakeCase(_username)) {
            revert InvalidUsernameFormat();
        }

        // Check if username already exists
        if (bytes(mentors[_username].username).length != 0) {
            revert UsernameAlreadyExists();
        }

        // Verify signature
        _verifySignature(
            MENTOR_REGISTER_TYPEHASH,
            _mentorAddress,
            _username,
            _mentorAddress,
            _deadline,
            _v,
            _r,
            _s
        );

        // Register the mentor
        mentors[_username] = Mentor({
            username: _username,
            currentAddress: _mentorAddress
        });

        // Emit event
        emit MentorRegisteredByRelayer(_username, _mentorAddress, msg.sender);
    }

    /**
     * @dev Update the address for an existing mentor (direct call)
     * @param _username Username of the mentor
     * @param _newAddress New address to set
     */
    function updateAddress(
        string calldata _username,
        address _newAddress
    ) external {
        // Check if mentor exists
        if (bytes(mentors[_username].username).length == 0) {
            revert MentorDoesNotExist();
        }

        Mentor storage mentor = mentors[_username];

        // Only the current address holder can update
        if (msg.sender != mentor.currentAddress) {
            revert Unauthorized();
        }

        // Store old address
        address oldAddress = mentor.currentAddress;

        // Update address
        mentor.currentAddress = _newAddress;

        // Emit event
        emit AddressUpdated(_username, oldAddress, _newAddress);
    }

    /**
     * @dev Update the address for an existing mentor via relayer (meta-transaction)
     * @param _username Username of the mentor
     * @param _newAddress New address to set
     * @param _deadline Time until which the signature is valid
     * @param _v Recovery ID
     * @param _r ECDSA signature r value
     * @param _s ECDSA signature s value
     */
    function updateAddressByRelayer(
        string calldata _username,
        address _newAddress,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        // Check if mentor exists
        if (bytes(mentors[_username].username).length == 0) {
            revert MentorDoesNotExist();
        }

        // Get current mentor
        Mentor storage mentor = mentors[_username];
        address mentorAddress = mentor.currentAddress;

        // Verify signature
        _verifySignature(
            ADDRESS_UPDATE_TYPEHASH,
            mentorAddress,
            _username,
            _newAddress,
            _deadline,
            _v,
            _r,
            _s
        );

        // Store old address
        address oldAddress = mentor.currentAddress;

        // Update address
        mentor.currentAddress = _newAddress;

        // Emit event
        emit AddressUpdatedByRelayer(
            _username,
            oldAddress,
            _newAddress,
            msg.sender
        );
    }

    /**
     * @dev Verify EIP-712 signature
     */
    function _verifySignature(
        bytes32 _typeHash,
        address _signer,
        string calldata _username,
        address _address,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal {
        // Check deadline
        if (block.timestamp > _deadline) {
            revert DeadlineExceeded();
        }

        // Get current nonce for the signer
        uint256 nonce = nonces[_signer];

        // Create the digest
        bytes32 domainSeparator = _domainSeparatorV4();
        bytes32 structHash = _hashStruct(
            _typeHash,
            _username,
            _address,
            nonce,
            _deadline
        );
        bytes32 digest = _buildTypedDataV4(domainSeparator, structHash);

        // Verify signature
        if (!_verify(digest, _v, _r, _s, _signer)) {
            revert InvalidSignature();
        }

        // Increment nonce to prevent replay
        nonces[_signer]++;
    }

    /**
     * @dev Verify ECDSA signature
     */
    function _verify(
        bytes32 _digest,
        uint8 _v,
        bytes32 _r,
        bytes32 _s,
        address _signer
    ) internal pure returns (bool) {
        address recovered = ecrecover(_digest, _v, _r, _s);
        return recovered == _signer;
    }

    /**
     * @dev Hash struct using inline assembly for gas efficiency
     */
    function _hashStruct(
        bytes32 _typeHash,
        string calldata _username,
        address _address,
        uint256 _nonce,
        uint256 _deadline
    ) internal pure returns (bytes32) {
        bytes memory data = abi.encode(
            _typeHash,
            _username,
            _address,
            _nonce,
            _deadline
        );
        bytes32 hash;

        assembly {
            hash := keccak256(add(data, 0x20), mload(data))
        }

        return hash;
    }

    /**
     * @dev Get mentor information by username
     * @param _username Username to look up
     * @return username The username
     * @return currentAddress The current address
     * @return exists Whether the mentor exists
     */
    function getMentor(
        string calldata _username
    )
        external
        view
        returns (string memory username, address currentAddress, bool exists)
    {
        Mentor memory mentor = mentors[_username];
        return (
            mentor.username,
            mentor.currentAddress,
            bytes(mentor.username).length != 0
        );
    }

    /**
     * @dev Check if a username exists
     * @param _username Username to check
     * @return exists True if username exists
     */
    function usernameExists(
        string calldata _username
    ) external view returns (bool exists) {
        return bytes(mentors[_username].username).length != 0;
    }

    /**
     * @dev Get nonce for an address
     * @param _address Address to get nonce for
     * @return nonce Current nonce
     */
    function getNonce(address _address) external view returns (uint256 nonce) {
        return nonces[_address];
    }

    /**
     * @dev Validate if username is in snake_case format
     * @param _username Username to validate
     * @return valid True if valid snake_case format
     */
    function _isValidSnakeCase(
        string calldata _username
    ) internal pure returns (bool valid) {
        bytes memory b = bytes(_username);
        if (b.length == 0) return false;

        // Check first character is lowercase letter or number
        if (!(_isLowerCaseLetter(b[0]) || _isNumber(b[0]))) {
            return false;
        }

        // Check all characters
        for (uint256 i = 0; i < b.length; i++) {
            if (!(_isLowerCaseLetter(b[i]) || _isNumber(b[i]) || b[i] == "_")) {
                return false;
            }
        }

        // Check no consecutive underscores
        for (uint256 i = 1; i < b.length; i++) {
            if (b[i] == "_" && b[i - 1] == "_") {
                return false;
            }
        }

        // Check doesn't start or end with underscore
        if (b[0] == "_" || b[b.length - 1] == "_") {
            return false;
        }

        return true;
    }

    /**
     * @dev Check if character is a lowercase letter
     */
    function _isLowerCaseLetter(bytes1 c) internal pure returns (bool) {
        return (c >= "a" && c <= "z");
    }

    /**
     * @dev Check if character is a number
     */
    function _isNumber(bytes1 c) internal pure returns (bool) {
        return (c >= "0" && c <= "9");
    }

    /**
     * @dev EIP-712: The hash of the complete typed data structure
     */
    function _buildTypedDataV4(
        bytes32 _domainSeparator,
        bytes32 _structHash
    ) internal pure returns (bytes32 digest) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, "\x19\x01")
            mstore(add(ptr, 0x02), _domainSeparator)
            mstore(add(ptr, 0x22), _structHash)
            digest := keccak256(ptr, 0x42)
        }
    }

    /**
     * @dev EIP-712: Domain separator to prevent replay attacks
     */
    function _domainSeparatorV4() internal view returns (bytes32) {
        bytes memory data = abi.encode(
            _DOMAIN_TYPE_HASH,
            _DOMAIN_NAME_HASH,
            _DOMAIN_VERSION_HASH,
            block.chainid,
            address(this)
        );
        bytes32 hash;

        assembly {
            hash := keccak256(add(data, 0x20), mload(data))
        }

        return hash;
    }
}
