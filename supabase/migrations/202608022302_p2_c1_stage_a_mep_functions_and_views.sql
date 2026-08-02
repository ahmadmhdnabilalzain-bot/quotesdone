-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802165447   name: p2_c1_stage_a_mep_functions_and_views
-- SHA-256 of the applied SQL: d76e42057852d7a1eb75d3b55a8288ea69eb15597466abd42c718b55b710d848
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE A part 2 - activation, the setter, confirmation, and the derived views.

create or replace function public.fn_inquiry_workstream_activate(
  p_group_id bigint, p_trade_key text, p_actor text default 'system')
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_ws_id bigint; v_route integer; v_reactivated boolean := false; v_reqs integer;
begin
  if not exists (select 1 from public.mep_trade where trade_key = p_trade_key) then
    return jsonb_build_object('ok', false, 'error', 'unknown_trade', 'trade_key', p_trade_key);
  end if;
  if not exists (select 1 from public.inquiry_workstream_group where id = p_group_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_group');
  end if;

  select catalog_num into v_route from public.mep_trade_route
   where trade_key = p_trade_key and is_primary order by catalog_num limit 1;

  select id into v_ws_id from public.inquiry_workstream
   where group_id = p_group_id and trade_key = p_trade_key;

  if v_ws_id is null then
    insert into public.inquiry_workstream (group_id, trade_key, route_catalog_num)
    values (p_group_id, p_trade_key, v_route) returning id into v_ws_id;
  else
    update public.inquiry_workstream
       set active = true, activated_at = now(), deactivated_at = null
     where id = v_ws_id and active = false;
    v_reactivated := found;
    update public.inquiry_workstream set active = true where id = v_ws_id;
  end if;

  insert into public.inquiry_workstream_requirement (workstream_id, question_id, field_id, mandatory)
  select v_ws_id, min(q.question_id), s.field_id, bool_or(q.mandatory)
    from public.mep_trade_route tr
    join public.kb_operational_route_map m on m.catalog_num = tr.catalog_num
    join kb_stage.questions q on q.subcategory_slug = m.subcategory_slug
    join public.field_definition_source s
      on s.subcategory_slug = q.subcategory_slug and s.source_field_key = q.field_key
   where tr.trade_key = p_trade_key and q.field_key is not null
   group by s.field_id
  on conflict (workstream_id, field_id) do update
     set mandatory = public.inquiry_workstream_requirement.mandatory or excluded.mandatory;

  get diagnostics v_reqs = row_count;

  insert into public.inquiry_state_audit (group_id, workstream_id, event, detail, actor)
  values (p_group_id, v_ws_id,
          case when v_reactivated then 'workstream_reactivated' else 'workstream_activated' end,
          jsonb_build_object('trade_key', p_trade_key, 'route_catalog_num', v_route,
                             'requirements', v_reqs), p_actor);

  return jsonb_build_object('ok', true, 'workstream_id', v_ws_id, 'trade_key', p_trade_key,
                            'reactivated', v_reactivated, 'requirements', v_reqs);
end $fn$;

create or replace function public.fn_inquiry_workstream_deactivate(
  p_group_id bigint, p_trade_key text, p_actor text default 'system')
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_ws_id bigint;
begin
  update public.inquiry_workstream
     set active = false, deactivated_at = now()
   where group_id = p_group_id and trade_key = p_trade_key and active
   returning id into v_ws_id;
  if v_ws_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_active');
  end if;
  insert into public.inquiry_state_audit (group_id, workstream_id, event, detail, actor)
  values (p_group_id, v_ws_id, 'workstream_deactivated',
          jsonb_build_object('trade_key', p_trade_key), p_actor);
  return jsonb_build_object('ok', true, 'workstream_id', v_ws_id);
end $fn$;

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
  v_fd            public.field_definition%rowtype;
  v_answer_scope  text;
  v_live          public.inquiry_answer%rowtype;
  v_new_id        bigint;
  v_conflict_id   bigint;
  v_norm_new      text;
  v_norm_live     text;
  v_rank_new      integer;
  v_rank_live     integer;
  v_ws            bigint;
  v_bad_ws        bigint[];
  v_action        text;
begin
  select * into v_fd from public.field_definition where field_id = p_field_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_field', 'field_id', p_field_id);
  end if;
  if not exists (select 1 from public.inquiry_workstream_group where id = p_group_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_group');
  end if;

  v_answer_scope := case v_fd.scope when 'shared' then 'inquiry_shared' else v_fd.scope end;

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

    if v_rank_new < v_rank_live
       or (v_rank_new = v_rank_live and p_precedence = 'customer_confirmed'
           and v_norm_new is distinct from v_norm_live) then
      insert into public.inquiry_answer (group_id, field_id, value, unit, scope, precedence,
                                         source_kind, confirmed_at, confirmed_by)
      values (p_group_id, p_field_id, p_value, coalesce(p_unit, v_fd.unit), v_answer_scope,
              p_precedence, p_source_kind,
              case when p_precedence = 'customer_confirmed' then now() end,
              case when p_precedence = 'customer_confirmed' then p_actor end)
      returning id into v_new_id;
      update public.inquiry_answer set superseded_by = v_new_id where id = v_live.id;
      insert into public.inquiry_answer_scope (answer_id, workstream_id)
        select v_new_id, workstream_id from public.inquiry_answer_scope where answer_id = v_live.id
        on conflict do nothing;
      v_action := 'superseded';

    elsif v_norm_new is not distinct from v_norm_live then
      v_new_id := v_live.id;
      insert into public.inquiry_answer_corroboration
        (answer_id, value, normalised_value, precedence, source_kind, document_id)
      values (v_live.id, p_value, v_norm_new, p_precedence, p_source_kind, p_document->>'document_id');
      v_action := 'corroborated';

    else
      v_new_id := v_live.id;
      select id into v_conflict_id from public.inquiry_answer_conflict
       where group_id = p_group_id and field_id = p_field_id and resolved_at is null;
      if v_conflict_id is null then
        insert into public.inquiry_answer_conflict (group_id, field_id, blocking_scope)
        values (p_group_id, p_field_id,
                case when v_fd.scope = 'shared' then 'shared' else 'trade' end)
        returning id into v_conflict_id;
        insert into public.inquiry_answer_conflict_value
          (conflict_id, value, precedence, source_kind)
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
            (p_document->>'extraction_confidence')::numeric, p_document->>'original_text',
            v_answer_scope);
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

create or replace function public.fn_inquiry_answer_confirm(
  p_group_id bigint, p_field_id text, p_value text,
  p_confirmed_by text, p_reason text, p_workstream_ids bigint[] default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_res jsonb; v_conflict_id bigint; v_kept integer;
begin
  if coalesce(btrim(p_confirmed_by),'') = '' or coalesce(btrim(p_reason),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'who_and_why_required');
  end if;

  select id into v_conflict_id from public.inquiry_answer_conflict
   where group_id = p_group_id and field_id = p_field_id and resolved_at is null;

  v_res := public.fn_inquiry_answer_set(p_group_id, p_field_id, p_value, 'customer_confirmed',
             'customer', p_confirmed_by, null, p_workstream_ids, null);
  if not (v_res->>'ok')::boolean then return v_res; end if;

  if v_conflict_id is not null then
    insert into public.inquiry_answer_conflict_value (conflict_id, value, precedence, source_kind)
    values (v_conflict_id, p_value, 'customer_confirmed', 'customer');
    update public.inquiry_answer_conflict
       set resolved_at = now(), resolved_by = p_confirmed_by, resolution_reason = p_reason
     where id = v_conflict_id;
    select count(*) into v_kept from public.inquiry_answer_conflict_value where conflict_id = v_conflict_id;
  end if;

  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (p_group_id, 'conflict_resolved_by_confirmation',
          jsonb_build_object('field_id', p_field_id, 'conflict_id', v_conflict_id,
                             'reason', p_reason, 'evidence_values_kept', v_kept), p_confirmed_by);

  return jsonb_build_object('ok', true, 'action', v_res->>'action', 'conflict_id', v_conflict_id,
                            'evidence_values_kept', v_kept);
end $fn$;

create or replace view public.v_workstream_answer as
select w.id as workstream_id, w.group_id, w.trade_key, w.active,
       a.id as answer_id, a.field_id, a.value, a.unit, a.scope, a.precedence, a.source_kind,
       a.confirmed_at,
       (a.value is not null and btrim(a.value) <> ''
        and a.precedence not in ('model_inference','unknown')) as satisfies_mandatory
  from public.inquiry_workstream w
  join public.inquiry_answer a
    on a.group_id = w.group_id and a.superseded_by is null
 where a.scope = 'inquiry_shared'
    or exists (select 1 from public.inquiry_answer_scope s
                where s.answer_id = a.id and s.workstream_id = w.id);

comment on view public.v_workstream_answer is
  'Every live answer visible to every workstream. A shared answer is joined by group_id and appears for all of them from a single row - which is why one UPDATE changes five workstream views at once, and why no workstream copy can go stale.';

create or replace view public.v_workstream_conflict as
select w.id as workstream_id, w.group_id, w.trade_key, c.id as conflict_id, c.field_id,
       c.blocking_scope, c.opened_at
  from public.inquiry_workstream w
  join public.inquiry_answer_conflict c on c.group_id = w.group_id and c.resolved_at is null
  join public.field_definition fd on fd.field_id = c.field_id
 where fd.scope = 'shared'
    or (fd.scope = 'trade_specific' and fd.trade_key = w.trade_key)
    or (fd.scope = 'trade_subset' and exists (
          select 1 from public.field_definition_trade t
           where t.field_id = fd.field_id and t.trade_key = w.trade_key));

create or replace view public.v_workstream_completeness as
select w.id as workstream_id, w.group_id, w.trade_key, w.active,
       count(*) filter (where r.mandatory) as required_mandatory,
       count(*) filter (where r.mandatory and va.satisfies_mandatory) as answered_mandatory,
       count(*) filter (where not r.mandatory) as required_optional,
       count(*) filter (where not r.mandatory and va.satisfies_mandatory) as answered_optional,
       coalesce(array_agg(r.field_id order by r.field_id)
                filter (where r.mandatory and not coalesce(va.satisfies_mandatory,false)),
                '{}'::text[]) as missing_mandatory,
       coalesce((select array_agg(distinct vc.field_id)
                   from public.v_workstream_conflict vc where vc.workstream_id = w.id),
                '{}'::text[]) as blocked_by
  from public.inquiry_workstream w
  left join public.inquiry_workstream_requirement r on r.workstream_id = w.id
  left join public.v_workstream_answer va on va.workstream_id = w.id and va.field_id = r.field_id
 group by w.id, w.group_id, w.trade_key, w.active;

create or replace view public.v_workstream_dispatch as
select c.workstream_id, c.group_id, c.trade_key, c.active,
       c.required_mandatory, c.answered_mandatory, c.missing_mandatory, c.blocked_by,
       (cardinality(c.missing_mandatory) = 0) as mandatory_complete,
       (cardinality(c.blocked_by) = 0)        as no_unresolved_conflict,
       not exists (
         select 1 from public.inquiry_gate_required gr
          where gr.level = 'workstream'
            and not exists (select 1 from public.inquiry_gate g
                             where g.workstream_id = c.workstream_id
                               and g.gate_key = gr.gate_key and g.passed)) as gates_passed,
       (c.active
        and cardinality(c.missing_mandatory) = 0
        and cardinality(c.blocked_by) = 0
        and not exists (
          select 1 from public.inquiry_gate_required gr
           where gr.level = 'workstream'
             and not exists (select 1 from public.inquiry_gate g
                              where g.workstream_id = c.workstream_id
                                and g.gate_key = gr.gate_key and g.passed))) as dispatch_eligible
  from public.v_workstream_completeness c;

comment on view public.v_workstream_dispatch is
  'A missing required gate row reads as failed, not as absent. Fail-closed: "zero incorrect dispatch_eligible = true" is only reachable if an unasserted gate blocks.';

create or replace view public.v_group_completeness as
select g.id as group_id, g.inquiry_id, g.rfq_mode,
       count(*) filter (where sr.mandatory) as shared_required_mandatory,
       count(*) filter (where sr.mandatory and a.id is not null) as shared_answered_mandatory,
       coalesce(array_agg(sr.field_id order by sr.field_id)
                filter (where sr.mandatory and a.id is null), '{}'::text[]) as shared_missing_mandatory,
       (select count(*) from public.inquiry_workstream w where w.group_id = g.id and w.active) as active_workstreams,
       (select count(*) from public.inquiry_answer_conflict c
         join public.field_definition fd on fd.field_id = c.field_id
        where c.group_id = g.id and c.resolved_at is null and fd.scope = 'shared') as open_shared_conflicts
  from public.inquiry_workstream_group g
  left join lateral (
    select r.field_id, bool_or(r.mandatory) as mandatory
      from public.inquiry_workstream_requirement r
      join public.inquiry_workstream w on w.id = r.workstream_id
      join public.field_definition fd on fd.field_id = r.field_id
     where w.group_id = g.id and w.active and fd.scope = 'shared'
     group by r.field_id
  ) sr on true
  left join public.inquiry_answer a
    on a.group_id = g.id and a.field_id = sr.field_id and a.superseded_by is null
   and a.value is not null and btrim(a.value) <> ''
   and a.precedence not in ('model_inference','unknown')
 group by g.id, g.inquiry_id, g.rfq_mode;

create or replace view public.v_group_dispatch as
select gc.group_id, gc.inquiry_id, gc.rfq_mode, gc.active_workstreams,
       gc.shared_missing_mandatory,
       (cardinality(gc.shared_missing_mandatory) = 0) as shared_complete,
       (gc.open_shared_conflicts = 0)                 as no_unresolved_shared_conflict,
       coalesce((select bool_and(wd.dispatch_eligible) from public.v_workstream_dispatch wd
                  where wd.group_id = gc.group_id and wd.active), false) as all_active_workstreams_eligible,
       coalesce((select array_agg(wd.trade_key order by wd.trade_key) from public.v_workstream_dispatch wd
                  where wd.group_id = gc.group_id and wd.active and not wd.dispatch_eligible),
                '{}'::text[]) as blocking_trades,
       not exists (
         select 1 from public.inquiry_gate_required gr
          where gr.level = 'group'
            and not exists (select 1 from public.inquiry_gate g
                             where g.group_id = gc.group_id and g.workstream_id is null
                               and g.gate_key = gr.gate_key and g.passed)) as group_gates_passed,
       (gc.active_workstreams > 0
        and cardinality(gc.shared_missing_mandatory) = 0
        and gc.open_shared_conflicts = 0
        and coalesce((select bool_and(wd.dispatch_eligible) from public.v_workstream_dispatch wd
                       where wd.group_id = gc.group_id and wd.active), false)
        and not exists (
          select 1 from public.inquiry_gate_required gr
           where gr.level = 'group'
             and not exists (select 1 from public.inquiry_gate g
                              where g.group_id = gc.group_id and g.workstream_id is null
                                and g.gate_key = gr.gate_key and g.passed))) as overall_dispatch_eligible
  from public.v_group_completeness gc;

create or replace view public.v_inquiry_workstream_identity as
select i.id as inquiry_id, g.id as group_id,
       (g.id is not null) as has_group,
       coalesce((select count(*) from public.inquiry_workstream w where w.group_id = g.id and w.active), 1)
         as effective_workstreams,
       case when g.id is null then 'implicit_single_workstream' else 'multi_workstream' end as shape
  from public.inquiry_intake i
  left join public.inquiry_workstream_group g on g.inquiry_id = i.id;

comment on view public.v_inquiry_workstream_identity is
  'Reading this view writes nothing. An inquiry with no group reports one implicit workstream, which is exactly how the system behaves today.';

revoke all on function public.fn_inquiry_answer_set(bigint, text, text, public.answer_precedence, text, text, text, bigint[], jsonb) from public, anon, authenticated;
revoke all on function public.fn_inquiry_answer_confirm(bigint, text, text, text, text, bigint[]) from public, anon, authenticated;
revoke all on function public.fn_inquiry_workstream_activate(bigint, text, text) from public, anon, authenticated;
revoke all on function public.fn_inquiry_workstream_deactivate(bigint, text, text) from public, anon, authenticated;
revoke all on function public.fn_field_normalise(text, text) from public, anon, authenticated;
;