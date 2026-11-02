# Supplier journey audit, 28 Oct 2026: the sales agent (auditor C, `it_engineer`)

Founder ledger 1401. Auditors A (browser) and B (code) report the journey scenarios in their own folders here. This
folder answers whether the `sales_engineer` seat is qualified and running.

| file | what it holds |
|---|---|
| `SALES_AGENT_AUDIT_28_OCT.md` | The report: verdict, per-area PASS/FAIL, findings ranked by severity, the conversation grading table, SLAs, fix PRs, clean-up |
| `CONVERSATION_ANSWERS_28_OCT.md` | The eight supplier replies and the re-run after #1714/#1715: each answer verbatim (claim tokens masked), with path, time, spend and clean-up |
| `verification_decision_table_28_oct.json` | `fn_sales_engineer_verifies_supplier` on eight licence situations, run once in one aborted transaction on production |
| `verification_decision_table_probe.sql` | The probe that produced the table. It always raises, so it rolls back; send it only through `scripts/lib/safe_replay.mjs` `replaySql` |
