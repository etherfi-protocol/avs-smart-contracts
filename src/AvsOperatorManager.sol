// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import "./AvsOperator.sol";
import "./interfaces/IAvsOperatorManager.sol";
import "./interfaces/IRoleRegistry.sol";

import "./eigenlayer-interfaces/IAVSDirectory.sol";

contract AvsOperatorManager is
    IAvsOperatorManager,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{

    //---------------------------------------------------------------------------
    //-----------------------------  Storage  -----------------------------------
    //---------------------------------------------------------------------------

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
    mapping(address => mapping(bytes4 => bool)) public allowedAdminCalls;

    //---------------------------------------------------------------------------
    //---------------------------  ROLES  ---------------------------------------
    //---------------------------------------------------------------------------

    IRoleRegistry public immutable roleRegistry;
    bytes32 public constant AVS_OPERATOR_MANAGER_ADMIN_ROLE = keccak256("AVS_OPERATOR_MANAGER_ADMIN_ROLE");
    bytes32 public constant AVS_OPERATOR_MANAGER_WHITELIST_UPDATER_ROLE = keccak256("AVS_OPERATOR_MANAGER_WHITELIST_UPDATER_ROLE");

     /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _roleRegistry) {
        roleRegistry = IRoleRegistry(_roleRegistry);
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
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
    //---------------------------------  Eigenlayer Core  ----------------------------------
    //--------------------------------------------------------------------------------------

    // This registers the operator contract as delegatable operator within Eigenlayer's core contracts.
    // Once an operator is registered, they cannot 'deregister' as an operator, and they will forever be considered "delegated to themself"
    function registerAsOperator(uint256 _id, address _delegationApprover, uint32 _allocationDelay, string calldata _metaDataURI) external onlyWhitelistUpdater {
        avsOperators[_id].registerAsOperator(delegationManager, _delegationApprover, _allocationDelay, _metaDataURI);
    }

    function modifyOperatorDetails(uint256 _id, address _delegationApprover) external onlyAdmin {
        avsOperators[_id].modifyOperatorDetails(delegationManager, _delegationApprover);
    }

    function updateOperatorMetadataURI(uint256 _id, string calldata _metadataURI) external onlyAdmin {
        avsOperators[_id].updateOperatorMetadataURI(delegationManager, _metadataURI);
    }

    function queueWithdrawals(IDelegationManager.QueuedWithdrawalParams[] calldata params) external onlyAdmin returns (bytes32[] memory withdrawalRoots) {
        return delegationManager.queueWithdrawals(params);
    }

    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) external onlyAdmin {
        delegationManager.completeQueuedWithdrawals(withdrawals, tokens, receiveAsTokens);
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------  Call Forwarding  ------------------------------------
    //--------------------------------------------------------------------------------------

    // Forward an arbitrary call to be run by the operator contract.
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

    // Forward an arbitrary call to be run by the operator conract. Admins can forward calls to any of the operator contracts
    function adminForwardCall(uint256 _id, address _target, bytes4 _selector, bytes calldata _args) external onlyAdmin {
        if (!isValidOperatorCall(_id, _target, _selector, _args)) revert InvalidOperatorCall();

        avsOperators[_id].forwardCall(_target, abi.encodePacked(_selector, _args));
        emit ForwardedOperatorCall(_id, _target, _selector, _args, msg.sender);
    }

    function isValidOperatorCall(uint256 _id, address _target, bytes4 _selector, bytes calldata) public view returns (bool) {

        // ensure this method is allowed by this operator on target contract
        if (!allowedOperatorCalls[_id][_target][_selector]) return false;

        // could add other custom logic here that inspects payload or other data

        return true;
    }

    function isValidAdminCall(address _target, bytes4 _selector, bytes calldata) public view returns (bool) {

        // ensure this method is allowed by this operator on target contract
        if (!allowedAdminCalls[_target][_selector]) return false;

        // could add other custom logic here that inspects payload or other data

        return true;
    }

    // specify which calls an node runner can make against which target contracts through the operator contract
    function updateAllowedOperatorCalls(uint256 _operatorId, address _target, bytes4 _selector, bool _allowed) external onlyWhitelistUpdater {
        allowedOperatorCalls[_operatorId][_target][_selector] = _allowed;
        emit AllowedOperatorCallsUpdated(_operatorId, _target, _selector, _allowed);
    }

    // specify which calls an admin can make against which target contracts through any operator contract
    function updateAllowedAdminCalls(address _target, bytes4 _selector, bool _allowed) external onlyWhitelistUpdater {
        allowedAdminCalls[_target][_selector] = _allowed;
        emit AllowedAdminCallsUpdated(_target, _selector, _allowed);
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------------  Admin  ---------------------------------------
    //--------------------------------------------------------------------------------------

    function updateAvsNodeRunner(uint256 _id, address _avsNodeRunner) external onlyAdmin {
        avsOperators[_id].updateAvsNodeRunner(_avsNodeRunner);
        emit UpdatedAvsNodeRunner(_id, _avsNodeRunner);
    }

    function updateEcdsaSigner(uint256 _id, address _ecdsaSigner) external onlyAdmin {
        avsOperators[_id].updateEcdsaSigner(_ecdsaSigner);
        emit UpdatedEcdsaSigner(_id, _ecdsaSigner);
    }

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

    function avsNodeRunner(uint256 _id) external view returns (address) {
        return avsOperators[_id].avsNodeRunner();
    }

    function ecdsaSigner(uint256 _id) external view returns (address) {
        return avsOperators[_id].ecdsaSigner();
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

    // is the caller an admin or the specified operator for a given operator contract
    modifier onlyOperator(uint256 _id) {
        if (!(roleRegistry.hasRole(AVS_OPERATOR_MANAGER_ADMIN_ROLE, msg.sender) || msg.sender == avsOperators[_id].avsNodeRunner())) revert IncorrectRole();
        _;
    }

    modifier onlyAdmin() {
        if (!roleRegistry.hasRole(AVS_OPERATOR_MANAGER_ADMIN_ROLE, msg.sender)) revert IncorrectRole();
        _;
    }

    modifier onlyWhitelistUpdater() {
        if (!roleRegistry.hasRole(AVS_OPERATOR_MANAGER_WHITELIST_UPDATER_ROLE, msg.sender)) revert IncorrectRole();
        _;
    }


}
