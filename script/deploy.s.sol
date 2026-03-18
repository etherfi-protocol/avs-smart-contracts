// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import "../src/AvsOperator.sol";
import "../src/AvsOperatorManager.sol";

import "forge-std/console2.sol";

contract DeployAvsContracts is Script {

    function run() public {

        vm.startBroadcast(address(0xf8a86ea1Ac39EC529814c377Bd484387D395421e));
        address newManagerImpl = address(new AvsOperatorManager());
        address newOperatorImpl = address(new AvsOperator());

        console2.log("New manager:", newManagerImpl);
        console2.log("New operator:", newOperatorImpl);
        vm.stopBroadcast();

    }
}

/// @notice Deploys a new AvsOperatorManager implementation that enforces the whitelist
/// on all call paths (including adminForwardCall) and restricts whitelist updates to owner.
/// The actual upgrade transaction must be executed by the proxy owner (multisig / timelock).
contract DeployWhitelistEnforcementUpgrade is Script {

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);
        address newManagerImpl = address(new AvsOperatorManager());
        vm.stopBroadcast();

        bytes memory upgradeCalldata = abi.encodeWithSignature(
            "upgradeTo(address)",
            newManagerImpl
        );

        console2.log("New implementation:", newManagerImpl);
        console2.log("upgradeTo calldata:");
        console2.logBytes(upgradeCalldata);
    }
}
