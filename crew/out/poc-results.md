# PoC Results

All tests run from `contracts/` with `forge test`.
Forge version: see `foundry.toml` (solc 0.8.20).

---

## C-1 — Reentrancy in `Vault.withdraw()`

| Field | Detail |
|---|---|
| **Status** | ✅ PASS |
| **Test file** | `contracts/test/PocC1Reentrancy.t.sol` |
| **Test name** | `PocC1Reentrancy::test_reentrancyDrainsVault` |
| **Command** | `forge test --match-test test_reentrancyDrainsVault -vv` |

**Observed numbers (from test output):**

| Metric | Value |
|---|---|
| Vault ETH before attack | 10,000,000,000,000,000,000 wei (10 ETH) |
| Vault ETH after attack | 0 wei |
| Attacker contract ETH after attack | 11,000,000,000,000,000,000 wei (11 ETH) |
| Attacker profit | 10,000,000,000,000,000,000 wei (10 ETH) |
| Reentrancy depth | 10 |

**Mechanics confirmed.**
`AttackReentrancy` deposited 1 ETH (normal user action, no privilege).
Its `receive()` re-entered `vault.withdraw()` ten times before the vault
balance fell to zero. The attacker recovered all 10 ETH of victim funds
plus their own 1 ETH deposit — a total of 11 ETH — from a 1 ETH starting
capital. The vault is fully drained.

---

## C-2 — Unrestricted oracle price manipulation → share-price desync

| Field | Detail |
|---|---|
| **Status** | ✅ PASS |
| **Test file** | `contracts/test/PocC2OracleManip.t.sol` |
| **Test name** | `PocC2OracleManip::test_oracleManipDrainsVault` |
| **Command** | `forge test --match-test test_oracleManipDrainsVault -vv` |

**Observed numbers (from test output):**

| Metric | Value |
|---|---|
| Vault ETH before attack | 10,000,000,000,000,000,000 wei (10 ETH) |
| Vault ETH after attack | 9,000,000,000,000,000,001 wei (~9 ETH) |
| Attacker contract ETH after attack | 1,000,000,000,000,000,000 wei (1 ETH) |
| Attacker profit | 999,999,999,999,999,999 wei (~1 ETH − 1 wei) |
| Attacker deposit cost | 1 wei |

**Mechanics confirmed.**
`AttackOracle` (unprivileged address) called `oracle.setPrice(1)`,
deposited 1 wei at the crashed price (minting 1e18 shares), restored the
price to 1e18, then called `vault.withdraw()` and received 1 ETH.
One iteration extracts ~1 ETH for a 1-wei deposit. Repeating the
sequence (or frontrunning real depositors) can drain the entire vault.

---

## Killed candidates

No new kills in this run. Killed candidates K-1 through K-4 are
documented in `crew/out/scout-candidates.md`.
