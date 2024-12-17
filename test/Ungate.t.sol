// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";
import "../src/othentic/BLSAuthLibrary.sol";

import "forge-std/console2.sol";

interface IUngateServiceManager {
    function registerAsOperator(
        uint256[4] memory _blsKey,
        address _rewardsReceiver,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature,
        uint256[2] memory _blsRegistrationSignature
    ) external;
}

contract UngateTest is TestSetup, CryptoTestHelper {

    function test_registerUngate() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        //IRegistryCoordinator registryCoordinator = IRegistryCoordinator(address(0xA8CC0749b4409c3c47012323E625aEcBA92f64b9));
        IUngateServiceManager serviceManager = IUngateServiceManager(address(0xB3e069FD6dDA251AcBDE09eDa547e0AB207016ee));

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
        uint256[4] memory blsPubkey;
        uint256[2] memory blsSignature;
        {
            uint256 blsPrivKey = 0xaaaabbbb;

            // generate the hash we need to sign with the BLS key
            uint256[2] memory registrationMessage = OthenticBLSAuthLibrary._message(operator, address(serviceManager));

            // convert to format expected by eigenlayer helpers
            BN254.G1Point memory message = BN254.G1Point({ X: registrationMessage[0], Y: registrationMessage[1] });
            console2.log("original message", message.X, message.Y);

            // sign
            blsPubkeyRegistrationParams = generateSignedPubkeyRegistrationParams(message, blsPrivKey);

            blsSignature[0] = blsPubkeyRegistrationParams.pubkeyRegistrationSignature.X;
            blsSignature[1] = blsPubkeyRegistrationParams.pubkeyRegistrationSignature.Y;

            blsPubkey[0] = blsPubkeyRegistrationParams.pubkeyG2.X[1];
            blsPubkey[1] = blsPubkeyRegistrationParams.pubkeyG2.X[0];
            blsPubkey[2] = blsPubkeyRegistrationParams.pubkeyG2.Y[1];
            blsPubkey[3] = blsPubkeyRegistrationParams.pubkeyG2.Y[0];

            bool valid = OthenticBLSAuthLibrary.isValidSignature(OthenticBLSAuthLibrary.Signature(blsSignature), operator, address(serviceManager), blsPubkey);
            console2.log("Valid:", valid);
            return;


        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
           address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
           signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, address(serviceManager), signerKey);
        }

        //uint256[2] memory signature = new uint256[](2);


        {
            vm.prank(operator);
            serviceManager.registerAsOperator(
                blsPubkey,
                operator,
                signatureWithSaltAndExpiry,
                blsSignature
            );

        }

        /*
        // register
        {
            bytes memory quorums = hex"00";
            string memory socket = "https://test-socket";

            vm.prank(operator);
            registryCoordinator.registerOperator(quorums, socket, blsPubkeyRegistrationParams, signatureWithSaltAndExpiry);
        }
        */
    }

}
