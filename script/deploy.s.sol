// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import "../src/AvsOperator.sol";
import "../src/AvsOperatorManager.sol";

import "forge-std/console2.sol";

contract DeployAvsContracts is Script {

    function run() public {

        // TODO: set me
        address roleRegistry = address(0x0);
        assert(roleRegistry != address(0x0));
        address avsOperatorManager = address(0x0);
        assert(avsOperatorManager != address(0x0));

        vm.startBroadcast(address(0xf8a86ea1Ac39EC529814c377Bd484387D395421e));
        address newManagerImpl = address(new AvsOperatorManager(roleRegistry));
        address newOperatorImpl = address(new AvsOperator(avsOperatorManager, roleRegistry));

        console2.log("New manager:", newManagerImpl);
        console2.log("New operator:", newOperatorImpl);
        vm.stopBroadcast();

    }
}
