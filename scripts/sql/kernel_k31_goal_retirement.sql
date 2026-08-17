-- K31 — goal retirement, resolved truthfully. §3, option B.
--
-- THE CHOICE, AND WHY IT IS NOT A.
--
-- `trg_goal_cascade` fires on `old.active is true and new.active is false` — a company goal being
-- RETIRED. K10 mapped it to kpi.company_target_miss -> W02 "Company target miss and corrective
-- management". A retired goal is not a missed target. Routing it there would open a corrective-
-- management run every time the founder tidies up a goal he no longer wants, which is a workflow
-- run manufactured by a misreading, and §3 forbids exactly that.
--
-- Option A would need goal retirement to belong to an existing objective or workflow lifecycle.
-- It does not. W01 "Founder mandate to company objectives" starts from a founder MANDATE, not from
-- a retirement, and no other workflow of the thirty declares the behaviour. There is no existing
-- run to signal, because nothing opens one for a goal.
--
-- So: option B. No founder-approved Phase B workflow currently defines this business behaviour.
--
-- WHAT THE BYPASS ACTUALLY IS, and it is one statement, not the whole trigger.
--
-- The trigger does three things when a goal is retired:
--
--   1. supersedes the department_objective rows serving that goal
--   2. INSERTS an org_tasks row per affected department asking it to re-plan
--   3. calls fn_emit_event('goal.retired', ...) inside a try/catch
--
-- Only (2) is a kernel bypass: it creates operational work for a department with no workflow run,
-- no step, no accountable owner resolved through the kernel and no trace. (1) is the objective
-- lifecycle correcting itself — superseding an objective that serves a retired goal is bookkeeping
-- on the goal's own record, not the creation of work. (3) writes no canonical outbox row —
-- measured: fn_emit_event's body does not name phase_c_event_outbox — so it is a legacy notice,
-- not a duplicate domain event.
--
-- This file disables (2) and leaves (1) and (3) exactly as they are. Disabling the whole trigger
-- would leave objectives pointing at a goal that no longer exists, which is worse than the defect.
--
-- WHAT IS LOST, said plainly. Departments stop being asked to re-plan when a goal is retired.
-- Measured before writing this: `org_tasks` contains ZERO rows titled 'Re-plan after goal retired'
-- — the branch has never produced one, so nothing that exists today stops working. The behaviour
-- is recorded as owed in phase_b_phase_c_wiring_gap so it is a claim on the next phase rather than
-- a silence, and the statement is kept in the body, commented, so a reader can see what was
-- removed rather than inferring it from a gap.
--
-- Rollback: scripts/sql/rollback/kernel_k31_goal_retirement.rollback.sql

begin;

create or replace function public.trg_goal_cascade()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k31_goal$
begin
  if old.active is true and new.active is false then
    -- (1) KEPT. An objective serving a retired goal is superseded. This is the goal's own record
    -- being made consistent, not the creation of work, and leaving it out would strand objectives
    -- against a goal that no longer exists.
    update department_objective
       set status='superseded', updated_at=now()
     where goal_key = new.key and status='active';

    -- (2) DISABLED BY K31 — this was the bypass. It created an operational task per affected
    -- department, with no workflow run, no step, no accountable owner resolved through the kernel
    -- and no trace. No Phase B workflow starts from a goal retirement, so there is nowhere honest
    -- to route it; inventing a workflow to obtain a connected count is what §3 forbids. The
    -- statement is left here, commented, so a reader sees what was removed:
    --
    --   insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    --   select distinct o.dept_key,
    --          'Re-plan after goal retired: '||new.key,
    --          'Company goal "'||coalesce(new.goal,new.key)||'" was retired. Objectives serving it
    --           are now superseded. Propose replacement objectives that serve an active goal.',
    --          'proposed','advisory', false, 'coordinate'
    --     from department_objective o
    --    where o.goal_key = new.key and o.status='superseded'
    --      and not exists (select 1 from org_tasks t
    --                       where t.title='Re-plan after goal retired: '||new.key and t.status<>'done');
    --
    -- It had never produced a row: org_tasks held zero 'Re-plan after goal retired' titles when
    -- this was written. The owed behaviour is recorded in phase_b_phase_c_wiring_gap.

    -- (3) KEPT. fn_emit_event does not write phase_c_event_outbox — measured, not assumed — so
    -- this is a legacy notice and not a second copy of a canonical domain event.
    begin
      perform fn_emit_event('goal.retired','company_goals',new.key,'ceo',
                            jsonb_build_object('goal',new.key));
    exception when others then null; end;
  end if;
  return new;
end
$k31_goal$;

comment on function public.trg_goal_cascade() is
  'Goal retirement. K31: the org_tasks re-plan insert is disabled — it created operational work '
  'with no run, no step, no kernel-resolved owner and no trace, and no Phase B workflow starts '
  'from a goal retirement. Objective supersession and the legacy notice are kept. The owed '
  'behaviour is recorded in phase_b_phase_c_wiring_gap.';

-- ------------------------------------------------------------------ the owed behaviour, recorded
insert into public.phase_b_phase_c_wiring_gap (gap, measurement, evidence_command)
values (
  'no Phase B workflow defines what happens when a company goal is retired',
  'trg_goal_cascade fires on old.active true -> new.active false and superseded the department '
  'objectives serving that goal, then created an org_tasks re-plan row per affected department. '
  'That task creation was a kernel bypass and K31 disabled it on 2026-08-17. None of the thirty '
  'workflows starts from a goal retirement: W01 starts from a founder mandate and W02 from a '
  'material KPI or trajectory miss, which a deliberate retirement is not. Until a workflow '
  'declares the behaviour, retiring a goal supersedes its objectives and asks nobody to re-plan.',
  'select prosrc from pg_proc where proname = ''trg_goal_cascade''')
on conflict (gap) do update set
  measurement = excluded.measurement, evidence_command = excluded.evidence_command;

-- ------------------------------------------------------------------ the register says so
update public.phase_c_source_cutover
   set source_class = 'D RETIRE_OR_HISTORICAL',
       target_kernel_adapter = 'none — this class may not create business work',
       target_workflow = 'none',
       target_step_or_signal = 'none',
       idempotency_key = 'n/a — creates nothing to deduplicate',
       trace_policy = 'TRACE-MONITORING',
       status = 'BUSINESS_SIDE_EFFECT_DISABLED_BEHAVIOUR_OWED',
       cutover_action = 'The org_tasks re-plan insert is disabled: it created operational work '
                     || 'outside the kernel and no Phase B workflow starts from a goal '
                     || 'retirement. Objective supersession and the legacy notice are kept. The '
                     || 'owed behaviour is recorded in phase_b_phase_c_wiring_gap.',
       classification_reason = classification_reason
         || ' | K31 2026-08-17: resolved under §3 option B. Not routed to W02 — a retired goal is '
         || 'not a missed target, and routing it there would open a corrective-management run '
         || 'every time the founder tidies up a goal. Option A was rejected because no existing '
         || 'objective or workflow lifecycle owns goal retirement: W01 starts from a founder '
         || 'mandate, and nothing opens a run for a goal. The trigger keeps its historical '
         || 'definition; only the task-creating statement is disabled, and it is left in the body '
         || 'commented so what was removed is visible.'
 where source_component_id = 'dbtrigger:public.company_goals:trg_goal_cascade';

commit;
