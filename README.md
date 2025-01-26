# Ether.fi AVS Smart Contracts

Ether.fi utilizes a contract based AVS operator instead of an EOA in order to enable multiple security and efficiency improvements when working with a large number of eigenpods and AVS's

Each operator contract is a designed to be a simple forwarding contract

## Whitelisting an operation for an operator

    // specify which calls an node runner can make against which target contracts through the operator contract
    function updateAllowedOperatorCalls(uint256 _operatorId, address _target, bytes4 _selector, bool _allowed) external onlyAdmin {
        allowedOperatorCalls[_operatorId][_target][_selector] = _allowed;
        emit AllowedOperatorCallsUpdated(_operatorId, _target, _selector, _allowed);
    }

## Tracking operator actions
All forwarded operator actions will emit the following event

    event ForwardedOperatorCall(uint256 indexed id, address indexed target, bytes4 indexed selector, bytes data, address sender);

This can be used to track which actions have been taken by which operators

## ARPA Node Registration

The ARPA node registration process is now fully implemented and tested. The following functions are available for ARPA node registration:

### AvsOperatorManager.sol

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

### AvsOperator.sol

    function registerAsOperator(IDelegationManager _delegationManager, IDelegationManager.OperatorDetails calldata _detail, string calldata _metaDataURI) external managerOnly {
        _delegationManager.registerAsOperator(_detail, _metaDataURI);
    }

    function modifyOperatorDetails(IDelegationManager _delegationManager, IDelegationManager.OperatorDetails calldata _newOperatorDetails) external managerOnly {
        _delegationManager.modifyOperatorDetails(_newOperatorDetails);
    }

    function updateOperatorMetadataURI(IDelegationManager _delegationManager, string calldata _metadataURI) external managerOnly {
        _delegationManager.updateOperatorMetadataURI(_metadataURI);
    }
