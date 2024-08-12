// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import "./AvsOperator.sol";
import "./IRoleRegistry.sol";

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

    mapping(address => bool) public DEPRECATED_admins;
    mapping(address => bool) public DEPRECATED_pausers;

    IAVSDirectory public avsDirectory;

    // operator -> targetAddress -> selector -> allowed
    // allowed calls that AvsRunner can trigger from operator contract
    mapping(uint256 => mapping(address => mapping(bytes4 => bool))) public allowedOperatorCalls;

    IRoleRegistry public immutable roleRegistry;

    event ForwardedOperatorCall(uint256 indexed id, address indexed target, bytes4 indexed selector, bytes data, address sender);
    event CreatedEtherFiAvsOperator(uint256 indexed id, address etherFiAvsOperator);
    event RegisteredAsOperator(uint256 indexed id, IDelegationManager.OperatorDetails detail);
    event ModifiedOperatorDetails(uint256 indexed id, IDelegationManager.OperatorDetails newOperatorDetails);
    event UpdatedOperatorMetadataURI(uint256 indexed id, string metadataURI);
    event UpdatedAvsNodeRunner(uint256 indexed id, address avsNodeRunner);
    event AllowedOperatorCallsUpdated(uint256 indexed id, address indexed target, bytes4 indexed selector, bool allowed);

     /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _roleRegistry) {
        roleRegistry = IRoleRegistry(_roleRegistry);
        _disableInitializers();
    }

    /// @notice Initialize to set variables on deployment
    function initialize(address _delegationManager, address _avsDirectory, address _etherFiAvsOperatorImpl) external initializer {
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        nextAvsOperatorId = 1;
        upgradableBeacon = new UpgradeableBeacon(_etherFiAvsOperatorImpl);
        delegationManager = IDelegationManager(_delegationManager);
        avsDirectory = IAVSDirectory(_avsDirectory);
    }

    function initializeAvsDirectory(address _avsDirectory) external onlyOwner {
        avsDirectory = IAVSDirectory(_avsDirectory);
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------------  ROLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 constant public ECDSA_SIGNER_ROLE = keccak256("AOM_ECDSA_SIGNER_ROLE");
    bytes32 constant public AVS_OPERATOR_ADMIN_ROLE = keccak256("AOM_AVS_OPERATOR_ADMIN_ROLE");

    //--------------------------------------------------------------------------------------
    //---------------------------------  Eigenlayer Core  ----------------------------------
    //--------------------------------------------------------------------------------------


    // This registers the operator contract as delegatable operator within Eigenlayer's core contracts.
    // Once an operator is registered, they cannot 'deregister' as an operator, and they will forever be considered "delegated to themself"
    function registerAsOperator(uint256 _id, IDelegationManager.OperatorDetails calldata _detail, string calldata _metaDataURI) external onlyOwner {
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
    error InvalidCaller();

    // Forward an arbitrary call to be run by the operator conract.
    // That operator must be approved for the specific method and target
    function forwardOperatorCall(uint256 _id, address _target, bytes4 _selector, bytes calldata _args) external {
        _forwardOperatorCall(_id, _target, _selector, _args);
    }

    // alternative version where you just pass raw input. Not sure which will end up being more convenient
    function forwardOperatorCall(uint256 _id, address _target, bytes calldata _input) external {

        if (_input.length < 4) revert InvalidOperatorCall();

        bytes4 _selector = bytes4(_input[:4]);
        bytes calldata _args = _input[4:];

        _forwardOperatorCall(_id, _target, _selector, _args);
    }

    function _forwardOperatorCall(uint256 _id, address _target, bytes4 _selector, bytes calldata _args) private {
        if (!canForwardCall(_id)) revert InvalidCaller();
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

    function updateAvsNodeRunner(uint256 _id, address _avsNodeRunner) external onlyAdmin {
        avsOperators[_id].updateAvsNodeRunner(_avsNodeRunner);
        emit UpdatedAvsNodeRunner(_id, _avsNodeRunner);
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

    function operatorDetails(uint256 _id) external view returns (IDelegationManager.OperatorDetails memory) {
        return delegationManager.operatorDetails(address(avsOperators[_id]));
    }

    function canForwardCall(uint256 _id) public view returns (bool) {
        // only can forward call to operator contract if an admin, or the registered node runner
        return (msg.sender == avsOperators[_id].avsNodeRunner() || roleRegistry.hasRole(AVS_OPERATOR_ADMIN_ROLE, msg.sender));
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


    modifier onlyAdmin() {
        if (!roleRegistry.hasRole(AVS_OPERATOR_ADMIN_ROLE, msg.sender)) revert InvalidCaller();
        _;
    }


}
