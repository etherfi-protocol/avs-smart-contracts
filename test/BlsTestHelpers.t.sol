// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "../src/eigenlayer-libraries/BN254.sol";
import "../src/eigenlayer-interfaces/IBLSApkRegistry.sol";
import "../src/eigenlayer-interfaces/ISignatureUtils.sol";
import "../src/eigenlayer-interfaces/IAVSDirectory.sol";

contract BlsTestHelper is Test {
    using Strings for uint256;
    using BN254 for BN254.G1Point;

    // This function utilizes the FFI to compute the G2 point of the provided private bls key.
    function mul(uint256 x) public returns (BN254.G2Point memory g2Point) {
        string[] memory inputs = new string[](5);
        inputs[0] = "go";
        inputs[1] = "run";
        inputs[2] = "test/ffi/go/g2mul.go";
        inputs[3] = x.toString(); 

        inputs[4] = "1";
        bytes memory res = vm.ffi(inputs);
        g2Point.X[1] = abi.decode(res, (uint256));

        inputs[4] = "2";
        res = vm.ffi(inputs);
        g2Point.X[0] = abi.decode(res, (uint256));

        inputs[4] = "3";
        res = vm.ffi(inputs);
        g2Point.Y[1] = abi.decode(res, (uint256));

        inputs[4] = "4";
        res = vm.ffi(inputs);
        g2Point.Y[0] = abi.decode(res, (uint256));
    }

    // This function utilizes the FFI to compute the G2 point.
    // It is intended to only be used for signing test values
    function generateSignedPubkeyRegistrationParams(BN254.G1Point memory registrationHash, uint256 privKey) internal returns (IBLSApkRegistry.PubkeyRegistrationParams memory) {

        IBLSApkRegistry.PubkeyRegistrationParams memory params;
        params.pubkeyG1 = BN254.generatorG1().scalar_mul(privKey);
        params.pubkeyG2 = BlsTestHelper.mul(privKey);
        params.pubkeyRegistrationSignature = signBLSHash(registrationHash, privKey);

        return params;
    }

    function signBLSHash(BN254.G1Point memory messageHash, uint256 privKey) internal view returns (BN254.G1Point memory) {
        return BN254.scalar_mul(messageHash, privKey);
    }

    // The serviceManager parameter is the address of the contract serving as the "ServiceManager" as defined in
    // the Eigenlayer docs. For non-EigenDA based AVS's this contract often has a different name
    // such as "WitnessHub" for witness chain
    function generateAvsRegistrationSignature(
        address avsDirectory,
        address operator,
        address serviceManager,
        uint256 signerKey
    ) internal view returns (ISignatureUtils.SignatureWithSaltAndExpiry memory) {

        // 1. compute registration digest
        uint256 expiry = block.timestamp + 10000;
        bytes32 salt = bytes32(0x1234567890000000000000000000000000000000000000000000000000000000);

        bytes32 registrationDigest = IAVSDirectory(avsDirectory).calculateOperatorAVSRegistrationDigestHash(
            address(operator),
            address(serviceManager),
            salt,
            expiry
        );

        // 2. sign digest with configured signer
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, registrationDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        return ISignatureUtils.SignatureWithSaltAndExpiry({
                signature: signature,
                salt: salt,
                expiry: expiry
        });

    }


    function parseBlsKey(string memory filepath) internal view returns (IBLSApkRegistry.PubkeyRegistrationParams memory) {

        string memory json = vm.readFile(filepath);

        uint256 g1x = vm.parseJsonUint(json, ".g1.x");
        uint256 g1y = vm.parseJsonUint(json, ".g1.y");
        uint256[] memory g2xArray = vm.parseJsonUintArray(json, ".g2.x");
        uint256[] memory g2yArray = vm.parseJsonUintArray(json, ".g2.y");
        uint256 sx = vm.parseJsonUint(json, ".signature.x");
        uint256 sy = vm.parseJsonUint(json, ".signature.y");

        uint256[2] memory g2x;
        g2x[0] = g2xArray[0];
        g2x[1] = g2xArray[1];

        uint256[2] memory g2y;
        g2y[0] = g2yArray[0];
        g2y[1] = g2yArray[1];

        BN254.G1Point memory pubkeySignaturePoint = BN254.G1Point({
            X: sx,
            Y: sy
        });
        BN254.G1Point memory pubkeyG1 = BN254.G1Point({
            X: g1x,
            Y: g1y
        });
        BN254.G2Point memory pubkeyG2 = BN254.G2Point({
            X: g2x,
            Y: g2y
        });
        IBLSApkRegistry.PubkeyRegistrationParams memory pubkeyRegistrationParams = IBLSApkRegistry.PubkeyRegistrationParams({
            pubkeyRegistrationSignature: pubkeySignaturePoint,
            pubkeyG1: pubkeyG1,
            pubkeyG2: pubkeyG2
        });

        return pubkeyRegistrationParams;

    }

}
