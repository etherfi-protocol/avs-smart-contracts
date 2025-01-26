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

## `updateAllowedOperatorCalls` function

The `updateAllowedOperatorCalls` function allows an admin to specify which calls a node runner can make against which target contracts through the operator contract. This function takes four parameters:

- `_operatorId`: The ID of the operator.
- `_target`: The address of the target contract.
- `_selector`: The function selector of the target contract.
- `_allowed`: A boolean value indicating whether the call is allowed or not.

## `allowedOperatorCalls` mapping

The `allowedOperatorCalls` mapping is used to store the allowed calls that an operator can make. It is a nested mapping with the following structure:

- The first key is the operator ID.
- The second key is the target contract address.
- The third key is the function selector.
- The value is a boolean indicating whether the call is allowed or not.

## `AllowedOperatorCallsUpdated` event

The `AllowedOperatorCallsUpdated` event is emitted whenever the `updateAllowedOperatorCalls` function is called. This event has four parameters:

- `_operatorId`: The ID of the operator.
- `_target`: The address of the target contract.
- `_selector`: The function selector of the target contract.
- `_allowed`: A boolean value indicating whether the call is allowed or not.

## ARPA Node Registration

The ARPA node registration process is now fully implemented and tested. The following functions have been added to handle ARPA node registration:

### `registerAsOperator`

The `registerAsOperator` function registers the operator with the ARPA node registry. This function takes the following parameters:

- `_delegationManager`: The delegation manager contract.
- `_detail`: The operator details.
- `_metaDataURI`: The metadata URI.

### `modifyOperatorDetails`

The `modifyOperatorDetails` function modifies the operator details in the ARPA node registry. This function takes the following parameter:

- `_delegationManager`: The delegation manager contract.
- `_newOperatorDetails`: The new operator details.

### `updateOperatorMetadataURI`

The `updateOperatorMetadataURI` function updates the operator metadata URI in the ARPA node registry. This function takes the following parameter:

- `_delegationManager`: The delegation manager contract.
- `_metadataURI`: The new metadata URI.

### Test Case

The test case in `test/ARPA.sol` now fully verifies the ARPA node registration process. The test case includes the following steps:

- Initialize the necessary contracts and variables.
- Update the ECDSA signer for the operator.
- Generate and sign the operator registration digest with the ECDSA key.
- Unregister and re-register the operator with the ARPA node registry.
- Verify that the operator is correctly registered with the ARPA node registry.
