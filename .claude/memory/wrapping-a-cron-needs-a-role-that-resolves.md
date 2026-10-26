---
name: wrapping-a-cron-needs-a-role-that-resolves
description: a wrapped kernel cron fails every tick unless its accountable_role_id resolves in org_role; fn_kernel_wrap_and_enable_cron early-returns without updating the role on re-wrap
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T01:36:18.926Z
---

3 Sep 2026. Enabling a cron via `fn_kernel_wrap_and_enable_cron(jobid, role, dept)` stores the role
in `phase_c_component.accountable_role_id` (keyed by component_id = 'cron:'||jobname). At every tick
`fn_kernel_cron_exec` → `fn_kernel_system_execution_trace` RAISES 23514 "accountable role X does not
resolve in org_role. A system execution with no accountable role is an action nobody owns" unless
that role is a real `org_role.role_id`. So a cron wrapped with a made-up role name (I used
`ops_director`, `qa_manager`, and one pre-existing one was `brief`) is WORSE than disabled — it errors
hourly and shows up as a cron failure.

**Why:** valid roles are `org_role.role_id` values (176 of them), e.g. `corporate_performance_director`,
`quality_and_release_director`, `chief_operating_officer`, `chief_of_staff`, `ceo`, `cfo` — NOT the
loose department-title names. Check with `select role_id, primary_department_id from org_role`.

**THE ROLE IS ALREADY DECIDED — use the crosswalk, don't invent.** `docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv` carries the committed accountable_role_id + department_id for every `cron:*` component. Enabling a cron with a role of your own choosing drifts from it and reddens TWO CI checks — "the database is running what this repository says" and phase_c_invariants (inside "the Phase C kernel gate"). Before wrapping/enabling a cron, read its crosswalk row and use THAT role. A cron the crosswalk does not carry must also get a literal declaration (a committed `insert into public.phase_c_component`) — a non-literal insert...select via the wrap fn does not count — plus its CSV row, or phase_c_invariants fails "db-only cron:<name>". (Learned 3 Sep 2026 the hard way — cost a red PR.)

**How to apply:** (1) pass the crosswalk's role_id when wrapping. (2) CRUCIAL: `fn_kernel_wrap_and_enable_cron`
EARLY-RETURNS 'already_wrapped_activated' when the job's command already calls fn_kernel_cron_exec, and
in that path it does NOT update the role — so re-calling it to "fix" a role is a no-op. To correct a
role on an already-wrapped cron you must UPDATE `phase_c_component` directly:
`update phase_c_component c set accountable_role_id=..., department_id=... from
phase_c_system_execution_wrapper w where w.jobid=<jobid> and c.component_id=w.component_id`.
(3) audit with: active wrapped crons whose accountable_role_id has no matching org_role.role_id → must
be zero. See [[enable_self_management_crons.sql]] for the reproducible pattern + in-file guard.
Related: [[deactivation-is-not-death]], [[cron-command-no-longer-names-the-routine]].
