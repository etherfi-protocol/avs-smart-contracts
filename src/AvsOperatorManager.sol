pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import "./AvsOperator.sol";

import "./eigenlayer-interfaces/IAVSDirectory.sol";
import "./eigenlayer-interfaces/IServiceManager.sol";

contract AvsOperatorManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    UpgradeableBeacon public upgradableBeacon;
    uint256 public nextAvsOperatorId;

    mapping(uint256 => AvsOperator) public avsOperators;

    IDelegationManager public delegationManager;

    mapping(address => bool) public admins;
    mapping(address => bool) public pausers;

    IAVSDirectory public avsDirectory;

    // operator -> targetAddress -> selector -> allowed
    // allowed calls that AvsRunner can trigger from operator contract
    mapping(uint256 => mapping(address => mapping(bytes4 => bool))) public allowedOperatorCalls;

    event ForwardedOperatorCall(uint256 indexed id, address indexed target, bytes4 indexed selector, bytes data, address sender);
    event CreatedEtherFiAvsOperator(uint256 indexed id, address etherFiAvsOperator);
    event RegisteredAsOperator(uint256 indexed id, IDelegationManager.OperatorDetails detail);
    event ModifiedOperatorDetails(uint256 indexed id, IDelegationManager.OperatorDetails newOperatorDetails);
    event UpdatedOperatorMetadataURI(uint256 indexed id, string metadataURI);
    event UpdatedAvsNodeRunner(uint256 indexed id, address avsNodeRunner);
    event UpdatedEcdsaSigner(uint256 indexed id, address ecdsaSigner);
    event AllowedOperatorCallsUpdated(uint256 indexed id, address indexed target, bytes4 indexed selector, bool allowed);
    event AdminUpdated(address indexed admin, bool isAdmin);

     /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize to set variables on deployment
    function initialize(address _delegationManager, address _avsDirectory, address _etherFiAvsOperatorImpl) external initializer {
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        require(_delegationManager != address(0), "DelegationManager address cannot be zero");
        require(_avsDirectory != address(0), "AVSDirectory address cannot be zero");
        require(_etherFiAvsOperatorImpl != address(0), "EtherFiAvsOperatorImpl address cannot be zero");

        nextAvsOperatorId = 1;
        upgradableBeacon = new UpgradeableBeacon(_etherFiAvsOperatorImpl);
        delegationManager = IDelegationManager(_delegationManager);
        avsDirectory = IAVSDirectory(_avsDirectory);
    }

    function initializeAvsDirectory(address _avsDirectory) external onlyOwner {
        avsDirectory = IAVSDirectory(_avsDirectory);
    }

    //--------------------------------------------------------------------------------------
    //---------------------------------  Eigenlayer Core  ----------------------------------
    //--------------------------------------------------------------------------------------

    // This registers the operator contract as delegatable operator within Eigenlayer's core contracts.
    // Once an operator is registered, they cannot 'deregister' as an operator, and they will forever be considered "delegated to themself"
    function registerAsOperator(uint256 _id, IDelegationManager.OperatorDetails calldata _detail, string calldata _metaDataURI) external onlyOwner {
        require(bytes(_detail).length > 0, "Operator details cannot be empty");
        require(bytes(_metaDataURI).length > 0, "Metadata URI cannot be empty");

        avsOperators[_id].registerAsOperator(delegationManager, _detail, _metaDataURI);
        emit RegisteredAsOperator(_id, _detail);
    }

    function modifyOperatorDetails(uint256 _id, IDelegationManager.OperatorDetails calldata _newOperatorDetails) external onlyAdmin {
        avsOperators[_id].modifyOperatorDetails(delegationManager, _newOperatorDetails);
        emit ModifiedOperatorDetails(_id, _newOperatorDetails);
    }

    function updateOperatorMetadataURI(uint256 _id, string calldata _metadataURI) external onlyAdmin {
        avsOperators[_id].updateOperatorMetadataURI(delegationManager, _metadataURI);
        emit UpdatedOperatorMetadataURI(_id, _metadataURI);
    }

    //--------------------------------------------------------------------------------------
    //-----------------------------------  AVS Actions  ------------------------------------
    //--------------------------------------------------------------------------------------

    error InvalidOperatorCall();

    // Forward an arbitrary call to be run by the operator conract.
    // That operator must be approved for the specific method and target
    function forwardOperatorCall(uint256 _id, address _target, bytes4 _selector, bytes calldata _args) external onlyOperator(_id) {
        _forwardOperatorCall(_id, _target, _selector, _args);
    }

    // alternative version where you just pass raw input. Not sure which will end up being more convenient
    function forwardOperatorCall(uint256 _id, address _target, bytes calldata _input) external onlyOperator(_id) {

        if (_input.length < 4) revert InvalidOperatorCall();

        bytes4 _selector = bytes4(_input[:4]);
        bytes calldata _args = _input[4:];

        _forwardOperatorCall(_id, _target, _selector, _args);
    }

    function _forwardOperatorCall(uint256 _id, address _target, bytes4 _selector, bytes calldata _args) private {
        if (!isValidOperatorCall(_id, _target, _selector, _args)) revert InvalidOperatorCall();

        avsOperators[_id].forwardCall(_target, abi.encodePacked(_selector, _args));
        emit ForwardedOperatorCall(_id, _target, _selector, _args, msg.sender);
    }

    // Forward an arbitrary call to be run by the operator conract. Admins can ignore the call whitelist
    function adminForwardCall(uint256 _id, address _target, bytes4 _selector, bytes calldata _args) external onlyAdmin {

        avsOperators[_id].forwardCall(_target, abi.encodePacked(_selector, _args));
        emit ForwardedOperatorCall(_id, _target, _selector, _args, msg.sender);
    }

    function isValidOperatorCall(uint256 _id, address _target, bytes4 _selector, bytes calldata) public view returns (bool) {

        // ensure this method is allowed by this operator on target contract
        if (!allowedOperatorCalls[_id][_target][_selector]) return false;

        // could add other custom logic here that inspects payload or other data

        return true;
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------------  Admin  ---------------------------------------
    //--------------------------------------------------------------------------------------

    // specify which calls an node runner can make against which target contracts through the operator contract
    function updateAllowedOperatorCalls(uint256 _operatorId, address _target, bytes4 _selector, bool _allowed) external onlyAdmin {
        allowedOperatorCalls[_operatorId][_target][_selector] = _allowed;
        emit AllowedOperatorCallsUpdated(_operatorId, _target, _selector, _allowed);
    }

    function updateAdmin(address _address, bool _isAdmin) external onlyOwner {
        admins[_address] = _isAdmin;
        emit AdminUpdated(_address, _isAdmin);
    }

    function updateAvsNodeRunner(uint256 _id, address _avsNodeRunner) external onlyAdmin {
        avsOperators[_id].updateAvsNodeRunner(_avsNodeRunner);
        emit UpdatedAvsNodeRunner(_id, _avsNodeRunner);
    }

    function updateEcdsaSigner(uint256 _id, address _ecdsaSigner) external onlyAdmin {
        avsOperators[_id].updateEcdsaSigner(_ecdsaSigner);
        emit UpdatedEcdsaSigner(_id, _ecdsaSigner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function upgradeEtherFiAvsOperator(address _newImplementation) public onlyOwner {
        upgradableBeacon.upgradeTo(_newImplementation);
    }

    function instantiateEtherFiAvsOperator(uint256 _nums) external onlyOwner returns (uint256[] memory _ids) {
        _ids = new uint256[](_nums);
        for (uint256 i = 0; i < _nums; i++) {
            _ids[i] = _instantiateEtherFiAvsOperator();
        }
    }

    function _instantiateEtherFiAvsOperator() internal returns (uint256 _id) {
        _id = nextAvsOperatorId++;
        require(address(avsOperators[_id]) == address(0), "INVALID_ID");

        BeaconProxy proxy = new BeaconProxy(address(upgradableBeacon), "");
        avsOperators[_id] = AvsOperator(address(proxy));
        avsOperators[_id].initialize(address(this));

        emit CreatedEtherFiAvsOperator(_id, address(avsOperators[_id]));

        return _id;
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------  View Functions  -------------------------------------
    //--------------------------------------------------------------------------------------

    /// @param _id The id of etherfi avs operator
    /// @param _avsServiceManager The AVS's service manager contract address
    function avsOperatorStatus(uint256 _id, address _avsServiceManager) external view returns (IAVSDirectory.OperatorAVSRegistrationStatus) {
        return avsDirectory.avsOperatorStatus(_avsServiceManager, address(avsOperators[_id]));
    }

    function avsNodeRunner(uint256 _id) external view returns (address) {
        return avsOperators[_id].avsNodeRunner();
    }

    function ecdsaSigner(uint256 _id) external view returns (address) {
        return avsOperators[_id].ecdsaSigner();
    }

    function operatorDetails(uint256 _id) external view returns (IDelegationManager.OperatorDetails memory) {
        return delegationManager.operatorDetails(address(avsOperators[_id]));
    }

    // DEPRECATED
    function getAvsInfo(uint256 _id, address _avsRegistryCoordinator) external view returns (AvsOperator.AvsInfo memory) {
         return avsOperators[_id].getAvsInfo(_avsRegistryCoordinator);
    }

    /**
     * @notice Calculates the digest hash to be signed by an operator to register with an AVS
     * @param _id The id of etherfi avs operator
     * @param _avsServiceManager The AVS's service manager contract address
     * @param _salt A unique and single use value associated with the approver signature.
     * @param _expiry Time after which the approver's signature becomes invalid
     */
    function calculateOperatorAVSRegistrationDigestHash(uint256 _id, address _avsServiceManager, bytes32 _salt, uint256 _expiry) external view returns (bytes32) {
        address _operator = address(avsOperators[_id]);
        return avsDirectory.calculateOperatorAVSRegistrationDigestHash(_operator, _avsServiceManager, _salt, _expiry);
    }

    //--------------------------------------------------------------------------------------
    //------------------------------------  Modifiers  -------------------------------------
    //--------------------------------------------------------------------------------------

    function _onlyAdmin() internal view {
        require(admins[msg.sender] || msg.sender == owner(), "INCORRECT_CALLER");
    }

    function _onlyOperator(uint256 _id) internal view {
        require(msg.sender == avsOperators[_id].avsNodeRunner() || admins[msg.sender] || msg.sender == owner(), "INCORRECT_CALLER");
    }

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyOperator(uint256 _id) {
        _onlyOperator(_id);
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

    function setRequiredConfirmations(uint256 _requiredConfirmations) external onlyOwner {
        require(_requiredConfirmations > 0, "Required confirmations must be greater than zero");
        requiredConfirmations = _requiredConfirmations;
    }

    function createMultiSigTransaction(address _target, bytes calldata _data) external onlyAdmin {
        uint256 txId = transactionCount++;
        multiSigTransactions[txId] = MultiSigTransaction({
            target: _target,
            data: _data,
            executed: false,
            numConfirmations: 0
        });

        emit MultiSigTransactionCreated(txId, _target, _data);
    }

    function confirmMultiSigTransaction(uint256 _txId) external onlyAdmin {
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
