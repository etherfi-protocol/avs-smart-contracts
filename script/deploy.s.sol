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

/// @notice Deploys a new AvsOperatorManager implementation and logs the upgradeToAndCall
/// calldata needed to upgrade the proxy and initialize the AllocationManager block.
/// The actual upgrade transaction must be executed by the proxy owner (multisig / timelock).
contract DeployTierBUpgrade is Script {

    // TODO(deploy): replace with the confirmed EigenLayer AllocationManager proxy address
    address constant ALLOCATION_MANAGER = address(0);

    function run() public {
        require(ALLOCATION_MANAGER != address(0), "Set ALLOCATION_MANAGER before deploying");

        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);
        address newManagerImpl = address(new AvsOperatorManager());
        vm.stopBroadcast();

        bytes memory initData = abi.encodeCall(AvsOperatorManager.initializeV2, (ALLOCATION_MANAGER));
        bytes memory upgradeCalldata = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)",
            newManagerImpl,
            initData
        );

        console2.log("New implementation:", newManagerImpl);
        console2.log("AllocationManager blocked:", ALLOCATION_MANAGER);
        console2.log("upgradeToAndCall calldata:");
        console2.logBytes(upgradeCalldata);
    }
}
