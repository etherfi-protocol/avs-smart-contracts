// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/BlsTestHelpers.t.sol";
import "../src/eigenlayer-interfaces/IMachServiceManager.sol";

contract AltLayerTest is TestSetup, BlsTestHelper {

    function test_registeraltlayer() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        IMachServiceManager altlayerMachServiceManager = IMachServiceManager(0x71a77037870169d47aad6c2C9360861A4C0df2bF);
        IRegistryCoordinator altlayerRegistryCoordinator = IRegistryCoordinator(address(0x561be1AB42170a19f31645F774e6e3862B2139AA));
        uint256 operatorId = 1;
        address operator = address(avsOperatorManager.avsOperators(operatorId));

        // add operator to altLayer whitelist
        address altLayerWhitelister = address(0x1bf89a27815bdc2B845D6064DaB21B4487F81Cc2);
        vm.prank(altLayerWhitelister);
        address[] memory operatorAddress = new address[](1);
        operatorAddress[0] = address(operator);
        altlayerMachServiceManager.allowOperators(operatorAddress);

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
            BN254.G1Point memory blsPubkeyRegistrationHash = altlayerRegistryCoordinator.pubkeyRegistrationMessageHash(operator);

            // sign
            blsPubkeyRegistrationParams = generateSignedPubkeyRegistrationParams(blsPubkeyRegistrationHash, blsPrivKey);
        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
           address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
           address serviceManager = address(0x71a77037870169d47aad6c2C9360861A4C0df2bF);
           signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, serviceManager, signerKey);
        }

        // register
        {
            bytes memory quorums = hex"01";
            string memory socket = "https://test-socket";

            vm.prank(operator);
            altlayerRegistryCoordinator.registerOperator(quorums, socket, blsPubkeyRegistrationParams, signatureWithSaltAndExpiry);
        }
    }

}
