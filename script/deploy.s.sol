```
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

        // Add the git submodule update command
        string[] memory cmds = new string[](3);
        cmds[0] = "git";
        cmds[1] = "submodule";
        cmds[2] = "update --init --recursive";
        vm.ffi(cmds);

        // Add the forge build command
        string[] memory forgeCmds = new string[](2);
        forgeCmds[0] = "forge";
        forgeCmds[1] = "build";
        vm.ffi(forgeCmds);
    }
}
