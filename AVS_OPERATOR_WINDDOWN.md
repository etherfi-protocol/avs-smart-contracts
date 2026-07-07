# AVS Operator Wind-Down — Learnings & Runbook

Consolidated findings from investigating how to wind down the **ether.fi-9 (Nethermind)**
EigenLayer operator, after Nethermind wound down their own operator and asked ether.fi to do the
same. All data verified live on Ethereum mainnet. Companion to the fork simulation in
`test/DeregisterEtherFi9Sim.t.sol`.

---

## 1. Architecture

ether.fi's EigenLayer operators are **smart contracts** (`AvsOperator` beacon proxies), not EOAs,
all managed by one `AvsOperatorManager`. The `AvsOperator` contract *is* the registered EigenLayer
operator: restakers delegate to its address, and AVS registrations are made from it via forwarded
calls.

- **ether.fi owns the keys.** The `ecdsaSigner` (ERC-1271 signing) is ether.fi's; the operator
  contract is controlled through the manager. The node-runner company only runs the **off-chain
  duties** (AVS software, task signing, proof submission). This is why only ether.fi can
  deregister/undelegate — and why it can do so **without the company's cooperation**.
- `avsNodeRunner` = the staking company (Nethermind, DSRV, Pier Two, …) that can forward
  whitelisted calls.

## 2. Governance routing (THE critical finding — differs from a normal 3CP)

The **live** `AvsOperatorManager` is the **OLD** implementation, not this repo's RoleRegistry
branch:

| Thing | Value |
|---|---|
| Manager proxy | `0x2093Bbb221f1d8C7c932c32ee28Be6dEe4a37A6a` |
| Live impl | `0xdc9e0d46bd75aa2837b266715d870b497104fae7` (old: `admins` mapping + `owner`) |
| Admin gate | `admins[caller] || caller == owner()` — **`admins` mapping is EMPTY** (Operating Safe was revoked) |
| **Executor** | `owner()` = **EtherFiTimelock `0x9f26d4C958fD811A1F59B01B86Be7dFFc9d20761`** |
| Timelock delay | **10 days** (`getMinDelay` = 864000s) |
| Timelock proposer/executor | ether.fi core Safe `0xcdd57D11476c22d265722F68390b036f3DA48c21` (6-of-10) |

**Routing = Safe → `scheduleBatch` on the 10-day timelock → wait 10d → `executeBatch` →
`adminForwardCall`.** The Operating Admin Safe `0x2aCA…`, the 2-day operating timelock, and the
RoleRegistry `0x62247D…` have **zero authority** over this contract — using them reverts
`INCORRECT_CALLER`. Confirmed: `adminForwardCall(uint256,address,bytes4,bytes)` selector
`0x907382ac`.

## 3. What Nethermind actually did (their own operator `0x110af279…5945e`)

A clean, ordered **deregister-then-undelegate** wind-down (final wave 2026-07-01/02):
1. **Deregistered from every AVS** (EigenDA, Hyperlane, Vision, bolt, … — 21 AVSs over time).
2. **Force-undelegated only the leftover stakers.** Of 137 total undelegations over two years,
   **128 were stakers leaving voluntarily**; only **8 were operator-initiated force-undelegates**
   in one batch on 2026-07-02. No metadata change.

Takeaway: "undelegated the top restakers" was mostly two years of natural attrition + force-removing
the last 8 stragglers.

## 4. ether.fi-9 current state

- **Operator:** `0xD972a58B6A582954e578455E4752B12F2C8FcDBc` (manager id `9`)
- **nodeRunner:** `0x67f02DFd96B2f5a013928b2D744A9751e5323FA3` (Nethermind) · **ecdsaSigner:**
  `0xF2E184F97dE7E842df0B09460Fcc445c90F3915d` (shared ether.fi signer)
- **Registered with 8 AVSs** (see §5). Already off EigenDA + OpenOracle.
- **1,583 stakers still `delegatedTo` it:** ~1,393 internal EtherFiNode contracts + 165 external
  EOAs.
- **Residual shares still on the books:** ~282.22 beacon-ETH shares + 5.31 stETH shares.

### ⚠️ "Unrestaking" ≠ undelegated (a key EigenLayer distinction)

Exiting validators / queueing beacon withdrawals reduced the **native ETH** but did **NOT**:
- undelegate the EtherFiNodes (all sampled nodes still `delegatedTo(node) == operator`), nor
- zero the operator's DelegationManager **shares**.

Delegation link and delegated shares are **separate accounting** from the underlying ETH; they only
clear on explicit `undelegate` / completed EigenLayer-side withdrawal. So the operator is **not** in
a clean state despite the unrestaking.

## 5. Per-AVS deregistration plan (all 8 are legacy AVSDirectory M2 — zero AllocationManager operatorSets)

| # | AVS | AVS addr | Deregister target | Call (selector) | Args |
|---|---|---|---|---|---|
| A | Witness Chain | `0xD25c2c5802198CB8541987b73A8db4c9BCaE5cC7` | same | `deregisterOperatorFromAVS(address)` `0xa364f4da` | operator |
| B | eoracle | `0x23221c5bB90C7c57ecc1E75513e2E4257673F0ef` | RegistryCoordinator `0x757E6f572AfD8E111bD913d35314B5472C051cA8` | `deregisterOperator(bytes)` `0xca4f2d97` | quorum `0x00` |
| C | Hyperlane | `0xe8E59c6C8B56F2c178f63BCFC4ce5e5e2359c8fc` | ECDSAStakeRegistry `0x272CF0BB70D3B4f79414E0823B426d2EaFd48910` | `deregisterOperator()` `0x857dc190` | — |
| D | Lagrange State Committees | `0x35F4f28A8d3Ff20EEd10e087e8F96Ea2641E6AA2` | same | `unsubscribe(uint32)` `0x0512d04c` ×3 **then** `deregister()` `0xaff5edb1` | chains 10, 8453, 42161 |
| E | Lagrange ZK Prover | `0x22CAc0e6A1465F043428e8AeF737b3cb09D0eEDa` | ZKMRStakeRegistry `0x8dcdCc50Cc00Fe898b037bF61cCf3bf9ba46f15C` | `deregisterOperator()` `0x857dc190` | — |
| F | Cyber MACH / AltLayer | `0x1F2c296448f692af840843d993fFC0546619Dcdb` | RegistryCoordinator `0x118610D207A32f10F4f7C3a1FEFac5b3327c2bad` | `deregisterOperator(bytes)` `0xca4f2d97` | quorum `0x00` |
| G | Puffer / UniFi | `0x2d86E90ED40a034C753931eE31b1bD5E1970113d` | same | `startDeregisterOperator()` `0x389517e4` **then** `finishDeregisterOperator()` `0xe3672163` | — (delay 0s) |
| H | ethgas Vision | `0x6201bc0A699e3b10f324204e6F8EcdD0983De227` | registry `0xfF94c9859E4b15341c1BA3e80CF80044cA2C4e76` | `deregisterOperator()` `0x857dc190` | — |

**Preconditions:** D reverts `"operator is not able to deregister"` until it unsubscribes its 3
subscribed chains first; G is two-step (delay 0s → same batch is fine). All others are single calls.
Ordered 12-call list + full calldata payloads are captured in the simulation and the local (ignored)
`docs/etherfi-9-deregistration*` files.

## 6. Simulation (`test/DeregisterEtherFi9Sim.t.sol`)

`set -a; . ./.env; set +a; forge test --match-contract DeregisterEtherFi9Sim -vvv`

- `test_directOwnerSim` ✅ — impersonate `owner()`, forward all 12 calls → all 8 AVSs `1 → 0`.
- `test_fullGovernancePath` ✅ — core Safe → `scheduleBatch` → warp +10d → `executeBatch` → all 8
  `1 → 0`. Proves the real governance path incl. the delay, the Lagrange unsubscribe-first sequence,
  and the UniFi two-step.
- `test_postRunVerify` — skips until the real deregistration executes; then asserts all 8 read
  UNREGISTERED against latest mainnet.

## 7. Post-run verification ("did it do what was intended?")

1. **Authoritative:** `test_postRunVerify`, or per-AVS
   `cast call 0x2093Bbb…A6a "avsOperatorStatus(uint256,address)(uint8)" 9 <avs>` → expect `0`.
2. **Event reconciliation:** the execute tx emits exactly 12 `ForwardedOperatorCall(9,…)` + 8
   `OperatorAVSRegistrationStatusUpdated(operator, avs, 0)` — no extras.
3. **Timelock reconciliation:** `CallExecuted` set matches the hashed `CallScheduled`
   (same targets/payloads/salt) — nothing swapped between schedule and execute.
4. **Negative check:** `AllocationManager.getRegisteredSets(operator)` stays empty; no unexpected
   `undelegate` / share movement (this plan touches AVS registration only).

## 8. Should we undelegate the external EOA restakers? — Generally no

Once the AVSs are deregistered, external restakers earn **nothing** and bear **no** slashing risk
(a deregistered operator secures nothing), and they can `undelegate` themselves any time.
Force-undelegating 165 EOAs buys ~no protocol benefit, forces them into an involuntary 7-day escrow,
and is 165 extra calls. Recommendation: **leave them**; only force-undelegate to reach a hard-zero
terminal state (as Nethermind did with their last 8).

## 9. Batching across operators — one batch per operator

There are ~12 node-runner operators (ids 1–12: Pier Two, P2P, DSRV, Finoa, Cosmostation, A41,
Chainnodes, DSRV, **Nethermind=9**, Node.Monster, Validation Cloud, Allnodes; plus Oracle Committee
14/15/16 and ether.fi-17…20; id 13 uninitialized). **Only ether.fi-9 is being wound down** — the
others are actively run and earning.

If a broader wind-down is ever intended, `adminForwardCall` is per-`id`, so calls for different
operators *can* co-bundle and signing cost is per-batch (not per-call). But:
- **EIP-7825 16.77M gas cap** forces a split — ether.fi-9 alone is ~2M gas for 12 calls; all
  operators would blow past the cap.
- **`executeBatch` is atomic** — one reverting call (e.g. an unmapped Lagrange/UniFi precondition)
  rolls back the whole batch.
- **Verification blast radius** grows with batch size.

→ **One batch per operator** (or a few grouped, sized to ≤~14M gas). Never one mega-batch. The
10-day delay is paid once per batch in parallel, so it isn't reduced by bundling.

## 10. What happens if a company stops running the operator and we haven't deregistered?

State = **"registered but idle."** Nothing breaks instantly and **custody is never at risk**
(ether.fi retains full on-chain control via the owner timelock and the `ecdsaSigner`; stakers can
always self-withdraw after the 7-day escrow). But:

- **Slashing/ejection risk with no one minding it.** A registered-but-non-performing operator is
  what slashing/ejection target; a slash burns delegated shares — hitting both internal EtherFiNodes
  and external restakers.
  - **Current exposure is LOW** because all 8 registrations are legacy AVSDirectory (M2), where
    mainnet slashing was largely never wired. **But this is a moving target:** as AVSs migrate to
    the AllocationManager/operator-set slashing model, an unattended operator can be pulled into a
    **live slashable set nobody is running** — a benign idle registration silently becomes a real
    liability. That migration risk is the main reason to deregister promptly.
- **Rewards stop, risk stays** — zero AVS rewards accrue while stakers keep the downside (native
  ETH/Lido yield is unaffected).

**Best practice:** deregister promptly so the operator is out of every AVS **before** any of them
turns it into a live, slashable, unattended set — and **redelegate** the internal EtherFiNode stake
to an active operator rather than leaving it dangling.

---

### Key addresses (reference)

| Contract | Address |
|---|---|
| DelegationManager | `0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A` |
| AVSDirectory | `0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF` |
| AllocationManager | `0x948a420b8CC1d6BFd0B6087C2E7c344a2CD0bc39` |
| Beacon-chain ETH strategy | `0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0` |
| stETH strategy | `0x93c4b944D05dfe6df7645A86cd2206016c51564D` |
| Nethermind's own operator | `0x110af279aAFfB0d182697d7fC87653838AA5945e` |
