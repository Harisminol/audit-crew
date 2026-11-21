# AuditCrew steering — severity + evidence discipline

## Never do these
- Never report a finding without an executed PoC.
- Never call an admin-only path a finding.
- Never inflate severity. If the precondition needs the victim to do
  something irrational, it is Low at best.
- Never present a predicted number as a measured one. Profits, balances
  and gas come from test output, not from reasoning.
- Never audit a contract you have not read in full. No "probably safe".

## Evidence rules
- Every claim in the report traces to one of: a source line, a PoC log
  line, or a live on-chain read (address, block, value).
- Quote the exact numbers. "Attacker profit: 10 ETH" beats "attacker
  profits significantly".
- If two agents disagree, the PoC decides. Re-run it, don't argue.

## Language
Reports are written in plain, direct English. Findings first, caveats
second. No marketing language, no hype, no apologies.
