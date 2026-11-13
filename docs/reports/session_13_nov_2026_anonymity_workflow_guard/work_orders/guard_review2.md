# Brief: guard_review2 — second independent review of the replay guard and the lost-write fixes
Read `SP/briefs/COMMON.md` first. You are an INDEPENDENT reviewer; you wrote none of this.
Worktree: /tmp/claude-0/review-guard2 from `origin/it_engineer-a-suppliers-certificate-is-written-in-time-and-never-silently-lost`
(head 8502c8d5a). Local database: use the branch's own `scripts/db/local_pg16.mjs` (default /tmp/pg-qd): testing that script
from a clean start is part of the review.
Read: the first review, REVIEW.md section "REPLAY GUARD AND ACCEPTANCE 1" and `SP/handbacks/GUARD_REVIEW.md` (ten items);
the author's account `SP/handbacks/GUARD_FIX.md`; `git diff origin/main...HEAD`; the incident it answers:
`SP/incident_13_nov_2026_rehearsals_on_production_held_live_locks.md`.
What this branch must guarantee: (a) no session can again stall live users by rehearsing SQL on production: a replay is
local unless production is asked for; a production replay is refused if its file takes a lock stronger than ROW EXCLUSIVE
on an existing relation, and is cut at 5 s; the real apply has a short lock_timeout and never re-sends after a 5xx;
(b) a write a person depends on (terms acceptance at kyc, a supplier's agreement at supplier_api, the certificate at
compliance_archive, a spec_fill approval) is either recorded or the person is TOLD and a seat is told: never a silent
success; (c) a recorded acceptance always gets its certificate (the pending SQL file).
VERIFY:
1. Each of the ten items at the head: DONE-AND-PROVEN / NOT (file:line, the test you ran). Trust no commit title.
2. ATTACK the refusal: write 25 SQL files of your own that take a strong lock on an existing table in ways a parser
   misses (DO blocks with EXECUTE, a function called that does DDL, comments and dollar-quoting tricks, `ALTER TABLE IF
   EXISTS ONLY`, schema-qualified and quoted names, CREATE INDEX on an existing table, `LOCK` inside a CTE-less
   statement, COMMENT ON, GRANT on a table, ALTER FUNCTION, DROP TRIGGER, CREATE RULE, ALTER SEQUENCE OWNED BY, REFRESH
   MATERIALIZED VIEW, CLUSTER, ALTER TYPE used by a table, ALTER PUBLICATION, SECURITY LABEL …). For each: REFUSED /
   PASSES; for one that passes, what lock it really takes LOCAL (pg_locks) and whether the 5 s cut then bounds the harm.
   Never send any of them to production; the guard's decision is computed offline.
3. And 15 files that MUST pass (new table, new function, CREATE OR REPLACE FUNCTION, insert/update with a WHERE, a
   policy on a NEW table, an index on a NEW table): any refused is a defect too.
4. `scripts/apply_sql.mjs`: dry run only. The lock_timeout it would set, the refusal of bad `--lock-timeout` values, the
   no-resend rule by its test; READ whether a response lost after the server committed can lead to a second apply by
   the operator's own retry, and what the file-level protections are (idempotent files; MANIFEST).
5. The four write paths in (b): for each, the test in which the write fails: the person's response, the finding to the
   seat, no contact detail in any log line or stored cause (mask). Find one more failing-write path of the same family
   that the branch did NOT cover (grep the same pattern: `await ...insert/update/rpc` whose error is ignored on a path
   that answers ok:true) in kyc, supplier_api, customer_api, compliance_archive: list up to 10, most harmful first.
6. The pending SQL file + probe LOCAL, twice; its lock table; the author's 7 mutants re-run.
7. `_shared/observe.ts` changed and 67 functions import it: read the change; can it throw, slow or change any response?
8. The memory note and the runbook: true to the code? Any sentence that still tells a session to rehearse on production?
9. Suites: deno kyc, compliance_archive, supplier_api, `_shared`; node tests of scripts/lib and the checks the diff touches.
VERDICT: MERGE or FIX (numbered: file:line, input, smallest fix), most harmful first; the release steps and the exact
deploy list; under 55 lines. Append the full review to `SP/show/REVIEW.md` under "REPLAY GUARD AND ACCEPTANCE 2".
Progress notes: `SP/progress/guard_review2.md`. Delete your cluster and worktree at the end.
