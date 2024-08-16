// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/AvsOperatorManager.t.sol";

interface IHyperlaneEcdsaStakeRegistry {
    function registerOperatorWithSignature(ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature, address signingKey) external;
}

interface IHyperlaneServiceManager {}

contract HyperlaneTest is TestSetup {

    // Mainnet
    IHyperlaneEcdsaStakeRegistry stakeRegistry = IHyperlaneEcdsaStakeRegistry(address(0x272CF0BB70D3B4f79414E0823B426d2EaFd48910));
    IHyperlaneServiceManager serviceManager = IHyperlaneServiceManager(address(0xe8E59c6C8B56F2c178f63BCFC4ce5e5e2359c8fc));

    function test_registerWithHyperlane() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

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

        // Register operator with hyperlane
        {
            // 1. compute registration digest
            uint256 expiry = block.timestamp + 10000;
            bytes32 salt = bytes32(0x1234567890000000000000000000000000000000000000000000000000000000);
            IAVSDirectory avsDirectory = IAVSDirectory(address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF));

            bytes32 registrationDigest = avsDirectory.calculateOperatorAVSRegistrationDigestHash(
                address(operator),
                address(address(serviceManager)),
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

            // node operator provides a separate ecdsa key for signing avs messages
            address avsSigner = vm.addr(0x1234abfe);

            vm.prank(address(operator));
            stakeRegistry.registerOperatorWithSignature(signatureWithSaltAndExpiry, avsSigner);
        }

    }


}
