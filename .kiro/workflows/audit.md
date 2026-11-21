# Audit workflow — run the full crew on a target

## When to use
`./crew/run-audit.sh [target-dir]` — audits the contracts in the target
directory end to end: scout, exploit, verify, report.

## Steps
1. **Scout.** Run the `scout` agent on the target contracts. Output:
   `crew/out/scout-candidates.md` (candidates + killed, with file:line).
2. **Exploit.** For each candidate, run the `exploiter` agent. It writes
   a Foundry PoC in `contracts/test/` and runs `forge test` until green
   or the candidate is killed. Output: `crew/out/poc-results.md`.
3. **Verify.** Run the `verifier` agent on every green PoC. Read-only
   chain checks only — never send a transaction against a live program.
   Output: `crew/out/verification.md`.
4. **Report.** Run the `reporter` agent. A finding enters the report
   only with a green PoC AND a VERIFIED live check. Output:
   `AUDIT-REPORT.md` at the repo root.
5. **Stop conditions.** If the scout finds zero candidates, stop after
   step 1 and report that plainly. If every candidate is killed, the
   report says so — an empty findings list is a valid result, never a
   failure to hide.

## Credit discipline
- One agent run per step. Do not re-run an agent to "double-check" —
  the PoC and the live check are the verification.
- Keep prompts short: point at the files, don't paste them.
- The orchestrator passes the previous step's output file as context,
  never the whole repo.
