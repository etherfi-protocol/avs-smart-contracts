// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRoleRegistry
/// @notice Minimal interface for the etherfi shared RoleRegistry consumed by this contract.
/// @dev Mirrors the production RoleRegistry deployed alongside the etherfi smart-contracts repo.
interface IRoleRegistry {
    error OnlyProtocolUpgrader();

    function PROTOCOL_PAUSER() external view returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function onlyProtocolUpgrader(address account) external view;
}
