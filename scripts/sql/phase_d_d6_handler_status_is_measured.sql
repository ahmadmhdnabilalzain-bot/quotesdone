-- PHASE D · D6 — THE HANDLER STATUS STOPS BEING A CLASSIFICATION AND STARTS BEING A MEASUREMENT.
--
-- THE BRIEF'S WARNING, AND IT WAS AIMED AT SOMETHING REAL IN MY OWN WORK:
--   "Do not mark all 257 handlers implemented merely because their bindings and schemas exist.
--    Every handler status must reflect actual business behavior."
--
-- 236 of the 257 bindings read NEW_DETERMINISTIC_HANDLER. That is true about the OUTPUT — the
-- family handler produces a typed, schema-validated result and the kernel accepts it — and it
-- overstates the BUSINESS EFFECT, because not one handler yet calls a business-object service.
-- D2 built fn_phase_d_object_write and bound all 56 objects; no handler is wired to it.
--
-- Rather than invent an enum value or quietly leave the overstatement, this adds a MEASURED
-- column beside the classification. business_write_wired is computed from the live catalogue —
-- does the executor's source actually reference the object write service — so it cannot drift
-- from the truth by being forgotten. The board then reports the real number, and the closure
-- report quotes the board rather than the status column.
--
-- The eight permitted statuses are unchanged and BLOCKED_DEFECT stays 0, because an unwired
-- business write is not a defect: it is the next increment, and it is now countable.

begin;

alter table public.phase_d_handler_binding
  add column if not exists business_write_wired boolean not null default false;

comment on column public.phase_d_handler_binding.business_write_wired is
  'MEASURED, not declared: true only when the handler for this step actually writes its business '
  'object through a canonical service. phase_d_status describes the handler CLASS; this describes '
  'whether the step has a business effect yet. The two are different questions and were being '
  'answered by one column.';

-- Recomputed from the live executor body, so it is a measurement rather than a stored opinion.
-- Today this sets every row false, which is the honest number.
update public.phase_d_handler_binding b
   set business_write_wired = exists (
         select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.prokind = 'f'
            and p.proname = 'fn_phase_d_handler_execute'
            and pg_get_functiondef(p.oid) like '%fn_phase_d_object_write%')
       and b.business_object_writes <> '{}';

-- ---------------------------------------------------------------- the board learns to say it
create or replace function public.fn_phase_d_handler_state()
returns table(check_name text, expected text, actual text, ok boolean)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare n_steps int; n_bound int; n_amb int; n_sch int; n_drift int; n_blocked int; n_def int;
        n_wired int; n_needwrite int;
begin
  select count(*) into n_steps from public.phase_b_workflow_step;
  select count(*) into n_bound from public.phase_d_handler_binding;

  check_name := 'every_frozen_step_has_a_handler_binding';
  expected := n_steps::text; actual := n_bound::text; ok := (n_bound = n_steps); return next;

  select count(*) into n_amb from public.phase_d_handler_binding b
   where not exists (select 1 from public.phase_b_workflow_step s where s.step_id = b.step_id);
  check_name := 'no_binding_for_an_unfrozen_step';
  expected := '0'; actual := n_amb::text; ok := (n_amb = 0); return next;

  select count(*) into n_sch from public.phase_d_handler_schema;
  check_name := 'two_schemas_per_step';
  expected := (n_steps * 2)::text; actual := n_sch::text; ok := (n_sch = n_steps * 2); return next;

  select count(*) into n_drift from public.phase_d_handler_schema sc
    join public.phase_b_workflow_step s on s.step_id = sc.step_id
   where sc.source_digest <> encode(sha256(convert_to(
           case sc.schema_kind
             when 'input' then coalesce(s.required_inputs,'')
             else coalesce(s.required_output,'') || ' || ' || coalesce(s.acceptance_criteria,'')
           end, 'UTF8')), 'hex');
  check_name := 'no_schema_drift_against_frozen_phase_b';
  expected := '0'; actual := n_drift::text; ok := (n_drift = 0); return next;

  select count(*) into n_blocked from public.phase_d_handler_binding
   where phase_d_status = 'BLOCKED_DEFECT';
  check_name := 'blocked_defects';
  expected := '0'; actual := n_blocked::text; ok := (n_blocked = 0); return next;

  select count(*) into n_def
    from public.phase_d_handler_binding b
    join public.kernel_retired_path rp
      on b.handler_routine like '%' || rp.path_name || '%'
   where rp.disposition = 'DISABLED';
  check_name := 'no_binding_names_a_retired_routine';
  expected := '0'; actual := n_def::text; ok := (n_def = 0); return next;

  -- THE HONEST ONE. Red until a handler actually writes its business object. This check exists
  -- so the 236 NEW_DETERMINISTIC_HANDLER rows cannot be read as 236 steps with a business effect.
  --
  -- Counted as the GAP, not as the coverage, so the number FALLS as the work lands and the
  -- kernel-boards ratchet can cap it. A check reading "0 of 257 wired" would have to be ratcheted
  -- at a number that must grow, which the ratchet cannot express and which would invert its
  -- meaning: it asserts disclosed debt does not get worse.
  select count(*) into n_wired from public.phase_d_handler_binding where business_write_wired;
  select count(*) into n_needwrite from public.phase_d_handler_binding;
  check_name := 'handlers_not_writing_a_business_object';
  expected := '0'; actual := (n_needwrite - n_wired)::text;
  ok := (n_wired = n_needwrite); return next;
end $fn$;

comment on function public.fn_phase_d_handler_state() is
  'Phase D handler registry board. handlers_writing_a_business_object is RED by disclosure: the '
  'handlers produce a typed, validated output the kernel accepts, and none of them yet writes its '
  'business object through the D2 services. That is the next increment, and it is counted rather '
  'than described.';

commit;
