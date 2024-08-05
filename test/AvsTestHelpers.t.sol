// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../test/AvsOperatorManager.t.sol";

contract AvsTestHelpers is EtherFiAvsOperatorsManagerTest {

    // The avs parameter is the address of the contract serving as the "ServiceManager" as defined in
    // the Eigenlayer docs. For non-EigenDA based AVS's this contract often has a different name
    // such as "WitnessHub" for witness chain
    function calculateAvsRegistrationaDigestHash(address operator, address avs, bytes32 salt, uint256 expiry) external view returns (bytes32) {

            IAVSDirectory avsDirectory = IAVSDirectory(avsOperatorManager.avsDirectory());
            return avsDirectory.calculateOperatorAVSRegistrationDigestHash(
                address(operator),
                address(avs),
                salt,
                expiry
            );
    }
}
