// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "./CryptoTestHelpers.t.sol";

interface ILido {
    function submit(address _referral) external payable returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IEtherFiRestaker {
    function depositIntoStrategy(address token, uint256 amount) external returns (uint256);
    function delegateTo(address operator, ISignatureUtils.SignatureWithExpiry memory sig, bytes32 salt) external;
    function isDelegated() external view returns (bool);
    function owner() external view returns (address);
    function pendingWithdrawalRoots() external view returns (bytes32[] memory);
    function completeQueuedWithdrawals(IDelegationManager.Withdrawal[] memory w, IERC20[][] memory t) external;
    function getRestakedAmount(address token) external view returns (uint256);
}

/// @title Exact mainnet replica: EtherFiRestaker -> EigenDA operator 17
/// @notice Two Gnosis Safes, both direct admins. No timelock. No contract upgrades.
/// @dev Run: forge test --match-contract EigenDAOperator17RegistrationTest -vvv
contract EigenDAOperator17RegistrationTest is Test, CryptoTestHelper {

    // ── Mainnet contracts ──────────────────────────────────────────────
    IRegistryCoordinator constant EIGENDA_REGISTRY = IRegistryCoordinator(0x0BAAc79acD45A023E19345c352d8a7a83C4e5656);
    address constant EIGENDA_SERVICE_MANAGER = 0x870679E138bCdf293b7Ff14dD44b70FC97e12fc0;
    address constant AVS_DIRECTORY = 0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF;
    IDelegationManager constant DELEGATION_MANAGER = IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
    ILido constant STETH = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IStrategy constant STETH_STRATEGY = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
    IEtherFiRestaker constant RESTAKER = IEtherFiRestaker(0x1B7a4C3797236A1C37f8741c0Be35c2c72736fFf);
    AvsOperatorManager constant AVS_MGR = AvsOperatorManager(0x2093Bbb221f1d8C7c932c32ee28Be6dEe4a37A6a);

    // ── Mainnet Gnosis Safes ───────────────────────────────────────────
    // Restaker Safe: direct admin on EtherFiRestaker
    address constant RESTAKER_SAFE = 0x2aCA71020De61bb532008049e1Bd41E451aE8AdC;
    // AVS Admin Safe: direct admin on AvsOperatorManager
    address constant AVS_ADMIN_SAFE = 0x9c729226e993211a816FfA79fD4F3bB40d157F29;

    string constant REGISTRATION_JSON = "test/fixtures/eigenda-prepare-registration-17.json";

    // Test-only: vm.store overwrites ecdsaSigner slot so we can sign in the test.
    // In production the real ecdsaSigner 0xF2E184... is unchanged, CLI signs off-chain.
    uint256 constant TEST_SIGNER_KEY = 0x1234abcd5678ef;

    // ── JSON parsing ───────────────────────────────────────────────────

    function _loadRegistrationInput() internal view returns (
        uint256 operatorId,
        string memory socket,
        bytes memory quorums,
        IBLSApkRegistry.PubkeyRegistrationParams memory blsParams
    ) {
        string memory json = vm.readFile(REGISTRATION_JSON);
        operatorId = vm.parseJsonUint(json, ".OperatorID");
        socket = vm.parseJsonString(json, ".Socket");

        uint256[] memory qa = vm.parseJsonUintArray(json, ".Quorums");
        quorums = new bytes(qa.length);
        for (uint256 i = 0; i < qa.length; i++) quorums[i] = bytes1(uint8(qa[i]));

        blsParams = IBLSApkRegistry.PubkeyRegistrationParams({
            pubkeyRegistrationSignature: BN254.G1Point({
                X: vm.parseJsonUint(json, ".BLSPubkeyRegistrationParams.signature.x"),
                Y: vm.parseJsonUint(json, ".BLSPubkeyRegistrationParams.signature.y")
            }),
            pubkeyG1: BN254.G1Point({
                X: vm.parseJsonUint(json, ".BLSPubkeyRegistrationParams.g1.x"),
                Y: vm.parseJsonUint(json, ".BLSPubkeyRegistrationParams.g1.y")
            }),
            pubkeyG2: BN254.G2Point({
                X: [
                    vm.parseJsonUintArray(json, ".BLSPubkeyRegistrationParams.g2.x")[0],
                    vm.parseJsonUintArray(json, ".BLSPubkeyRegistrationParams.g2.x")[1]
                ],
                Y: [
                    vm.parseJsonUintArray(json, ".BLSPubkeyRegistrationParams.g2.y")[0],
                    vm.parseJsonUintArray(json, ".BLSPubkeyRegistrationParams.g2.y")[1]
                ]
            })
        });
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    function _setupFork() internal {
        vm.selectFork(vm.createFork(vm.envString("MAINNET_RPC_URL")));
    }

    function _operatorAddr(uint256 id) internal view returns (address) {
        return address(AVS_MGR.avsOperators(id));
    }

    function _operatorShares(address op) internal view returns (uint256) {
        IStrategy[] memory s = new IStrategy[](1);
        s[0] = STETH_STRATEGY;
        return DELEGATION_MANAGER.getOperatorShares(op, s)[0];
    }

    function _setTestSigner(address operatorAddr) internal {
        // AvsOperator slot 1 = ecdsaSigner
        vm.store(operatorAddr, bytes32(uint256(1)), bytes32(uint256(uint160(vm.addr(TEST_SIGNER_KEY)))));
    }

    function _generateRegSig(address operatorAddr) internal view returns (ISignatureUtils.SignatureWithSaltAndExpiry memory) {
        uint256 expiry = block.timestamp + 7 days;
        bytes32 salt = keccak256("eigenda-registration-salt");
        bytes32 digest = IAVSDirectory(AVS_DIRECTORY).calculateOperatorAVSRegistrationDigestHash(
            operatorAddr, EIGENDA_SERVICE_MANAGER, salt, expiry
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_SIGNER_KEY, digest);
        return ISignatureUtils.SignatureWithSaltAndExpiry({
            signature: abi.encodePacked(r, s, v),
            salt: salt,
            expiry: expiry
        });
    }

    // ── Tests ───────────────────────────────────────────────────────────

    /// @notice Read-only diagnostic
    function test_diagnoseCurrentState() public {
        _setupFork();

        (uint256 operatorId,,,) = _loadRegistrationInput();
        address operatorAddr = _operatorAddr(operatorId);

        emit log("=== Gnosis Safes ===");
        emit log_named_address("Restaker Safe (admin on EtherFiRestaker)", RESTAKER_SAFE);
        emit log_named_address("AVS Admin Safe (admin on AvsOperatorManager)", AVS_ADMIN_SAFE);

        emit log("=== Operator ===");
        emit log_named_uint("Operator ID", operatorId);
        emit log_named_address("Operator contract", operatorAddr);
        emit log_named_uint("EL operator", DELEGATION_MANAGER.isOperator(operatorAddr) ? 1 : 0);
        emit log_named_address("ecdsaSigner", AVS_MGR.ecdsaSigner(operatorId));
        emit log_named_address("avsNodeRunner", AVS_MGR.avsNodeRunner(operatorId));
        emit log_named_uint("stETH shares", _operatorShares(operatorAddr));
        emit log_named_uint("EigenDA status (0=NEVER,1=REG,2=DEREG)", uint256(EIGENDA_REGISTRY.getOperatorStatus(operatorAddr)));

        emit log("=== EtherFiRestaker ===");
        emit log_named_uint("stETH balance (ETH)", STETH.balanceOf(address(RESTAKER)) / 1e18);
        emit log_named_uint("stETH restaked (ETH)", RESTAKER.getRestakedAmount(address(STETH)) / 1e18);
        emit log_named_uint("Delegated", RESTAKER.isDelegated() ? 1 : 0);
        emit log_named_uint("Pending withdrawals", RESTAKER.pendingWithdrawalRoots().length);
        emit log_named_uint("EigenDA q0 min (ETH)", uint256(EIGENDA_REGISTRY.stakeRegistry().minimumStakeForQuorum(0)) / 1e18);
    }

    /// @notice EXACT PRODUCTION FLOW -- all direct calls, no timelock
    ///
    /// All steps happen on Day 0 (no waiting):
    ///
    ///   Restaker Safe (0x2aCA71):
    ///     TX 1: EtherFiRestaker.depositIntoStrategy(stETH, 100 ETH)
    ///     TX 2: EtherFiRestaker.delegateTo(operator17)
    ///
    ///   Off-chain:
    ///     CLI: ./avs-cli eigenda register --registration-input <json>
    ///     -> signs with ADMIN_1271_SIGNING_KEY, outputs Gnosis batch JSON
    ///
    ///   AVS Admin Safe (0x9c7292):
    ///     TX 3: AvsOperatorManager.adminForwardCall(17, registerOperator, ...)
    ///
    ///   Notify operator -> starts EigenDA node
    ///
    ///   Day 10+ (Restaker Safe):
    ///     TX 4: EtherFiRestaker.completeQueuedWithdrawals(...)
    ///     TX 5: EtherFiRestaker.depositIntoStrategy(stETH, returned)
    ///
    function test_productionFlow() public {
        _setupFork();

        (uint256 operatorId, string memory socket, bytes memory quorums, IBLSApkRegistry.PubkeyRegistrationParams memory blsParams) = _loadRegistrationInput();
        address operatorAddr = _operatorAddr(operatorId);

        // Pre-flight
        assertTrue(DELEGATION_MANAGER.isOperator(operatorAddr), "Must be EL operator");
        assertFalse(RESTAKER.isDelegated(), "Restaker not yet delegated");
        assertEq(uint256(EIGENDA_REGISTRY.getOperatorStatus(operatorAddr)), 0, "Not yet registered");

        // ════════════════════════════════════════════════════════════════
        //  TX 1: Deposit stETH (Restaker Safe -- direct)
        // ════════════════════════════════════════════════════════════════
        emit log("--- TX 1: EtherFiRestaker.depositIntoStrategy(stETH, 100 ETH) ---");
        emit log_named_address("Called by: Restaker Safe", RESTAKER_SAFE);

        vm.prank(RESTAKER_SAFE);
        uint256 shares = RESTAKER.depositIntoStrategy(address(STETH), 100 ether);
        emit log_named_uint("Strategy shares received", shares);

        // ════════════════════════════════════════════════════════════════
        //  TX 2: Delegate to operator 17 (Restaker Safe -- direct)
        // ════════════════════════════════════════════════════════════════
        emit log("--- TX 2: EtherFiRestaker.delegateTo(operator17) ---");
        emit log_named_address("Called by: Restaker Safe", RESTAKER_SAFE);

        ISignatureUtils.SignatureWithExpiry memory emptySig;
        emptySig.expiry = type(uint256).max;
        vm.prank(RESTAKER_SAFE);
        RESTAKER.delegateTo(operatorAddr, emptySig, bytes32(0));

        assertTrue(RESTAKER.isDelegated(), "Delegated");
        assertEq(DELEGATION_MANAGER.delegatedTo(address(RESTAKER)), operatorAddr, "To operator 17");
        emit log_named_uint("Operator 17 stETH shares", _operatorShares(operatorAddr));

        // ════════════════════════════════════════════════════════════════
        //  CLI signs registration digest (off-chain)
        // ════════════════════════════════════════════════════════════════
        emit log("--- CLI: ./avs-cli eigenda register --registration-input <json> ---");

        _setTestSigner(operatorAddr);
        ISignatureUtils.SignatureWithSaltAndExpiry memory regSig = _generateRegSig(operatorAddr);

        // ════════════════════════════════════════════════════════════════
        //  TX 3: Register with EigenDA (AVS Admin Safe -- direct)
        // ════════════════════════════════════════════════════════════════
        emit log("--- TX 3: AvsOperatorManager.adminForwardCall(registerOperator) ---");
        emit log_named_address("Called by: AVS Admin Safe", AVS_ADMIN_SAFE);

        bytes memory registerArgs = abi.encode(quorums, socket, blsParams, regSig);
        vm.prank(AVS_ADMIN_SAFE);
        AVS_MGR.adminForwardCall(
            operatorId, address(EIGENDA_REGISTRY),
            IRegistryCoordinator.registerOperator.selector, registerArgs
        );

        // Verify registration
        assertEq(uint256(EIGENDA_REGISTRY.getOperatorStatus(operatorAddr)), 1, "REGISTERED");
        bytes32 eigenId = EIGENDA_REGISTRY.getOperatorId(operatorAddr);
        assertTrue(eigenId != bytes32(0), "Has EigenDA ID");
        uint192 bitmap = EIGENDA_REGISTRY.getCurrentQuorumBitmap(eigenId);
        emit log_named_uint("Quorum bitmap", uint256(bitmap));
        assertTrue(bitmap & 1 != 0, "Quorum 0");

        emit log("=== REGISTERED. Notify operator -> start EigenDA node ===");

        // ════════════════════════════════════════════════════════════════
        //  Day 10+: Complete pending withdrawals (Restaker Safe -- direct)
        // ════════════════════════════════════════════════════════════════
        bytes32[] memory pendingRoots = RESTAKER.pendingWithdrawalRoots();
        emit log_named_uint("Pending withdrawal roots", pendingRoots.length);

        if (pendingRoots.length > 0) {
            emit log("--- Day 10+: Complete withdrawals + re-deposit ---");
            _completePendingWithdrawals(operatorAddr);
        }

        emit log_named_uint("Final operator shares", _operatorShares(operatorAddr));
        emit log("=== FULL FLOW COMPLETE ===");
    }

    function _completePendingWithdrawals(address operatorAddr) internal {
        // Warp past EigenLayer withdrawal delay
        uint256 elDelay;
        (bool ok, bytes memory d) = address(DELEGATION_MANAGER).staticcall(
            abi.encodeWithSignature("minWithdrawalDelayBlocks()")
        );
        elDelay = (ok && d.length >= 32) ? abi.decode(d, (uint256)) : 50400;
        vm.roll(block.number + elDelay + 1);

        (bool qOk, bytes memory qData) = address(DELEGATION_MANAGER).staticcall(
            abi.encodeWithSignature("getQueuedWithdrawals(address)", address(RESTAKER))
        );
        if (!qOk) {
            emit log("getQueuedWithdrawals unavailable -- complete manually");
            return;
        }

        (IDelegationManager.Withdrawal[] memory withdrawals,) = abi.decode(qData, (IDelegationManager.Withdrawal[], uint256[][]));
        if (withdrawals.length == 0) return;

        IERC20[][] memory tokens = new IERC20[][](withdrawals.length);
        for (uint256 i = 0; i < withdrawals.length; i++) {
            tokens[i] = new IERC20[](withdrawals[i].strategies.length);
            for (uint256 j = 0; j < withdrawals[i].strategies.length; j++) {
                tokens[i][j] = withdrawals[i].strategies[j].underlyingToken();
            }
        }

        // TX 4: Complete withdrawals
        emit log_named_address("Called by: Restaker Safe", RESTAKER_SAFE);
        uint256 balBefore = STETH.balanceOf(address(RESTAKER));
        vm.prank(RESTAKER_SAFE);
        RESTAKER.completeQueuedWithdrawals(withdrawals, tokens);
        uint256 returned = STETH.balanceOf(address(RESTAKER)) - balBefore;
        emit log_named_uint("stETH returned (ETH)", returned / 1e18);

        // TX 5: Re-deposit
        if (returned > 0) {
            emit log_named_address("Called by: Restaker Safe", RESTAKER_SAFE);
            vm.prank(RESTAKER_SAFE);
            RESTAKER.depositIntoStrategy(address(STETH), returned);
            emit log_named_uint("Operator shares after re-deposit", _operatorShares(operatorAddr));
        }
    }

    /// @notice Generate Gnosis Safe batch JSON + log calldata for TX 1 + TX 2
    ///         Import the output file into Restaker Safe (0x2aCA71) Transaction Builder
    function test_generateRestakerSafeBatch() public {
        _setupFork();

        (uint256 operatorId,,,) = _loadRegistrationInput();
        address operatorAddr = _operatorAddr(operatorId);

        // TX 1 calldata: depositIntoStrategy(stETH, 100 ETH)
        bytes memory tx1Data = abi.encodeWithSignature(
            "depositIntoStrategy(address,uint256)",
            address(STETH),
            150000 ether
        );

        // TX 2 calldata: delegateTo(operator17, emptySig, 0x0)
        ISignatureUtils.SignatureWithExpiry memory emptySig;
        emptySig.expiry = type(uint256).max;
        bytes memory tx2Data = abi.encodeWithSignature(
            "delegateTo(address,(bytes,uint256),bytes32)",
            operatorAddr,
            emptySig,
            bytes32(0)
        );

        // Log calldata for manual verification
        emit log("=== TX 1: depositIntoStrategy ===");
        emit log_named_address("Target", address(RESTAKER));
        emit log_named_bytes("Calldata", tx1Data);
        emit log("");

        emit log("=== TX 2: delegateTo ===");
        emit log_named_address("Target", address(RESTAKER));
        emit log_named_bytes("Calldata", tx2Data);
        emit log("");

        // Build Gnosis Safe batch JSON
        string memory json = string.concat(
            '{\n',
            '  "version": "1.0",\n',
            '  "chainId": "1",\n',
            '  "createdAt": ', vm.toString(block.timestamp), ',\n',
            '  "meta": {\n',
            '    "name": "eigenda-operator-17-deposit-delegate",\n',
            '    "description": "Deposit 100 stETH into EL strategy and delegate to operator 17"\n',
            '  },\n',
            '  "transactions": [\n',
            '    {\n',
            '      "to": "', vm.toString(address(RESTAKER)), '",\n',
            '      "value": "0",\n',
            '      "data": "', vm.toString(tx1Data), '",\n',
            '      "contractMethod": null,\n',
            '      "contractInputsValues": null\n',
            '    },\n',
            '    {\n',
            '      "to": "', vm.toString(address(RESTAKER)), '",\n',
            '      "value": "0",\n',
            '      "data": "', vm.toString(tx2Data), '",\n',
            '      "contractMethod": null,\n',
            '      "contractInputsValues": null\n',
            '    }\n',
            '  ]\n',
            '}'
        );

        // Write to file
        vm.writeFile("test/fixtures/restaker-safe-batch-operator-17.json", json);

        emit log("=== Gnosis Safe batch JSON written to: ===");
        emit log("test/fixtures/restaker-safe-batch-operator-17.json");
        emit log("");
        emit log_named_address("Import into Restaker Safe", RESTAKER_SAFE);
        emit log_named_address("Operator 17 contract", operatorAddr);
        emit log_named_uint("Deposit amount (ETH)", 100);

        // Verify the batch works by executing it
        vm.prank(RESTAKER_SAFE);
        (bool s1,) = address(RESTAKER).call(tx1Data);
        assertTrue(s1, "TX 1 should succeed");

        vm.prank(RESTAKER_SAFE);
        (bool s2,) = address(RESTAKER).call(tx2Data);
        assertTrue(s2, "TX 2 should succeed");

        assertTrue(RESTAKER.isDelegated(), "Should be delegated after batch");
        assertEq(DELEGATION_MANAGER.delegatedTo(address(RESTAKER)), operatorAddr, "Delegated to operator 17");
        emit log_named_uint("Operator 17 shares after batch", _operatorShares(operatorAddr));
    }

    /// @notice Prove registration reverts without stake
    function test_revertsWithoutStake() public {
        _setupFork();

        (uint256 operatorId, string memory socket, bytes memory quorums, IBLSApkRegistry.PubkeyRegistrationParams memory blsParams) = _loadRegistrationInput();
        address operatorAddr = _operatorAddr(operatorId);

        emit log_named_uint("Current stETH shares", _operatorShares(operatorAddr));

        _setTestSigner(operatorAddr);
        ISignatureUtils.SignatureWithSaltAndExpiry memory regSig = _generateRegSig(operatorAddr);

        bytes memory registerArgs = abi.encode(quorums, socket, blsParams, regSig);

        vm.expectRevert();
        vm.prank(AVS_ADMIN_SAFE);
        AVS_MGR.adminForwardCall(
            operatorId, address(EIGENDA_REGISTRY),
            IRegistryCoordinator.registerOperator.selector, registerArgs
        );
    }
}
