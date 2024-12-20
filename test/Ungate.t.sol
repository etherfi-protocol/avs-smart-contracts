// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/TestSetup.sol";
import "../test/CryptoTestHelpers.t.sol";
import "../src/othentic/BLSAuthLibrary.sol";

import "forge-std/console2.sol";

interface IUngateAVSGovernance {

    function registerAsOperator(
        uint256[4] memory _blsKey,
        address _rewardsReceiver,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature,
        OthenticBLSAuthLibrary.Signature memory _blsRegistrationSignature
    ) external;

    function registerAsAllowedOperator(
        uint256[4] memory _blsKey,
        bytes calldata _authToken,
        address _rewardsReceiver,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature,
        OthenticBLSAuthLibrary.Signature memory _blsRegistrationSignature
    ) external;

    function setIsAllowlisted(bool) external;
}

contract UngateTest is TestSetup, CryptoTestHelper {

    function test_registerUngate() public {
        initializeRealisticFork(MAINNET_FORK);

        upgradeAvsContracts();

        IUngateAVSGovernance avsGovernance = IUngateAVSGovernance(address(0xB3e069FD6dDA251AcBDE09eDa547e0AB207016ee));

        uint256 operatorId = 1;
        address operator = address(avsOperatorManager.avsOperators(operatorId));

        // re-configure signer for testing
        uint256 signerKey = 0x1234abcd;
        {
            address signer = vm.addr(signerKey);
            vm.prank(admin);
            avsOperatorManager.updateEcdsaSigner(operatorId, signer);
        }

        // generate + sign the pubkey registration params with BLS key
        IBLSApkRegistry.PubkeyRegistrationParams memory blsPubkeyRegistrationParams;
        uint256[4] memory blsPubkey;
        uint256[2] memory blsSignature;
        {
            uint256 blsPrivKey = 0xaaaabbbb;

            // generate the hash we need to sign with the BLS key
            uint256[2] memory registrationMessage = OthenticBLSAuthLibrary._message(operator, address(avsGovernance));

            // convert to format expected by eigenlayer helpers
            BN254.G1Point memory message = BN254.G1Point({ X: registrationMessage[0], Y: registrationMessage[1] });
            console2.log("message", message.X, message.Y);

            // sign
            blsPubkeyRegistrationParams = generateSignedPubkeyRegistrationParams(message, blsPrivKey);

            blsSignature[0] = blsPubkeyRegistrationParams.pubkeyRegistrationSignature.X;
            blsSignature[1] = blsPubkeyRegistrationParams.pubkeyRegistrationSignature.Y;

            blsPubkey[0] = blsPubkeyRegistrationParams.pubkeyG2.X[1];
            blsPubkey[1] = blsPubkeyRegistrationParams.pubkeyG2.X[0];
            blsPubkey[2] = blsPubkeyRegistrationParams.pubkeyG2.Y[1];
            blsPubkey[3] = blsPubkeyRegistrationParams.pubkeyG2.Y[0];

            bool valid = OthenticBLSAuthLibrary.isValidSignature(OthenticBLSAuthLibrary.Signature(blsSignature), operator, address(avsGovernance), blsPubkey);
            require(valid, "Invalid BLS Signature");
        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
           address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
           signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, address(avsGovernance), signerKey);
        }

        // disable whitelist for testing
        vm.prank(address(0xe77aeb1fC3573D8e6FfafA3bAa06DF606F5c0c7F));
        avsGovernance.setIsAllowlisted(false);

        vm.prank(operator);
        avsGovernance.registerAsOperator(
            blsPubkey,
            operator,
            signatureWithSaltAndExpiry,
            OthenticBLSAuthLibrary.Signature(blsSignature)
        );
    }

    function test_registerUngateAllowlist() public {
        initializeRealisticFork(MAINNET_FORK);

        upgradeAvsContracts();

        IUngateAVSGovernance avsGovernance = IUngateAVSGovernance(address(0xB3e069FD6dDA251AcBDE09eDa547e0AB207016ee));

        uint256 operatorId = 1;
        address operator = address(avsOperatorManager.avsOperators(operatorId));

        // re-configure signer for testing
        uint256 signerKey = 0x1234abcd;
        {
            address signer = vm.addr(signerKey);
            vm.prank(admin);
            avsOperatorManager.updateEcdsaSigner(operatorId, signer);
        }

        // generate + sign the pubkey registration params with BLS key
        IBLSApkRegistry.PubkeyRegistrationParams memory blsPubkeyRegistrationParams;
        uint256[4] memory blsPubkey;
        uint256[2] memory blsSignature;
        {
            uint256 blsPrivKey = 0xaaaabbbb;

            // generate the hash we need to sign with the BLS key
            uint256[2] memory registrationMessage = OthenticBLSAuthLibrary._message(operator, address(avsGovernance));

            // convert to format expected by eigenlayer helpers
            BN254.G1Point memory message = BN254.G1Point({ X: registrationMessage[0], Y: registrationMessage[1] });

            // sign
            blsPubkeyRegistrationParams = generateSignedPubkeyRegistrationParams(message, blsPrivKey);

            blsSignature[0] = blsPubkeyRegistrationParams.pubkeyRegistrationSignature.X;
            blsSignature[1] = blsPubkeyRegistrationParams.pubkeyRegistrationSignature.Y;

            blsPubkey[0] = blsPubkeyRegistrationParams.pubkeyG2.X[1];
            blsPubkey[1] = blsPubkeyRegistrationParams.pubkeyG2.X[0];
            blsPubkey[2] = blsPubkeyRegistrationParams.pubkeyG2.Y[1];
            blsPubkey[3] = blsPubkeyRegistrationParams.pubkeyG2.Y[0];

            bool valid = OthenticBLSAuthLibrary.isValidSignature(OthenticBLSAuthLibrary.Signature(blsSignature), operator, address(avsGovernance), blsPubkey);
            require(valid, "Invalid BLS Signature");
        }

        // generate + sign operator registration digest with signer ECDSA key
        ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        {
           address avsDirectory = address(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
           signatureWithSaltAndExpiry = generateAvsRegistrationSignature(avsDirectory, operator, address(avsGovernance), signerKey);
        }

        // auth token generated externally via othentic signing server
        bytes memory _authToken = hex"53aaa5aad4efbfd8eb5792a2decdffe676959ce77c6d72d9da52abcac4eb7c4815c352c874165cfc2dd433be4ff94aeaeec5e7733f914dda67094d9ed739aaee1c";

        vm.prank(operator);
        avsGovernance.registerAsAllowedOperator(
            blsPubkey,
            _authToken,
            operator,
            signatureWithSaltAndExpiry,
            OthenticBLSAuthLibrary.Signature(blsSignature)
        );
    }

}
