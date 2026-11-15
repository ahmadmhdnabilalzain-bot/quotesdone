---
name: a-rehearsal-on-production-holds-the-locks-of-a-real-change
description: "13 Nov 2026: a rolled-back rehearsal on production takes and HOLDS the same locks as the real change. 28 rehearsals (whole DDL files + a 12-15 s probe, one transaction) queued 103 live requests and 11 cron jobs; the live role's 8 s statement_timeout cancelled a supplier's certificate write, a quotation's approval and a customer's acceptance. Rule: local first; a production replay is never the default and is cut at 5 s; the real apply uses lock_timeout 1500 ms and a quiet minute."
metadata:
  type: feedback
  modified: 2026-11-15
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
No real person was hit (every one was a ZZ DEMO fixture or a real supplier certified within minutes). Reproduced by the independent
review on a local Postgres 16 built from the mirror: a live reader (8 s statement_timeout) behind `alter table quotes` + a 12 s
probe was cancelled at 8.04 s; behind a 1 s lock_timeout it waited 0.83 s; behind a replay cut at 5 s it waited 4.65 s and answered.

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
  whatever it locks; it is sent once, never re-sent after a 5xx. Measured (review, local): a live reader behind a replay cut at
  5 s waited 4.65 s and answered (8.04 s and cancelled without the cut). The cut holds only because the file cannot lift it:
  the second review (13 Nov) lifted lock_timeout with `set local "lock_timeout" = 0`, a DO block's EXECUTE and
  `set_config(E'lock_timeout', ...)`, and transaction_timeout the same four ways. Since 15 Nov the guard refuses, on the raw text,
  the word transaction_timeout anywhere, any set_config of lock/statement/transaction_timeout or with a computed name, a SET of
  those inside a DO block or EXECUTE, a quoted top-level SET of one, and RESET ALL; only a top-level `set local lock_timeout =
  <ms>` is kept (lowered to the cap). Any EXECUTE of a non-literal is refused on production as dynamic SQL (replay and apply).
  All of this is read in the top level, in DO blocks, and (since the third review, 15 Nov) in the body and SET clause of every
  function or procedure the file both defines and calls: the third review lifted both limits from such a body
  (`execute 'set local transaction' || '_timeout = 0'` in a function, then `select f()`), which the first wording of this rule
  claimed was impossible. A routine the file only defines is not read (it runs later under its own limits).
- **The early refusal reads what the text SAYS, not everything it does.** It refuses a lock stronger than ROW EXCLUSIVE on a
  relation pg_class has, read through quoted, `U&"..."` and three-part names, the file's own search_path, DO blocks and literal
  EXECUTE strings; DROP FUNCTION/TYPE/DOMAIN ... CASCADE, ALTER DOMAIN and a bare CLUSTER count as an unknown table. It does
  NOT see a lock taken inside a routine the file calls but did not define in it (bounded only by the 5 s cut). Review 2 found
  16 shapes it missed; 15 were refused in round 3, and a05 (DDL in a routine the file defines and calls) since round 4.
- **The real apply** (scripts/apply_sql.mjs) sets lock_timeout 1500 ms (`--lock-timeout=<ms>` to change, 1-15000) and lowers
  the file's own to it, prints the limits it set, cuts a file that stops writers at 60 s, retries a lock not granted after a
  fixed 10 s, and NEVER re-sends after a 5xx: if its first copy is still on production after 2 minutes it says STILL RUNNING,
  do not re-run (exit 5); it says "run the same command again" (exit 4) only when it proved nothing committed and the MANIFEST
  does not list the file; anything else is exit 5, check by hand. `--lock-timeout` below 1 ms is refused (0.4 used to round to
  0, no limit). Apply a file that locks a busy table in a quiet minute, and split a backfill.
- Before blaming code for a statement timeout, read the postgres log at that second for "still waiting for" and the holder's
  `application_name` (`mgmt-api` = one of our sessions).
- A write a person depends on is read back and a blip retried within the page's budget (`_shared/recorded_write.ts`); a
  failure is said to the person (`terms_not_recorded`) and raised to the it_engineer seat in the background.

Prevented by: `scripts/checks/a_rehearsal_never_makes_a_live_user_wait.test.mjs` (40 evasions), `scripts/lib/replay_guard.test.mjs`
(review 2's lifts and missed shapes, and the 15 files that must pass),
`scripts/checks/no_script_sends_ddl_to_production_except_through_the_guard.test.mjs`,
`scripts/checks/a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one.test.mjs`,
`supabase/functions/kyc/a_terms_write_that_never_lands_is_said.test.ts`, `src/components/me/auth/acceptTerms.test.mjs`,
`supabase/functions/_shared/line_specs/workflow.test.ts` ("two tabs, or a double press").
Related: [[an-apply-can-lock-sign-in]], [[a-check-that-replays-sql-can-commit-it]], [[two-applied-prs-deadlock-each-others-database-check]],
[[a-probe-can-run-locally-on-a-stub-built-from-the-mirror]].
