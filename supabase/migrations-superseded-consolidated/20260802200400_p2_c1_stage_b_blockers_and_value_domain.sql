-- P2-C1 STAGE B (5/6) - structured blockers, the trade status surface, value-domain enforcement.
-- Applied as p2_c1_stage_b_dispatch_blockers_and_trade_status + p2_c1_stage_b_value_domain_enforcement.
--
-- "overall_dispatch_eligible = false" is not an answer, it is the beginning of one. Every false
-- now comes with the list of reasons, each naming the thing to fix.

create or replace view public.v_inquiry_trade_status as
select c.group_id, c.trade_key, t.label_en, t.is_core, c.status, c.evidence_source,
       c.confidence, c.requires_confirmation, c.match_reason,
       c.proposed_at, c.confirmed_at, c.confirmed_by, c.rejected_at, c.rejection_reason,
       c.inactivated_at, c.activated_at, c.workstream_id,
       w.active as workstream_active,
       (select count(*) from public.inquiry_trade_candidate_evidence e where e.candidate_id = c.id) as evidence_rows,
       (c.status = 'confirmed' and w.active) as counts_toward_dispatch
  from public.inquiry_trade_candidate c
  join public.mep_trade t on t.trade_key = c.trade_key
  left join public.inquiry_workstream w on w.id = c.workstream_id;

comment on view public.v_inquiry_trade_status is
  'Only a confirmed candidate with an active workstream counts toward dispatch. A proposed trade is visible, evidenced, and inert.';

create or replace function public.fn_group_dispatch_report(p_group_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_gd public.v_group_dispatch%rowtype; v_blockers jsonb := '[]'::jsonb; r record;
begin
  select * into v_gd from public.v_group_dispatch where group_id = p_group_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_group');
  end if;

  if v_gd.active_workstreams = 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','no_active_workstream','severity','blocking',
      'detail','No trade has been confirmed for this inquiry, so there is nothing to dispatch.',
      'remedy','Confirm at least one trade, or answer the open clarification.'));
  end if;

  if cardinality(v_gd.shared_missing_mandatory) > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','shared_mandatory_missing','severity','blocking',
      'fields', to_jsonb(v_gd.shared_missing_mandatory),
      'detail','Shared project fields required by an active workstream are unanswered.'));
  end if;

  if not v_gd.no_unresolved_shared_conflict then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','open_shared_conflict','severity','blocking',
      'fields', (select coalesce(jsonb_agg(c.field_id), '[]'::jsonb)
                   from public.inquiry_answer_conflict c
                   join public.field_definition fd on fd.field_id = c.field_id
                  where c.group_id = p_group_id and c.resolved_at is null and fd.scope = 'shared'),
      'detail','A shared field has sources that disagree. Every workstream is affected.'));
  end if;

  for r in select * from public.v_workstream_dispatch
            where group_id = p_group_id and active and not dispatch_eligible loop
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','trade_not_eligible','severity','blocking','trade_key', r.trade_key,
      'missing_mandatory', to_jsonb(r.missing_mandatory),
      'unresolved_conflicts', to_jsonb(r.blocked_by),
      'gate_states', r.gate_states,
      'detail','This trade is not dispatch-eligible, so the group is not.'));
  end loop;

  for r in select gr.gate_key,
                  coalesce((select g.state::text from public.inquiry_gate g
                             where g.group_id = p_group_id and g.workstream_id is null
                               and g.gate_key = gr.gate_key), 'not_evaluated') as state
             from public.inquiry_gate_required gr where gr.level = 'group' loop
    if r.state not in ('passed','not_applicable') then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','group_gate_not_satisfied','severity','blocking',
        'gate_key', r.gate_key, 'state', r.state,
        'detail', case when r.state = 'not_evaluated'
                       then 'This gate has never been evaluated. Absent reads as failed.'
                       else 'Gate state is ' || r.state || '.' end));
    end if;
  end loop;

  for r in select trade_key, confidence, evidence_source from public.inquiry_trade_candidate
            where group_id = p_group_id and status = 'proposed' loop
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','trade_awaiting_confirmation','severity','informational','trade_key', r.trade_key,
      'evidence_source', r.evidence_source, 'confidence', r.confidence,
      'detail','Proposed but not confirmed. It contributes nothing to dispatch until a person confirms it.'));
  end loop;

  if exists (select 1 from public.inquiry_trade_clarification
              where group_id = p_group_id and answered_at is null) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','open_clarification','severity','blocking',
      'question', (select question_en from public.inquiry_trade_clarification
                    where group_id = p_group_id and answered_at is null limit 1),
      'detail','The customer has been asked which trades this enquiry covers.'));
  end if;

  return jsonb_build_object(
    'ok', true, 'group_id', p_group_id,
    'overall_dispatch_eligible', v_gd.overall_dispatch_eligible,
    'active_workstreams', v_gd.active_workstreams,
    'shared_complete', v_gd.shared_complete,
    'group_gate_states', v_gd.gate_states,
    'blocking_trades', to_jsonb(v_gd.blocking_trades),
    'blockers', v_blockers,
    'blocker_count', jsonb_array_length(v_blockers));
end $fn$;

-- Value domains, enforced at the table rather than only in the setter. A domain that only one
-- write path respects is a domain the second write path will break.
create or replace function public.fn_field_value_allowed(p_field_id text, p_value text)
returns boolean language sql stable security definer set search_path to 'public' as $fn$
  select case
    when p_value is null then true
    else coalesce(
      (select p_value = any(fd.allowed_values) from public.field_definition fd
        where fd.field_id = p_field_id and fd.allowed_values is not null), true)
  end;
$fn$;

create or replace function public.trg_inquiry_answer_value_domain()
returns trigger language plpgsql as $fn$
begin
  if not public.fn_field_value_allowed(new.field_id, new.value) then
    raise exception 'value %L is not in the allowed domain for field %', new.value, new.field_id
      using hint = 'Allowed values are listed in field_definition.allowed_values.';
  end if;
  return new;
end $fn$;

drop trigger if exists inquiry_answer_value_domain on public.inquiry_answer;
create trigger inquiry_answer_value_domain before insert on public.inquiry_answer
  for each row execute function public.trg_inquiry_answer_value_domain();

-- The fixture helper must produce domain-valid values now that domains exist, and writes gate
-- STATE rather than the older boolean.
create or replace function public.fn_p2c1_fixture_satisfy(
  p_group bigint, p_ws bigint, p_actor text default 'selftest')
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare rec record; n integer := 0; v_val text;
begin
  for rec in
    select r.field_id, fd.scope, fd.allowed_values
      from public.inquiry_workstream_requirement r
      join public.field_definition fd on fd.field_id = r.field_id
     where r.workstream_id = p_ws and r.mandatory
  loop
    v_val := coalesce(rec.allowed_values[1], 'fixture-value');
    if rec.scope = 'shared' then
      perform public.fn_inquiry_answer_set(p_group, rec.field_id, v_val,
                'customer_confirmed', 'customer', p_actor);
    else
      perform public.fn_inquiry_answer_set(p_group, rec.field_id, v_val,
                'customer_confirmed', 'customer', p_actor, null, array[p_ws]);
    end if;
    n := n + 1;
  end loop;

  insert into public.inquiry_gate (group_id, workstream_id, gate_key, state, asserted_by)
  select p_group, p_ws, gr.gate_key, 'passed'::public.gate_state, p_actor
    from public.inquiry_gate_required gr where gr.level = 'workstream'
  on conflict do nothing;

  return n;
end $fn$;

revoke all on function public.fn_group_dispatch_report(bigint) from public, anon, authenticated;
revoke all on function public.fn_field_value_allowed(text, text) from public, anon, authenticated;
revoke all on function public.fn_p2c1_fixture_satisfy(bigint, bigint, text) from public, anon, authenticated;
