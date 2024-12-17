// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.25;

/*______     __      __                              __      __
 /      \   /  |    /  |                            /  |    /  |
/$$$$$$  | _$$ |_   $$ |____    ______   _______   _$$ |_   $$/   _______
$$ |  $$ |/ $$   |  $$      \  /      \ /       \ / $$   |  /  | /       |
$$ |  $$ |$$$$$$/   $$$$$$$  |/$$$$$$  |$$$$$$$  |$$$$$$/   $$ |/$$$$$$$/
$$ |  $$ |  $$ | __ $$ |  $$ |$$    $$ |$$ |  $$ |  $$ | __ $$ |$$ |
$$ \__$$ |  $$ |/  |$$ |  $$ |$$$$$$$$/ $$ |  $$ |  $$ |/  |$$ |$$ \_____
$$    $$/   $$  $$/ $$ |  $$ |$$       |$$ |  $$ |  $$  $$/ $$ |$$       |
 $$$$$$/     $$$$/  $$/   $$/  $$$$$$$/ $$/   $$/    $$$$/  $$/  $$$$$$$/
*/

import { BLS } from "./OthenticBLS.sol";

import "forge-std/console2.sol";

library OthenticBLSAuthLibrary {
    using BLS for uint256[2];

    bytes32 internal constant DOMAIN = keccak256("OthenticBLSAuth");

    struct Signature {
        uint256[2] signature;
    }

    /// @dev because of backwards compatibility issues, _signature is memory
    /// even though it should be calldata. Once old registration is removed, adjust accordingly
    function isValidSignature(
        Signature memory _signature,
        address _signer,
        address _contract,
        uint256[4] memory _blsKey
    ) internal view returns (bool) {
        /// @dev signature verification succeeds if signature and pubkey are empty
        if (!_signature.signature.isValidSignature()) return false;
        
        console2.log("passed valid check");
        console2.log("Signature", _signature.signature[0], _signature.signature[1]);
        console2.log("signer", _signer);
        console2.log("contract", _contract);
        console2.log(_blsKey[0], _blsKey[1], _blsKey[2], _blsKey[3]);

        uint256[2] memory _messageHash = _message(_signer, _contract);
        console2.log("hash", _messageHash[0], _messageHash[1]);
        (bool _callSuccess, bool _result) = _signature.signature.verifySingle(_blsKey, _messageHash);
        console2.log("callSuccess", _callSuccess, "result", _result);
        return _callSuccess && _result;
    }

    /// @dev uses abi.encode twice because of the way the bls signatures are implemented in the CLI
    /// if we want to reduce more gas we should look into how polygon implemented it
    function _message(address _signer, address _contract) internal view returns (uint256[2] memory) {
        // slither-disable-next-line calls-loop
        bytes32 _hash = keccak256(abi.encode(_signer, _contract, block.chainid));
        return BLS.hashToPoint(DOMAIN, abi.encode(_hash));
    }
}
