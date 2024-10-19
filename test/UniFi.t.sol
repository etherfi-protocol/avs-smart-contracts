// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";
import "../src/eigenlayer-interfaces/IMachServiceManager.sol";

interface IUniFiAvsManager {
        function registerOperator(ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature) external;
}

contract UniFiTest is TestSetup, CryptoTestHelper {

    // Due to the avs contract's use the use of the latest evm features,
    // this test will only work if you use the "--evm-version cancun" flag
    function test_registerUniFi() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        IUniFiAvsManager avsManager = IUniFiAvsManager(0x2d86E90ED40a034C753931eE31b1bD5E1970113d);
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
           signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, address(avsManager), signerKey);
        }

        // register
        {
            vm.prank(operator);
            avsManager.registerOperator(signatureWithSaltAndExpiry);
        }
    }

}
