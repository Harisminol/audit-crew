# Audit Report — Vault / PriceOracle

**Date:** 2026-11-21  
**Scope:** `contracts/src/Vault.sol`, `contracts/src/PriceOracle.sol`  
**Methodology:** Static analysis (Scout) → Foundry PoC (Hunter) → Live-state verification (Verifier) → Report (Reporter).  
**Compiler:** solc 0.8.20  
**Findings:** 2 Critical, 0 High, 0 Medium, 0 Low  
**Total attacker profit demonstrated:** F-1: 10 ETH (from an 11 ETH vault); F-2: ~1 ETH per iteration (from a 10 ETH vault, repeatable to full drain). The two PoCs ran against separate vault deployments, so their profits are not summed.

---

## Findings

---

### F-1 — Reentrancy in `Vault.withdraw()` drains entire vault

| Field | Detail |
|---|---|
| **Severity** | Critical |
| **Class** | Reentrancy (same-function) |
| **Location** | `Vault.sol` lines 42–48 |
| **Invariant broken** | After `withdraw()` returns, `shares[caller]` must be 0 and the vault's ETH balance must have decreased by exactly `(s * p) / 1e18`. A caller must not redeem more ETH than their attributed share value. |

#### Attack walkthrough

1. Attacker deploys `AttackReentrancy`, a contract whose `receive()` calls `vault.withdraw()` again.
2. Attacker calls `vault.deposit{value: 1 ether}()` to acquire 1e18 shares — a normal user action requiring no privilege.
3. Attacker calls `attack()`, which calls `vault.withdraw()`.
4. `withdraw()` reads `shares[attacker] = 1e18`, computes `ethOut = 1 ETH`, and executes `msg.sender.call{value: 1 ether}("")` **before** clearing `shares[attacker]`.
5. Control enters `AttackReentrancy.receive()`. `shares[attacker]` is still 1e18, so `require(s > 0)` passes. `withdraw()` is called again.
6. This repeats until the vault's ETH balance falls to zero (10 re-entrant calls in the PoC run).
7. `shares[attacker]` is finally zeroed in the last stack frame. The vault is empty.

#### PoC

| Item | Detail |
|---|---|
| **File** | `contracts/test/PocC1Reentrancy.t.sol` |
| **Test** | `PocC1Reentrancy::test_reentrancyDrainsVault` |
| **Command** | `forge test --match-test test_reentrancyDrainsVault -vv` |

**Observed output:**

| Metric | Value |
|---|---|
| Vault ETH before attack | 10,000,000,000,000,000,000 wei (10 ETH) |
| Vault ETH after attack | 0 wei |
| Attacker ETH after attack | 11,000,000,000,000,000,000 wei (11 ETH) |
| Attacker profit | 10,000,000,000,000,000,000 wei (10 ETH) |
| Reentrancy depth | 10 |

**Verification:** VERIFIED — `forge test --match-contract VerifyPreconditions` 7/7 PASS. `withdraw()` has no access control beyond `require(s > 0, "no shares")`; vault held 10 ETH at verification time; victim shares were correctly recorded.

#### Impact

The vault is fully drained in a single transaction. Any depositor's funds are at risk. No privileged role, no special setup, no flash loan required — just one ETH deposit.

#### Fix

Apply checks-effects-interactions: zero `shares[msg.sender]` and decrement `totalShares` **before** transferring ETH.

```solidity
// Recommended order in withdraw()
shares[msg.sender] = 0;      // 1. effect
totalShares -= s;             // 2. effect
(bool ok, ) = msg.sender.call{value: ethOut}("");   // 3. interaction
require(ok, "ETH send failed");
```

Alternatively, add a `nonReentrant` modifier (OpenZeppelin `ReentrancyGuard`), but fixing the ordering is the simpler and gas-cheaper solution.

---

### F-2 — Unrestricted `PriceOracle.setPrice()` allows share-price desync and vault drain

| Field | Detail |
|---|---|
| **Severity** | Critical |
| **Class** | Oracle manipulation / share-price accounting desync |
| **Location** | `PriceOracle.sol` line 13 (`setPrice`); `Vault.sol` lines 32, 39, 44 (oracle reads in `deposit`/`withdraw`) |
| **Invariant broken** | The ETH redeemable by a share-holder must never exceed their pro-rata claim on the vault's ETH balance. |

#### Attack walkthrough

1. Victim deposits 10 ETH at `oracle.price() = 1e18`, receiving 10e18 shares. Vault holds 10 ETH.
2. Attacker (unprivileged EOA or contract) calls `oracle.setPrice(1)` — no access guard exists.
3. Attacker calls `vault.deposit{value: 1}()`. Share formula: `(1 * 1e18) / 1 = 1e18 shares` for 1 wei.
4. Attacker calls `oracle.setPrice(1e18)`, restoring the price.
5. Attacker calls `vault.withdraw()`. Payout formula: `(1e18 * 1e18) / 1e18 = 1 ETH`.
6. Attacker spent 1 wei, received 1 ETH — a profit of 999,999,999,999,999,999 wei per iteration. Repeating the sequence drains the vault completely.

#### PoC

| Item | Detail |
|---|---|
| **File** | `contracts/test/PocC2OracleManip.t.sol` |
| **Test** | `PocC2OracleManip::test_oracleManipDrainsVault` |
| **Command** | `forge test --match-test test_oracleManipDrainsVault -vv` |

**Observed output (single iteration):**

| Metric | Value |
|---|---|
| Vault ETH before attack | 10,000,000,000,000,000,000 wei (10 ETH) |
| Vault ETH after attack (1 iter.) | 9,000,000,000,000,000,001 wei (~9 ETH) |
| Attacker ETH after attack | 1,000,000,000,000,000,000 wei (1 ETH) |
| Attacker profit | 999,999,999,999,999,999 wei (≈ 1 ETH − 1 wei) |
| Attacker deposit cost | 1 wei |

**Verification:** VERIFIED — `oracle.setPrice(1)` accepted from address `0x9dF0…B4e` (unprivileged); 1-wei deposit at price=1 minted exactly 1,000,000,000,000,000,000 shares; restoring price to 1e18 yielded an `ethOut` of exactly 1,000,000,000,000,000,000 wei. All four precondition checks passed.

#### Impact

Any unprivileged address can extract victim ETH at a cost of 1 wei per 1 ETH stolen. The full vault balance is drainable by repeating the sequence (10 iterations for the 10 ETH vault in scope). No flash loan is needed; the attack is executable from an ordinary EOA.

#### Fix

Add access control to `PriceOracle.setPrice()` so only an authorized address (owner or keeper role) can update the price:

```solidity
// PriceOracle.sol
address public owner;
constructor() { owner = msg.sender; }

function setPrice(uint256 p) external {
    require(msg.sender == owner, "not owner");
    price = p;
}
```

Additionally, `Vault` should enforce a price sanity bound (e.g., reject prices outside a [min, max] band) and consider a TWAP or commit-reveal mechanism for production use, so a compromised oracle key cannot instantly corrupt share prices.

---

## Killed candidates

| ID | Candidate | Kill reason |
|----|-----------|-------------|
| K-1 | Rounding / precision loss in `deposit` / `withdraw` | Integer division truncates at most 1 wei per round-trip (`Vault.sol` lines 33, 43). No accumulation path an attacker can exploit; grief cost equals attacker loss. Not a finding. |
| K-2 | Unchecked low-level call in `withdraw` | `require(ok, "ETH send failed")` on line 45 checks the return value. Not unchecked (`Vault.sol` lines 44–45). |
| K-3 | Access control on `Vault` owner/admin paths | No owner or admin functions exist in `Vault`. Nothing to audit. |
| K-4 | Flash-loan price manipulation as a separate class | Oracle price is writable by any EOA without a flash loan; no flash-loan receiver or callback in scope. The attack in F-2 (C-2) needs no flash loan — same root cause, not a distinct finding. |

---

## Scope & method

**Contracts audited:**
- `contracts/src/Vault.sol`
- `contracts/src/PriceOracle.sol`

**What the crew ran:**
- Scout: full manual read of both contracts; candidate list with root-cause analysis.
- Hunter: Foundry PoCs (`PocC1Reentrancy.t.sol`, `PocC2OracleManip.t.sol`) executed against real contract code with no mocked vulnerable logic; both tests passed (`forge test`, exit 0).
- Verifier: `contracts/test/Verify.t.sol` (`VerifyPreconditions`) — 7/7 checks passed against deterministic Anvil deployment.

**What the crew did not check:**
- Any contract outside the two files listed above.
- Off-chain components (front-end, keeper bots, deployment scripts).
- Gas-griefing or DoS vectors beyond those surfaced during candidate triage.
- Formal verification or symbolic execution.
- Upgradeability, proxy patterns, or governance (none present in scope).
