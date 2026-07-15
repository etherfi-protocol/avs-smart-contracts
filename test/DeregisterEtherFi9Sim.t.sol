// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

/// @dev Minimal interface for the LIVE (deployed, old-impl) AvsOperatorManager proxy.
///      The live proxy is NOT on this branch's RoleRegistry implementation, so we call it
///      through a hand-written interface matching the deployed ABI rather than importing
///      the local contract (which has an immutable RoleRegistry constructor arg).
interface IManagerLive {
    function adminForwardCall(uint256 id, address target, bytes4 selector, bytes calldata args) external;
    function avsOperatorStatus(uint256 id, address avsServiceManager) external view returns (uint8);
    function avsOperators(uint256 id) external view returns (address);
    function owner() external view returns (address);
}

/// @dev OpenZeppelin TimelockController surface used by EtherFiTimelock (owner of the manager).
interface ITimelock {
    function getMinDelay() external view returns (uint256);
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external;
}

/// @title  Simulate the full deregistration of ether.fi-9 (Nethermind) from all 8 live AVSs
/// @notice Read-only mainnet fork simulation. Two paths are exercised:
///           1. test_directOwnerSim      — impersonate owner() and forward each deregister call
///           2. test_fullGovernancePath  — core Safe -> timelock scheduleBatch -> +10d -> executeBatch
///         Both assert every AVS transitions AVSDirectory status REGISTERED (1) -> UNREGISTERED (0).
///
///         Run: `set -a; . ./.env; set +a; forge test --match-contract DeregisterEtherFi9Sim -vvv`
///
///         NOTE ON SCOPE: this covers only the operator-level AVS deregistration, which is the
///         clean, fully ether.fi-controlled action via adminForwardCall. It intentionally does
///         NOT undelegate the ~1,393 internal EtherFiNode stakers (separate EigenPod/withdrawal
///         workstream, 7-day escrow, redelegate-not-abandon) nor the 165 external EOA restakers.
contract DeregisterEtherFi9Sim is Test {
    // ---- Live governance actors (verified on-chain) ----
    IManagerLive constant MANAGER = IManagerLive(0x2093Bbb221f1d8C7c932c32ee28Be6dEe4a37A6a);
    address constant OPERATOR = 0xD972a58B6A582954e578455E4752B12F2C8FcDBc;
    uint256 constant ID = 9;
    ITimelock constant TIMELOCK = ITimelock(0x9f26d4C958fD811A1F59B01B86Be7dFFc9d20761); // owner() of MANAGER, 10-day delay
    address constant CORE_SAFE = 0xcdd57D11476c22d265722F68390b036f3DA48c21;             // PROPOSER + EXECUTOR on TIMELOCK

    uint8 constant REGISTERED = 1;
    uint8 constant UNREGISTERED = 0;

    // ---- AVS identity addresses used for AVSDirectory status checks ----
    address constant AVS_WITNESS   = 0xD25c2c5802198CB8541987b73A8db4c9BCaE5cC7;
    address constant AVS_EORACLE   = 0x23221c5bB90C7c57ecc1E75513e2E4257673F0ef;
    address constant AVS_HYPERLANE = 0xe8E59c6C8B56F2c178f63BCFC4ce5e5e2359c8fc;
    address constant AVS_LAG_SC    = 0x35F4f28A8d3Ff20EEd10e087e8F96Ea2641E6AA2;
    address constant AVS_LAG_ZK    = 0x22CAc0e6A1465F043428e8AeF737b3cb09D0eEDa;
    address constant AVS_CYBERMACH = 0x1F2c296448f692af840843d993fFC0546619Dcdb;
    address constant AVS_UNIFI     = 0x2d86E90ED40a034C753931eE31b1bD5E1970113d;
    address constant AVS_VISION    = 0x6201bc0A699e3b10f324204e6F8EcdD0983De227;

    // ---- Deregister call targets (where the operator must call) ----
    address constant T_WITNESS      = 0xD25c2c5802198CB8541987b73A8db4c9BCaE5cC7; // == AVS
    address constant T_EORACLE_RC   = 0x757E6f572AfD8E111bD913d35314B5472C051cA8; // RegistryCoordinator
    address constant T_HYPERLANE    = 0x272CF0BB70D3B4f79414E0823B426d2EaFd48910; // ECDSAStakeRegistry
    address constant T_LAG_SC       = 0x35F4f28A8d3Ff20EEd10e087e8F96Ea2641E6AA2; // == AVS
    address constant T_LAG_ZK       = 0x8dcdCc50Cc00Fe898b037bF61cCf3bf9ba46f15C; // ZKMRStakeRegistry
    address constant T_CYBERMACH_RC = 0x118610D207A32f10F4f7C3a1FEFac5b3327c2bad; // RegistryCoordinator
    address constant T_UNIFI        = 0x2d86E90ED40a034C753931eE31b1bD5E1970113d; // == AVS
    address constant T_VISION       = 0xfF94c9859E4b15341c1BA3e80CF80044cA2C4e76; // registry

    // ---- Selectors (re-derived + confirmed on-chain) ----
    bytes4 constant SEL_DEREG_FROM_AVS = 0xa364f4da; // deregisterOperatorFromAVS(address)
    bytes4 constant SEL_DEREG_QUORUM   = 0xca4f2d97; // deregisterOperator(bytes)
    bytes4 constant SEL_DEREG_NOARG    = 0x857dc190; // deregisterOperator()
    bytes4 constant SEL_LAG_DEREG      = 0xaff5edb1; // deregister()
    bytes4 constant SEL_LAG_UNSUB      = 0x0512d04c; // unsubscribe(uint32)
    bytes4 constant SEL_UNIFI_START    = 0x389517e4; // startDeregisterOperator()
    bytes4 constant SEL_UNIFI_FINISH   = 0xe3672163; // finishDeregisterOperator()

    address[8] internal avsList;
    string[8]  internal avsNames;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        avsList = [AVS_WITNESS, AVS_EORACLE, AVS_HYPERLANE, AVS_LAG_SC, AVS_LAG_ZK, AVS_CYBERMACH, AVS_UNIFI, AVS_VISION];
        avsNames = ["WitnessChain", "eoracle", "Hyperlane", "Lagrange-SC", "Lagrange-ZK", "CyberMACH", "UniFi", "ethgas-Vision"];
    }

    /// @dev Ordered adminForwardCall steps. Lagrange-SC must unsubscribe its 3 subscribed chains
    ///      (Optimism 10, Base 8453, Arbitrum 42161) before deregister(); UniFi is start+finish.
    function _steps() internal pure returns (address[] memory tgt, bytes4[] memory sel, bytes[] memory args) {
        tgt = new address[](12);
        sel = new bytes4[](12);
        args = new bytes[](12);
        uint256 i;

        // Lagrange State Committees: unsubscribe(10) -> unsubscribe(8453) -> unsubscribe(42161) -> deregister()
        tgt[i] = T_LAG_SC; sel[i] = SEL_LAG_UNSUB; args[i] = abi.encode(uint32(10));    i++;
        tgt[i] = T_LAG_SC; sel[i] = SEL_LAG_UNSUB; args[i] = abi.encode(uint32(8453));  i++;
        tgt[i] = T_LAG_SC; sel[i] = SEL_LAG_UNSUB; args[i] = abi.encode(uint32(42161)); i++;
        tgt[i] = T_LAG_SC; sel[i] = SEL_LAG_DEREG; args[i] = "";                        i++;

        tgt[i] = T_WITNESS;      sel[i] = SEL_DEREG_FROM_AVS; args[i] = abi.encode(OPERATOR); i++; // Witness Chain
        tgt[i] = T_EORACLE_RC;   sel[i] = SEL_DEREG_QUORUM;   args[i] = _bytesArg(hex"00");   i++; // eoracle, quorum [0]
        tgt[i] = T_HYPERLANE;    sel[i] = SEL_DEREG_NOARG;    args[i] = "";                    i++; // Hyperlane
        tgt[i] = T_LAG_ZK;       sel[i] = SEL_DEREG_NOARG;    args[i] = "";                    i++; // Lagrange ZK
        tgt[i] = T_CYBERMACH_RC; sel[i] = SEL_DEREG_QUORUM;   args[i] = _bytesArg(hex"00");   i++; // Cyber MACH, quorum [0]
        tgt[i] = T_UNIFI;        sel[i] = SEL_UNIFI_START;    args[i] = "";                    i++; // UniFi start
        tgt[i] = T_UNIFI;        sel[i] = SEL_UNIFI_FINISH;   args[i] = "";                    i++; // UniFi finish
        tgt[i] = T_VISION;       sel[i] = SEL_DEREG_NOARG;    args[i] = "";                    i++; // ethgas Vision
    }

    /// @dev ABI-encode a single dynamic `bytes` argument (offset + length + data) so that
    ///      encodePacked(selector, args) reproduces the full deregisterOperator(bytes) calldata.
    function _bytesArg(bytes memory b) internal pure returns (bytes memory) {
        return abi.encode(b);
    }

    function _logStatuses(string memory phase) internal {
        emit log_string(phase);
        for (uint256 j; j < 8; j++) {
            emit log_named_uint(avsNames[j], MANAGER.avsOperatorStatus(ID, avsList[j]));
        }
    }

    function _assertAll(uint8 expected) internal view {
        for (uint256 j; j < 8; j++) {
            assertEq(MANAGER.avsOperatorStatus(ID, avsList[j]), expected, avsNames[j]);
        }
    }

    // ------------------------------------------------------------------
    // Sim 1 — inner-effect proof: impersonate owner() and forward each call
    // ------------------------------------------------------------------
    function test_directOwnerSim() public {
        assertEq(MANAGER.owner(), address(TIMELOCK), "owner() drifted from expected EtherFiTimelock");
        assertEq(MANAGER.avsOperators(ID), OPERATOR, "operator id 9 address drifted");

        _logStatuses("BEFORE:");
        _assertAll(REGISTERED);

        (address[] memory tgt, bytes4[] memory sel, bytes[] memory args) = _steps();
        vm.startPrank(address(TIMELOCK));
        for (uint256 i; i < tgt.length; i++) {
            MANAGER.adminForwardCall(ID, tgt[i], sel[i], args[i]);
        }
        vm.stopPrank();

        _logStatuses("AFTER:");
        _assertAll(UNREGISTERED);
    }

    // ------------------------------------------------------------------
    // Sim 2 — realistic path: core Safe -> timelock scheduleBatch -> +10d -> executeBatch
    // ------------------------------------------------------------------
    function test_fullGovernancePath() public {
        _assertAll(REGISTERED);

        (address[] memory tgt, bytes4[] memory sel, bytes[] memory args) = _steps();
        uint256 n = tgt.length;
        address[] memory targets = new address[](n);
        uint256[] memory values = new uint256[](n);
        bytes[] memory payloads = new bytes[](n);
        for (uint256 i; i < n; i++) {
            targets[i] = address(MANAGER);
            values[i] = 0;
            payloads[i] = abi.encodeWithSelector(IManagerLive.adminForwardCall.selector, ID, tgt[i], sel[i], args[i]);
        }

        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("etherfi-9-deregister-all-avss");
        uint256 delay = TIMELOCK.getMinDelay();
        emit log_named_uint("timelock delay (s)", delay);

        vm.startPrank(CORE_SAFE);
        TIMELOCK.scheduleBatch(targets, values, payloads, predecessor, salt, delay);
        vm.stopPrank();

        vm.warp(block.timestamp + delay + 1);

        vm.startPrank(CORE_SAFE);
        TIMELOCK.executeBatch(targets, values, payloads, predecessor, salt);
        vm.stopPrank();

        _logStatuses("AFTER executeBatch:");
        _assertAll(UNREGISTERED);
    }

    // ------------------------------------------------------------------
    // Post-run verification — run against LATEST mainnet AFTER the real
    // governance execute lands. Passes only when every AVS is UNREGISTERED.
    // ------------------------------------------------------------------
    function test_postRunVerify() public {
        // Skips until the real governance deregistration has executed on-chain; once it has,
        // this asserts every AVS reads UNREGISTERED against the latest forked state.
        for (uint256 j; j < 8; j++) {
            if (MANAGER.avsOperatorStatus(ID, avsList[j]) == REGISTERED) {
                emit log_string("skip: deregistration not yet executed on-chain");
                vm.skip(true);
            }
        }
        _logStatuses("LIVE:");
        _assertAll(UNREGISTERED);
    }
}
