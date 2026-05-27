// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRoleRegistry
 * @notice Interface for the RoleRegistry contract
 * @dev Defines the external interface for RoleRegistry with role management functions
 * @author ether.fi
 */
interface IRoleRegistry {
    /**
     * @dev Error thrown when a function is called by an account without the operating multisig role
     */
    error OnlyOperatingMultisig();
    /**
     * @notice Grants a role to an account
     * @dev Only callable by the contract owner
     * @param role The role to grant (as bytes32)
     * @param account The address to grant the role to
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @notice Revokes a role from an account
     * @dev Only callable by the contract owner
     * @param role The role to revoke (as bytes32)
     * @param account The address to revoke the role from
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @notice Checks if an account is the operating multisig
     * @dev Reverts if the account is not the operating multisig
     * @param account The address to check
     */
    function onlyOperatingMultisig(address account) external view;
}
