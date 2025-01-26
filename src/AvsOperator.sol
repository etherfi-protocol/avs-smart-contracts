```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";

import "./eigenlayer-interfaces/IRegistryCoordinator.sol";
import "./eigenlayer-interfaces/ISignatureUtils.sol";
import "./eigenlayer-interfaces/IBLSApkRegistry.sol";
import  "./eigenlayer-interfaces/IDelegationManager.sol";

interface IARPANodeRegsitry {
    function nodeRegister(bytes calldata dkgPublicKey, bool isEigenlayerNode, address assetAccountAddress, ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry) external;
    function nodeQuit() external;
    function nodeLogOff() external;
}

contract AvsOperator is IERC1271, IBeacon {

    address public avsOperatorsManager;
    address public ecdsaSigner;   // ECDSA signer that ether.fi owns
    address public avsNodeRunner; // Staking Company such as DSRV, Pier Two, Nethermind, ...

    // DEPRECATED
    struct AvsInfo {
        bool isWhitelisted;
        bytes quorumNumbers;
        string socket;
        IBLSApkRegistry.PubkeyRegistrationParams params;
        bool isRegistered;
    }
    mapping(address => AvsInfo) public avsInfos;


    //--------------------------------------------------------------------------------------
    //----------------------------------  Admin  -------------------------------------------
    //--------------------------------------------------------------------------------------

    function initialize(address _avsOperatorsManager) external {
        require(avsOperatorsManager == address(0), "ALREADY_INITIALIZED");
        avsOperatorsManager = _avsOperatorsManager;
    }

    /// @dev implementation address for beacon proxy.
    ///      https://docs.openzeppelin.com/contracts/3.x/api/proxy#beacon
    function implementation() external view returns (address) {
        bytes32 slot = bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1);
        address implementationVariable;
        assembly {
            implementationVariable := sload(slot)
        }

        IBeacon beacon = IBeacon(implementationVariable);
        return beacon.implementation();
    }

    //--------------------------------------------------------------------------------------
    //------------------------------  AVS Operations  --------------------------------------
    //--------------------------------------------------------------------------------------

    // forwards a whitelisted call from the manager contract to an arbitrary target
    function forwardCall(address to, bytes calldata data) external managerOnly returns (bytes memory) {
        return Address.functionCall(to, data);
    }

    //--------------------------------------------------------------------------------------
    //-----------------------------  ARPA Node Operations  ---------------------------------
    //--------------------------------------------------------------------------------------

    function registerWithARPA(bytes calldata dkgPublicKey, bool isEigenlayerNode, address assetAccountAddress, ISignatureUtils.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry, address arpaNodeRegistry) external managerOnly {
        IARPANodeRegsitry(arpaNodeRegistry).nodeRegister(dkgPublicKey, isEigenlayerNode, assetAccountAddress, signatureWithSaltAndExpiry);
    }

    function unregisterFromARPA(address arpaNodeRegistry) external managerOnly {
        IARPANodeRegsitry(arpaNodeRegistry).nodeQuit();
    }

    function logOffFromARPA(address arpaNodeRegistry) external managerOnly {
        IARPANodeRegsitry(arpaNodeRegistry).nodeLogOff();
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------  AVS Metadata  --------------------------------------
    //--------------------------------------------------------------------------------------

    // register this contract as a valid operator that can be delegated funds within eigenlayer core contracts
    function registerAsOperator(IDelegationManager _delegationManager, IDelegationManager.OperatorDetails calldata _detail, string calldata _metaDataURI) external managerOnly {
        _delegationManager.registerAsOperator(_detail, _metaDataURI);
    }

    function modifyOperatorDetails(IDelegationManager _delegationManager, IDelegationManager.OperatorDetails calldata _newOperatorDetails) external managerOnly {
        _delegationManager.modifyOperatorDetails(_newOperatorDetails);
    }

    function updateOperatorMetadataURI(IDelegationManager _delegationManager, string calldata _metadataURI) external managerOnly {
        _delegationManager.updateOperatorMetadataURI(_metadataURI);
    }

    function updateAvsNodeRunner(address _avsNodeRunner) external managerOnly {
        avsNodeRunner = _avsNodeRunner;
    }

    function updateEcdsaSigner(address _ecdsaSigner) external managerOnly {
        ecdsaSigner = _ecdsaSigner;
    }

    // DEPRECATED
    function getAvsInfo(address _avsRegistryCoordinator) external view returns (AvsInfo memory) {
        return avsInfos[_avsRegistryCoordinator];
    }

    //--------------------------------------------------------------------------------------
    //---------------------------------  Signatures-  --------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Should return whether the signature provided is valid for the provided data
     * @param _digestHash   Hash of the data to be signed
     * @param _signature Signature byte array associated with _data
    */
    function isValidSignature(bytes32 _digestHash, bytes memory _signature) public view override returns (bytes4 magicValue) {
        (address recovered, ) = ECDSA.tryRecover(_digestHash, _signature);
        return recovered == ecdsaSigner ? this.isValidSignature.selector : bytes4(0xffffffff);
    }


    function verifyBlsKeyAgainstHash(BN254.G1Point memory pubkeyRegistrationMessageHash, IBLSApkRegistry.PubkeyRegistrationParams memory params) public view returns (bool) {
        // gamma = h(sigma, P, P', H(m))
        uint256 gamma = uint256(keccak256(abi.encodePacked(
            params.pubkeyRegistrationSignature.X,
            params.pubkeyRegistrationSignature.Y,
            params.pubkeyG1.X,
            params.pubkeyG1.Y,
            params.pubkeyG2.X,
            params.pubkeyG2.Y,
            pubkeyRegistrationMessageHash.X,
            pubkeyRegistrationMessageHash.Y
        ))) % BN254.FR_MODULUS;

        // e(sigma + P * gamma, [-1]_2) = e(H(m) + [1]_1 * gamma, P') 
        return BN254.pairing(
                BN254.plus(params.pubkeyRegistrationSignature, BN254.scalar_mul(params.pubkeyG1, gamma)),
                BN254.negGeneratorG2(),
                BN254.plus(pubkeyRegistrationMessageHash, BN254.scalar_mul(BN254.generatorG1(), gamma)),
                params.pubkeyG2
              );
    }

    function verifyBlsKey(address registryCoordinator, IBLSApkRegistry.PubkeyRegistrationParams memory params) public view returns (bool) {
        BN254.G1Point memory pubkeyRegistrationMessageHash = IRegistryCoordinator(registryCoordinator).pubkeyRegistrationMessageHash(address(this));

        return verifyBlsKeyAgainstHash(pubkeyRegistrationMessageHash, params);
    }

    //--------------------------------------------------------------------------------------
    //------------------------------------  Modifiers  -------------------------------------
    //--------------------------------------------------------------------------------------

    modifier managerOnly() {
        require(msg.sender == avsOperatorsManager, "NOT_MANAGER");
        _;
    }
}
```
