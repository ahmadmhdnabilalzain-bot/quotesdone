-- =================================================================================================
-- Phase D — D48. A two-context probe cannot find a rule that only refuses a withheld authority.
--
-- D47's fn_phase_d_rule_can_refuse() drove every rule with two contexts — empty, and fully
-- populated — and reported seven rules as unable to fail:
--
--     BR-021 BR-022 BR-023 BR-024 BR-028 BR-043 BR-048
--
-- Six of those seven DO refuse, and D47's own control block proves BR-048 does — it refuses any of
-- the 86 overlay ids. The probe missed them because of what the two contexts are:
--
--     the EMPTY context      names no subject at all, so the rule is not applicable
--     the FULL context       names the subject AND the authority that permits it, so it passes
--
-- The refusal these rules exist for lives between those two: the subject is named and the authority
-- is NOT. BR-021 to BR-024 refuse a commercial_policy_change with no founder_authority_ref; BR-043
-- refuses a policy_exception with no exception_authority_ref; BR-048 refuses an actor that resolves
-- to a category overlay. A probe that never withholds an authority cannot see a rule that only
-- refuses one — which is the same defect as a check whose WHERE clause empties its own denominator,
-- one layer up.
--
-- A third context is added: the full one with the authorities removed and the actor replaced by a
-- real overlay id read from phase_c_overlay_binding. Nothing is invented — the overlay is a live row.
--
-- BR-028 IS DIFFERENT AND STAYS REPORTED SEPARATELY. Its refusal is not in fn_phase_d_rule_check at
-- all: it is the capability boundary in fn_phase_d_handler_execute, which fires when
-- capability_dependency <> 'NONE' and execution_context is not 'test'. 21 of the 257 bindings carry
-- capability_dependency 'REASONING'. Calling that boundary "a rule that cannot fail" would be the
-- instrument reporting on the wrong subject; it is labelled as enforced at the executor, and the
-- board says where.
-- =================================================================================================

-- The return type changes (refusing_context is new), so this is a DROP and CREATE rather than a
-- replace. A fresh CREATE is granted EXECUTE to PUBLIC, which is why the revoke below names public
-- first rather than only anon.
drop function if exists public.fn_phase_d_rule_can_refuse();

create or replace function public.fn_phase_d_rule_can_refuse()
returns table(rule_id text, refusing_context text, states text, can_refuse boolean, note text)
language plpgsql
stable
as $fn$
declare
  v_full jsonb; v_held jsonb; v_overlay text;
  r record; s1 text; s2 text; s3 text;
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

    rule_id := r.rule_id;
    states  := format('empty=%s full=%s authority_withheld=%s', s1, s2, s3);
    can_refuse := 'ENFORCED_FAIL' in (s1, s2, s3);
    refusing_context := case
      when s1 = 'ENFORCED_FAIL' then 'empty'
      when s3 = 'ENFORCED_FAIL' then 'authority_withheld'
      when s2 = 'ENFORCED_FAIL' then 'full'
      else '(none)' end;
    note := case
      when can_refuse then 'a context producing ENFORCED_FAIL exists'
      when s1 = 'DELEGATED_TO_KERNEL_GUARD' then 'delegated: the kernel guard decides, this predicate cannot invoke it'
      when r.rule_id = 'BR-028' then 'enforced at fn_phase_d_handler_execute section 3, the capability boundary, on the 21 bindings whose capability_dependency is REASONING — not in this predicate'
      when r.rule_id in ('BR-053','BR-054') then 'constant while the founder provider hold stands'
      else 'NO CONTEXT PRODUCED A REFUSAL — this rule cannot fail' end;
    return next;
  end loop;
end
$fn$;

revoke execute on function public.fn_phase_d_rule_can_refuse() from public, anon, authenticated;
grant  execute on function public.fn_phase_d_rule_can_refuse() to service_role;


-- ---- CONTROL ------------------------------------------------------------------------------------
-- The third context must be what finds them, and the probe must not have become one that passes
-- everything. Both directions.

do $ctl$
declare v_can int; v_third int; v_cannot text; v_deleg int; v_held int;
begin
  select count(*) filter (where can_refuse),
         count(*) filter (where refusing_context = 'authority_withheld'),
         count(*) filter (where note like 'delegated%'),
         count(*) filter (where note like 'constant%'),
         string_agg(rule_id, ' ' order by rule_id) filter (where note like 'NO CONTEXT%')
    into v_can, v_third, v_deleg, v_held, v_cannot
    from public.fn_phase_d_rule_can_refuse();

  -- POSITIVE: the third context must have found rules the first two could not.
  if v_third = 0 then
    raise exception 'D48: the authority-withheld context found nothing, so it is not doing anything the other two were not.';
  end if;

  -- The six named rules must each be found, by name. A count alone would let a different six pass.
  if exists (select 1 from unnest(array['BR-021','BR-022','BR-023','BR-024','BR-043','BR-048']) x
              where not exists (select 1 from public.fn_phase_d_rule_can_refuse() q
                                 where q.rule_id = x and q.can_refuse)) then
    raise exception 'D48: at least one of BR-021..024, BR-043, BR-048 still cannot be made to refuse: %',
      (select string_agg(x, ' ') from unnest(array['BR-021','BR-022','BR-023','BR-024','BR-043','BR-048']) x
        where not exists (select 1 from public.fn_phase_d_rule_can_refuse() q
                           where q.rule_id = x and q.can_refuse));
  end if;

  -- NEGATIVE: the probe must NOT now report everything as able to refuse. The delegated eleven and
  -- the two provider-held rules are still not two-state, and a board that says otherwise is worse
  -- than the one it replaced.
  if v_can = 54 then
    raise exception 'D48: all 54 rules report can_refuse. The probe has stopped distinguishing.';
  end if;
  if v_deleg = 0 then
    raise exception 'D48: no rule reports as delegated; D47 has regressed.';
  end if;
  if v_held = 0 then
    raise exception 'D48: BR-053/BR-054 no longer report as constant under the provider hold.';
  end if;

  raise notice 'D48: can refuse %, delegated to a kernel guard %, constant under the hold %, enforced at the executor 1 (BR-028), still unable to fail: %',
    v_can, v_deleg, v_held, coalesce(v_cannot, '(none)');
end
$ctl$;
