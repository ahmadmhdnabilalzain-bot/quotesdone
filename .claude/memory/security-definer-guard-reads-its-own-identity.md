---
name: security-definer-guard-reads-its-own-identity
description: A SECURITY DEFINER guard testing current_user compares the owner against itself and is always true; use SECURITY INVOKER and isolate the one privileged act.
metadata:
  type: project
---

`fn_kernel_write_guard`'s maintenance door was `if v_reason is not null and current_user = v_owner`.
The guard was SECURITY DEFINER owned by postgres, so **current_user inside it was always the owner**
— the test compared the owner against itself. The door reduced to "state any reason and pass", and
any Edge Function with the service key could write `phase_c_workflow_run`, `phase_c_task` or the
founder's refund ledger by adding one `set local kernel.maintenance_reason`.

**Why:** SECURITY DEFINER rebinds `current_user` to the definer. Any identity check inside one is
checking the function, not the caller.

**How to apply:** make the guard **SECURITY INVOKER** so `current_user` is the real caller, and move
the one privileged act (here, writing the audit row) into a separate SECURITY DEFINER helper called
only *after* the check passes. Grant EXECUTE on the invoker guard to the writing roles — that grants
the right to be judged, not to write. Not `session_user`: under PostgREST it is `authenticator`, so
it refuses correctly in production but a test cannot tell it from postgres.

**And test as the role, not as yourself.** This was invisible until the check ran under
`set local role service_role`. Testing as postgres — which owns the tables — proves the guard
against the one identity it is least meant to stop. See [[a-guard-that-reads-a-shadowed-table]] and
[[a-rehearsal-proves-creation-not-execution]]. Fixed in `scripts/sql/kernel_k37_guard_sees_the_real_caller.sql`.
