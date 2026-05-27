// SPDX-License-Identifier: MIT
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
import "./interfaces/IRoleRegistry.sol";

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

    // Superseded by RoleRegistry; storage slot retained for upgrade compatibility.
    mapping(address => bool) public DEPRECATED_admins;
    // Superseded by RoleRegistry; storage slot retained for upgrade compatibility.
    mapping(address => bool) public DEPRECATED_pausers;

    IAVSDirectory public avsDirectory;

    // operator -> targetAddress -> selector -> allowed
    // allowed calls that AvsRunner can trigger from operator contract
    mapping(uint256 => mapping(address => mapping(bytes4 => bool))) public allowedOperatorCalls;

    //--------------------------------------------------------------------------------------
    //----------------------------  Slashing kill switch state  ----------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Per-selector configuration for the slashing-registration kill switch.
    /// @dev `avsArgOffset` is the byte offset (within calldata args, after the 4-byte selector)
    ///      where the AVS address word lives. Defaults to 0 (first arg).
    struct SlashingSelectorConfig {
        bool watched;
        uint16 avsArgOffset;
    }

    /// @notice Shared etherfi RoleRegistry. Set in the implementation constructor — each upgrade
    ///         deploys a new implementation referencing the canonical RoleRegistry deployment.
    IRoleRegistry public immutable roleRegistry;

    /// @notice One-way circuit breaker. Once `true`, any forwarded call whose selector is in
    ///         `slashingSelectorConfigs` reverts. There is no method to flip this back to `false`.
    bool public slashingRegistrationDisabled;

    /// @notice Selectors classified as slashing-relevant. Add-only (no removal).
    mapping(bytes4 => SlashingSelectorConfig) public slashingSelectorConfigs;

    /// @notice Per-AVS surgical block. Add-only (no removal). Independent of the global flag.
    mapping(address => bool) public isSlashingRegistrationDisabledForAvs;

    //--------------------------------------------------------------------------------------
    //----------------------------------  Events / Errors  ---------------------------------
    //--------------------------------------------------------------------------------------

    event ForwardedOperatorCall(uint256 indexed id, address indexed target, bytes4 indexed selector, bytes data, address sender);
    event CreatedEtherFiAvsOperator(uint256 indexed id, address etherFiAvsOperator);
    event RegisteredAsOperator(uint256 indexed id, IDelegationManager.OperatorDetails detail);
    event ModifiedOperatorDetails(uint256 indexed id, IDelegationManager.OperatorDetails newOperatorDetails);
    event UpdatedOperatorMetadataURI(uint256 indexed id, string metadataURI);
    event UpdatedAvsNodeRunner(uint256 indexed id, address avsNodeRunner);
    event UpdatedEcdsaSigner(uint256 indexed id, address ecdsaSigner);
    event AllowedOperatorCallsUpdated(uint256 indexed id, address indexed target, bytes4 indexed selector, bool allowed);

    event SlashingRegistrationDisabled();
    event SlashingRegistrationSelectorAdded(bytes4 indexed selector, uint16 avsArgOffset);
    event SlashingRegistrationDisabledForAvs(address indexed avs);

    error InvalidOperatorCall();
    error IncorrectRole();
    error SlashingAlreadyDisabled();
    error SlashingDisabledRegistrationBlocked();
    error SlashingDisabledForAvs(address avs);
    error SlashingCalldataTooShort();
    error SelectorAlreadyWatched();
    error AvsAlreadyDisabled();
    error InvalidAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _roleRegistry) {
        if (_roleRegistry == address(0)) revert InvalidAddress();
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

        _enforceSlashingKillSwitch(_selector, _args);

        avsOperators[_id].forwardCall(_target, abi.encodePacked(_selector, _args));
        emit ForwardedOperatorCall(_id, _target, _selector, _args, msg.sender);
    }

    // Forward an arbitrary call to be run by the operator conract. Admins can ignore the call whitelist.
    // The slashing kill switch still applies — there is no admin bypass once a watched selector is involved.
    function adminForwardCall(uint256 _id, address _target, bytes4 _selector, bytes calldata _args) external onlyAdmin {

        _enforceSlashingKillSwitch(_selector, _args);

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
    //----------------------------  Slashing kill switch  ----------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice One-way: flip the global slashing-registration kill switch ON. Cannot be reversed.
    /// @dev Caller must hold `OPERATING_MULTISIG` in the configured RoleRegistry.
    function disableSlashingRegistration() external {
        roleRegistry.onlyOperatingMultisig(msg.sender);
        if (slashingRegistrationDisabled) revert SlashingAlreadyDisabled();

        slashingRegistrationDisabled = true;
        emit SlashingRegistrationDisabled();
    }

    /// @notice Add a selector to the watched list. Add-only — selectors cannot be removed.
    /// @param _selector Function selector classified as slashing-relevant.
    /// @param _avsArgOffset Byte offset (within args, after selector) of the AVS address word.
    function addSlashingRegistrationSelector(bytes4 _selector, uint16 _avsArgOffset) external onlyAdmin {
        if (slashingSelectorConfigs[_selector].watched) revert SelectorAlreadyWatched();

        slashingSelectorConfigs[_selector] = SlashingSelectorConfig({
            watched: true,
            avsArgOffset: _avsArgOffset
        });
        emit SlashingRegistrationSelectorAdded(_selector, _avsArgOffset);
    }

    /// @notice Block slashing registration for a single AVS. Add-only — entries cannot be removed.
    /// @dev Independent of the global flag: a per-AVS block fires whether or not the global
    ///      switch is on, but only for selectors in the watched list.
    function disableSlashingRegistrationForAvs(address _avs) external onlyAdmin {
        if (_avs == address(0)) revert InvalidAddress();
        if (isSlashingRegistrationDisabledForAvs[_avs]) revert AvsAlreadyDisabled();

        isSlashingRegistrationDisabledForAvs[_avs] = true;
        emit SlashingRegistrationDisabledForAvs(_avs);
    }

    function _enforceSlashingKillSwitch(bytes4 _selector, bytes calldata _args) internal view {
        SlashingSelectorConfig memory cfg = slashingSelectorConfigs[_selector];
        if (!cfg.watched) return;

        if (slashingRegistrationDisabled) revert SlashingDisabledRegistrationBlocked();

        uint256 offset = uint256(cfg.avsArgOffset);
        if (_args.length < offset + 32) revert SlashingCalldataTooShort();

        address avs = abi.decode(_args[offset:offset + 32], (address));
        if (isSlashingRegistrationDisabledForAvs[avs]) revert SlashingDisabledForAvs(avs);
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
        roleRegistry.onlyOperatingMultisig(msg.sender);
    }

    function _onlyOperator(uint256 _id) internal view {
        if (msg.sender == avsOperators[_id].avsNodeRunner()) return;
        roleRegistry.onlyOperatingMultisig(msg.sender);
    }

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyOperator(uint256 _id) {
        _onlyOperator(_id);
        _;
    }

}
