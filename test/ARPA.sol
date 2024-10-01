// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";

import "../src/eigenlayer-interfaces/IAVSDirectory.sol";

interface IARPANodeRegsitry {
    function nodeRegister(bytes calldata dkgPublicKey, bool isEigenlayerNode, address assetAccountAddress, ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry) external;
    function nodeQuit() external;
    function nodeLogOff() external;
}

contract ARPATest is TestSetup, CryptoTestHelper {

    function test_registerARPA() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        IARPANodeRegsitry arpaNodeRegsitry = IARPANodeRegsitry(address(0x58e39879374901e17A790af039DC9Ac06baCf25B));

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
            address serviceManager = address(0x1DE75EaAb2df55d467494A172652579E6FA4540E);
            signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, serviceManager, signerKey);
        }

        // unregister and re-register an operator with ARPA
        {
            // call from our smart contract operator to unregister the operator
            vm.prank(operator);
            arpaNodeRegsitry.nodeLogOff();

            bytes memory dkgPublicKey =
            hex"047b565c2e1724fda37d648746d778618f995f6635bb38a71be2f60c09ffbea011a8fe485a7a3a41c7eab1004bb1b5f90b49210173c24cb90dfe99f6c92970660b80428a38cff7734a4c853bd87b55dc2b3f850081323658326fd8468660aa170c74ee6c4fb599c426e4041fb7795164ea0dd1ac362437d3c82647705a5d13a1";

            // re-register the operator from an arbitrary address (the node operators themselves will call this with their ECDSA key)
            vm.prank(vm.addr(0x1234abcd));
            arpaNodeRegsitry.nodeRegister(dkgPublicKey, true, operator, signatureWithSaltAndExpiry);
        }
    }
}
