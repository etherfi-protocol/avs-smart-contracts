// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";


interface IEthGasRegistryCoordinator {

    function registerOperatorWithSignature(
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature,
        address _signingKey
    ) external;

}

contract EthGasTest is TestSetup, CryptoTestHelper {

    function test_registerEthGas() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        IEthGasRegistryCoordinator registryCoordinator = IEthGasRegistryCoordinator(address(0xfF94c9859E4b15341c1BA3e80CF80044cA2C4e76));
        address serviceManager = address(0x6201bc0A699e3b10f324204e6F8EcdD0983De227);

        uint256 operatorId = 1;
        address operator = address(avsOperatorManager.avsOperators(operatorId));

        // re-configure signer for testing
        uint256 signerKey = 0x1234abcd;
        {
            address signer = vm.addr(signerKey);
            vm.prank(admin);
            avsOperatorManager.updateEcdsaSigner(operatorId, signer);
        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
            address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
            signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, serviceManager, signerKey);
        }

        // node operator provides a separate ecdsa key for signing avs messages
        address avsSigner = vm.addr(0x1234abfe);

        // register
        {
            vm.prank(operator);
            registryCoordinator.registerOperatorWithSignature(signatureWithSaltAndExpiry, avsSigner);
        }
    }

}
