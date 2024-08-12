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

        // TESTNET
        vm.selectFork(vm.createFork(vm.envString("HOLESKY_RPC_URL")));
        AvsOperatorManager avsOperatorManager = AvsOperatorManager(address(0xDF9679E8BFce22AE503fD2726CB1218a18CD8Bf4));

        // sanity check
        address sanityOperator = address(avsOperatorManager.avsOperators(1));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy new implementations
        address newManagerImpl = address(new AvsOperatorManager(roleRegistry));
        address newOperatorImpl = address(new AvsOperator(address(avsOperatorManager), roleRegistry));

        // original version was deployed with an older version of UUPS upgradeable
        // I can can use the new version after the first upgrade
        //avsOperatorManager.upgradeToAndCall(address(new AvsOperatorManager()), "");

        bytes4 selector = bytes4(keccak256(bytes("upgradeTo(address)")));
        bytes memory data = abi.encodeWithSelector(selector, newManagerImpl);
        (bool success, ) = address(avsOperatorManager).call(data);
        require(success, "Call failed");

        avsOperatorManager.upgradeEtherFiAvsOperator(address(newOperatorImpl));

        console2.log("New managerImpl:", newManagerImpl);
        console2.log("New operatorImpl:", newOperatorImpl);
        vm.stopBroadcast();

        // sanity check that contract still works and storage didn't shift
        assert(sanityOperator == address(avsOperatorManager.avsOperators(1)));

    }
}
