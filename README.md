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

# ether.fi Cash Smart Contracts

Welcome to the ether.fi Cash Smart Contracts repository! This project powers the ether.fi Cash product, providing seamless debit and credit functionalities for users.

## Overview

ether.fi Cash allows users to manage their funds through two primary mechanisms:

- **Debit:** Users spend their own funds via the ether.fi card, with transactions flowing directly from their UserSafe contracts to the Settlement Dispatcher contract.
- **Credit:** Users can borrow funds from the ether.fi Debt Manager by holding collateral with their UserSafe. These funds are available for spending with the ether.fi card, much like a traditional credit card, but backed by the user's collateral.

## Key Contracts

The project comprises several smart contracts that ensure secure and efficient handling of user funds, collateral, and borrowing. Some of the main components include:

- **UserSafe**: Manages user-owned assets and permissions.
- **L2DebtManager**: Handles debt management for credit flows.
- **PriceProvider**: Supplies price data for collateral valuation.

## Get Started

To deploy and interact with these smart contracts, clone the repository and follow the build and test instructions provided below.

### Clone the repository

```shell
git clone https://github.com/etherfi-protocol/cash-contracts
```

### Install dependencies

```shell
yarn
```

### Build the repo

```shell
yarn build
```

### Test

```shell
yarn test
```

## Security

The contracts are designed with security in mind, incorporating features like spending limits, delayed withdrawals, and recovery mechanisms.
