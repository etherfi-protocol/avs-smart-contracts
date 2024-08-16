// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";

// Omni's AVS contract. It is responsible for faciiltating registration / deregistration of EigenLayer operators, and for syncing operator delegations with the Omni chain.
interface IOmniAVS { 
    function registerOperator(bytes calldata pubkey, ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature) external;
}


contract OmniTest is TestSetup, CryptoTestHelper {

    function test_registerOmniZK() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        // Also the service manager
        IOmniAVS omniAVS = IOmniAVS(address(0xed2f4d90b073128ae6769a9A8D51547B1Df766C8));
        
        // pick an arbitrary operator not currently registered
        uint256 operatorId = 2;
        AvsOperator operator = avsOperatorManager.avsOperators(operatorId);

        // re-configure signer for testing with with known pubkey
        uint256 signerKey = 0xc374556584db050001c2c9265b546e66d3dbbe8239d17427c176d834a19638dc;
        bytes32 x = 0x10b5d9028ec828a0f9111e36f046afa5a0c677357351093426bcec10c663db7d;
        bytes32 y = 0x271763c56fcd87b72d59ceaa5b9c3fd2122788fe344751a9bde373f903e5bb20;
        bytes memory pubkey = abi.encodePacked(x, y);

        {
            address signer = vm.addr(signerKey);
            vm.prank(admin);
            avsOperatorManager.updateEcdsaSigner(operatorId, signer);
        }

        // Register operator with omni
        {

            // 1. compute registration digest
            uint256 expiry = block.timestamp + 10000;
            bytes32 salt = bytes32(0x1234567890000000000000000000000000000000000000000000000000000000);
            IAVSDirectory avsDirectory = IAVSDirectory(address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF));

            bytes32 registrationDigest = avsDirectory.calculateOperatorAVSRegistrationDigestHash(
                address(operator),
                address(omniAVS),
                salt,
                expiry
            );

            // 2. sign digest with configured signer
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, registrationDigest);

            // 3. register to AVS
            bytes memory signature = abi.encodePacked(r, s, v);
            ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry = ISignatureUtils.SignatureWithSaltAndExpiry({
                signature: signature,
                salt: salt,
                expiry: expiry
            });

            vm.prank(address(operator));
            omniAVS.registerOperator(pubkey, signatureWithSaltAndExpiry);
        }
    }

}
