// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/**
 * @title MinimalForwarder
 * @dev Minimal forwarder contract for gasless meta-transactions
 *
 * This contract allows a relayer to execute transactions on behalf of a user
 * without the user paying gas fees. The user signs a request that the relayer
 * then executes.
 */
contract MinimalForwarder {
    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
        uint256 deadline;
    }

    bytes32 private constant _TYPEHASH =
        keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data,uint256 deadline)");

    // EIP-712: Domain separator components (precomputed for gas optimization)
    bytes32 private constant _DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _DOMAIN_NAME_HASH = keccak256("MinimalForwarder");
    bytes32 private constant _DOMAIN_VERSION_HASH = keccak256("1");

    mapping(address => uint256) public nonces;

    event ExecutedForwardRequest(
        address indexed from,
        address indexed to,
        bool success,
        bytes returnData
    );

    error DeadlineExceeded();
    error ReplayAttack();
    error ForwardCallFailed();

    /**
     * @dev Get the domain separator for EIP-712 signature
     */
    function getDomainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                _DOMAIN_TYPE_HASH,
                _DOMAIN_NAME_HASH,
                _DOMAIN_VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @dev Get the current nonce for an address
     */
    function getNonce(address from) public view returns (uint256) {
        return nonces[from];
    }

    /**
     * @dev Execute a forward request
     * @param req The forward request containing:
     *   - from: The user who signed the request
     *   - to: The contract to call
     *   - value: ETH value to send (usually 0)
     *   - gas: Gas limit for the call
     *   - nonce: Nonce to prevent replay attacks
     *   - data: Calldata to execute
     *   - deadline: Expiration timestamp
     * @param signature The EIP-712 signature from the user
     * @return success True if the call succeeded
     * @return returnData The return data from the call
     */
    function execute(
        ForwardRequest calldata req,
        bytes calldata signature
    ) external payable returns (bool success, bytes memory returnData) {
        // Check deadline
        if (block.timestamp > req.deadline) {
            revert DeadlineExceeded();
        }

        // Check nonce
        if (nonces[req.from] != req.nonce) {
            revert ReplayAttack();
        }

        // Build the digest
        bytes32 dataHash = keccak256(req.data);
        bytes32 structHash = keccak256(
            abi.encode(
                _TYPEHASH,
                req.from,
                req.to,
                req.value,
                req.gas,
                req.nonce,
                dataHash,
                req.deadline
            )
        );

        bytes32 domainSeparator = getDomainSeparator();
        bytes32 digest;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, "\x19\x01")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            digest := keccak256(ptr, 0x42)
        }

        // Verify signature
        address signer = ecrecover(digest, uint8(signature[64]), bytes32(signature[:32]), bytes32(signature[32:64]));
        if (signer != req.from) {
            revert ReplayAttack();
        }

        // Increment nonce
        nonces[req.from]++;

        // Execute the call
        (success, returnData) = req.to.call{gas: req.gas, value: req.value}(req.data);

        emit ExecutedForwardRequest(req.from, req.to, success, returnData);

        return (success, returnData);
    }
}
