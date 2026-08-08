-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802182230   name: p2_c1_stage_b6_blocker_rename_compat
-- SHA-256 of the applied SQL: 3b66e052956c42d6bf22c25f0be9bdf5bc557989b78976ea9e37c70300435b71
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- The B.6 spec renamed the empty-scope blocker to no_active_trade (it is about trades, not
-- workstreams - a trade can be excluded before a workstream ever exists). Stage B test 12 asserted
-- the OLD key, which is a test asserting an implementation detail rather than a behaviour.
-- Rather than quietly break consumers, the blocker now carries `supersedes`, which names the old
-- key. Stage C should tighten test 12 to assert the behaviour and this field can then go.

create or replace function public.fn_p2c1_no_active_trade_blocker(
  p_out jsonb, p_opt jsonb) returns jsonb language sql immutable as $fn$
  select jsonb_build_object(
    'blocker','no_active_trade','supersedes','no_active_workstream','severity','blocking',
    'excluded_or_by_others', p_out, 'optional_or_future', p_opt,
    'detail','Every detected trade is excluded, by others, optional, future-phase or unconfirmed. There is nothing in scope to dispatch.',
    'remedy','Confirm at least one trade as included, or answer the open clarification.');
$fn$;

create or replace function public.fn_group_dispatch_report(p_group_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_gd public.v_group_dispatch%rowtype; v_blockers jsonb := '[]'::jsonb; r record;
        v_active jsonb; v_out jsonb; v_opt jsonb; v_conf jsonb; v_comp jsonb; v_n_active int;
begin
  select * into v_gd from public.v_group_dispatch where group_id = p_group_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_group'); end if;

  select coalesce(jsonb_agg(jsonb_build_object('trade', trade_key, 'disposition', disposition)
                            order by trade_key), '[]'::jsonb), count(*)
    into v_active, v_n_active from public.v_trade_scope_status
   where group_id = p_group_id and coalesce(contributes,false) and coalesce(workstream_active,false);
  select coalesce(jsonb_agg(jsonb_build_object('trade', trade_key, 'disposition', disposition,
                                               'reason', reason) order by trade_key), '[]'::jsonb)
    into v_out from public.v_trade_scope_status
   where group_id = p_group_id and disposition in ('excluded','by_others','client_supplied');
  select coalesce(jsonb_agg(jsonb_build_object('trade', trade_key, 'disposition', disposition,
                                               'reason', reason) order by trade_key), '[]'::jsonb)
    into v_opt from public.v_trade_scope_status
   where group_id = p_group_id and disposition in ('optional','future_phase','proposed','unknown');
  select coalesce(jsonb_agg(jsonb_build_object('trade', trade_key, 'clauses', clause_indexes,
                                               'reason', reason) order by trade_key), '[]'::jsonb)
    into v_conf from public.v_trade_scope_status
   where group_id = p_group_id and coalesce(is_conflict,false);
  select coalesce(jsonb_agg(jsonb_build_object('trade', trade_key, 'component', scope_component,
                                               'disposition', disposition) order by trade_key, scope_component), '[]'::jsonb)
    into v_comp from public.v_scope_disposition_effective
   where group_id = p_group_id and scope_component <> 'complete_trade_scope' and disposition <> 'included';

  if v_n_active = 0 then
    if jsonb_array_length(v_conf) > 0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','scope_confirmation_required','severity','blocking','conflicts', v_conf,
        'detail','Contradictory scope statements of equal specificity. The customer must say which applies.',
        'remedy','Answer the open clarification.'));
    else
      v_blockers := v_blockers || jsonb_build_array(public.fn_p2c1_no_active_trade_blocker(v_out, v_opt));
    end if;
  elsif jsonb_array_length(v_conf) > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','scope_confirmation_required','severity','blocking','conflicts', v_conf,
      'detail','Some trades are active but an unresolved scope conflict remains.'));
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
      'unresolved_conflicts', to_jsonb(r.blocked_by), 'gate_states', r.gate_states,
      'detail','This trade is not dispatch-eligible, so the group is not.'));
  end loop;
  for r in select gr.gate_key,
                  coalesce((select g.state::text from public.inquiry_gate g
                             where g.group_id = p_group_id and g.workstream_id is null
                               and g.gate_key = gr.gate_key), 'not_evaluated') as state
             from public.inquiry_gate_required gr where gr.level = 'group' loop
    if r.state not in ('passed','not_applicable') then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','group_gate_not_satisfied','severity','blocking','gate_key', r.gate_key,
        'state', r.state,
        'detail', case when r.state = 'not_evaluated'
                       then 'This gate has never been evaluated. Absent reads as failed.'
                       else 'Gate state is ' || r.state || '.' end));
    end if;
  end loop;
  if jsonb_array_length(v_comp) > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','component_scope_restriction','severity','informational','restrictions', v_comp,
      'detail','Parts of an active trade are out of scope. The trade still dispatches; the RFQ must carry the restriction.'));
  end if;
  for r in select trade_key, evidence_score, score_basis, evidence_source
             from public.inquiry_trade_candidate
            where group_id = p_group_id and status = 'proposed' loop
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','trade_awaiting_confirmation','severity','informational','trade_key', r.trade_key,
      'evidence_source', r.evidence_source, 'evidence_score', r.evidence_score,
      'score_basis', r.score_basis,
      'detail','Proposed but not confirmed. It contributes nothing to dispatch until a person confirms it.'));
  end loop;
  if exists (select 1 from public.inquiry_trade_clarification
              where group_id = p_group_id and answered_at is null) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','open_clarification','severity','blocking',
      'question', (select question_en from public.inquiry_trade_clarification
                    where group_id = p_group_id and answered_at is null limit 1),
      'detail','The customer has been asked to settle the scope.'));
  end if;

  return jsonb_build_object(
    'ok', true, 'group_id', p_group_id,
    'overall_dispatch_eligible', (v_gd.overall_dispatch_eligible and v_n_active > 0
                                  and jsonb_array_length(v_conf) = 0),
    'active_included_trades', v_active, 'excluded_or_by_others_trades', v_out,
    'optional_or_future_trades', v_opt, 'unresolved_scope_conflicts', v_conf,
    'component_scope_restrictions', v_comp,
    'active_workstreams', v_gd.active_workstreams, 'shared_complete', v_gd.shared_complete,
    'group_gate_states', v_gd.gate_states, 'blocking_trades', to_jsonb(v_gd.blocking_trades),
    'blockers', v_blockers, 'blocker_count', jsonb_array_length(v_blockers));
end $fn$;

revoke all on function public.fn_group_dispatch_report(bigint) from public, anon, authenticated;
;