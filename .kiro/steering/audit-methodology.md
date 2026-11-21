# AuditCrew steering — how this crew audits

## The rule that matters most
A finding exists only when an **unprivileged** actor can break an invariant
and extract value or strand someone else's value — demonstrated by an
**executed** Foundry PoC, not by reading code. No PoC, no finding.

## Hunt order
1. **Primitives first.** List what the protocol IS (vault, AMM, lending,
   oracle, bridge) and the invariant each primitive must hold.
2. **Map the money.** Who puts value IN, who takes value OUT, who decides
   the PRICE at each step, where value sits BETWEEN steps. Every edge where
   the price-decider is unprivileged or manipulable in one transaction is
   a candidate.
3. **Hunt by class, not by line.** Reentrancy (incl. cross-function),
   access control, oracle manipulation, share-price / accounting desync,
   flash-loan price corruption, precision / rounding, unchecked external
   calls. A finding must name the class, the exact function + line, and
   the invariant broken.
4. **Kill fast.** Admin-only paths, self-harm, theoretical manipulation
   with no live route, and already-audited duplicates are NOT findings.
   Record the kill with one line of evidence and move on.

## Severity rubric
- **Critical:** direct theft / drain of user funds, unprivileged, no
  preconditions beyond normal use. Example: reentrancy draining a vault.
- **High:** theft / drain with a cheap precondition (e.g. a price the
  attacker can move), or permanent loss of funds.
- **Medium:** funds at risk under narrow conditions, or griefing that
  strands value.
- **Low / Info:** everything else. Never inflate severity to make a
  report look better.

## PoC standard (non-negotiable)
Every finding ships with a Foundry test that:
1. Deploys the real contracts (no mocks of the vulnerable logic).
2. Attacks from an **unprivileged** address — no owner/admin/signer role.
3. Asserts the concrete outcome with numbers in the output
   (attacker profit in wei, vault balance after attack).
4. Passes: `forge test` green, exit 0. A PoC that does not run is not
   evidence.

## Report format
Ranked by severity, one finding per section: title, severity, class,
location (file:line), invariant broken, attack walkthrough (numbered
steps), PoC (file + test name + observed numbers), impact, fix.
Findings the crew could NOT prove go in a separate "Killed candidates"
section with one line each — never silently dropped, never promoted.
