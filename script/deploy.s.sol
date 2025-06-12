// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import "../src/AvsOperator.sol";
import "../src/AvsOperatorManager.sol";

import "forge-std/console2.sol";

contract DeployAvsContracts is Script {

    function run() public {

        // TODO(dave): set
        address roleRegistry;
        address strategyManager;
        address delegationManager;
        address etherfiRestaker;
        if (roleRegistry == address(0) || strategyManager == address(0) || delegationManager == address(0) || etherfiRestaker == address(0)) {
            revert("must set addresses");
        }

        vm.startBroadcast(address(0xf8a86ea1Ac39EC529814c377Bd484387D395421e));
        address newManagerImpl = address(new AvsOperatorManager(roleRegistry));
        address newOperatorImpl = address(new AvsOperator(strategyManager, delegationManager, etherfiRestaker));

        console2.log("New manager:", newManagerImpl);
        console2.log("New operator:", newOperatorImpl);
        vm.stopBroadcast();

    }
}
