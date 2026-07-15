// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../src/interfaces/IRoleRegistry.sol";

/// @notice Minimal in-test stand-in for the production RoleRegistry. Avoids vendoring solady.
contract MockRoleRegistry is IRoleRegistry {
    bytes32 public constant OPERATING_MULTISIG = keccak256("OPERATING_MULTISIG");

    address public operatingMultisig;
    mapping(bytes32 => mapping(address => bool)) private roles;

    constructor(address _operatingMultisig) {
        operatingMultisig = _operatingMultisig;
    }

    function grantRole(bytes32 role, address account) external {
        roles[role][account] = true;
    }

    function revokeRole(bytes32 role, address account) external {
        roles[role][account] = false;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return roles[role][account];
    }

    function onlyOperatingMultisig(address account) external view override {
        if (!hasRole(OPERATING_MULTISIG, account)) revert OnlyOperatingMultisig();
    }
}
