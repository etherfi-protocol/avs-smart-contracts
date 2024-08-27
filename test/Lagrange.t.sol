// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";


contract LagrangeSCTest is TestSetup {

    function test_registerLagrangeSC() public {
        initializeRealisticFork(MAINNET_FORK);
        upgradeAvsContracts();

        // pick an arbitrary operator not currently registered
        uint256 operatorId = 1;
        AvsOperator operator = avsOperatorManager.avsOperators(operatorId);

        // re-configure signer for testing
        uint256 signerKey = 0x1234567890000000000000000000000000000000000000000000000000000000;
        {
            address signer = vm.addr(signerKey);
            vm.prank(admin);
            avsOperatorManager.updateEcdsaSigner(operatorId, signer);
        }

        // Registering for lagrangeSC involves computing aggregate BLS pubkeys and signatures
        // which we currently don't have tooling built for here. But the steps to follow are
        //
        // 1. Compute the hash to be signed by the aggregate bls key
        //
        //     LagrangeCommittee.CalculateKeyWithProofHash(operator.Address, [32]byte(salt), expiry)
        //
        // 2. Sign the digest with 1 or more BLS keys
        //
        //    // using lagrange cli library
        //    lagrangeutils.GenerateBLSSignature(keyWithProofDigest[:], blsPrivKeys...)
        //
        // 3. Generate and sign eigenlayer operator digest with ECDSA signer keys
        //
        // 4. Register (avsSignerAddress is a separate key provided by the operator)
        //
        //    LagrangeService.register(avsSignerAddress, signedBLSData, signedRegistrationData)

        {
            // Sample data signed with testing keys
            bytes memory data = hex"907382ac000000000000000000000000000000000000000000000000000000000000000100000000000000000000000035f4f28a8d3ff20eed10e087e8f96ea2641e6aa24e32e90400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000002c00000000000000000000000007b5ae07e2af1c861bcc4736d23f5f66a61e0ca5e000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000001201b3b74d0a3b79ced007f5b9d64c8614331bc448637f524335ab2d6980c882f5f05866e5f0342475b3dd2f3b82db9074b088e806e0fa35e0b05db8f3e8fa4d9ff2e44b7e5826a5ca0576cda477efc3a3dd6d22b550c78703d9af4971e1fe003f40063eabcfea0dfa7162511df6ec36ea200db924108b7fcba114d8d80640c6d430ef387c0dcf3e0a45e06a653093a8e6ba0f01e94d6493564d2685b8555f10bee059c15eff7e7c20a26a4b209af9175d4b9176a9e489636bae43bdd2e837cff8f4c17b1b943a712042153a5fb3df21d4251eb794dac3672dbd3b2b73fb565b5320000000000000000000000000000000000000000000000000000000066d7334a0000000000000000000000000000000000000000000000000000000000000001076ee7288cdf1d7f80e1edb03da5d8a1776892f50b53b9710e0115bed8eeec531cab7e597c86a81de4ad77f8ef235308a8becdacae081e8c1abb2e1407d47b5f0000000000000000000000000000000000000000000000000000000000000060cb0ec21950a2de7b2ce1bbf7e73331a65bd999261e236547d95c1fe9e40aa3440000000000000000000000000000000000000000000000000000000066d73a6100000000000000000000000000000000000000000000000000000000000000413598a8ff323672c0bbf358a61c387cc948d84c28b4faae9e925f8753122e2f770e4ac3966266030c978abe95ab43897b37db0200b6f359e04e201e76ada031251c00000000000000000000000000000000000000000000000000000000000000";
            vm.prank(address(0x9c729226e993211a816FfA79fD4F3bB40d157F29));
            (bool success, ) = address(avsOperatorManager).call(data);
            require(success, "call failed");
        }

    }
}

