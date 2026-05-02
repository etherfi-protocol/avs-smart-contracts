// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../src/interfaces/IRoleRegistry.sol";

/// @notice Minimal in-test stand-in for the production RoleRegistry. Avoids vendoring solady.
contract MockRoleRegistry is IRoleRegistry {
    bytes32 public constant override PROTOCOL_PAUSER = keccak256("PROTOCOL_PAUSER");

    address public protocolUpgrader;
    mapping(bytes32 => mapping(address => bool)) private roles;

    constructor(address _protocolUpgrader) {
        protocolUpgrader = _protocolUpgrader;
    }

    function grantRole(bytes32 role, address account) external {
        roles[role][account] = true;
    }

    function revokeRole(bytes32 role, address account) external {
        roles[role][account] = false;
    }

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        return roles[role][account];
    }

    function onlyProtocolUpgrader(address account) external view override {
        if (account != protocolUpgrader) revert OnlyProtocolUpgrader();
    }
}
