// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";

interface IGaspUnpauser {
    function unpause(uint256 status) external;
}

contract GaspTest is TestSetup, CryptoTestHelper {

    function test_registerGasp() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        IRegistryCoordinator gaspRegistryCoordinator = IRegistryCoordinator(address(0x9A986296d45C327dAa5998519AE1B3757F1e6Ba1));
        address gaspServiceManager = address(0x3aDdEb54ddd43Eb40235eC32DfA7928F28A44bb5);

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
            BN254.G1Point memory blsPubkeyRegistrationHash = gaspRegistryCoordinator.pubkeyRegistrationMessageHash(operator);

            // sign
            blsPubkeyRegistrationParams = generateSignedPubkeyRegistrationParams(blsPubkeyRegistrationHash, blsPrivKey);
        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
           address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
           signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, gaspServiceManager, signerKey);
        }

        // unpause their contracts
        vm.prank(gaspRegistryCoordinator.owner());
        IGaspUnpauser(address(gaspRegistryCoordinator)).unpause(0);

        // register
        {
            bytes memory quorums = hex"00";
            string memory socket = "https://test-socket";

            vm.prank(operator);
            gaspRegistryCoordinator.registerOperator(quorums, socket, blsPubkeyRegistrationParams, signatureWithSaltAndExpiry);
        }
    }

}
