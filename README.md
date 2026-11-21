# AuditCrew — a Kiro-powered multi-agent smart contract audit crew

> **Kiroween 2026 · Frankenstein category.** AuditCrew stitches four
> seemingly incompatible things into one audit: static analysis, Foundry
> proof-of-concept exploits, live on-chain verification, and a ranked
> report — each done by its own Kiro agent, orchestrated by one script.

A finding exists only when an **unprivileged** actor can break an invariant
and extract value — demonstrated by an **executed** Foundry PoC, not by
reading code. No PoC, no finding.

## The crew

| Agent | Job | Output |
|---|---|---|
| `scout` | Reads every contract, maps money flows, lists candidates with file:line + invariant broken, kills non-findings with one line of evidence | `crew/out/scout-candidates.md` |
| `exploiter` | Authors a Foundry PoC per candidate, runs `forge test` until green or the candidate is killed | `crew/out/poc-results.md` |
| `verifier` | Checks every green PoC against live chain state (read-only calls only) | `crew/out/verification.md` |
| `reporter` | Assembles the ranked report. A finding enters only with a green PoC **and** a VERIFIED live check | `AUDIT-REPORT.md` |

The agents live in `.kiro/agents/`, the methodology in
`.kiro/steering/`, the pipeline in `.kiro/workflows/audit.md`, and the
orchestrator in `crew/run-audit.sh`. One command runs the whole crew:

```bash
./crew/run-audit.sh [contracts-dir]
```

## Demo target — and what the crew found

`contracts/src/` holds a demo vault built for this project: `Vault.sol`
(an ETH vault whose share price comes from an oracle) and
`PriceOracle.sol`. Two High/Critical bugs are seeded in it, documented in
the source so judges can verify the crew actually finds them.

**Crew run 1 (2026-11-21) — 2 Critical findings, both proven:**

| Finding | PoC | Observed result |
|---|---|---|
| **F-1 — Reentrancy in `Vault.withdraw()`** | `PocC1Reentrancy::test_reentrancyDrainsVault` | 1 ETH in, vault drained to 0, **10 ETH profit** |
| **F-2 — Unrestricted `PriceOracle.setPrice()`** | `PocC2OracleManip::test_oracleManipDrainsVault` | 1 wei in, **~1 ETH out per iteration**, repeatable to full drain |

Plus 4 killed candidates (rounding dust, checked call, no admin paths,
flash-loan as a separate class) and 7/7 live-state precondition checks
VERIFIED. Full report: [`AUDIT-REPORT.md`](AUDIT-REPORT.md).

The crew authored its own PoCs from the scout's candidates — the author's
reference PoCs are kept separately in `demo/ground-truth/` for comparison
and are **not** run by the crew.

## Quick start

```bash
git clone --recursive https://github.com/Harisminol/audit-crew.git
cd audit-crew
# Foundry: https://getfoundry.sh  |  Kiro CLI: https://kiro.dev (log in first)
forge build --root contracts
./crew/run-audit.sh
```

Each step is one headless `kiro-cli chat --agent <name>` run. Credit
discipline is built into the workflow: one run per step, short prompts,
the previous step's output file as context — never the whole repo.

## How the Kiro part actually works

- The crew runs on **Kiro CLI built-in tools** (`read_file`, `fs_write`,
  `execute_bash`). Custom agents declare their tools in the frontmatter
  of `.kiro/agents/*.md` — without that list, headless sessions start
  with no tools at all (found the hard way during the build).
- MCP servers (filesystem + a small shell server) were evaluated during
  development and turned out to be unnecessary once the frontmatter tools
  were declared, so they are not part of the repo.
- `--effort` is intentionally not passed: on this CLI version it forces a
  model-list fetch that fails with `ModelRegistryUnavailableError`.
- Verification runs against deployed contracts in Foundry's in-process
  EVM (read-only calls, no transactions) — the same reads `cast call`
  would make against a local Anvil node.

## Project status

Built during the Kiroween 2026 submission period (Oct 30 – Dec 4, 2026).
The audit methodology adapts the author's own bug-bounty playbooks
(static-analysis checklists, Foundry-PoC standard, submission gates);
the crew code, agents, vault, and PoCs in this repo are new work written
for this hackathon.

## License

MIT — see [LICENSE](LICENSE).
