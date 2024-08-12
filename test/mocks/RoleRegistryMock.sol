// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../src/IRoleRegistry.sol";

contract RoleRegistryMock is IRoleRegistry {

    mapping(bytes32 => mapping(address => bool)) public roles;
    string public test = "hello";

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    constructor() {}

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return roles[role][account];
    }

    function grantRole(bytes32 role, address account) external {
        if (!hasRole(role, account)) {
            roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) external {
        if (hasRole(role, account)) {
            roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }
}
