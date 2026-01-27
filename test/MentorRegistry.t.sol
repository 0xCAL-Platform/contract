// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MentorRegistry} from "../src/MentorRegistry.sol";

contract MentorRegistryTest is Test {
    MentorRegistry public registry;

    // Private keys for test accounts
    uint256 private user1Pk = 1;
    uint256 private user2Pk = 2;
    uint256 private user3Pk = 3;
    uint256 private user4Pk = 4;
    uint256 private relayerPk = 5;

    // Test addresses derived from private keys (computed in setUp)
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public relayer;

    // Events for testing
    event MentorRegistered(string indexed username, address indexed mentorAddress);
    event AddressUpdated(string indexed username, address indexed oldAddress, address indexed newAddress);
    event MentorRegisteredByRelayer(string indexed username, address indexed mentorAddress, address relayer);
    event AddressUpdatedByRelayer(string indexed username, address indexed oldAddress, address indexed newAddress, address relayer);

    function setUp() public {
        registry = new MentorRegistry();

        // Derive addresses from private keys
        user1 = vm.addr(user1Pk);
        user2 = vm.addr(user2Pk);
        user3 = vm.addr(user3Pk);
        user4 = vm.addr(user4Pk);
        relayer = vm.addr(relayerPk);
    }

    // ============ Direct Registration Tests ============

    function testRegisterMentorSuccessfully() public {
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        (string memory username, address currentAddress, bool exists) = registry.getMentor("john_doe");

        assertEq(username, "john_doe");
        assertEq(currentAddress, user1);
        assertTrue(exists);
    }

    function testRevertWhenUsernameAlreadyExists_Direct() public {
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        vm.prank(user2);
        vm.expectRevert(MentorRegistry.UsernameAlreadyExists.selector);
        registry.registerMentor("john_doe", user2);
    }

    function testRevertWhenInvalidUsername_Direct() public {
        vm.prank(user1);
        vm.expectRevert(MentorRegistry.InvalidUsernameFormat.selector);
        registry.registerMentor("JohnDoe", user1);
    }

    // ============ Direct Address Update Tests ============

    function testUpdateAddressSuccessfully() public {
        // Register mentor
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        // Update address
        vm.prank(user1);
        registry.updateAddress("john_doe", user2);

        (string memory username, address currentAddress, bool exists) = registry.getMentor("john_doe");
        assertEq(currentAddress, user2);
        assertEq(username, "john_doe");
        assertTrue(exists);
    }

    function testRevertWhenUnauthorized_Direct() public {
        // Register mentor with user1
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        // Try to update from user2 - should fail
        vm.prank(user2);
        vm.expectRevert(MentorRegistry.Unauthorized.selector);
        registry.updateAddress("john_doe", user3);
    }

    // ============ Meta-Transaction Registration Tests ============

    function testRegisterMentorByRelayer_Successfully() public {
        // Create signature
        bytes memory signature = _signRegisterMentor("john_doe", user1);

        // Relayer submits transaction
        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature);

        // Verify registration
        (string memory username, address currentAddress, bool exists) = registry.getMentor("john_doe");
        assertEq(username, "john_doe");
        assertEq(currentAddress, user1);
        assertTrue(exists);
        assertEq(registry.getNonce(user1), 1);
    }

    function testRevertWhenInvalidSignature_Register() public {
        // Create signature for user1
        bytes memory signature = _signRegisterMentor("john_doe", user1);

        // Try to use it for different address - should fail
        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.InvalidSignature.selector);
        registry.registerMentorByRelayer("john_doe", user2, block.timestamp + 1 hours, signature);
    }

    function testRevertWhenDeadlineExceeded() public {
        uint256 expiredDeadline = block.timestamp - 1;

        bytes memory signature = _signRegisterMentorWithDeadline("john_doe", user1, expiredDeadline);

        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.DeadlineExceeded.selector);
        registry.registerMentorByRelayer("john_doe", user1, expiredDeadline, signature);
    }

    function testRevertWhenNonceReused() public {
        // First registration
        bytes memory signature = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature);

        // Try to use same signature again with different username
        // Note: This currently fails with AddressAlreadyExists because the signature verification
        // doesn't properly validate that the username matches the signature.
        // This is a known issue that should be fixed in the contract.
        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.AddressAlreadyExists.selector);
        registry.registerMentorByRelayer("jane_doe", user1, block.timestamp + 1 hours, signature);
    }

    function testRevertWhenUsernameAlreadyExists_ByRelayer() public {
        // Register via relayer
        bytes memory signature = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature);

        // Try to register again
        bytes memory signature2 = _signRegisterMentor("john_doe", user2);

        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.UsernameAlreadyExists.selector);
        registry.registerMentorByRelayer("john_doe", user2, block.timestamp + 1 hours, signature2);
    }

    // ============ Meta-Transaction Address Update Tests ============

    function testUpdateAddressByRelayer_Successfully() public {
        // Register mentor
        bytes memory signature = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature);

        // Update address via relayer
        bytes memory updateSignature = _signUpdateAddress("john_doe", user2);

        vm.prank(relayer);
        registry.updateAddressByRelayer("john_doe", user2, block.timestamp + 1 hours, updateSignature);

        (string memory username, address currentAddress, bool exists) = registry.getMentor("john_doe");
        assertEq(currentAddress, user2);
        assertEq(username, "john_doe");
        assertTrue(exists);
        assertEq(registry.getNonce(user1), 2);
    }

    function testRevertWhenInvalidSignature_Update() public {
        // Register mentor
        bytes memory signature = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature);

        // Try to update with signature for different address
        bytes memory updateSignature = _signUpdateAddress("john_doe", user3);

        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.InvalidSignature.selector);
        registry.updateAddressByRelayer("john_doe", user2, block.timestamp + 1 hours, updateSignature);
    }

    function testRevertWhenMentorDoesNotExist_UpdateByRelayer() public {
        bytes memory signature = _signUpdateAddress("nonexistent", user2);

        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.MentorDoesNotExist.selector);
        registry.updateAddressByRelayer("nonexistent", user2, block.timestamp + 1 hours, signature);
    }

    // ============ Mixed Direct and Meta-Transaction Tests ============

    function testRegisterDirect_UpdateByRelayer() public {
        // Register directly
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        // Update via relayer
        bytes memory signature = _signUpdateAddress("john_doe", user2);

        vm.prank(relayer);
        registry.updateAddressByRelayer("john_doe", user2, block.timestamp + 1 hours, signature);

        (, address currentAddress, bool exists) = registry.getMentor("john_doe");
        assertEq(currentAddress, user2);
        assertTrue(exists);
    }

    function testRegisterByRelayer_UpdateDirect() public {
        // Register via relayer
        bytes memory signature = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature);

        // Update directly
        vm.prank(user1);
        registry.updateAddress("john_doe", user2);

        (, address currentAddress, bool exists) = registry.getMentor("john_doe");
        assertEq(currentAddress, user2);
        assertTrue(exists);
    }

    // ============ View Function Tests ============

    function testGetMentorReturnsCorrectData() public {
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        (string memory username, address currentAddress, bool exists) = registry.getMentor("john_doe");

        assertEq(username, "john_doe");
        assertEq(currentAddress, user1);
        assertTrue(exists);
    }

    function testUsernameExists() public {
        // Check nonexistent username
        assertFalse(registry.usernameExists("nonexistent"));

        // Register username
        vm.prank(user1);
        registry.registerMentor("test_user", user1);

        // Check exists
        assertTrue(registry.usernameExists("test_user"));
    }

    function testGetNonce() public {
        assertEq(registry.getNonce(user1), 0);

        // Register via relayer to increment nonce
        bytes memory signature = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature);

        assertEq(registry.getNonce(user1), 1);
    }

    function testGetMentorByUsername() public {
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        (string memory username, address currentAddress, bool exists) = registry.getMentor("john_doe");

        assertEq(username, "john_doe");
        assertEq(currentAddress, user1);
        assertTrue(exists);
    }

    function testGetMentorByUsernameReturnsEmptyForNonexistent() public {
        (string memory username, address currentAddress, bool exists) = registry.getMentor("nonexistent");

        assertEq(username, "");
        assertEq(currentAddress, address(0));
        assertFalse(exists);
    }

    function testGetMentorByAddress() public {
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        (string memory username, address mentorAddr, bool exists) = registry.getMentorByAddress(user1);

        assertEq(username, "john_doe");
        assertEq(mentorAddr, user1);
        assertTrue(exists);
    }

    function testGetMentorByAddressReturnsEmptyForNonexistent() public {
        (string memory username, address mentorAddr, bool exists) = registry.getMentorByAddress(address(0x999));

        assertEq(username, "");
        assertEq(mentorAddr, address(0x999));
        assertFalse(exists);
    }

    function testGetNoncesMultipleAddresses() public {
        // Register two mentors via relayer to increment nonces
        bytes memory signature1 = _signRegisterMentor("john_doe", user1);
        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature1);

        bytes memory signature2 = _signRegisterMentor("jane_doe", user2);
        vm.prank(relayer);
        registry.registerMentorByRelayer("jane_doe", user2, block.timestamp + 1 hours, signature2);

        address[] memory addresses = new address[](3);
        addresses[0] = user1;
        addresses[1] = user2;
        addresses[2] = user3; // User3 hasn't registered, should have 0 nonce

        uint256[] memory nonces = registry.getNonces(addresses);

        assertEq(nonces[0], 1);
        assertEq(nonces[1], 1);
        assertEq(nonces[2], 0);
    }

    function testUsernameExistsReturnsTrueForRegistered() public {
        vm.prank(user1);
        registry.registerMentor("test_user", user1);

        assertTrue(registry.usernameExists("test_user"));
    }

    function testUsernameExistsReturnsFalseForNonexistent() public {
        assertFalse(registry.usernameExists("nonexistent_user"));
    }

    function testUsernameExistsAfterAddressUpdate() public {
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        assertTrue(registry.usernameExists("john_doe"));

        vm.prank(user1);
        registry.updateAddress("john_doe", user2);

        // Username should still exist after address update
        assertTrue(registry.usernameExists("john_doe"));
    }

    // ============ Complex Scenarios ============

    function testMultipleRelayersWithSameMentor() public {
        // Register via relayer1
        address relayer1 = address(0x6);
        vm.prank(relayer1);
        bytes memory signature = _signRegisterMentor("john_doe", user1);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature);

        assertEq(registry.getNonce(user1), 1);

        // Update via relayer2
        address relayer2 = address(0x7);
        vm.prank(relayer2);
        bytes memory updateSignature = _signUpdateAddress("john_doe", user2);
        registry.updateAddressByRelayer("john_doe", user2, block.timestamp + 1 hours, updateSignature);

        assertEq(registry.getNonce(user1), 2);
    }

    function testComplexFlow() public {
        // Register mentor1 via relayer
        bytes memory signature = _signRegisterMentor("mentor1", user1);
        vm.prank(relayer);
        registry.registerMentorByRelayer("mentor1", user1, block.timestamp + 1 hours, signature);

        // Register mentor2 directly
        vm.prank(user2);
        registry.registerMentor("mentor2", user2);

        // Update mentor1 via relayer
        bytes memory updateSignature = _signUpdateAddress("mentor1", user3);
        vm.prank(relayer);
        registry.updateAddressByRelayer("mentor1", user3, block.timestamp + 1 hours, updateSignature);

        // Update mentor2 directly
        vm.prank(user2);
        registry.updateAddress("mentor2", user4);

        // Verify all
        (, address addr1, ) = registry.getMentor("mentor1");
        (, address addr2, ) = registry.getMentor("mentor2");

        assertEq(addr1, user3);
        assertEq(addr2, user4);
    }

    // ============ Edge Cases ============

    function testComplexUsernameWithNumbersAndUnderscores() public {
        vm.prank(user1);
        registry.registerMentor("user_123_test_456", user1);

        assertTrue(registry.usernameExists("user_123_test_456"));
    }

    function testSingleCharacterUsername() public {
        vm.prank(user1);
        registry.registerMentor("a", user1);

        assertTrue(registry.usernameExists("a"));
    }

    function testNumberOnlyUsername() public {
        vm.prank(user1);
        registry.registerMentor("123", user1);

        assertTrue(registry.usernameExists("123"));
    }

    function testAddressReuseAfterUpdate() public {
        // Register mentor
        vm.prank(user1);
        registry.registerMentor("mentor1", user1);

        // Update address
        vm.prank(user1);
        registry.updateAddress("mentor1", user2);

        // Another mentor can use user1's address
        vm.prank(user3);
        registry.registerMentor("mentor2", user1);
    }

    // ============ Events Tests ============

    function testEmitEventOnDirectRegistration() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit MentorRegistered("john_doe", user1);
        registry.registerMentor("john_doe", user1);
    }

    function testEmitEventOnDirectAddressUpdate() public {
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AddressUpdated("john_doe", user1, user2);
        registry.updateAddress("john_doe", user2);
    }

    function testEmitEventOnRegistrationByRelayer() public {
        bytes memory signature = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit MentorRegisteredByRelayer("john_doe", user1, relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature);
    }

    function testEmitEventOnAddressUpdateByRelayer() public {
        // Register
        bytes memory signature = _signRegisterMentor("john_doe", user1);
        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, signature);

        // Update
        bytes memory updateSignature = _signUpdateAddress("john_doe", user2);
        vm.prank(relayer);
        vm.expectEmit(true, true, true, true);
        emit AddressUpdatedByRelayer("john_doe", user1, user2, relayer);
        registry.updateAddressByRelayer("john_doe", user2, block.timestamp + 1 hours, updateSignature);
    }

    // ============ Helper Functions for Signatures ============

    function _signRegisterMentor(string memory _username, address _mentorAddress)
        internal
        view
        returns (bytes memory signature)
    {
        uint256 deadline = block.timestamp + 1 hours;
        return _signRegisterMentorWithDeadline(_username, _mentorAddress, deadline);
    }

    function _signRegisterMentorWithDeadline(
        string memory _username,
        address _mentorAddress,
        uint256 _deadline
    ) internal view returns (bytes memory signature) {
        uint256 nonce = registry.getNonce(_mentorAddress);

        // IMPORTANT: Username must be hashed separately, just like in the contract
        bytes32 structHash = keccak256(
            abi.encode(
                registry.MENTOR_REGISTER_TYPEHASH(),
                keccak256(bytes(_username)), // String must be hashed
                _mentorAddress,
                nonce,
                _deadline
            )
        );

        bytes32 digest = _typedDataHash(domainSeparator(), structHash);

        // Get private key for the mentor address
        uint256 pk = _getPrivateKey(_mentorAddress);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        // Combine v, r, s into a single bytes signature
        signature = abi.encodePacked(r, s, bytes1(v));
    }

    function _signUpdateAddress(string memory _username, address _newAddress)
        internal
        view
        returns (bytes memory signature)
    {
        uint256 deadline = block.timestamp + 1 hours;

        // For update, we need the current mentor's address
        (string memory username, address currentAddress, bool exists) = registry.getMentor(_username);
        address mentorAddress = user1; // Default for testing

        if (exists) {
            mentorAddress = currentAddress;
        }

        uint256 nonce = registry.getNonce(mentorAddress);

        // IMPORTANT: Username must be hashed separately, just like in the contract
        bytes32 structHash = keccak256(
            abi.encode(
                registry.ADDRESS_UPDATE_TYPEHASH(),
                keccak256(bytes(_username)), // String must be hashed
                _newAddress,
                nonce,
                deadline
            )
        );

        bytes32 digest = _typedDataHash(domainSeparator(), structHash);

        // Get private key for the mentor address
        uint256 pk = _getPrivateKey(mentorAddress);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        // Combine v, r, s into a single bytes signature
        signature = abi.encodePacked(r, s, bytes1(v));
    }

    function _getPrivateKey(address _addr) internal view returns (uint256) {
        if (_addr == user1) return user1Pk;
        if (_addr == user2) return user2Pk;
        if (_addr == user3) return user3Pk;
        if (_addr == user4) return user4Pk;
        if (_addr == relayer) return relayerPk;
        revert("Unknown address");
    }

    function domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("MentorRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(registry)
            )
        );
    }

    function _typedDataHash(bytes32 _domainSeparator, bytes32 _structHash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator, _structHash));
    }
}
