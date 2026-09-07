-- E20 — four instruments that named the wrong thing
--
-- Findings 10, 12, 16 and 17 of the 2026-08-20 independent acceptance, each closed by making the
-- instrument report on the subject its name claims.
--
-- ---- 10. A CHECK NAMED AFTER A WRITE, COMPUTED FROM A STORED BOOLEAN --------------------------
-- `handlers_not_writing_a_business_object = 0` was `count(*) where business_write_wired`. That
-- column records that a binding DECLARES a business write; it is not a write. E10 added a comment
-- saying so and a second row counting effects, which stopped a reader being misled but left the
-- check asserting something untrue in its own name. Renamed to what it computes. The second row
-- stays, and a third is added for what it can now measure that it could not on 19 August: after E14
-- a step CAN reach EXECUTED, so "declared" and "run" are two ends of a real range rather than one
-- number and an aspiration.
--
-- ---- 12. AN EXPLANATION TYPED IN BESIDE A COMPUTED NUMBER ------------------------------------
-- `fn_phase_d_rule_can_refuse()` computed `can_refuse` honestly and then explained it with
-- `when r.rule_id = 'BR-028' then ...` and `when r.rule_id in ('BR-053','BR-054') then ...`. If one
-- of those three started or stopped refusing, the note would print the same excuse. Both branches
-- are now derived from `phase_d_rule_enforcement`, which is where the fact actually lives:
--   * EXECUTOR_ENFORCED -> "enforced at <enforcement_point>, which is not this predicate" (BR-028)
--   * the same state under every context AND no required_context -> "reads no call context at all;
--     its verdict comes from <enforcement_point>, which is estate state" (BR-053, BR-054)
-- No rule id appears in the function any more. Verified after apply by reading the rows: the three
-- notes must still be the right ones, arrived at without naming the rules.
--
-- ---- 16. A READER THAT BELIEVED WHOEVER CALLED IT --------------------------------------------
-- `fn_phase_d_object_read` is SECURITY DEFINER and took `caller_ref` verbatim from its input, so the
-- owner scoping it performs was scoping to whoever the caller SAID they were. E4 revoked it from
-- anon and authenticated, so today only service_role reaches it — the finding's own words were
-- "bounded by the service_role grant alone", and a grant is not an identity check.
--
-- It now derives the caller from the verified JWT the same way `fn_customer_document_refs` does —
-- `auth.email()` / `auth.uid()` against `public.customers`, and `public.leads` for a supplier — and
-- accepts a supplied `caller_ref` ONLY when there is no end-user JWT at all, which is the
-- service_role case. A JWT that resolves to somebody, plus a `caller_ref` naming somebody else, is
-- refused rather than silently honoured. Reading who you are must not be something the caller
-- tells you.
--
-- ---- 17. THIRTY VIEWS CLOSED BY GRANT ALONE --------------------------------------------------
-- All 30 `v_obj_*` views had `security_invoker` off, so they ran with the view owner's rights and
-- were closed only by their own grants. Turning it on makes the caller's own privileges apply to
-- `phase_d_object_record` underneath. Nothing that legitimately reads them loses access —
-- service_role holds the table privilege — and anon and authenticated, who hold neither the view
-- grant nor the table grant, are now refused twice instead of once. A definer view handing back what
-- the table withheld is a shape this estate has already been caught by, in E8.

-- ---------------------------------------------------------------------------------------------
-- 17 first: DDL only, no routine depends on it.
do $$
declare v record; n int := 0;
begin
  for v in select c.relname from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
            where ns.nspname = 'public' and c.relkind = 'v' and c.relname like 'v\_obj\_%'
            order by c.relname
  loop
    execute format('alter view public.%I set (security_invoker = true)', v.relname);
    n := n + 1;
  end loop;
  if n <> 30 then
    raise exception 'E20: expected 30 v_obj_ views, altered %. The population moved; re-measure before assuming this file covered it.', n;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_rule_can_refuse()
 RETURNS TABLE(rule_id text, refusing_context text, states text, can_refuse boolean, note text)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_full jsonb; v_held jsonb; v_overlay text;
  r record; e public.phase_d_rule_enforcement%rowtype; s1 text; s2 text; s3 text;
begin
  select ob.overlay_id into v_overlay from public.phase_c_overlay_binding ob order by 1 limit 1;

  -- (2) everything named, including the authority that permits it
  v_full := jsonb_build_object(
    'accountable_role_id','rfq_qualification_manager','actor_role_id','rfq_qualification_manager',
    'reviewer_role_id','inquiry_quality_analyst','step_id','W05-S01','workflow_id','W05',
    'run_id', 1, 'founder_gate','NONE','execution_context','production',
    'evidence_refs', jsonb_build_array('e1'), 'assumptions', jsonb_build_array('a real assumption'),
    'formula','numerator/denominator','denominator', 2, 'numerator', 1,
    'inquiry_owner','rfq_qualification_manager','evidence_authority','A NEW_WORK_REQUEST',
    'commercial_policy_change','raise reveal fee','founder_authority_ref','founder_command:1',
    'policy_exception','waive fee','exception_authority_ref','founder_command:1',
    'sla_policy_id', (select sp.sla_policy_id from public.phase_b_sla_policy sp order by 1 limit 1),
    'handoff_id', (select hc.handoff_id from public.phase_d_handoff_contract hc order by 1 limit 1),
    'packet', '{}'::jsonb);

  -- (3) the same subjects with the AUTHORITY WITHHELD, and an actor that resolves to an overlay.
  -- This is the context the first two could not express, and it is where six of the seven refuse.
  v_held := (v_full - 'founder_authority_ref' - 'exception_authority_ref')
            || jsonb_build_object('actor_role_id', coalesce(v_overlay,'rfq_qualification_manager'));

  for r in select br.rule_id from public.phase_b_business_rule br order by br.rule_id loop
    select rc.state into s1 from public.fn_phase_d_rule_check(r.rule_id, '{}'::jsonb) rc limit 1;
    select rc.state into s2 from public.fn_phase_d_rule_check(r.rule_id, v_full)      rc limit 1;
    select rc.state into s3 from public.fn_phase_d_rule_check(r.rule_id, v_held)      rc limit 1;
    select * into e from public.phase_d_rule_enforcement en where en.rule_id = r.rule_id;

    rule_id := r.rule_id;
    states  := format('empty=%s full=%s authority_withheld=%s', s1, s2, s3);
    can_refuse := 'ENFORCED_FAIL' in (s1, s2, s3);
    refusing_context := case
      when s1 = 'ENFORCED_FAIL' then 'empty'
      when s3 = 'ENFORCED_FAIL' then 'authority_withheld'
      when s2 = 'ENFORCED_FAIL' then 'full'
      else '(none)' end;
    -- E20. DERIVED FROM THE ENFORCEMENT ROW, NEVER FROM A RULE ID. The prior body matched
    -- 'BR-028' and 'BR-053'/'BR-054' as literals, so the excuse would have printed unchanged if any
    -- of them had started or stopped refusing. Every branch below reads a column.
    note := case
      when can_refuse then 'a context producing ENFORCED_FAIL exists'
      when s1 = 'DELEGATED_TO_KERNEL_GUARD' then 'delegated: the kernel guard decides, this predicate cannot invoke it'
      when e.rule_id is null then 'this rule has no row in phase_d_rule_enforcement, so nothing here can explain it'
      when e.enforcement_kind = 'EXECUTOR_ENFORCED'
        then format('enforced at %s, which is not this predicate; the predicate is not where this rule refuses',
                    coalesce(e.enforcement_point,'(unstated)'))
      when s1 = s2 and s2 = s3 and coalesce(cardinality(e.required_context),0) = 0
        then format('constant under every context tried, and it must be: this rule declares no required_context, so its verdict comes from %s — estate state, not the call. It will vary when that does.',
                    coalesce(e.enforcement_point,'(unstated)'))
      else 'NO CONTEXT PRODUCED A REFUSAL — this rule cannot fail' end;
    return next;
  end loop;
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_object_read was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


CREATE OR REPLACE FUNCTION public.fn_phase_d_handler_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n_steps int; n_bound int; n_amb int; n_sch int; n_drift int; n_blocked int; n_def int;
        n_produced int;
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
  -- E20 / finding 10. RENAMED TO WHAT IT COMPUTES. It reads business_write_wired, a stored boolean
  -- that records a binding DECLARING a business write. A declaration is not a write, and a check
  -- whose name says "not writing" while its body counts a column asserts something untrue about
  -- itself. E10 added a comment saying so; the name still said the other thing.
  check_name := 'handler_bindings_that_declare_no_business_write';
  expected := '0'; actual := (n_needwrite - n_wired)::text
           || ' of ' || n_needwrite::text || ' (source: phase_d_handler_binding.business_write_wired, '
           || 'a declaration; see handlers_that_have_actually_produced_an_effect below for writes)';
  ok := (n_needwrite - n_wired = 0); return next;

  -- E10. WHAT THAT ZERO IS, AND WHAT IT IS NOT. It is derived from the handler's declared call to
  -- fn_phase_d_effect_produce plus a stored boolean — a statement that the PATH EXISTS. It is not a
  -- statement that any handler has ever written a business object, and the two read identically at
  -- a glance because both are the number 0 beside a green tick.
  -- The question it does not answer is on fn_phase_d_effect_state as
  -- steps_with_no_effect_ever_produced, which reads 257 and is this phase's only red. Both numbers
  -- are quoted here so a reader of this board cannot take the green one for the other.
  select count(distinct step_id) into n_produced from public.phase_d_effect_ledger;

  check_name := 'handlers_that_have_actually_produced_an_effect';
  expected := 'informational — the green above says the path EXISTS, this says whether it has RUN';
  actual := n_produced::text || ' of ' || n_steps::text
         || ' steps have ever produced an effect; see fn_phase_d_effect_state.'
         || 'steps_with_no_effect_ever_produced for what holds the remainder';
  ok := true; return next;
end $function$;
