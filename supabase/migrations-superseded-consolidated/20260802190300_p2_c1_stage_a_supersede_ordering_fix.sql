-- P2-C1 STAGE A - the supersede ordering fix, and the setter that uses it.
-- Applied as migrations:
--   20260802170028 p2_c1_stage_a_fix_supersede_ordering
--   20260802170101 p2_c1_stage_a_setter_uses_supersede_helper
--
-- FOUND BY STAGE A TEST 1, which is exactly the test that was supposed to find it.
--
-- The partial unique index says: at most ONE live answer per (group, field). Superseding inserted
-- the replacement first and marked the old row superseded second, so for one statement both rows
-- were live and the index refused it. The invariant was right; the write order was wrong.
--
-- Fix: allocate the new id first, point the old row at it, then insert. That requires the
-- self-referencing foreign key to be deferred to end of transaction - which is correct anyway,
-- because "superseded_by must reference a real answer" is a statement about the committed state,
-- not about the middle of a two-statement handover.

alter table public.inquiry_answer drop constraint if exists inquiry_answer_superseded_by_fkey;
alter table public.inquiry_answer
  add constraint inquiry_answer_superseded_by_fkey
  foreign key (superseded_by) references public.inquiry_answer(id)
  deferrable initially deferred;

create or replace function public.fn_inquiry_answer_supersede(
  p_live_id bigint, p_group_id bigint, p_field_id text, p_value text, p_unit text,
  p_scope text, p_precedence public.answer_precedence, p_source_kind text, p_actor text)
returns bigint language plpgsql security definer set search_path to 'public' as $fn$
declare v_new_id bigint;
begin
  v_new_id := nextval(pg_get_serial_sequence('public.inquiry_answer','id'));
  update public.inquiry_answer set superseded_by = v_new_id where id = p_live_id;
  insert into public.inquiry_answer (id, group_id, field_id, value, unit, scope, precedence,
                                     source_kind, confirmed_at, confirmed_by)
  values (v_new_id, p_group_id, p_field_id, p_value, p_unit, p_scope, p_precedence, p_source_kind,
          case when p_precedence = 'customer_confirmed' then now() end,
          case when p_precedence = 'customer_confirmed' then p_actor end);
  insert into public.inquiry_answer_scope (answer_id, workstream_id)
    select v_new_id, workstream_id from public.inquiry_answer_scope where answer_id = p_live_id
    on conflict do nothing;
  return v_new_id;
end $fn$;

revoke all on function public.fn_inquiry_answer_supersede(bigint, bigint, text, text, text, text, public.answer_precedence, text, text) from public, anon, authenticated;

-- The setter, now delegating path 1 to the helper. Everything else is unchanged from
-- 20260802190000_p2_c1_stage_a_mep_model.sql.
create or replace function public.fn_inquiry_answer_set(
  p_group_id       bigint,
  p_field_id       text,
  p_value          text,
  p_precedence     public.answer_precedence,
  p_source_kind    text,
  p_actor          text default 'system',
  p_unit           text default null,
  p_workstream_ids bigint[] default null,
  p_document       jsonb default null
) returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_fd public.field_definition%rowtype; v_answer_scope text;
  v_live public.inquiry_answer%rowtype; v_new_id bigint; v_conflict_id bigint;
  v_norm_new text; v_norm_live text; v_rank_new integer; v_rank_live integer;
  v_ws bigint; v_bad_ws bigint[]; v_action text;
begin
  select * into v_fd from public.field_definition where field_id = p_field_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_field', 'field_id', p_field_id);
  end if;
  if not exists (select 1 from public.inquiry_workstream_group where id = p_group_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_group');
  end if;

  v_answer_scope := case v_fd.scope when 'shared' then 'inquiry_shared' else v_fd.scope end;

  -- A trade-specific answer must name its workstreams, and every named workstream must belong to
  -- the trade that owns the field. This is the structural half of "a trade-specific answer cannot
  -- satisfy another trade"; the derivation half is in the completeness views.
  if v_fd.scope <> 'shared' then
    if p_workstream_ids is null or array_length(p_workstream_ids, 1) is null then
      return jsonb_build_object('ok', false, 'error', 'workstream_required',
        'message', 'A trade-specific answer must say which workstream it belongs to.');
    end if;
    select array_agg(w.id) into v_bad_ws
      from public.inquiry_workstream w
     where w.id = any(p_workstream_ids)
       and (w.group_id <> p_group_id
            or (v_fd.scope = 'trade_specific' and w.trade_key <> v_fd.trade_key)
            or (v_fd.scope = 'trade_subset' and not exists (
                  select 1 from public.field_definition_trade t
                   where t.field_id = v_fd.field_id and t.trade_key = w.trade_key)));
    if v_bad_ws is not null then
      return jsonb_build_object('ok', false, 'error', 'trade_mismatch',
        'field_id', p_field_id, 'field_trade', v_fd.trade_key, 'rejected_workstreams', v_bad_ws,
        'message', 'This field belongs to another trade. A trade-specific answer cannot satisfy a workstream that does not own the field.');
    end if;
    if (select count(*) from public.inquiry_workstream
         where id = any(p_workstream_ids)) <> array_length(p_workstream_ids, 1) then
      return jsonb_build_object('ok', false, 'error', 'unknown_workstream');
    end if;
  end if;

  select * into v_live from public.inquiry_answer
   where group_id = p_group_id and field_id = p_field_id and superseded_by is null;

  if not found then
    insert into public.inquiry_answer (group_id, field_id, value, unit, scope, precedence,
                                       source_kind, confirmed_at, confirmed_by)
    values (p_group_id, p_field_id, p_value, coalesce(p_unit, v_fd.unit), v_answer_scope,
            p_precedence, p_source_kind,
            case when p_precedence = 'customer_confirmed' then now() end,
            case when p_precedence = 'customer_confirmed' then p_actor end)
    returning id into v_new_id;
    v_action := 'inserted';
  else
    v_rank_new  := public.fn_answer_precedence_rank(p_precedence);
    v_rank_live := public.fn_answer_precedence_rank(v_live.precedence);
    v_norm_new  := public.fn_field_normalise(p_field_id, p_value);
    v_norm_live := public.fn_field_normalise(p_field_id, v_live.value);

    -- Equal precedence normally cannot supersede. The one exception is the customer restating
    -- their own answer: `customer_confirmed` over `customer_confirmed` is the customer's latest
    -- word, not a dispute with themselves. Without this, a customer resolving a conflict by
    -- confirming the drawing's value would open a second conflict against their own first answer.
    if v_rank_new < v_rank_live
       or (v_rank_new = v_rank_live and p_precedence = 'customer_confirmed'
           and v_norm_new is distinct from v_norm_live) then
      v_new_id := public.fn_inquiry_answer_supersede(v_live.id, p_group_id, p_field_id, p_value,
                    coalesce(p_unit, v_fd.unit), v_answer_scope, p_precedence, p_source_kind, p_actor);
      v_action := 'superseded';

    elsif v_norm_new is not distinct from v_norm_live then
      -- It AGREES. Evidence, not a dispute.
      v_new_id := v_live.id;
      insert into public.inquiry_answer_corroboration
        (answer_id, value, normalised_value, precedence, source_kind, document_id)
      values (v_live.id, p_value, v_norm_new, p_precedence, p_source_kind, p_document->>'document_id');
      v_action := 'corroborated';

    else
      -- It DISAGREES at equal or lower precedence. Canonical value unchanged.
      v_new_id := v_live.id;
      select id into v_conflict_id from public.inquiry_answer_conflict
       where group_id = p_group_id and field_id = p_field_id and resolved_at is null;
      if v_conflict_id is null then
        insert into public.inquiry_answer_conflict (group_id, field_id, blocking_scope)
        values (p_group_id, p_field_id,
                case when v_fd.scope = 'shared' then 'shared' else 'trade' end)
        returning id into v_conflict_id;
        insert into public.inquiry_answer_conflict_value (conflict_id, value, precedence, source_kind)
        values (v_conflict_id, v_live.value, v_live.precedence, v_live.source_kind);
      end if;
      insert into public.inquiry_answer_conflict_value
        (conflict_id, value, precedence, source_kind, document_id)
      values (v_conflict_id, p_value, p_precedence, p_source_kind, p_document->>'document_id');
      v_action := 'conflict_opened';
    end if;
  end if;

  if v_fd.scope <> 'shared' and v_action in ('inserted','superseded') then
    foreach v_ws in array p_workstream_ids loop
      insert into public.inquiry_answer_scope (answer_id, workstream_id)
      values (v_new_id, v_ws) on conflict do nothing;
    end loop;
  end if;

  if p_document is not null and v_action in ('inserted','superseded') then
    insert into public.inquiry_answer_document
      (answer_id, document_id, page_or_sheet, extraction_confidence, original_text, assigned_scope)
    values (v_new_id, p_document->>'document_id', p_document->>'page_or_sheet',
            (p_document->>'extraction_confidence')::numeric, p_document->>'original_text', v_answer_scope);
  end if;

  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (p_group_id, 'answer_' || v_action,
          jsonb_build_object('field_id', p_field_id, 'precedence', p_precedence,
                             'source_kind', p_source_kind, 'answer_id', v_new_id,
                             'conflict_id', v_conflict_id), p_actor);

  return jsonb_build_object('ok', true, 'action', v_action, 'answer_id', v_new_id,
                            'field_id', p_field_id, 'conflict_id', v_conflict_id,
                            'scope', v_answer_scope);
end $fn$;

revoke all on function public.fn_inquiry_answer_set(bigint, text, text, public.answer_precedence, text, text, text, bigint[], jsonb) from public, anon, authenticated;
