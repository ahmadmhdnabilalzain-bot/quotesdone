---
name: guarded-by-a-condition-that-cannot-occur
description: "QuotesDone's most productive diagnostic lens — a recovery/fallback path that is correct, deployed, and reachable only under a condition that never holds. Found five times in one session."
metadata: 
  node_type: memory
  type: project
  originSessionId: f72e480c-33de-4520-a54b-3e1a96fe2a9d
  modified: 2026-08-12T10:09:37.934Z
---

The single most productive question to ask of this codebase: **for each recovery, fallback or
retry path — has it ever actually executed?** Not "is it correct", not "is it deployed". Has it run.

Found FIVE separate instances in one session (11–12 Aug 2026), plus two the codebase had already
documented in its own comments:

1. **195 workflow steps** ready, parked on an executor path that only takes low-risk reversible
   EDGE executors that do not notify a human. Most steps name an employee. 0 of 195 executable.
2. **`fn_ai_route`'s confidence arms.** Downgrade at ≥0.95 and escalate below the floor, both
   original, neither ever fired — `p_confidence` is *this* call's confidence and cannot exist
   before the call.
3. **`exec_review`'s 140s timeout.** `run_all` ran six officers in series (up to 289.8s of model
   time), so 25 of 40 dispatches timed out; `max_attempts: 1` made each one permanent.
4. **`cos_execute`'s stale reclaim.** `if (batch.length < MAX_TASKS)` — it takes the slots the
   assigned queue leaves over, and with 340 assigned the head always fills both. 48 tasks sat
   `in_progress` for up to six days; none was at MAX_ATTEMPTS.
5. **`fn_delete_proposer` reopening decided proposals** seconds after they were answered, because
   it only looked for an OPEN row of that category.

Two more on 12 Aug 2026, both on the revenue path, both reporting success daily:

6. **`backfill_invite_trades` (cron 120).** Computes exactly the right expression but filters
   `where invite_trades is null`. The 17,028 rows holding the WRONG trade vocabulary are not null,
   so it logged `UPDATE 0` every day and could never repair them.
7. **`enrich_capability`'s daily batch.** Selects `approval_status='approved'` AND
   `registration_submitted_at`. Approved suppliers: 0. `registration_submitted_at`: 0 across all
   20,470 leads. It has "succeeded" every day having selected nothing — and it writes
   `leads.capability_summary`, not `supplier_capabilities`, so even a full run leaves the gate and
   the matcher empty.

**A new tell, cheaper than any of the above:** read `cron.job_run_details.return_message`. `UPDATE 0`
or `1 row` repeated every day on a job that is supposed to be draining a backlog IS the signature,
and it costs one query.

Already in the codebase's own comments: the unreachable `model_policy_by_identity` branch in
`fn_ai_route` (guarded by `if not found` after `v_class` had already been rewritten to a value that
IS found), and `fn_kb_route_activation_blocked`.

**Why the 25 existing watcher functions miss all of them.** They detect *failures* and *runner
silence*. These are not failures — the runner ran, succeeded, and did nothing. Do not add a 26th
generic watcher; measure the specific queue.

**How to find them:** count executions of the guarded behaviour over a window and compare against
how often its precondition was true. Zero executions against a precondition that held repeatedly is
the signature. In data terms it usually shows as *a state that should be transient sitting for
days* — `in_progress` for six days, `ready` for weeks, `pending` forever.

**Related traps that produced wrong diagnoses on the way to these:** pg_net attributes the whole
elapsed time to DNS on any timeout; `action_execution.finished_at - started_at` is the invoker's
dispatch-then-collect cycle, not runtime; `agent_runs.agent` is a JOB name and one function may use
two of them (`cos_execute` logs its per-run row as `chief_of_staff`).

See [[addressed-to-an-identity-nobody-models]] — the sibling pattern, and often the reason the
condition cannot occur.
