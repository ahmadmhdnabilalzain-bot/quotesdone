---
name: a-rehearsal-on-production-holds-the-locks-of-a-real-change
description: "13 Nov 2026: a rolled-back rehearsal on production takes and HOLDS the same locks as the real change. 28 rehearsals (whole DDL files + a 12-15 s probe, one transaction) queued 103 live requests and 11 cron jobs; the live role's 8 s statement_timeout cancelled a supplier's certificate write, a quotation's approval and a customer's acceptance. Rule: local first; a production replay is never the default and is cut at 5 s; the real apply uses lock_timeout and a quiet minute."
metadata:
  type: feedback
  modified: 2026-11-13
---

**What happened (13 Nov 2026, measured in the production postgres log, 05:30-09:29 UTC).** This session's agents rehearsed SQL
files on PRODUCTION all morning: a whole file of DDL (ALTER TABLE inquiries/quotes/transactions, DROP/CREATE TRIGGER on quotes)
plus a 12-15 s probe inside ONE open transaction, rolled back at the end, re-run every ~20 s while a probe kept failing. 218
"still waiting for ... lock" lines, 217 behind management-API sessions: 103 live PostgREST requests and 11 pg_cron jobs waited
behind 28 rehearsals. A rolled-back transaction is not a harmless one: it takes the real change's locks and holds them until
its last statement. The live role (`authenticator`) has `statement_timeout = 8s`, so what queued behind was cancelled:
- 07:46:10 a supplier's signed-agreement certificate write on leads (`cert_record_failed`; repaired 5 minutes later by the
  minute sweep `fn_sales_engineer_resigns_unsigned_agreements`);
- 08:11:08 a quotation's approval request at the hold desk (`spec_fill` -> `fn_customer_support_takes_delivery`, 11.3 s);
- 08:47 a customer's acceptance of the terms: kyc discarded the write's error, answered ok, and he reached his dashboard with
  no acceptance on record; compliance_archive then refused his certificate (409 no_acceptance_on_record).
No real person was hit (every one was a ZZ DEMO fixture or a real supplier certified within minutes). Reproduced on a local
Postgres 17.6: a live SELECT behind `alter table quotes` + a 12 s probe was cancelled at 8.04 s.

**What the first fix got wrong (independent review, same day).** A regex on a list of "hot tables": quoted names, DDL in a DO
block or EXECUTE, DROP INDEX, a new table that REFERENCES a hot one, CREATE OR REPLACE VIEW, the second table of TRUNCATE/LOCK,
storage/auth tables and row locks all passed it with a 120 s hold; 3 of its 24 names were not tables and 9 busy ones were
missing. A list of what is dangerous is out of date the day it is written.

**The rule.**
- **Local first.** A rehearsal runs on the local database: `node scripts/db/local_pg16.mjs start` (Postgres 16 from the schema
  mirror, ~20 s, no Docker) and `export QD_LOCAL_DB_URL="$(node scripts/db/local_pg16.mjs url)"`. Runbook:
  docs/runbooks/local-database.md.
- **Production is never the default.** `replaySql` (scripts/lib/safe_replay.mjs) refuses production unless the caller says
  `target: 'production'` or the operator sets `QD_REPLAY_ON_PRODUCTION=1`; with neither and no local URL it sends nothing and
  says how to start the local database. `npm test` and `npm run gate` follow the same rule.
- **A production replay is cut at 5 s** (`transaction_timeout`, Postgres 17; plus `lock_timeout` 1 s and one replay at a time)
  whatever it locks and however it says it; it is sent once, never re-sent after a 5xx. Measured: a live reader behind a
  guarded replay waited 4.53 s and answered (8.04 s and cancelled without the guard). The static reading (a lock stronger than
  ROW EXCLUSIVE on any relation pg_class has) is only an early, friendly refusal.
- **The real apply** (scripts/apply_sql.mjs) caps the file's own lock_timeout at 2 s, cuts a file that stops writers at 60 s,
  retries a lock not granted after a fixed 10 s, and never re-sends after a 5xx unless it can prove nothing committed. Apply a
  file that locks a busy table in a quiet minute, and split a backfill.
- Before blaming code for a statement timeout, read the postgres log at that second for "still waiting for" and the holder's
  `application_name` (`mgmt-api` = one of our sessions).
- A write a person depends on is read back and a blip retried within the page's budget (`_shared/recorded_write.ts`); a
  failure is said to the person (`terms_not_recorded`) and raised to the it_engineer seat in the background.

Prevented by: `scripts/checks/a_rehearsal_never_makes_a_live_user_wait.test.mjs` (40 evasions),
`scripts/checks/no_script_sends_ddl_to_production_except_through_the_guard.test.mjs`,
`scripts/checks/a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one.test.mjs`,
`supabase/functions/kyc/a_terms_write_that_never_lands_is_said.test.ts`, `src/components/me/auth/acceptTerms.test.mjs`,
`supabase/functions/_shared/line_specs/workflow.test.ts` ("two tabs, or a double press").
Related: [[an-apply-can-lock-sign-in]], [[a-check-that-replays-sql-can-commit-it]], [[two-applied-prs-deadlock-each-others-database-check]],
[[a-probe-can-run-locally-on-a-stub-built-from-the-mirror]].
