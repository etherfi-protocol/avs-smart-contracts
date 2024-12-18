// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";

import "../src/eigenlayer-interfaces/IAVSDirectory.sol";

interface IPredicateRegistry {
    function registerOperatorToAVS(address _operatorSigningKey, ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature) external;
}

contract PredicateTest is TestSetup, CryptoTestHelper {

    function test_registerPredicate() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        IPredicateRegistry predicateRegsitry = IPredicateRegistry(address(0xaCB91045B8bBa06f9026e1A30855B6C4A1c5BaC6));
        address serviceManager = address(predicateRegsitry); // registry contract is used as the service manager

        uint256 operatorId = 1;
        address operator = address(avsOperatorManager.avsOperators(operatorId));

        // re-configure signer for testing
        uint256 signerKey = 0x1234abcd;
        address signer = vm.addr(signerKey);
        {
            vm.prank(admin);
            avsOperatorManager.updateEcdsaSigner(operatorId, signer);
        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
            address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
            signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, serviceManager, signerKey);
        }

        // key controlled by the node operator, not us
        uint256 externalSigningKey = 0x0987654321;
        address externalSigningAddress = vm.addr(externalSigningKey);

        vm.prank(operator);
        predicateRegsitry.registerOperatorToAVS(externalSigningAddress, signatureWithSaltAndExpiry);
    }
}
