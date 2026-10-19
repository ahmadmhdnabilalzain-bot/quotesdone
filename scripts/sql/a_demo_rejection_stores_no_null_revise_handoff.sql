-- Follow-up to #1465 (ruling 1199): fn_seat_handoff returns null for a demo row, so a demo rejection stored
-- array[null] in ceo_decision_round.revise_handoff_ids. The live body is unchanged except array_remove on that line.
-- fn_ceo_daily_run needs no change: it calls fn_seat_handoff at most once per run for that day's ceo_day row, and
-- a new day opens a new row, so a null note is retried only for the rest of that day and never loops.
create or replace function public.fn_ceo_decide(p_path text, p_item_key text, p_originator text, p_decision text, p_reasons text, p_version jsonb default '{}'::jsonb, p_source_table text default null::text, p_source_id text default null::text, p_revise_handoffs bigint[] default null::bigint[])
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare x public.ceo_decision_round; n jsonb; v_gen int; v_round int; v_rej int; v_h bigint;
  v_ids bigint[] := coalesce(p_revise_handoffs, '{}'); v_problem text; v_version jsonb := coalesce(p_version, '{}'::jsonb);
begin
  perform pg_advisory_xact_lock(hashtext('ceo_decision_round:' || p_item_key));
  if p_source_id is not null then
    select * into x from public.ceo_decision_round
     where item_key = p_item_key and source_table is not distinct from p_source_table and source_id = p_source_id;
    if found then
      return jsonb_build_object('recorded', true, 'already', true, 'round_id', x.id, 'decision', x.decision,
                                'generation', x.generation, 'round', x.round);
    end if;
  end if;
  n := public.fn_ceo_decision_next(p_item_key);
  if not (n->>'open')::boolean then
    return jsonb_build_object('recorded', false, 'closed', true, 'item_key', p_item_key, 'decision', n->>'last_decision', 'round_id', n->'last_id');
  end if;
  v_problem := public.fn_ceo_reasons_problem(p_reasons);
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: every CEO decision carries its reasons (' || p_decision || ' on ' || p_item_key || '): ' || v_problem;
  end if;
  -- what was decided on is kept, cut to the ledger's bound rather than refusing the decision
  v_version := public.fn_ceo_decision_version_cut(v_version);
  v_gen := (n->>'generation')::int; v_round := (n->>'round')::int; v_rej := (n->>'rejections')::int;
  if p_decision = 'rejected' then
    if v_rej >= 4 then
      v_h := public.fn_ceo_decision_owe(p_path, p_item_key, p_originator, v_gen,
               'sent back 4 times; a fifth rejection is refused, so the CEO approves it, or replaces or withdraws it', p_reasons, v_version);
      return jsonb_build_object('recorded', false, 'round_limit', true, 'item_key', p_item_key, 'generation', v_gen,
                                'rejections', v_rej, 'decision_owed_handoff', v_h);
    end if;
    if p_revise_handoffs is null then
      v_h := public.fn_seat_handoff('ceo', p_originator, 'ceo.revise', 'ceo_decision_round', p_item_key || ':g' || v_gen || ':r' || v_round,
        jsonb_build_object('path', p_path, 'item_key', p_item_key, 'generation', v_gen, 'round', v_round, 'rounds_left', 4 - v_rej - 1,
                           'reasons', left(p_reasons, 3000), 'version', v_version));
      v_ids := array_remove(array[v_h], null);   -- a demo row files no handoff (ruling 1199): store none, not a null
    end if;
  end if;
  insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons, version, source_table, source_id, revise_handoff_ids)
  values (p_path, p_item_key, p_originator, p_decision, p_reasons, v_version, p_source_table, p_source_id, v_ids)
  returning * into x;
  return jsonb_build_object('recorded', true, 'round_id', x.id, 'decision', x.decision, 'generation', x.generation,
                            'round', x.round, 'revise_handoff_ids', to_jsonb(x.revise_handoff_ids));
end $function$;
