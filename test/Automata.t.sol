// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/BlsTestHelpers.t.sol";

interface IAutomataServiceManagerWhitelist {
    function whitelistOperator(address operator) external;
}

contract AutomataTest is TestSetup, BlsTestHelper {

    function test_registerAutomata() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        IRegistryCoordinator automataRegistryCoordinator = IRegistryCoordinator(address(0x414696E4F7f06273973E89bfD3499e8666D63Bd4));
        uint256 operatorId = 1;
        address operator = address(avsOperatorManager.avsOperators(operatorId));

        // whitelist operator on Automata service manager
        IAutomataServiceManagerWhitelist serviceManagerWhitelist = IAutomataServiceManagerWhitelist(address(0xE5445838C475A2980e6a88054ff1514230b83aEb));
        vm.prank(0x0f5661B579fD19C9Bd14940555FeD67aff3FCe41);
        serviceManagerWhitelist.whitelistOperator(operator);

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
            BN254.G1Point memory blsPubkeyRegistrationHash = automataRegistryCoordinator.pubkeyRegistrationMessageHash(operator);

            // sign
            blsPubkeyRegistrationParams = generateSignedPubkeyRegistrationParams(blsPubkeyRegistrationHash, blsPrivKey);
        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
           address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
           address serviceManager = address(0xE5445838C475A2980e6a88054ff1514230b83aEb);
           signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, serviceManager, signerKey);
        }

        // register
        {
            bytes memory quorums = hex"00";
            string memory socket = "https://test-socket";

            vm.prank(operator);
            automataRegistryCoordinator.registerOperator(quorums, socket, blsPubkeyRegistrationParams, signatureWithSaltAndExpiry);
        }
    }

}
