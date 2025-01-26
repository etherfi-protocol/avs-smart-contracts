pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";

import "./eigenlayer-interfaces/IRegistryCoordinator.sol";
import "./eigenlayer-interfaces/ISignatureUtils.sol";
import "./eigenlayer-interfaces/IBLSApkRegistry.sol";
import  "./eigenlayer-interfaces/IDelegationManager.sol";

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
        require(_avsOperatorsManager != address(0), "INVALID_MANAGER_ADDRESS");
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
        require(Address.isContract(to), "TARGET_NOT_CONTRACT");
        return Address.functionCall(to, data);
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------  AVS Metadata  --------------------------------------
    //--------------------------------------------------------------------------------------

    // register this contract as a valid operator that can be delegated funds within eigenlayer core contracts
    function registerAsOperator(IDelegationManager _delegationManager, IDelegationManager.OperatorDetails calldata _detail, string calldata _metaDataURI) external managerOnly {
        require(Address.isContract(address(_delegationManager)), "DELEGATION_MANAGER_NOT_CONTRACT");
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

    //--------------------------------------------------------------------------------------
    //----------------------------------  Multi-Sig Wallet  --------------------------------
    //--------------------------------------------------------------------------------------

    struct MultiSigTransaction {
        address target;
        bytes data;
        bool executed;
        uint256 numConfirmations;
    }

    mapping(uint256 => MultiSigTransaction) public multiSigTransactions;
    mapping(uint256 => mapping(address => bool)) public isConfirmed;
    uint256 public transactionCount;
    uint256 public requiredConfirmations;

    event MultiSigTransactionCreated(uint256 indexed txId, address indexed target, bytes data);
    event MultiSigTransactionConfirmed(uint256 indexed txId, address indexed confirmer);
    event MultiSigTransactionExecuted(uint256 indexed txId, address indexed target, bytes data);

    function setRequiredConfirmations(uint256 _requiredConfirmations) external managerOnly {
        require(_requiredConfirmations > 0, "Required confirmations must be greater than zero");
        requiredConfirmations = _requiredConfirmations;
    }

    function createMultiSigTransaction(address _target, bytes calldata _data) external managerOnly {
        uint256 txId = transactionCount++;
        multiSigTransactions[txId] = MultiSigTransaction({
            target: _target,
            data: _data,
            executed: false,
            numConfirmations: 0
        });

        emit MultiSigTransactionCreated(txId, _target, _data);
    }

    function confirmMultiSigTransaction(uint256 _txId) external managerOnly {
        require(!multiSigTransactions[_txId].executed, "Transaction already executed");
        require(!isConfirmed[_txId][msg.sender], "Transaction already confirmed");

        isConfirmed[_txId][msg.sender] = true;
        multiSigTransactions[_txId].numConfirmations++;

        emit MultiSigTransactionConfirmed(_txId, msg.sender);

        if (multiSigTransactions[_txId].numConfirmations >= requiredConfirmations) {
            executeMultiSigTransaction(_txId);
        }
    }

    function executeMultiSigTransaction(uint256 _txId) internal {
        require(multiSigTransactions[_txId].numConfirmations >= requiredConfirmations, "Not enough confirmations");

        MultiSigTransaction storage transaction = multiSigTransactions[_txId];
        transaction.executed = true;

        (bool success, ) = transaction.target.call(transaction.data);
        require(success, "Transaction execution failed");

        emit MultiSigTransactionExecuted(_txId, transaction.target, transaction.data);
    }
}
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
    mapping(address => AvsInfo) public avsInfos;

    //--------------------------------------------------------------------------------------
    //----------------------------------  Admin  -------------------------------------------
    //--------------------------------------------------------------------------------------

    function initialize(address _avsOperatorsManager) external {
        require(avsOperatorsManager == address(0), "ALREADY_INITIALIZED");
        require(avsOperatorsManager == address(0), "ALREADY_INITIALIZED");
        require(_avsOperatorsManager != address(0), "INVALID_MANAGER_ADDRESS");
        avsOperatorsManager = _avsOperatorsManager;
    }

    /// @dev implementation address for beacon proxy.
        require(_avsOperatorsManager != address(0), "INVALID_MANAGER_ADDRESS");
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
        require(Address.isContract(to), "TARGET_NOT_CONTRACT");
        return Address.functionCall(to, data);
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------  AVS Metadata  --------------------------------------
    //--------------------------------------------------------------------------------------

    // register this contract as a valid operator that can be delegated funds within eigenlayer core contracts
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
    function registerAsOperator(IDelegationManager _delegationManager, IDelegationManager.OperatorDetails calldata _detail, string calldata _metaDataURI) external managerOnly {
    //--------------------------------------------------------------------------------------
    //--------------------------------  AVS Metadata  --------------------------------------
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
    // register this contract as a valid operator that can be delegated funds within eigenlayer core contracts
    //---------------------------------  Signatures-  --------------------------------------
    //--------------------------------------------------------------------------------------

    function registerAsOperator(IDelegationManager _delegationManager, IDelegationManager.OperatorDetails calldata _detail, string calldata _metaDataURI) external managerOnly {
    /**
     * @dev Should return whether the signature provided is valid for the provided data
        require(Address.isContract(address(_delegationManager)), "DELEGATION_MANAGER_NOT_CONTRACT");
        _delegationManager.registerAsOperator(_detail, _metaDataURI);
    }

     * @param _digestHash   Hash of the data to be signed
     * @param _signature Signature byte array associated with _data
    */
    function isValidSignature(bytes32 _digestHash, bytes memory _signature) public view override returns (bytes4 magicValue) {
        (address recovered, ) = ECDSA.tryRecover(_digestHash, _signature);
    function updateOperatorMetadataURI(IDelegationManager _delegationManager, string calldata _metadataURI) external managerOnly {
        _delegationManager.updateOperatorMetadataURI(_metadataURI);
    }

    function updateAvsNodeRunner(address _avsNodeRunner) external managerOnly {
        avsNodeRunner = _avsNodeRunner;
    }

    function updateEcdsaSigner(address _ecdsaSigner) external managerOnly {
            params.pubkeyG1.X,
            params.pubkeyG1.Y,
            params.pubkeyG2.X,
            params.pubkeyG2.Y,
        return avsInfos[_avsRegistryCoordinator];
    }

    //--------------------------------------------------------------------------------------
    /**
     * @dev Should return whether the signature provided is valid for the provided data
        // e(sigma + P * gamma, [-1]_2) = e(H(m) + [1]_1 * gamma, P') 
        return BN254.pairing(
                BN254.plus(params.pubkeyRegistrationSignature, BN254.scalar_mul(params.pubkeyG1, gamma)),
     * @param _digestHash   Hash of the data to be signed
     * @param _signature Signature byte array associated with _data
    */
                BN254.negGeneratorG2(),
                BN254.plus(pubkeyRegistrationMessageHash, BN254.scalar_mul(BN254.generatorG1(), gamma)),
                params.pubkeyG2
              );
    }

    function isValidSignature(bytes32 _digestHash, bytes memory _signature) public view override returns (bytes4 magicValue) {
        (address recovered, ) = ECDSA.tryRecover(_digestHash, _signature);
    function verifyBlsKey(address registryCoordinator, IBLSApkRegistry.PubkeyRegistrationParams memory params) public view returns (bool) {
    //--------------------------------------------------------------------------------------

    function _managerOnly() internal view {
        require(msg.sender == avsOperatorsManager, "NOT_MANAGER");
    }

    modifier managerOnly() {
        _managerOnly();
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  Multi-Sig Wallet  --------------------------------
    //--------------------------------------------------------------------------------------

    struct MultiSigTransaction {
        address target;
        bytes data;
        bool executed;
        uint256 numConfirmations;
    }

            pubkeyRegistrationMessageHash.X,
            pubkeyRegistrationMessageHash.Y
        ))) % BN254.FR_MODULUS;

        // e(sigma + P * gamma, [-1]_2) = e(H(m) + [1]_1 * gamma, P') 
        return BN254.pairing(
                BN254.plus(params.pubkeyRegistrationSignature, BN254.scalar_mul(params.pubkeyG1, gamma)),
    mapping(uint256 => MultiSigTransaction) public multiSigTransactions;
    mapping(uint256 => mapping(address => bool)) public isConfirmed;
                BN254.negGeneratorG2(),
                BN254.plus(pubkeyRegistrationMessageHash, BN254.scalar_mul(BN254.generatorG1(), gamma)),
    uint256 public transactionCount;
    uint256 public requiredConfirmations;

    event MultiSigTransactionCreated(uint256 indexed txId, address indexed target, bytes data);
                params.pubkeyG2
              );
    }

    event MultiSigTransactionConfirmed(uint256 indexed txId, address indexed confirmer);
    event MultiSigTransactionExecuted(uint256 indexed txId, address indexed target, bytes data);

    function setRequiredConfirmations(uint256 _requiredConfirmations) external managerOnly {
    function verifyBlsKey(address registryCoordinator, IBLSApkRegistry.PubkeyRegistrationParams memory params) public view returns (bool) {
    modifier managerOnly() {
        _managerOnly();
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  Multi-Sig Wallet  --------------------------------
    //--------------------------------------------------------------------------------------

    struct MultiSigTransaction {
        address target;
        bytes data;
        bool executed;
        uint256 numConfirmations;
    }

        emit MultiSigTransactionCreated(txId, _target, _data);
    }

    function confirmMultiSigTransaction(uint256 _txId) external managerOnly {
    mapping(uint256 => MultiSigTransaction) public multiSigTransactions;
    mapping(uint256 => mapping(address => bool)) public isConfirmed;
        require(!multiSigTransactions[_txId].executed, "Transaction already executed");
    uint256 public transactionCount;
    uint256 public requiredConfirmations;

    event MultiSigTransactionCreated(uint256 indexed txId, address indexed target, bytes data);
        require(!isConfirmed[_txId][msg.sender], "Transaction already confirmed");

        isConfirmed[_txId][msg.sender] = true;
        multiSigTransactions[_txId].numConfirmations++;

        emit MultiSigTransactionConfirmed(_txId, msg.sender);

        if (multiSigTransactions[_txId].numConfirmations >= requiredConfirmations) {
        require(_requiredConfirmations > 0, "Required confirmations must be greater than zero");
        requiredConfirmations = _requiredConfirmations;
    }

    function createMultiSigTransaction(address _target, bytes calldata _data) external managerOnly {
        uint256 txId = transactionCount++;
        emit MultiSigTransactionExecuted(_txId, transaction.target, transaction.data);
    }
}
        require(!multiSigTransactions[_txId].executed, "Transaction already executed");
        require(!isConfirmed[_txId][msg.sender], "Transaction already confirmed");

        isConfirmed[_txId][msg.sender] = true;
        multiSigTransactions[_txId].numConfirmations++;

        emit MultiSigTransactionConfirmed(_txId, msg.sender);

        if (multiSigTransactions[_txId].numConfirmations >= requiredConfirmations) {
            executeMultiSigTransaction(_txId);
        }
    }

    function executeMultiSigTransaction(uint256 _txId) internal {
        require(multiSigTransactions[_txId].numConfirmations >= requiredConfirmations, "Not enough confirmations");

        MultiSigTransaction storage transaction = multiSigTransactions[_txId];
        transaction.executed = true;

        (bool success, ) = transaction.target.call(transaction.data);
        require(success, "Transaction execution failed");

