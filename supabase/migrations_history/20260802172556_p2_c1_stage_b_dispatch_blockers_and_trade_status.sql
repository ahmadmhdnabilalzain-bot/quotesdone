-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802172556   name: p2_c1_stage_b_dispatch_blockers_and_trade_status
-- SHA-256 of the applied SQL: c62d6ebf43e3ae3d4afa50f0e5e1993493d2914fd07b856b1fbaf8427cc938b5
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B (5/5) - structured blockers and the trade status surface.
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

revoke all on function public.fn_group_dispatch_report(bigint) from public, anon, authenticated;

-- The setter learns about allowed_values, so the brand policy domain is enforced rather than hoped for.
create or replace function public.fn_field_value_allowed(p_field_id text, p_value text)
returns boolean language sql stable security definer set search_path to 'public' as $fn$
  select case
    when p_value is null then true
    else coalesce(
      (select p_value = any(fd.allowed_values) from public.field_definition fd
        where fd.field_id = p_field_id and fd.allowed_values is not null), true)
  end;
$fn$;
;