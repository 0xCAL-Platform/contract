// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title MockIDRX
 * @dev Mock ERC20 token for IDRX with enhanced features
 *
 * Features:
 * - ERC20 standard implementation with 2 decimals (unusual but requested)
 * - Permit (EIP-2612) for gasless meta-transactions
 * - Burnable tokens for flexibility
 * - Pausable emergency stop mechanism
 * - Role-based access control (RBAC)
 *
 * This is a comprehensive mock token suitable for testing complex DeFi scenarios.
 */
contract MockIDRX is ERC20, ERC20Permit, ERC20Burnable, ERC20Pausable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * Overridden to return 2 instead of the default 18.
     */
    function decimals() public pure override returns (uint8) {
        return 2;
    }

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, and `PAUSER_ROLE` to the deployer.
     */
    constructor() ERC20("Mock IDRX", "mIDRX") ERC20Permit("Mock IDRX") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /**
     * @dev Mints `amount` tokens to `to`, increasing the total supply.
     * Can only be called by accounts with `MINTER_ROLE`.
     *
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Pauses all token transfers.
     * Can only be called by accounts with `PAUSER_ROLE`.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     * Can only be called by accounts with `PAUSER_ROLE`.
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Hook that is called before any transfer of tokens.
     * This includes minting and burning, and also pausing.
     *
     * Calling conditions:
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     *   will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - the transfer is not paused.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, amount);
    }
}
