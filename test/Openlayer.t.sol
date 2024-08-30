// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/AvsOperatorManager.t.sol";

interface IOpenlayerRegistryCoordinator {
        function registerOperator(
            bytes calldata quorumNumbers,
            string calldata socket,
            IBLSApkRegistry.PubkeyRegistrationParams calldata params,
            ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature,
            address operatorSignatureAddress
        ) external;

        function serviceManager() external returns (address);
        function pubkeyRegistrationMessageHash(address operator) external view returns (BN254.G1Point memory);
}


contract OpenlayerTest is TestSetup, CryptoTestHelper {

    // Mainnet
    IOpenlayerRegistryCoordinator registryCoordinator = IOpenlayerRegistryCoordinator(address(0x7dd7320044013f7f49B1b6D67aED10726fe6e62b));

    function test_registerWithOpenlayer() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        address serviceManager = registryCoordinator.serviceManager();
        console2.log("serviceManager", serviceManager);

        // pick an arbitrary operator not currently registered
        uint256 operatorId = 2;
        AvsOperator operator = avsOperatorManager.avsOperators(operatorId);

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
            BN254.G1Point memory blsPubkeyRegistrationHash = registryCoordinator.pubkeyRegistrationMessageHash(address(operator));

            // sign
            blsPubkeyRegistrationParams = generateSignedPubkeyRegistrationParams(blsPubkeyRegistrationHash, blsPrivKey);
        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
           address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
           signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, address(operator), serviceManager, signerKey);
        }

        // register
        {
            bytes memory quorums = hex"00";
            string memory socket = "Not Needed";

            vm.prank(address(operator));
            // They add the address of the signer as an extra param here. No idea why because it can be recovered from the signature?
            registryCoordinator.registerOperator(quorums, socket, blsPubkeyRegistrationParams, signatureWithSaltAndExpiry, address(operator));
        }

    }


}
