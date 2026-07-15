// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import "../src/AvsOperatorManager.sol";

/**
 * @title DeployAvsOperatorManagerCreate2
 * @notice Deterministically deploys the audited `AvsOperatorManager` implementation via CREATE2.
 *
 *         The CREATE2 salt is the audited GitHub commit hash:
 *             c40319be0ede648041130376608b39fca11c6ecd
 *
 *         Because the resulting address is `keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))`,
 *         the deployed address itself is a cryptographic commitment to the exact init code (audited
 *         creation bytecode + constructor args). The script asserts the realized address equals the
 *         locally-predicted address, which is the strongest form of bytecode verification: any byte
 *         drift in the compiled contract or the constructor arg would change the address.
 *
 *         This uses Foundry's default deterministic CREATE2 factory (0x4e59b448...), which is
 *         pre-deployed on virtually every chain, so no `--create2-deployer` flag is required.
 *
 * Usage:
 *     forge script script/DeployAvsOperatorManagerCreate2.s.sol \
 *         --rpc-url $RPC_URL --broadcast --verify
 *
 * Dry-run (predict address / verify an existing deployment without broadcasting):
 *     forge script script/DeployAvsOperatorManagerCreate2.s.sol --rpc-url $RPC_URL
 */
contract DeployAvsOperatorManagerCreate2 is Script {
    /// @notice Foundry's default deterministic CREATE2 factory (Arachnid's), the one `new ...{salt}`
    ///         routes through during broadcast. Pre-deployed on nearly every chain.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice Audited GitHub commit hash `c40319be0ede648041130376608b39fca11c6ecd` (20 bytes),
    ///         right-aligned in the 32-byte salt.
    bytes32 internal constant SALT = bytes32(bytes20(hex"c40319be0ede648041130376608b39fca11c6ecd"));

    function run() public {
        // RoleRegistry is an immutable constructor arg of the audited implementation.
        address roleRegistry = 0x62247D29B4B9BECf4BB73E0c722cf6445cfC7cE9;

        // Exact init code = audited creation bytecode ++ abi-encoded constructor args.
        bytes memory initCode = abi.encodePacked(
            type(AvsOperatorManager).creationCode,
            abi.encode(roleRegistry)
        );
        bytes32 initCodeHash = keccak256(initCode);

        // Deterministic address derived from (deployer, salt, init code hash).
        address predicted = vm.computeCreate2Address(SALT, initCodeHash, CREATE2_DEPLOYER);

        console2.log("CREATE2 deployer:  ", CREATE2_DEPLOYER);
        console2.log("RoleRegistry arg:  ", roleRegistry);
        console2.log("Salt (commit hash):");
        console2.logBytes32(SALT);
        console2.log("Init code hash:");
        console2.logBytes32(initCodeHash);
        console2.log("Predicted address: ", predicted);

        // Idempotent: if already deployed at the deterministic address, only verify.
        if (predicted.code.length > 0) {
            console2.log("Implementation already deployed; verifying bytecode...");
            _verify(predicted, initCodeHash, roleRegistry);
            console2.log("Bytecode verification succeeded (no broadcast).");
            return;
        }

        vm.startBroadcast();
        AvsOperatorManager manager = new AvsOperatorManager{salt: SALT}(roleRegistry);
        vm.stopBroadcast();

        address deployed = address(manager);
        console2.log("Deployed address:  ", deployed);

        // Realized address must equal the locally-computed CREATE2 address.
        require(deployed == predicted, "CREATE2 address mismatch: init code differs from audited bytecode");

        _verify(deployed, initCodeHash, roleRegistry);
        console2.log("Deployment + bytecode verification succeeded.");
    }

    /// @dev Bytecode / wiring verification of a deployed implementation.
    function _verify(address deployed, bytes32 initCodeHash, address roleRegistry) internal view {
        // 1. The address is a commitment to (salt, initCodeHash, deployer) — re-derive and compare.
        address recomputed = vm.computeCreate2Address(SALT, initCodeHash, CREATE2_DEPLOYER);
        require(deployed == recomputed, "address does not match audited init code hash");

        // 2. Runtime bytecode must actually be present.
        require(deployed.code.length > 0, "no runtime bytecode at deployed address");

        // 3. The immutable RoleRegistry must be wired to the expected address.
        require(
            address(AvsOperatorManager(deployed).roleRegistry()) == roleRegistry,
            "roleRegistry immutable mismatch"
        );
    }
}
