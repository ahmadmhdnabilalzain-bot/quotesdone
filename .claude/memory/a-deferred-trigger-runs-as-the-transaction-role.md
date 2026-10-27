---
name: a-deferred-trigger-runs-as-the-transaction-role
description: "A DEFERRABLE INITIALLY DEFERRED constraint trigger fires at COMMIT, when the SECURITY DEFINER context is gone, so it runs as the caller's role."
metadata: 
  node_type: memory
  type: project
  originSessionId: 12007385-5c1a-4596-9522-d83edb00dcb7
  modified: 2026-08-25T00:58:08.295Z
---

`z90_system_execution_pair_guard` on `public.phase_c_trace` was SECURITY INVOKER and deferred. At
COMMIT the SECURITY DEFINER function that opened the transaction has long returned, so the trigger
ran as the TRANSACTION's role — `authenticated` for anything PostgREST handles. `authenticated` has
no SELECT on `phase_c_trace`, so it raised `42501` before reading anything it exists to check.
PostgREST returns 42501 as **403**.

Every founder governance decision routed through `asCaller(authHeader)` — which is exactly what
PCCR-003 required — had been failing at COMMIT since PCCR-003 was applied. Found 25 Aug 2026 when
the founder's PCCR-006 approval was audit-logged and then vanished. Fixed by
`scripts/sql/phase_d_q01_a_deferred_guard_that_ran_as_the_caller.sql`; its two siblings
(`fn_phase_c_task_trace_committed`, `fn_phase_c_step_run_trace_committed`) were already
`prosecdef = true`.

**Why:** an ordinary aborted-transaction probe NEVER FIRES a deferred trigger, so the probe passes
and production fails. The probe and the reality differ by one statement.

**How to apply:** add `set constraints all immediate` before the final `raise exception` in any
aborted-transaction probe — it fires the deferred triggers exactly as COMMIT would while the
transaction is still abortable. And when auditing a guard, check `pg_trigger.tgdeferrable` against
`pg_proc.prosecdef`: a deferred trigger whose function is SECURITY INVOKER can only work for roles
that hold the grants directly. Related: [[a-guard-that-fires-when-the-system-works]],
[[security-definer-guard-reads-its-own-identity]], [[a-raising-trigger-makes-a-table-enforcing]].
