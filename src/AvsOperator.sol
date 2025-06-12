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
import "./AvsOperatorManager.sol";



contract AvsOperator is IERC1271, IBeacon {

    AvsOperatorManager public avsOperatorManager;
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

    bool initialized;

    IStrategyManager public immutable strategyManager;
    IDelegationManager public immutable delegationManager;

    //--------------------------------------------------------------------------------------
    //----------------------------------  Admin  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _strategyManager, address _delegationManager) {
        strategyManager = IStrategyManager(_strategyManager);
        delegationManager = IDelegationManager(_delegationManager);
        initialized = true; // prevent initialization of the proxy implementation
    }

    function initialize(address _avsOperatorManager) external {
        require(!initialized, "ALREADY_INITIALIZED");
        require(address(avsOperatorManager) == address(0), "ALREADY_INITIALIZED");
        avsOperatorManager = AvsOperatorManager(_avsOperatorManager);
        initialized = true;
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

    function updateAvsNodeRunner(address _avsNodeRunner) external onlyManager {
        avsNodeRunner = _avsNodeRunner;
    }

    function updateEcdsaSigner(address _ecdsaSigner) external onlyManager {
        ecdsaSigner = _ecdsaSigner;
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------  Call Forwarding  ------------------------------------
    //--------------------------------------------------------------------------------------

    // forwards a whitelisted call from the manager contract to an arbitrary target
    function forwardCall(address to, bytes calldata data) external onlyManager returns (bytes memory) {
        return Address.functionCall(to, data);
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------  Eigenlayer  ----------------------------------------
    //--------------------------------------------------------------------------------------

    // register this contract as a valid operator that can be delegated funds within eigenlayer core contracts
    function registerAsOperator(address _delegationApprover, uint32 _allocationDelay, string calldata _metaDataURI) external onlyManager {
        delegationManager.registerAsOperator(_delegationApprover, _allocationDelay, _metaDataURI);
    }

    function modifyOperatorDetails(address _delegationApprover) external onlyManager {
        delegationManager.modifyOperatorDetails(address(this), _delegationApprover);
    }

    function updateOperatorMetadataURI(string calldata _metadataURI) external onlyManager {
        delegationManager.updateOperatorMetadataURI(address(this), _metadataURI);
    }

    function depositIntoStrategy(IStrategy strategy, address token, uint256 amount) external onlyManager {
        IERC20(token).approve(address(strategyManager), amount);

        strategyManager.depositIntoStrategy(strategy, IERC20(token), amount);
    }

    function queueWithdrawals(IDelegationManager.QueuedWithdrawalParams[] calldata params) external onlyManager returns (bytes32[] memory withdrawalRoots) {
        return delegationManager.queueWithdrawals(params);
    }

    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) external onlyManager {
        delegationManager.completeQueuedWithdrawals(withdrawals, tokens, receiveAsTokens);
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

    modifier onlyManager() {
        require(msg.sender == address(avsOperatorManager), "NOT_MANAGER");
        _;
    }
}
