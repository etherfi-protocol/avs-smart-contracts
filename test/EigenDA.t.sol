// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/BlsTestHelpers.t.sol";

contract EigenDATest is TestSetup, BlsTestHelper {

    function test_registerEigenDA() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        IRegistryCoordinator eigendaRegistryCoordinator = IRegistryCoordinator(address(0x0BAAc79acD45A023E19345c352d8a7a83C4e5656));
        uint256 operatorId = 1;
        address operator = address(avsOperatorManager.avsOperators(operatorId));

        // re-configure signer for testing
        uint256 signerKey = 0x1234abcd;
        {
            address signer = vm.addr(signerKey);
            roleRegistry.grantRole(AvsOperator(operator).ECDSA_SIGNER_ROLE(), signer);
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

}
