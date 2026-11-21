# Scout Candidates

Scope: `contracts/src/Vault.sol`, `contracts/src/PriceOracle.sol`

---

## Candidates

### C-1 — Reentrancy in `Vault.withdraw()`

| Field | Detail |
|---|---|
| **Contract** | `Vault` |
| **Function** | `withdraw()` |
| **Lines** | 42–48 (`Vault.sol`) |
| **Class** | Reentrancy (same-function, cross-call) |
| **Invariant broken** | A caller must not be able to redeem more ETH than the vault balance attributed to their shares. After `withdraw()` returns, `shares[caller]` must be 0 and the vault's ETH balance must have decreased by exactly `(s * p) / 1e18`. |

**Root cause.**
`withdraw()` violates checks-effects-interactions. The external ETH transfer on line 44 (`msg.sender.call{value: ethOut}("")`) fires before the state update on lines 46–47 (`shares[msg.sender] = 0; totalShares -= s`). While control is inside the caller's `receive()` or fallback, `shares[msg.sender]` still holds the original balance, so a re-entrant call to `withdraw()` passes the `require(s > 0)` guard and sends another round of ETH.

```solidity
// Vault.sol lines 42-48
(bool ok, ) = msg.sender.call{value: ethOut}("");   // ← ETH sent here
require(ok, "ETH send failed");
shares[msg.sender] = 0;      // ← state cleared only after the call returns
totalShares -= s;
```

**Attacker preconditions.**
- Deploy a contract with a `receive()` function that re-enters `withdraw()`.
- Deposit any nonzero ETH to obtain at least 1 share (normal user action).
- No privileged role required.

**PoC goal.**
Deploy `AttackReentrancy`. Call `deposit{value: 1 ether}()` from it, then call `attack()` which calls `withdraw()`. The attacker contract's `receive()` re-enters `withdraw()` until the vault is empty. Assert:
- Attacker ETH balance after attack > 1 ether (the deposited amount).
- `vault.balance == 0` (or close to 0, depending on other depositors).
- Quote exact attacker profit in wei from `forge test -vv` output.

---

### C-2 — Unrestricted oracle price manipulation → share-price desync in `Vault`

| Field | Detail |
|---|---|
| **Contract** | `PriceOracle` (exploited through `Vault`) |
| **Function** | `PriceOracle.setPrice()` → `Vault.deposit()` / `Vault.withdraw()` |
| **Lines** | `PriceOracle.sol` line 13 (`setPrice`); `Vault.sol` lines 32, 39, 44 (oracle reads in `deposit`/`withdraw`) |
| **Class** | Oracle manipulation / share-price accounting desync |
| **Invariant broken** | The ETH redeemable by a share-holder must never exceed their pro-rata claim on the vault's ETH balance. |

**Root cause.**
`PriceOracle.setPrice(uint256 p)` has no access control — any address can set `price` to any value. Both `deposit()` and `withdraw()` derive share counts and ETH payouts directly from this price with no TWAP, no bound check, and no slippage guard.

```solidity
// PriceOracle.sol lines 12-14
function setPrice(uint256 p) external {   // ← no onlyOwner, no guard
    price = p;
}
```

```solidity
// Vault.sol deposit() lines 31-37
uint256 p = oracle.price();               // ← reads manipulable price
uint256 s = (msg.value * 1e18) / p;      // ← low price → huge share count

// Vault.sol withdraw() lines 40-47
uint256 p = oracle.price();               // ← reads manipulable price
uint256 ethOut = (s * p) / 1e18;         // ← high price × huge shares → drains vault
```

**Attack sequence (single attacker, no flash loan needed).**
1. Victim deposits 100 ETH at price 1e18 → vault has 100 ETH, victim holds 100e18 shares.
2. Attacker calls `oracle.setPrice(1)` (price = 1 wei).
3. Attacker calls `vault.deposit{value: 1 wei}()` → receives `(1 * 1e18) / 1 = 1e18` shares for 1 wei.
4. Attacker calls `oracle.setPrice(1e18)` (price restored).
5. Attacker calls `vault.withdraw()` → receives `(1e18 * 1e18) / 1e18 = 1 ETH` back for a 1-wei deposit.
   Repeating steps 2–5 each iteration drains the vault; a single deposit at a price of `1` and withdrawal at `1e18` extracts ~100× the deposited value.

**Attacker preconditions.**
- No privileged role.
- Must hold enough ETH to call `deposit()` (minimum 1 wei at any price).

**PoC goal.**
Deploy `AttackOracle`. Seed the vault with victim ETH. Run the attack sequence above. Assert:
- Attacker ETH profit > 0 (quote exact wei).
- `vault.balance` after attack < vault balance before attack by more than the attacker's deposit.

---

## Killed

| # | Candidate | Reason |
|---|---|---|
| K-1 | Rounding / precision loss in `deposit` / `withdraw` | Integer division truncates dust (≤ 1 wei per round-trip). No accumulation path an attacker can exploit; grief cost equals attacker loss. Not a finding. Source: `Vault.sol` line 33 `(msg.value * 1e18) / p`, line 43 `(s * p) / 1e18`. |
| K-2 | Unchecked low-level call in `withdraw` | `require(ok, "ETH send failed")` on line 45 checks the return value. Not unchecked. Source: `Vault.sol` line 44–45. |
| K-3 | Access control on `Vault` owner/admin paths | No owner or admin functions exist in `Vault`. Nothing to audit. |
| K-4 | Flash-loan price manipulation as a separate class | Oracle price is writable by any EOA without a flash loan; no flash-loan receiver or callback in scope. The attack in C-2 needs no flash loan — same root cause, not a distinct finding. |
