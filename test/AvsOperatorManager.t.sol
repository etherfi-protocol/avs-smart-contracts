// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/eigenlayer-interfaces/IBLSApkRegistry.sol";
import "../src/eigenlayer-libraries/BN254.sol";
import "../src/eigenlayer-interfaces/IEigenPod.sol";
import "../src/eigenlayer-libraries/BeaconChainProofs.sol";
import "./ProofParsing.sol";

import "../src/AvsOperator.sol";
import "../src/AvsOperatorManager.sol";


import "forge-std/Test.sol";
import "forge-std/console2.sol";


contract EtherFiAvsOperatorsManagerTest is Test, ProofParsing {

    AvsOperatorManager avsOperatorManager;
    address admin;
    address operatorOneRunner;
    address operatorTwoRunner;
    
    IBLSApkRegistry.PubkeyRegistrationParams samplePubkeyRegistrationParams;
    ISignatureUtils.SignatureWithSaltAndExpiry sampleRegistrationSignature;

    function testBalancUpdateProof() public {
        initializeRealisticFork(MAINNET_FORK);

        IEigenPod eigenpod = IEigenPod(0x4F9E701a972CE90789FbbA4DE3ADF0753597568f);

        setJSON("test/mainnet_balance_update_proof_1393176_1718473883.json");

        uint64 oracleTimestamp = 1718473883;
        uint40[] memory validatorIndices = new uint40[](1);
        validatorIndices[0] = 1393176;

        BeaconChainProofs.StateRootProof memory stateRootProofStruct = _getStateRootProof();

        bytes[] memory validatorFieldsProofArray = new bytes[](1);
        validatorFieldsProofArray[0] = abi.encodePacked(getValidatorProof());

        bytes32[][] memory validatorFieldsArray = new bytes32[][](1);
        validatorFieldsArray[0] = getValidatorFields();

        eigenpod.verifyBalanceUpdates(
            oracleTimestamp,
            validatorIndices,
            stateRootProofStruct,
            validatorFieldsProofArray,
            validatorFieldsArray
        );

    }

        /*
                function verifyBalanceUpdates(
        uint64 oracleTimestamp,
        uint40[] calldata validatorIndices,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields
    ) external onlyWhenNotPaused(PAUSED_EIGENPODS_VERIFY_BALANCE_UPDATE) {
        */


    function testEigenlayer() public {
        initializeRealisticFork(MAINNET_FORK);

        IEigenPod eigenpod = IEigenPod(0xafd81A1f8062a383F9D5e067af3a6EB5F5171024);

        // setup proof
        //setJSON("test/mainnet_withdrawal_proof_1052563.json");
        setJSON("test/mainnet_withdrawal_proof_369_1052563_1713873719.json");
        //setJSON("test/mainnet_withdrawal_proof_369_1052563_1714616915.json");

        BeaconChainProofs.WithdrawalProof[] memory withdrawalProofsArray = new BeaconChainProofs.WithdrawalProof[](1);
        withdrawalProofsArray[0] = _getWithdrawalProof();
        bytes[] memory validatorFieldsProofArray = new bytes[](1);

        validatorFieldsProofArray[0] = abi.encodePacked(getValidatorProof());
        bytes32[][] memory validatorFieldsArray = new bytes32[][](1);
        validatorFieldsArray[0] = getValidatorFields();
        bytes32[][] memory withdrawalFieldsArray = new bytes32[][](1);
        withdrawalFieldsArray[0] = getWithdrawalFields();

        BeaconChainProofs.StateRootProof memory stateRootProofStruct = _getStateRootProof();

        uint64 oracleTimestamp = 1715097119;

        eigenpod.verifyAndProcessWithdrawals(
            oracleTimestamp,
            stateRootProofStruct,
            withdrawalProofsArray,
            validatorFieldsProofArray,
            validatorFieldsArray,
            withdrawalFieldsArray
        );

        console2.logBytes(
            abi.encodeWithSelector(
                eigenpod.verifyAndProcessWithdrawals.selector, 
                oracleTimestamp, 
                stateRootProofStruct, 
                withdrawalProofsArray,
                validatorFieldsProofArray,
                validatorFieldsArray,
                withdrawalFieldsArray
            )
        );

    }

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


    function testJson() public {
        string memory jsonPath = "test/altlayer.bls-signature.json";
        //string memory jsonBytes = vm.readFile(jsonPath);

        //(uint256 g1x, uint256 g1y, uint256[2] memory g2x, uint256[2] memory g2y, uint256 sx, uint256 sy) = parseBlsKey(jsonBytes);

        IBLSApkRegistry.PubkeyRegistrationParams memory pkeyParams = parseBlsKey(jsonPath);
        console2.log("hello");
        console2.log(pkeyParams.pubkeyG1.X);

        /*
        G1Point memory pubkeySignaturePoint = G1Point({
            X: sx,
            Y: sy
        });

        G1Point memory pubkeyG1 = G1Point({
            X: g1x,
            Y: g1y
        });

        G2Point memory pubkeyG2 = G2Point({
            X: g2x,
            Y: g2y
        });

        PubkeyRegistrationParams memory samplePubkeyRegistrationParams = PubkeyRegistrationParams({
            pubkeyRegistrationSignature: pubkeySignaturePoint,
            pubkeyG1: pubkeyG1,
            pubkeyG2: pubkeyG2
        });
        */

        // Additional code to use samplePubkeyRegistrationParams

    }

    function test_proxyStorage() public {
        initializeRealisticFork(MAINNET_FORK);

        AvsOperator operator = avsOperatorManager.avsOperators(4);
        address managerAddress = operator.avsOperatorsManager();

        // deploy new versions and perform upgrades of both manager and operator
        vm.startPrank(avsOperatorManager.owner());
        bytes4 selector = bytes4(keccak256(bytes("upgradeTo(address)")));
        bytes memory data = abi.encodeWithSelector(selector, address(new AvsOperatorManager()));
        (bool success, ) = address(avsOperatorManager).call(data);
        require(success, "Call failed");
        address newBeaconImpl = address(new AvsOperator());
        avsOperatorManager.upgradeEtherFiAvsOperator(newBeaconImpl);
        vm.stopPrank();

        // New contracts before initialization
        address managerAddress2 = operator.avsOperatorsManager();

        // initialize beacon implementation with garbage
        AvsOperator(newBeaconImpl).initialize(address(0x123456));
        
        // after garbage initialization
        address managerAddress3 = operator.avsOperatorsManager();

        // Initialization had zero effect because proxies have independent storage
        assertEq(managerAddress, managerAddress2);
        assertEq(managerAddress2, managerAddress3);

    }

    function parseBlsKey(string memory filepath) internal view returns (IBLSApkRegistry.PubkeyRegistrationParams memory) {

        string memory json = vm.readFile(filepath);

        uint256 g1x = vm.parseJsonUint(json, ".g1.x");
        uint256 g1y = vm.parseJsonUint(json, ".g1.y");
        uint256[] memory g2xArray = vm.parseJsonUintArray(json, ".g2.x");
        uint256[] memory g2yArray = vm.parseJsonUintArray(json, ".g2.y");
        uint256 sx = vm.parseJsonUint(json, ".signature.x");
        uint256 sy = vm.parseJsonUint(json, ".signature.y");

        uint256[2] memory g2x;
        g2x[0] = g2xArray[0];
        g2x[1] = g2xArray[1];

        uint256[2] memory g2y;
        g2y[0] = g2yArray[0];
        g2y[1] = g2yArray[1];

        BN254.G1Point memory pubkeySignaturePoint = BN254.G1Point({
            X: sx,
            Y: sy
        });
        BN254.G1Point memory pubkeyG1 = BN254.G1Point({
            X: g1x,
            Y: g1y
        });
        BN254.G2Point memory pubkeyG2 = BN254.G2Point({
            X: g2x,
            Y: g2y
        });
        IBLSApkRegistry.PubkeyRegistrationParams memory pubkeyRegistrationParams = IBLSApkRegistry.PubkeyRegistrationParams({
            pubkeyRegistrationSignature: pubkeySignaturePoint,
            pubkeyG1: pubkeyG1,
            pubkeyG2: pubkeyG2
        });

        return pubkeyRegistrationParams;

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

    function test_updateAllowedOperatorCalls() public {

        uint256 operatorId = 1;

        // calling the owner function of the manager contract
        address target = address(avsOperatorManager);
        bytes4 selector = avsOperatorManager.owner.selector;

        // shouldn't be able to forward if they are not the registered runner for this operator
        bytes memory args = hex"12345678";
        vm.prank(operatorTwoRunner);
        vm.expectRevert("INCORRECT_CALLER");
        avsOperatorManager.forwardOperatorCall(operatorId, target, selector, args);

        // this particular call hasn't been whitelisted
        vm.prank(operatorOneRunner);
        vm.expectRevert(AvsOperatorManager.InvalidOperatorCall.selector);
        avsOperatorManager.forwardOperatorCall(operatorId, target, selector, args);

        // only admin can update the whitelist
        vm.prank(operatorOneRunner);
        vm.expectRevert("INCORRECT_CALLER");
        avsOperatorManager.updateAllowedOperatorCalls(operatorId, target, selector, true);

        // update the whitelist
        vm.prank(admin);
        avsOperatorManager.updateAllowedOperatorCalls(operatorId, target, selector, true);

        // call should succeed now
        vm.prank(operatorOneRunner);
        avsOperatorManager.forwardOperatorCall(operatorId, target, selector, args);
    }

    function test_upgradePreservesStorage() public {
        initializeRealisticFork(MAINNET_FORK);

        // sanity checks that upgrade does not shift existing storage slots
        uint256 previousNextAvsOperatorId = avsOperatorManager.nextAvsOperatorId();
        address previousDelegationManager = address(avsOperatorManager.delegationManager());
        address previousAvsDirectory = address(avsOperatorManager.avsDirectory());
        address previousOperator = address(avsOperatorManager.avsOperators(1));
        address previousNodeRunner = AvsOperator(previousOperator).avsNodeRunner();
        address previousSigner = AvsOperator(previousOperator).ecdsaSigner();
        console2.log(previousNodeRunner);
        console2.log(previousSigner);

        upgradeAvsContracts();
        assertEq(previousNextAvsOperatorId, avsOperatorManager.nextAvsOperatorId());
        assertEq(previousDelegationManager, address(avsOperatorManager.delegationManager()));
        assertEq(previousAvsDirectory, address(avsOperatorManager.avsDirectory()));

        address updatedOperator = address(avsOperatorManager.avsOperators(1));
        assertEq(previousOperator, updatedOperator);
        assertEq(previousNodeRunner, AvsOperator(updatedOperator).avsNodeRunner());
        assertEq(previousSigner, AvsOperator(updatedOperator).ecdsaSigner());
    }

    function test_registerWithAltLayer() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        uint256 operatorId = 4;

        address operatorAddress = address(avsOperatorManager.avsOperators(operatorId));

        address altLayerRegistryCoordinator = address(0x561be1AB42170a19f31645F774e6e3862B2139AA);
        address brevisRegistryCoordinator = address(0x434621cfd8BcDbe8839a33c85aE2B2893a4d596C);

        IBLSApkRegistry.PubkeyRegistrationParams memory altLayerPubkeyParams = parseBlsKey("test/altlayer.bls-signature.json");

        ISignatureUtils.SignatureWithSaltAndExpiry memory altLayerSignature = ISignatureUtils.SignatureWithSaltAndExpiry({
            signature: hex"164fe4b0bc5cc8921c8a32aa6df6cc1195e3d81f082af80b2e1694e93a0544c33ecde76bacaab348fff6c19f17518bd632e97981e284a2b148dfa4af7779edea1b",
            salt: bytes32(0xa4d42b015321e1902884ddb1382cef346c3da8769e752d6ce55861467867196d),
            expiry: 1746078548
        });

        /*
            signature: 164fe4b0bc5cc8921c8a32aa6df6cc1195e3d81f082af80b2e1694e93a0544c33ecde76bacaab348fff6c19f17518bd632e97981e284a2b148dfa4af7779edea1b
            hash: a4d42b015321e1902884ddb1382cef346c3da8769e752d6ce55861467867196d
            salt: 17a6c7a46ee1b29463ffd3bfcd816e890126ad925c1451df51744e91d539d296
            Expiry: 1746078548
        */
        //IBLSApkRegistry.PubkeyRegistrationParams


        BN254.G1Point memory h1 = IRegistryCoordinator(altLayerRegistryCoordinator).pubkeyRegistrationMessageHash(operatorAddress);
       // BN254.G1Point memory h2 = IRegistryCoordinator(brevisRegistryCoordinator).pubkeyRegistrationMessageHash(operatorAddress);
        //console2.log("alt", h1.X, h1.Y);
       // console2.log("bre", h2.X, h2.Y);
        //return;

        bytes memory quorums = hex"00";
        string memory socket = "no need";

        bytes4 selector = IRegistryCoordinator.registerOperator.selector;
        bytes memory args = abi.encode(quorums, socket, altLayerPubkeyParams, altLayerSignature);

        // update the whitelist
        vm.prank(avsOperatorManager.owner());
        avsOperatorManager.updateAllowedOperatorCalls(operatorId, altLayerRegistryCoordinator, selector, true);

        vm.prank(avsOperatorManager.avsNodeRunner(operatorId));
        //vm.expectRevert("RegistryCoordinator._registerOperator: operator already registered for some quorums being registered for");
        avsOperatorManager.forwardOperatorCall(operatorId, altLayerRegistryCoordinator, selector, args);

    }

    function test_forwardOperatorCall() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        address brevisRegistryCoordinator = address(0x434621cfd8BcDbe8839a33c85aE2B2893a4d596C);
        bytes memory quorums = hex"01";
        string memory socket = "no need";

        bytes memory args = abi.encode(quorums, socket, samplePubkeyRegistrationParams, sampleRegistrationSignature);
        bytes4 selector = IRegistryCoordinator.registerOperator.selector;

        uint256 operatorId = 4;

        // update the whitelist
        vm.prank(avsOperatorManager.owner());
        avsOperatorManager.updateAllowedOperatorCalls(operatorId, brevisRegistryCoordinator, selector, true);

        // expect to fail for already being registered. Foundry seems to have issues with historical forks older than a certain time
        // so I'm unable to rewind to before this original register call happened
        vm.prank(avsOperatorManager.avsNodeRunner(operatorId));
        vm.expectRevert("RegistryCoordinator._registerOperator: operator already registered for some quorums being registered for");
        avsOperatorManager.forwardOperatorCall(operatorId, brevisRegistryCoordinator, selector, args);
    }
}
