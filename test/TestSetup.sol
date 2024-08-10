// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import "../src/AvsOperator.sol";
import "../src/AvsOperatorManager.sol";

contract TestSetup is Test {

    AvsOperatorManager avsOperatorManager;

    address admin;
    address operatorOneRunner;
    address operatorTwoRunner;

    IBLSApkRegistry.PubkeyRegistrationParams samplePubkeyRegistrationParams;
    ISignatureUtils.SignatureWithSaltAndExpiry sampleRegistrationSignature;

    function setUp() public {
        admin = vm.addr(0x9876543210);
        vm.startPrank(admin);

        // deploy manager
        AvsOperatorManager avsOperatorManagerImpl = new AvsOperatorManager();
        ERC1967Proxy avvsOperatorManagerProxy = new ERC1967Proxy(address(avsOperatorManagerImpl), "");
        avsOperatorManager = AvsOperatorManager(address(avvsOperatorManagerProxy));

        // initialize manager
        AvsOperator avsOperatorImpl = new AvsOperator();
        address delegationManager = address(0x1234); // TODO
        address avsDirectory = address(0x1235); // TODO
        avsOperatorManager.initialize(delegationManager, avsDirectory, address(avsOperatorImpl));

        // deploy a couple operators
        avsOperatorManager.instantiateEtherFiAvsOperator(2);
        operatorOneRunner = vm.addr(0x11111111);
        operatorTwoRunner = vm.addr(0x22222222);
        avsOperatorManager.updateAvsNodeRunner(1, operatorOneRunner);
        avsOperatorManager.updateAvsNodeRunner(2, operatorTwoRunner);

        // create an example bls pubkey and signature
        BN254.G1Point memory pubkeySignaturePoint = BN254.G1Point({
            X: 1737408473725330763843880782491037116654861901274329008829867944933220175236,
            Y: 10158965556018911028664489354186772678118499821014905102777776384489118430367
        });
        BN254.G1Point memory pubkeyG1 = BN254.G1Point({
            X: 1186892176333729259402566975799559819177585277458634869487759992514008184155,
            Y: 1186713232830160640205163521286989504734698387173894963064166847355519910294
        });
        BN254.G2Point memory pubkeyG2 = BN254.G2Point({
            X: [20373260592925970510436870156702493823059114246881996422295473156189283443836, 4874916298750258089447683583376932635557701511081659750045648280467126335967],
            Y: [1296067449676727247175027892935715275166282239219407876021181432383944469412, 14487491035855367176460402597285327371990118432785320314384630667240256562505]
        });
        samplePubkeyRegistrationParams = IBLSApkRegistry.PubkeyRegistrationParams({
            pubkeyRegistrationSignature: pubkeySignaturePoint,
            pubkeyG1: pubkeyG1,
            pubkeyG2: pubkeyG2
        });
        sampleRegistrationSignature = ISignatureUtils.SignatureWithSaltAndExpiry({
            signature: hex"a2dd466c26df1884d824c5cee74e3e249b4f9027f718a60779c760981d52fa4515a47481a05bc06fb81f0feba71c56f2155fbfb890eac058fbc29bfa0ba5be3a1c",
            salt: bytes32(0xa337bc4e9c416683d8ebcfd5261157ae5b7e6513ad364842cb1affaa281e6408),
            expiry: 1744938796
        });

        vm.stopPrank();
    }


    // enum for fork options
    uint8 HOLESKY_FORK = 1;
    uint8 MAINNET_FORK = 2;

    function initializeRealisticFork(uint8 forkEnum) public {

        if (forkEnum == MAINNET_FORK) {
            vm.selectFork(vm.createFork(vm.envString("MAINNET_RPC_URL")));
            avsOperatorManager = AvsOperatorManager(0x2093Bbb221f1d8C7c932c32ee28Be6dEe4a37A6a);
            operatorOneRunner = avsOperatorManager.avsNodeRunner(1);
            operatorTwoRunner = avsOperatorManager.avsNodeRunner(2);
        } else if (forkEnum == HOLESKY_FORK) {
            vm.selectFork(vm.createFork(vm.envString("HOLESKY_RPC_URL")));
            avsOperatorManager = AvsOperatorManager(0xDF9679E8BFce22AE503fD2726CB1218a18CD8Bf4);
            operatorOneRunner = avsOperatorManager.avsNodeRunner(1);
            operatorTwoRunner = avsOperatorManager.avsNodeRunner(2);
        } else {
            revert("Unimplemented fork");
        }

    }

    function upgradeAvsContracts() internal {
        vm.startPrank(avsOperatorManager.owner());

        // original version was deployed with an older version of UUPS upgradeable
        // I can can use the new version after the first upgrade
        //avsOperatorManager.upgradeToAndCall(address(new AvsOperatorManager()), "");

        bytes4 selector = bytes4(keccak256(bytes("upgradeTo(address)")));
        bytes memory data = abi.encodeWithSelector(selector, address(new AvsOperatorManager()));
        (bool success, ) = address(avsOperatorManager).call(data);
        require(success, "Call failed");

        avsOperatorManager.upgradeEtherFiAvsOperator(address(new AvsOperator()));

        avsOperatorManager.updateAdmin(admin, true);

        vm.stopPrank();
    }

}
