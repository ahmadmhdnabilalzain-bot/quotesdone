---
name: promote-carries-the-definition-not-the-grants
description: "apply_sql --promote carries only the routine definition, so a REVOKE in the same file lands on staging only — every new SECURITY DEFINER function is left anon-executable on production."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 198f60c3-c25a-4d37-845c-efd7f7799cb2
  modified: 2026-08-14T01:33:48.631Z
---

`node scripts/apply_sql.mjs <file> --promote` applies the whole file to STAGING, then reads
`pg_get_functiondef()` back from staging and posts **only that definition** to production. Any
other statement in the file — `revoke`, `grant`, `insert`, `update`, `comment` — never reaches
production.

Caught on 12 Aug 2026 by `project_parity.mjs`, not by me: `fn_org_task_assign` came out
`anon-executable SECURITY DEFINER   prod 57   staging 56   DRIFT +1 prod-only`. The
`revoke all ... from public` sat in the same file and had run on staging only, leaving a
SECURITY DEFINER function that assigns work to employees callable by `anon` in production.

**Why:** the promote rule exists so a routine reaches production by byte-identical read-back
rather than retyping — which is right for the body and silent about everything else.

**How to apply:** the operational rule is one line — **use `--promote --ddl` whenever the file
contains anything that is not a routine body**, and plain `--promote` only for a file that is
nothing but `CREATE OR REPLACE FUNCTION`. Then confirm with `has_function_privilege('anon',
'<fn>', 'execute')` and re-run `project_parity.mjs` expecting BOTH PROJECTS IN SYNC. The same
applies to the DML backfills that often accompany a fix. `CREATE OR REPLACE` of an *existing*
function preserves its ACL and needs no revoke. See [[green-pr-does-not-mean-deployable]].

**IT HAPPENED AGAIN ON 14 AUG 2026, WITH THIS MEMORY ALREADY WRITTEN.**
`a_staffing_check_is_not_a_rehearsal.sql` created `fn_scenario_rehearse` and
`fn_scenario_rehearse_all` with the revokes in the same file, applied with `--promote` alone, and
left both anon-executable on production — one of which WRITES `scenario_library.last_run` and
`agent_runs`. Knowing the trap is not enough; the habit has to be attached to the deploy command
itself. And `project_parity.mjs` caught it inside five minutes both times, which is the real
lesson: **run parity immediately after every deploy, not once at the end of the session.**
