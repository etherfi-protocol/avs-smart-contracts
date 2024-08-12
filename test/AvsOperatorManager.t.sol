// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../test/BlsTestHelpers.t.sol";
import "../test/TestSetup.sol";

import "../src/AvsOperator.sol";
import "../src/AvsOperatorManager.sol";
import "../src/eigenlayer-libraries/BeaconChainProofs.sol";
import "../src/eigenlayer-interfaces/IBLSApkRegistry.sol";
import "../src/eigenlayer-libraries/BN254.sol";
import "../src/eigenlayer-interfaces/IEigenPod.sol";


import "forge-std/Test.sol";
import "forge-std/console2.sol";


contract EtherFiAvsOperatorsManagerTest is TestSetup, BlsTestHelper {

    function test_registerEigenda() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        IRegistryCoordinator eigendaRegistryCoordinator = IRegistryCoordinator(address(0x0BAAc79acD45A023E19345c352d8a7a83C4e5656));
        uint256 operatorId = 1;
        address operator = address(avsOperatorManager.avsOperators(operatorId));

        // re-configure signer for testing
        uint256 signerKey = 0x1234abcd;
        {
            address signer = vm.addr(signerKey);
            vm.prank(admin);
            avsOperatorManager.updateEcdsaSigner(operatorId, signer);
        }

        // generate + sign the pubkey registration params with BLS key
        IBLSApkRegistry.PubkeyRegistrationParams memory blsPubkeyRegistrationParams;
        {
            uint256 blsPrivKey = 0xaaaabbbb;

            // generate the hash we need to sign with the BLS key
            BN254.G1Point memory blsPubkeyRegistrationHash = eigendaRegistryCoordinator.pubkeyRegistrationMessageHash(operator);

            // sign
            blsPubkeyRegistrationParams = generateSignedPubkeyRegistrationParams(blsPubkeyRegistrationHash, blsPrivKey);
        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
           address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
           address serviceManager = address(0x9FC952BdCbB7Daca7d420fA55b942405B073A89d);
           signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, serviceManager, signerKey);
        }

        // register
        {
            bytes memory quorums = hex"01";
            string memory socket = "https://test-socket";

            vm.prank(operator);
            eigendaRegistryCoordinator.registerOperator(quorums, socket, blsPubkeyRegistrationParams, signatureWithSaltAndExpiry);
        }
    }


    function test_parseBlsKey() public view {
        string memory jsonPath = "test/altlayer.bls-signature.json";

        IBLSApkRegistry.PubkeyRegistrationParams memory pkeyParams = parseBlsKey(jsonPath);
        assert(pkeyParams.pubkeyG1.X != 0);
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

        address altLayerRegistryCoordinator = address(0x561be1AB42170a19f31645F774e6e3862B2139AA);

        IBLSApkRegistry.PubkeyRegistrationParams memory altLayerPubkeyParams = parseBlsKey("test/altlayer.bls-signature.json");

        ISignatureUtils.SignatureWithSaltAndExpiry memory altLayerSignature = ISignatureUtils.SignatureWithSaltAndExpiry({
            signature: hex"164fe4b0bc5cc8921c8a32aa6df6cc1195e3d81f082af80b2e1694e93a0544c33ecde76bacaab348fff6c19f17518bd632e97981e284a2b148dfa4af7779edea1b",
            salt: bytes32(0xa4d42b015321e1902884ddb1382cef346c3da8769e752d6ce55861467867196d),
            expiry: 1746078548
        });


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
