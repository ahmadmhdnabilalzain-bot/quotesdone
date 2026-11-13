---
name: a-rehearsal-on-production-freezes-the-live-site
description: "13 Nov 2026: rolled-back rehearsals of SQL files on production held ACCESS EXCLUSIVE on quotes/inquiries/transactions for 12-15 s; live requests timed out behind them (a supplier's certificate, a spec_fill, dashboards). safe_replay now refuses hot-table DDL, caps lock and hold time and runs one at a time; rehearse such files on the local database."
metadata:
  type: feedback
  modified: 2026-11-13
---

**What happened (13 Nov 2026, measured in the postgres log).** 05:30 to 09:29 UTC: 218 "still waiting for ... lock" lines,
217 of them behind management-API sessions: 103 live PostgREST requests behind 28 holders, 11 pg_cron jobs. The holders were
rolled-back rehearsals (`scripts/ci/rehearse_sql.mjs` -> `scripts/lib/safe_replay.mjs`) of whole files whose DDL locks hot
tables (`alter table quotes ...`, `drop/create trigger on quotes`, `alter table transactions add column` x6) followed by a
12-15 s probe, re-run every ~20 s while the probe kept failing. The functions' role (`authenticator`) has
`statement_timeout=8s`, so everything behind the lock died at 8 s: a supplier's agreement certificate write on leads
(07:46:10, `cert_record_failed`; the gate it fires sends a notice whose trigger reads quotes), a supplier's `spec_fill`
(08:11:08, `unexpected_error`), 29 dashboard reads at 08:03/08:08, and a customer's acceptance of the terms (08:47; kyc did
not read the write and let him in with no acceptance on record). Real suppliers were not hit: leads 19398 and 158318 were
certified in 3 s and 176 s; 0 real people are without an acceptance or a certificate.

**The leads triggers were not the cause.** The certificate update fires z20 -> `fn_sales_engineer_verifies_supplier`, which
approves the supplier in the same statement and sends the approval notice; that chain reads quotes, so any lock on quotes
reaches it. Its normal cost is 198 ms mean (pg_stat_statements, 1,292 calls).

**Rules.**
- A rehearsal that takes a strong lock on a hot table runs on the LOCAL database (`QD_LOCAL_DB_URL`; psql -1), never on
  production unless the operator passes `acceptStall` / `QD_REPLAY_ACCEPT_STALL=1`, and then it is cut at 5 s
  (`transaction_timeout`, which on Postgres 17 works when set inside the transaction). `lock_timeout` alone does not help:
  the rehearsal gets its lock at once and then HOLDS it.
- Before blaming the code for a statement timeout, read the postgres log at that second for "still waiting for" and the
  holder's `application_name` (`mgmt-api` = a session of ours).
- A write a person depends on is read back and a blip retried (`_shared/recorded_write.ts`); a failure is said to the person
  and raised to the it_engineer seat; a swallowed error keeps its cause on the `agent_runs` row (supplier_api `failed()`).
- `fn_customer_support_campaign_list_tick` times out on its own every 15 min (12 Nov 14:00-19:30, no lock waits): a
  separate defect, not this one.

Prevented by: `scripts/checks/a_rehearsal_never_makes_a_live_user_wait.test.mjs`,
`scripts/checks/a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one.test.mjs`,
`supabase/functions/kyc/acceptance_write.test.ts`, `supabase/functions/supplier_api/a_swallowed_error_keeps_its_cause.test.ts`,
`supabase/functions/_shared/line_specs/workflow.test.ts` ("spec_fill pressed again").
Related: [[an-apply-can-lock-sign-in]], [[a-load-test-runs-on-production-with-tools-that-commit-nothing]],
[[a-check-that-replays-sql-can-commit-it]], [[two-applied-prs-deadlock-each-others-database-check]].
