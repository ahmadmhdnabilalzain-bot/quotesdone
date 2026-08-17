# K4 — cancellation service: aborted-transaction rehearsal

Run the migration and these probes in ONE transaction that ends in `raise exception`, so production
is untouched. The probes use the real orphans the audit found, not a synthetic fixture.

```sql
begin;
\i scripts/sql/kernel_k4_cancellation.sql
-- then the probe block below
rollback;   -- or let the raise abort it
```

## Probe block

```sql
do $probe$
declare v jsonb; s text := '';
begin
  -- STATE BEFORE: the orphans the audit measured
  s := s || 'before_live_task_794=' || (select state from public.phase_c_task where task_id = 794) || ' | ';
  s := s || 'before_live_run_96='   || (select state from public.phase_c_workflow_run where run_id = 96) || ' | ';
  s := s || 'before_cmd_227='       || (select state from public.founder_command where command_id = 227) || ' | ';

  -- 1. a cancel with no reason is refused
  begin
    v := public.fn_kernel_cancel(jsonb_build_object(
           'subject_kind','workflow_run','subject_ref','96','actor','audit:rehearsal'));
    s := s || 'NO_REASON_ACCEPTED=BAD | ';
  exception when others then s := s || 'no_reason_refused=' || sqlstate || ' | '; end;

  -- 2. a founder-command cancel by a non-founder is refused (K0 verifier, second caller)
  begin
    v := public.fn_kernel_cancel(jsonb_build_object(
           'subject_kind','founder_command','subject_ref','223','reason','probe',
           'actor','nobody@nowhere.test'));
    s := s || 'NON_FOUNDER_ACCEPTED=BAD | ';
  exception when others then s := s || 'non_founder_refused=' || sqlstate || ' | '; end;

  -- 3. the real repair: run 96, orphaned by cancelled command 227
  v := public.fn_kernel_cancel(jsonb_build_object(
         'subject_kind','workflow_run','subject_ref','96',
         'reason','orphaned by the cancellation of founder_command 227 on 16 Aug 2026; '
               || 'the old cancellation reached the command and its command-scoped tasks only',
         'actor','kernel:k4:rehearsal'));
  s := s || 'run96_ok=' || (v->>'ok') || ' closed=' || (v->'closed')::text || ' | ';
  s := s || 'after_task_794=' || (select state from public.phase_c_task where task_id = 794) || ' | ';
  s := s || 'after_run_96='   || (select state from public.phase_c_workflow_run where run_id = 96) || ' | ';
  s := s || 'after_step_41='  || (select state from public.phase_c_workflow_step_run where step_run_id = 41) || ' | ';

  -- 4. idempotent: a second cancel of the same run closes nothing and still returns ok
  v := public.fn_kernel_cancel(jsonb_build_object(
         'subject_kind','workflow_run','subject_ref','96','reason','second call','actor','kernel:k4'));
  s := s || 'second_call_ok=' || (v->>'ok') || ' closed_tasks=' || (v->'closed'->>'tasks') || ' | ';

  -- 5. the orphan invariant, before and after
  s := s || 'orphan_checks_failing=' ||
       (select count(*) from public.fn_kernel_orphaned_work() where not ok)::text || ' | ';

  -- 6. a full founder-command cancel, propagating to its run (command 223 -> run 97)
  v := public.fn_kernel_cancel(jsonb_build_object(
         'subject_kind','founder_command','subject_ref','223',
         'reason','K4 rehearsal: prove the propagation reaches the run and the run-scoped task',
         'actor','management@quotesdone.com'));
  s := s || 'cmd223_ok=' || (v->>'ok') || ' closed=' || (v->'closed')::text || ' | ';
  s := s || 'after_run_97='  || (select state from public.phase_c_workflow_run where run_id = 97) || ' | ';
  s := s || 'after_task_795='|| (select state from public.phase_c_task where task_id = 795) || ' | ';
  s := s || 'after_cmd_223=' || (select state from public.founder_command where command_id = 223) || ' | ';
  s := s || 'orphan_checks_failing_after=' ||
       (select count(*) from public.fn_kernel_orphaned_work() where not ok)::text;

  raise exception 'K4 REHEARSAL % ', s;
end $probe$;
```

## What each probe must answer

| Probe | Required |
|---|---|
| no reason | refused `23514` |
| non-founder cancelling a founder command | refused `28000` |
| run 96 cancel | `ok=true`, task 794 `cancelled`, run 96 `cancelled`, step run 41 `cancelled` |
| second cancel | `ok=true`, `closed_tasks=0` — idempotent, not an error |
| command 223 cancel | `ok=true`, command `cancelled`, run 97 `cancelled`, task 795 `cancelled` |
| orphan invariant after | `0` failing checks |

The postcondition inside `fn_kernel_cancel` raises `23514` if any queued derived work survives, so a
successful return is itself the proof — there is no way for it to return `ok:true` over a missed row.
