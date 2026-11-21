# Ground-truth reference (author's, not the crew's)

`VaultPoC.t.sol` is the author's own reference PoC, written while
scaffolding the demo vault — before the crew ever ran. It is kept here
for comparison only: the crew never reads this folder (the exploiter
is explicitly told it is off-limits) and `forge test` does not pick it
up, because it lives outside `contracts/test/`.

The crew authored its own PoCs (`contracts/test/PocC1Reentrancy.t.sol`,
`contracts/test/PocC2OracleManip.t.sol`) from the scout's candidates
and proved the same two bugs independently:
- reentrancy: 10 ETH profit, vault drained to 0
- oracle manipulation: ~1 ETH per 1-wei iteration, repeatable to drain
