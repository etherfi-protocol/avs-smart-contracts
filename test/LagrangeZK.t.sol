// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";

interface ILagrangeZkServiceManager {
    function registerOperatorToAVS(address operator, ISignatureUtils.SignatureWithSaltAndExpiry memory signature) external;
}

struct LagrangeZkPublicKey {
    uint256 x;
    uint256 y;
}

interface ILagrangeZkStakeRegistry {
        function registerOperator(LagrangeZkPublicKey calldata publicKey, ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature) external;
        function addToWhitelist(address[] calldata addrs) external;
        function owner() external returns (address);
}


contract LagrangeZKTest is TestSetup {


    function test_registerLagrangeZK() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        // Mainnet
        ILagrangeZkServiceManager serviceManager = ILagrangeZkServiceManager(address(0x22CAc0e6A1465F043428e8AeF737b3cb09D0eEDa));
        ILagrangeZkStakeRegistry stakeRegistry = ILagrangeZkStakeRegistry(address(0x8dcdCc50Cc00Fe898b037bF61cCf3bf9ba46f15C));

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

        // override their whitelist
        {
            address[] memory addrs = new address[](1);
            addrs[0] = address(operator);
            vm.prank(stakeRegistry.owner());
            stakeRegistry.addToWhitelist(addrs);
        }

        // Register operator with lagrange
        {
            // arbitrary pubkey of a random address. This is the public key of a separate
            // ECDSA key the node operator generates specific to lagrange
            LagrangeZkPublicKey memory pubkey = LagrangeZkPublicKey({
                x: 72411267774161223328936871581317255372657548077140631046357387218455746618577,
                y: 15973142100213816836658317139965288614640162930036908113704553730350155902020
            });

            // 1. compute registration digest
            uint256 expiry = block.timestamp + 10000;
            bytes32 salt = bytes32(0x1234567890000000000000000000000000000000000000000000000000000000);
            IAVSDirectory avsDirectory = IAVSDirectory(address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF));

            bytes32 registrationDigest = avsDirectory.calculateOperatorAVSRegistrationDigestHash(
                address(operator),
                address(serviceManager),
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
            stakeRegistry.registerOperator(pubkey, signatureWithSaltAndExpiry);
        }

    }

}
