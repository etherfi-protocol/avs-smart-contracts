// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/AvsOperatorManager.t.sol";

import "forge-std/console2.sol";

interface IWitnessOperatorRegistry {
    function calculateWatchtowerRegistrationMessageHash(address operator, uint256 expiry) external returns (bytes32);
    function registerWatchtowerAsOperator (address watchtower, uint256 expiry, bytes memory signedMessage) external;
    function addToOperatorWhitelist (address[] memory operatorsList) external;
    function owner() external returns (address);
}

interface IWitnessHub {
    function registerOperatorToAVS(address operator, ISignatureUtils.SignatureWithSaltAndExpiry memory signature) external;
}

contract WitnessChainTest is TestSetup {

    // Mainnet
    IWitnessHub witnessHub = IWitnessHub(address(0xD25c2c5802198CB8541987b73A8db4c9BCaE5cC7));
    IWitnessOperatorRegistry operatorRegistry = IWitnessOperatorRegistry(address(0xEf1a89841fd189ba28e780A977ca70eb1A5e985D));

    function test_registerWithWitnessChain() public {
        initializeRealisticFork(MAINNET_FORK); upgradeAvsContracts();

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

        // Register operator with witness chain
        {
            // 1. compute registration digest
            uint256 expiry = block.timestamp + 10000;
            bytes32 salt = bytes32(0x1234567890000000000000000000000000000000000000000000000000000000);
            IAVSDirectory avsDirectory = IAVSDirectory(address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF));

            bytes32 registrationDigest = avsDirectory.calculateOperatorAVSRegistrationDigestHash(
                address(operator),
                address(witnessHub),
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

            witnessHub.registerOperatorToAVS(address(operator), signatureWithSaltAndExpiry);
        }

        // register a watchtower
        {
            // 1. compute watchtower registration digest
            uint256 expiry = block.timestamp + 10000;
            bytes32 watchtowerRegistrationDigest = operatorRegistry.calculateWatchtowerRegistrationMessageHash(address(operator), expiry);

            // 2. sign digest with watchtower key
            uint256 watchtowerPrivateKey = 0xfedc3210;
            address watchtowerAddress = vm.addr(watchtowerPrivateKey);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(watchtowerPrivateKey, watchtowerRegistrationDigest);
            bytes memory signature = abi.encodePacked(r, s, v);
            console2.log("watchtowerAddress:", watchtowerAddress);

            // 3. register watchtower
            vm.prank(address(operator));
            operatorRegistry.registerWatchtowerAsOperator(watchtowerAddress, expiry, signature);

            // ensure we are now registered by checking that we can't register again
            vm.expectRevert("WitnessHub: Watchtower address already registered");
            vm.prank(address(operator));
            operatorRegistry.registerWatchtowerAsOperator(watchtowerAddress, expiry, signature);
        }
    }


}
