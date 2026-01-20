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
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);

        // Relayer submits transaction
        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, v, r, s);

        // Verify registration
        (string memory username, address currentAddress, bool exists) = registry.getMentor("john_doe");
        assertEq(username, "john_doe");
        assertEq(currentAddress, user1);
        assertTrue(exists);
        assertEq(registry.getNonce(user1), 1);
    }

    function testRevertWhenInvalidSignature_Register() public {
        // Create signature for user1
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);

        // Try to use it for different address - should fail
        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.InvalidSignature.selector);
        registry.registerMentorByRelayer("john_doe", user2, block.timestamp + 1 hours, v, r, s);
    }

    function testRevertWhenDeadlineExceeded() public {
        uint256 expiredDeadline = block.timestamp - 1;

        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentorWithDeadline("john_doe", user1, expiredDeadline);

        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.DeadlineExceeded.selector);
        registry.registerMentorByRelayer("john_doe", user1, expiredDeadline, v, r, s);
    }

    function testRevertWhenNonceReused() public {
        // First registration
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, v, r, s);

        // Try to use same signature again with different username - should fail due to nonce mismatch
        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.InvalidSignature.selector);
        registry.registerMentorByRelayer("jane_doe", user1, block.timestamp + 1 hours, v, r, s);
    }

    function testRevertWhenUsernameAlreadyExists_ByRelayer() public {
        // Register via relayer
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, v, r, s);

        // Try to register again
        (uint8 v2, bytes32 r2, bytes32 s2) = _signRegisterMentor("john_doe", user2);

        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.UsernameAlreadyExists.selector);
        registry.registerMentorByRelayer("john_doe", user2, block.timestamp + 1 hours, v2, r2, s2);
    }

    // ============ Meta-Transaction Address Update Tests ============

    function testUpdateAddressByRelayer_Successfully() public {
        // Register mentor
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, v, r, s);

        // Update address via relayer
        (v, r, s) = _signUpdateAddress("john_doe", user2);

        vm.prank(relayer);
        registry.updateAddressByRelayer("john_doe", user2, block.timestamp + 1 hours, v, r, s);

        (string memory username, address currentAddress, bool exists) = registry.getMentor("john_doe");
        assertEq(currentAddress, user2);
        assertEq(username, "john_doe");
        assertTrue(exists);
        assertEq(registry.getNonce(user1), 2);
    }

    function testRevertWhenInvalidSignature_Update() public {
        // Register mentor
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, v, r, s);

        // Try to update with signature for different address
        (v, r, s) = _signUpdateAddress("john_doe", user3);

        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.InvalidSignature.selector);
        registry.updateAddressByRelayer("john_doe", user2, block.timestamp + 1 hours, v, r, s);
    }

    function testRevertWhenMentorDoesNotExist_UpdateByRelayer() public {
        (uint8 v, bytes32 r, bytes32 s) = _signUpdateAddress("nonexistent", user2);

        vm.prank(relayer);
        vm.expectRevert(MentorRegistry.MentorDoesNotExist.selector);
        registry.updateAddressByRelayer("nonexistent", user2, block.timestamp + 1 hours, v, r, s);
    }

    // ============ Mixed Direct and Meta-Transaction Tests ============

    function testRegisterDirect_UpdateByRelayer() public {
        // Register directly
        vm.prank(user1);
        registry.registerMentor("john_doe", user1);

        // Update via relayer
        (uint8 v, bytes32 r, bytes32 s) = _signUpdateAddress("john_doe", user2);

        vm.prank(relayer);
        registry.updateAddressByRelayer("john_doe", user2, block.timestamp + 1 hours, v, r, s);

        (, address currentAddress, bool exists) = registry.getMentor("john_doe");
        assertEq(currentAddress, user2);
        assertTrue(exists);
    }

    function testRegisterByRelayer_UpdateDirect() public {
        // Register via relayer
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, v, r, s);

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
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, v, r, s);

        assertEq(registry.getNonce(user1), 1);
    }

    // ============ Complex Scenarios ============

    function testMultipleRelayersWithSameMentor() public {
        // Register via relayer1
        address relayer1 = address(0x6);
        vm.prank(relayer1);
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, v, r, s);

        assertEq(registry.getNonce(user1), 1);

        // Update via relayer2
        address relayer2 = address(0x7);
        vm.prank(relayer2);
        (v, r, s) = _signUpdateAddress("john_doe", user2);
        registry.updateAddressByRelayer("john_doe", user2, block.timestamp + 1 hours, v, r, s);

        assertEq(registry.getNonce(user1), 2);
    }

    function testComplexFlow() public {
        // Register mentor1 via relayer
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("mentor1", user1);
        vm.prank(relayer);
        registry.registerMentorByRelayer("mentor1", user1, block.timestamp + 1 hours, v, r, s);

        // Register mentor2 directly
        vm.prank(user2);
        registry.registerMentor("mentor2", user2);

        // Update mentor1 via relayer
        (v, r, s) = _signUpdateAddress("mentor1", user3);
        vm.prank(relayer);
        registry.updateAddressByRelayer("mentor1", user3, block.timestamp + 1 hours, v, r, s);

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
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);

        vm.prank(relayer);
        vm.expectEmit(true, true, true, true);
        emit MentorRegisteredByRelayer("john_doe", user1, relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, v, r, s);
    }

    function testEmitEventOnAddressUpdateByRelayer() public {
        // Register
        (uint8 v, bytes32 r, bytes32 s) = _signRegisterMentor("john_doe", user1);
        vm.prank(relayer);
        registry.registerMentorByRelayer("john_doe", user1, block.timestamp + 1 hours, v, r, s);

        // Update
        (v, r, s) = _signUpdateAddress("john_doe", user2);
        vm.prank(relayer);
        vm.expectEmit(true, true, true, true);
        emit AddressUpdatedByRelayer("john_doe", user1, user2, relayer);
        registry.updateAddressByRelayer("john_doe", user2, block.timestamp + 1 hours, v, r, s);
    }

    // ============ Helper Functions for Signatures ============

    function _signRegisterMentor(string memory _username, address _mentorAddress)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        uint256 deadline = block.timestamp + 1 hours;
        return _signRegisterMentorWithDeadline(_username, _mentorAddress, deadline);
    }

    function _signRegisterMentorWithDeadline(
        string memory _username,
        address _mentorAddress,
        uint256 _deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        uint256 nonce = registry.getNonce(_mentorAddress);

        bytes32 structHash = keccak256(
            abi.encode(registry.MENTOR_REGISTER_TYPEHASH(), _username, _mentorAddress, nonce, _deadline)
        );

        bytes32 digest = _typedDataHash(domainSeparator(), structHash);

        // Get private key for the mentor address
        uint256 pk = _getPrivateKey(_mentorAddress);
        return vm.sign(pk, digest);
    }

    function _signUpdateAddress(string memory _username, address _newAddress)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        uint256 deadline = block.timestamp + 1 hours;

        // For update, we need the current mentor's address
        (,, bool exists) = registry.getMentor(_username);
        address mentorAddress = user1; // Default for testing

        if (exists) {
            (, mentorAddress, ) = registry.getMentor(_username);
        }

        uint256 nonce = registry.getNonce(mentorAddress);

        bytes32 structHash = keccak256(
            abi.encode(registry.ADDRESS_UPDATE_TYPEHASH(), _username, _newAddress, nonce, deadline)
        );

        bytes32 digest = _typedDataHash(domainSeparator(), structHash);

        // Get private key for the mentor address
        uint256 pk = _getPrivateKey(mentorAddress);
        return vm.sign(pk, digest);
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
