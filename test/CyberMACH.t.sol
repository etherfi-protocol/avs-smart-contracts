// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";
import "../src/eigenlayer-interfaces/IMachServiceManager.sol";

contract CyberMachTest is TestSetup, CryptoTestHelper {

    function test_registercyberMach() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        IMachServiceManager cyberMachServiceManager = IMachServiceManager(0x1F2c296448f692af840843d993fFC0546619Dcdb);
        IRegistryCoordinator cyberMachRegistryCoordinator = IRegistryCoordinator(address(0x118610D207A32f10F4f7C3a1FEFac5b3327c2bad));
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
            BN254.G1Point memory blsPubkeyRegistrationHash = cyberMachRegistryCoordinator.pubkeyRegistrationMessageHash(operator);

            // sign
            blsPubkeyRegistrationParams = generateSignedPubkeyRegistrationParams(blsPubkeyRegistrationHash, blsPrivKey);
        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
           address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
           signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, address(cyberMachServiceManager), signerKey);
        }

        // register
        {
            bytes memory quorums = hex"00";
            string memory socket = "https://test-socket";

            vm.prank(operator);
            cyberMachRegistryCoordinator.registerOperator(quorums, socket, blsPubkeyRegistrationParams, signatureWithSaltAndExpiry);
        }
    }

}
