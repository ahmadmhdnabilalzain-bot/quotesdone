# Brief: guard_fix — fix round on the replay guard and the lost-acceptance fixes
Read `SP/briefs/COMMON.md` first. You are the FIX author (commit prefix `it_engineer:`).
Branch: `it_engineer-a-suppliers-certificate-is-written-in-time-and-never-silently-lost` (head 63f82cd5d).
Worktree: /tmp/claude-0/fix-guard2. Local database: /tmp/pg-guard2, port 55471.
Read: the review `SP/handbacks/GUARD_REVIEW.md` and REVIEW.md section "REPLAY GUARD AND ACCEPTANCE 1" (ten items);
`git diff origin/main...HEAD`. What happened this morning is in COMMON.md rule 1.
THE TEN ITEMS, WITH THE DECISIONS ALREADY TAKEN (do not re-open them):
1. Every replay that targets production sets `transaction_timeout = 5s` (Postgres 17) beside lock_timeout and
   statement_timeout; the local path (Postgres 16) skips the setting it does not have.
2. Drop the hot-table list. On production a replay is REFUSED before it is sent if the file takes any lock stronger than
   ROW EXCLUSIVE on any relation that already exists (decide from the parsed statements: ALTER TABLE, CREATE INDEX without
   CONCURRENTLY, DROP, TRUNCATE, CREATE TRIGGER, LOCK, REINDEX, VACUUM FULL, REFRESH MATERIALIZED VIEW without CONCURRENTLY,
   ALTER/DROP POLICY and CREATE POLICY on an existing table). New objects and CREATE OR REPLACE FUNCTION are allowed.
3. Fix the pending probe of `scripts/sql/a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one.sql`
   (it writes `customers.is_demo`, a GENERATED column; and a jsonb concatenation error), prove file + probe LOCAL, and add
   mutants (remove each guarantee in turn: the probe must fail by verdict).
4. `scripts/apply_sql.mjs`: the real apply sets `lock_timeout` (default 1500 ms, flag to change) and prints what it set.
5. No automatic retry after a 5xx from the management API on a replay or an apply (a retry doubles a held lock).
6. Production is never the default target: a replay runs on the local database unless the caller passes
   `target:'production'` or `QD_REPLAY_ON_PRODUCTION=1`; add `scripts/db/local_pg16.mjs` (start | load | stop | url) that
   performs the steps at the end of GUARD_REVIEW.md, with the stand-ins moved from `SP/rg_standins.sql` into the repo
   (`scripts/db/local_standins.sql`), cluster under /tmp/pg-qd by default, never as root.
7. Mask e-mail addresses and phone numbers in any `cause` text the functions log or return.
8. kyc: the finding raised on a failed write goes through `EdgeRuntime.waitUntil` so the response is not delayed and the
   finding is not lost when the isolate ends.
9. `tightenLimits`: accept the variants the review listed (case, spacing, `set local`, quoted values).
10. `spec_fill` approval: compare-and-set so a retried approval cannot apply twice; `supplier_api accept_terms` goes
    through `writeRecorded` like the customer side; the two missing tests the review names.
ALSO: the memory note `.claude/memory/a-rehearsal-on-production-holds-the-locks-of-a-real-change.md` (what happened with
the measured numbers from COMMON.md and GUARD_REVIEW.md, the rule, how to rehearse locally) and its line in
`.claude/memory/MEMORY.md`; update `docs/runbooks/release-without-ci.md` where it tells a session to rehearse on production.
PROVE: deno tests of kyc, compliance_archive, supplier_api, `_shared`; node tests of `scripts/lib/replay_guard*`,
`scripts/checks/*` you touched; file + probe LOCAL; `scripts/db/local_pg16.mjs start && load` from a clean /tmp/pg-qd.
Push small commits. HAND-BACK (under 50 lines): each item DONE (file:line, the test) / NOT DONE (why); tests with counts;
the SQL to apply and functions to deploy in order; what you are unsure of. Also write it to `SP/handbacks/GUARD_FIX.md`.

## State found at 20:10 UTC (read this before anything else)
A predecessor on this same brief pushed FOUR commits at 12:02 UTC and was then killed by a restart with no hand-back:
cc47aba0e "a production replay is never the default and is cut at 5 s, whatever it locks"; 09e6cf570 "the acceptance probe
can pass on production and catches the five mutants"; 4c32b3837 "a person's write is answered inside his page's clock,
carries no contact into agent_runs, and a press delivers once"; 63f82cd5d "memory - a rehearsal on production holds the
locks of a real change". So most of the ten items may be done. Your job is therefore: for EACH of the ten items and the
"ALSO" list, read the code at the head and decide DONE-AND-PROVEN (run the test that proves it and name it) or finish it.
Trust nothing by its commit title. Create the worktree from origin at the head. Anything the predecessor left half-done
or untested is yours.
