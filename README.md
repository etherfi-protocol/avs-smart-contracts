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

## Installing Foundry

To install Foundry, you can use the following command:

```sh
curl -L https://foundry.paradigm.xyz | bash
```

This command downloads and runs the Foundry installation script from the Paradigm website. Foundry is a smart contract development toolchain that includes Forge for building and testing smart contracts. 

After running the command, you can verify the installation by checking the version of Forge:

```sh
forge --version
```

## Running Tests with Foundry

To run tests using Foundry, you can use the following command:

```sh
forge test -vvv
```

This command runs the tests in the project with verbose output. For more details on how Foundry is used in this repository, you can refer to the following files:
* `.github/workflows/test.yml` - This GitHub Actions workflow file includes steps to install Foundry and run Forge build and tests.
* `foundry.toml` - This configuration file specifies the settings for Foundry in this project.
