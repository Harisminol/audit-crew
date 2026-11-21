#!/usr/bin/env bash
# AuditCrew orchestrator — runs the Kiro audit crew end to end.
# Usage: ./crew/run-audit.sh [target-dir]   (default: contracts/src)
# Each step is one headless kiro-cli run with the matching custom agent
# from .kiro/agents/. Credit discipline: one run per step, short prompts,
# previous step's output file as context — never the whole repo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$ROOT/contracts/src}"
OUT="$ROOT/crew/out"
mkdir -p "$OUT"

export PATH="$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

run_agent() {
  local agent="$1"; local prompt="$2"
  echo "=== agent: $agent ==="
  kiro-cli chat --agent "$agent" --no-interactive \
    --trust-all-tools --trust-workspace "$prompt"
}

# 1 — Scout: static analysis, candidates + killed.
run_agent scout \
  "Follow your agent definition in .kiro/agents/scout.md and the steering in .kiro/steering/. Audit the contracts in $TARGET. Write $OUT/scout-candidates.md with a Candidates section and a Killed section."

if ! grep -q "^## Candidates" "$OUT/scout-candidates.md" 2>/dev/null; then
  echo "scout produced no candidates file — stopping."
  exit 1
fi

# 2 — Exploiter: one PoC per candidate, forge test until green or killed.
run_agent exploiter \
  "Follow your agent definition in .kiro/agents/exploiter.md and the steering in .kiro/steering/. Work through every candidate in $OUT/scout-candidates.md, one at a time. Write each PoC test into $ROOT/contracts/test/ and run forge test from $ROOT/contracts/. Append results to $OUT/poc-results.md."

# 3 — Verifier: live-state checks on every green PoC (read-only).
run_agent verifier \
  "Follow your agent definition in .kiro/agents/verifier.md and the steering in .kiro/steering/. Verify every green PoC in $OUT/poc-results.md against live chain state (read-only calls only; for the demo target use a local Anvil fork). Append results to $OUT/verification.md."

# 4 — Reporter: ranked report, findings need green PoC + VERIFIED.
run_agent reporter \
  "Follow your agent definition in .kiro/agents/reporter.md and the steering in .kiro/steering/. Assemble $ROOT/AUDIT-REPORT.md from $OUT/scout-candidates.md, $OUT/poc-results.md and $OUT/verification.md, then print a one-paragraph summary."

echo "=== audit complete: $ROOT/AUDIT-REPORT.md ==="
