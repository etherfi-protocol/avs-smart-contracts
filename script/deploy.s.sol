```solidity
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

        require(Address.isContract(newManagerImpl), "New manager implementation is not a contract");
        require(Address.isContract(newOperatorImpl), "New operator implementation is not a contract");

        console2.log("New manager:", newManagerImpl);
        console2.log("New operator:", newOperatorImpl);
        vm.stopBroadcast();
    }
}
```
