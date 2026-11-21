#!/usr/bin/env bash
# AuditCrew demo — the fast, visual version of the full crew run.
# Used to record the demo video. Shows: the crew layout, the scout's
# candidates, the crew-authored PoCs going green, and the report.
# The full agent pipeline lives in crew/run-audit.sh; this script
# replays its already-produced evidence plus a live forge test run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "================ AuditCrew ================"
echo "Kiro-powered multi-agent smart contract audit crew"
echo "Kiroween 2026 — Frankenstein"
echo
echo "--- the crew (.kiro/agents) ---"
ls .kiro/agents/
echo
echo "--- the pipeline (.kiro/workflows) ---"
ls .kiro/workflows/
echo
echo "--- scout: candidates found ---"
grep -E "^### C-|^## " crew/out/scout-candidates.md
echo
echo "--- exploiter: crew-authored PoCs, live run ---"
export PATH="$HOME/.foundry/bin:$PATH"
forge test --root contracts -vv 2>&1 | grep -E "PASS|FAIL|Suite result|Ran [0-9]+ test"
echo
echo "--- verifier: live-state preconditions ---"
grep -E "^\|.*PASS|Verdict" crew/out/verification.md | head -12
echo
echo "--- reporter: AUDIT-REPORT.md ---"
grep -E "^### F-|^\*\*Findings:\*\*" AUDIT-REPORT.md
echo
echo "Full report: AUDIT-REPORT.md"
echo "Repo: https://github.com/Harisminol/audit-crew"
