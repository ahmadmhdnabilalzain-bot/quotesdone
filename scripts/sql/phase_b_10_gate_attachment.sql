-- Phase B — resolve every gate to the steps it actually guards.
--
-- The founder's approval requires that "W22 has an explicit closure step or closure transition,
-- and GATE-008 is attached to it". W22-S07 already carries is_closure_step = true, but GATE-008
-- reached it only through workflow_scope = 'ALL' — which is scope, not attachment. A gate that
-- applies to everything and is anchored to nothing cannot be checked, and cannot be shown to a
-- reader as attached.
--
-- This resolves scope into concrete (gate, workflow, step) rows, and labels each row with HOW it
-- was anchored, so a derived attachment is never displayed as a declared one:
--
--   declared_step_property — the registry itself identifies the step: the closure step for
--                            GATE-008, founder-gated steps for GATE-005, reviewed steps for
--                            GATE-004, handoff-sending steps for GATE-007.
--   universal              — the gate governs every step (owner, single-owner, transition).
--   workflow_scope         — the package scopes the gate to a workflow but declares no finer
--                            anchor, so every step of that workflow carries it.
--   phase_level            — the gate governs the phase, not a step; step_id is null.
--
-- Nothing here invents a gate, a step or an authority. It only makes an existing scope
-- addressable, and it activates nothing.

set lock_timeout = '8s';
set statement_timeout = '600s';

create or replace function public.fn_phase_b_gate_attachment()
returns table(gate_id text, workflow_id text, step_id text, attachment_basis text)
language sql
stable
set search_path = public, pg_temp
as $$
  with scoped as (
    -- expand workflow_scope; 'ALL' means every canonical workflow. Both ';' and '/' appear as
    -- separators across the package's registries, so both are split on.
    select g.gate_id, g.gate_name, g.gate_type, w.workflow_id
    from public.phase_b_gate g
    join public.phase_b_workflow w
      on g.workflow_scope = 'ALL'
      or w.workflow_id = any (string_to_array(replace(g.workflow_scope, '/', ';'), ';'))
  )
  -- gates that govern the phase rather than a step
  select s.gate_id, s.workflow_id, null::text, 'phase_level'
  from scoped s
  where s.gate_type = 'phase_boundary' or s.gate_id = 'GATE-001'

  union all
  -- GATE-008 closure completeness -> the workflow's closure step
  select s.gate_id, s.workflow_id, st.step_id, 'declared_step_property'
  from scoped s
  join public.phase_b_workflow_step st on st.workflow_id = s.workflow_id and st.is_closure_step
  where s.gate_id = 'GATE-008'

  union all
  -- GATE-005 founder boundary -> steps that carry a founder gate
  select s.gate_id, s.workflow_id, st.step_id, 'declared_step_property'
  from scoped s
  join public.phase_b_workflow_step st on st.workflow_id = s.workflow_id
   and st.founder_gate is not null and lower(st.founder_gate) <> 'none'
  where s.gate_id = 'GATE-005'

  union all
  -- GATE-004 creator/reviewer separation -> steps that carry an independent reviewer
  select s.gate_id, s.workflow_id, st.step_id, 'declared_step_property'
  from scoped s
  join public.phase_b_workflow_step st on st.workflow_id = s.workflow_id
   and st.independent_reviewer_role_id is not null
  where s.gate_id = 'GATE-004'

  union all
  -- GATE-007 complete handoff -> steps that send one
  select distinct s.gate_id, s.workflow_id, h.from_step_id, 'declared_step_property'
  from scoped s
  join public.phase_b_handoff h on h.workflow_id = s.workflow_id
  where s.gate_id = 'GATE-007'

  union all
  -- gates that govern every step
  select s.gate_id, s.workflow_id, st.step_id, 'universal'
  from scoped s
  join public.phase_b_workflow_step st on st.workflow_id = s.workflow_id
  where s.gate_id in ('GATE-002','GATE-003','GATE-006')

  union all
  -- workflow-scoped gates with no finer anchor declared in the package
  select s.gate_id, s.workflow_id, st.step_id, 'workflow_scope'
  from scoped s
  join public.phase_b_workflow_step st on st.workflow_id = s.workflow_id
  where s.gate_id not in ('GATE-001','GATE-002','GATE-003','GATE-004','GATE-005',
                          'GATE-006','GATE-007','GATE-008')
    and s.gate_type <> 'phase_boundary';
$$;

comment on function public.fn_phase_b_gate_attachment() is
  'Resolves every gate to the steps it guards, labelling each row with how it was anchored so a derived attachment is never read as a declared one.';

-- ------------------------------------------------------------- effective errata resolution
-- One reader for the founder's three approval conditions, answerable by query rather than by
-- reading a document.  Each row states the condition, what was measured, and whether it holds.
create or replace function public.fn_phase_b_effective_errata()
returns table(erratum text, condition text, measured text, resolved boolean)
language sql
stable
set search_path = public, pg_temp
as $$
  select 'EX-006',
         'exception is complete: escalation owner, required response and closure condition present, and escalation is independent of detection',
         format('escalation=%s detection=%s response=%s closure=%s',
                e.escalation_owner_role_id, e.detection_owner_role_id,
                case when e.required_response <> '' then 'present' else 'MISSING' end,
                case when e.closure_condition <> '' then 'present' else 'MISSING' end),
         e.escalation_owner_role_id <> '' and e.required_response <> ''
           and e.closure_condition <> '' and e.escalation_owner_role_id <> e.detection_owner_role_id
  from public.phase_b_exception e where e.exception_id = 'EX-006'

  union all
  select 'W13',
         'primary business object references an existing canonical object',
         format('primary_object=%s exists=%s', w.primary_object, (o.object_id is not null)),
         o.object_id is not null
  from public.phase_b_workflow w
  left join public.phase_b_business_object o on o.object_id = w.primary_object
  where w.workflow_id = 'W13'

  union all
  select 'W22',
         'workflow has exactly one explicit closure step, it is the step reaching WORKFLOW_COMPLETE, and GATE-008 is attached to it',
         format('closure_steps=%s reaches_complete=%s gate_008_attached_to=%s',
                (select count(*) from public.phase_b_workflow_step where workflow_id='W22' and is_closure_step),
                (select bool_and(next_step_if_pass = 'WORKFLOW_COMPLETE')
                   from public.phase_b_workflow_step where workflow_id='W22' and is_closure_step),
                coalesce((select string_agg(a.step_id, ',') from public.fn_phase_b_gate_attachment() a
                           where a.gate_id='GATE-008' and a.workflow_id='W22'), 'NONE')),
         (select count(*) from public.phase_b_workflow_step where workflow_id='W22' and is_closure_step) = 1
         and (select bool_and(next_step_if_pass = 'WORKFLOW_COMPLETE')
                from public.phase_b_workflow_step where workflow_id='W22' and is_closure_step)
         and exists (select 1 from public.fn_phase_b_gate_attachment() a
                      where a.gate_id='GATE-008' and a.workflow_id='W22' and a.step_id is not null);
$$;

comment on function public.fn_phase_b_effective_errata() is
  'The three founder-stated erratum conditions, each answered from the live registry.';

-- Verify by reading it back: all three must resolve, and GATE-008 must reach every workflow's
-- closure step, not merely be scoped to them.
do $$
declare v_unresolved bigint; v_missing bigint;
begin
  select count(*) into v_unresolved from public.fn_phase_b_effective_errata() where not resolved;
  if v_unresolved > 0 then
    raise exception 'phase_b: % erratum condition(s) unresolved', v_unresolved;
  end if;

  select count(*) into v_missing
  from public.phase_b_workflow w
  where not exists (select 1 from public.fn_phase_b_gate_attachment() a
                     where a.gate_id = 'GATE-008' and a.workflow_id = w.workflow_id
                       and a.step_id is not null);
  if v_missing > 0 then
    raise exception 'phase_b: GATE-008 is not attached to a closure step in % workflow(s)', v_missing;
  end if;
end $$;
