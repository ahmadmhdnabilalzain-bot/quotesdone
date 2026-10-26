-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802181524   name: p2_c1_stage_b6_scope_detection_and_resolution
-- SHA-256 of the applied SQL: 8f750626c1f688efb9cc0d4a2ac80c5767b4707c1a910a25f8c48990f120012a
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- P2-C1 STAGE B.6 (3/n) - clause segmentation, disposition detection, precedence, application.

create or replace function public.fn_scope_clauses(p_text_norm text)
returns table(idx integer, clause text) language sql immutable as $fn$
  select row_number() over ()::integer, btrim(c)
    from regexp_split_to_table(coalesce(p_text_norm,''), '[.;,،؛\n]') c
   where btrim(c) <> '';
$fn$;

create or replace function public.fn_scope_inverse(p_disposition text)
returns text language sql immutable as $fn$
  select case when p_disposition = 'included' then 'excluded' else 'included' end;
$fn$;

comment on function public.fn_scope_inverse(text) is
  'The disposition on the far side of an exception marker. "MEP excluded except plumbing" inverts to included; "MEP package excluding HVAC" inverts to excluded.';

create or replace function public.fn_scope_detect(
  p_group_id bigint, p_customer_text text, p_actor text default 'system')
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_norm text := public.fn_norm_text(p_customer_text);
  cl record; m record;
  v_exc_pos int; v_base text; v_base_marker text; v_pos int;
  v_umbrella boolean; v_umb_pos int;
  v_comps text[]; v_comp text; v_n integer := 0;
  v_trades jsonb; v_tk text; v_tpos int; v_disp text; v_spec int;
  v_mod boolean; v_active_trades text[];
begin
  for cl in select * from public.fn_scope_clauses(v_norm) loop
    -- earliest exception marker in this clause
    v_exc_pos := null;
    for m in select pattern_norm, lang from public.scope_marker where marker_type = 'exception' loop
      if public.fn_term_matches(cl.clause, m.pattern_norm, m.lang) then
        v_pos := position(m.pattern_norm in cl.clause);
        if v_pos > 0 and (v_exc_pos is null or v_pos < v_exc_pos) then v_exc_pos := v_pos; end if;
      end if;
    end loop;

    -- best-priority disposition marker positioned before the exception (or anywhere if none)
    v_base := null; v_base_marker := null;
    for m in select disposition, pattern_norm, lang, priority from public.scope_marker
              where marker_type = 'disposition' order by priority, length(pattern_norm) desc loop
      if public.fn_term_matches(cl.clause, m.pattern_norm, m.lang) then
        v_pos := position(m.pattern_norm in cl.clause);
        if v_exc_pos is null or (v_pos > 0 and v_pos < v_exc_pos) then
          v_base := m.disposition; v_base_marker := m.pattern_norm; exit;
        end if;
      end if;
    end loop;

    -- modification turns "existing" from "nothing to do" into bounded work
    v_mod := exists (select 1 from public.scope_marker m2 where m2.marker_type='modification'
                      and public.fn_term_matches(cl.clause, m2.pattern_norm, m2.lang));

    -- every component named in this clause, not just the first
    select coalesce(array_agg(distinct m2.component), '{}') into v_comps
      from public.scope_marker m2
     where m2.marker_type = 'component'
       and public.fn_term_matches(cl.clause, m2.pattern_norm, m2.lang);

    -- umbrella
    select coalesce(bool_or(public.fn_term_matches(cl.clause, p.pattern_norm, p.lang)), false),
           min(case when public.fn_term_matches(cl.clause, p.pattern_norm, p.lang)
                    then position(p.pattern_norm in cl.clause) end)
      into v_umbrella, v_umb_pos
      from public.mep_trade_pattern p where p.kind in ('mep_anchor','mep_full_phrase');

    -- trades named in this clause: patterns plus the terms that already produced a candidate
    select coalesce(jsonb_object_agg(t.trade_key, t.pos), '{}'::jsonb) into v_trades
      from (
        select p.trade_key, min(position(p.pattern_norm in cl.clause)) as pos
          from public.mep_trade_pattern p
         where p.kind in ('trade_name','trade_hint') and p.trade_key is not null
           and public.fn_term_matches(cl.clause, p.pattern_norm, p.lang)
         group by p.trade_key
        union all
        select c.trade_key, min(position(public.fn_norm_text(e.matched_term) in cl.clause))
          from public.inquiry_trade_candidate c
          join public.inquiry_trade_candidate_evidence e on e.candidate_id = c.id
         where c.group_id = p_group_id and e.matched_term is not null
           and length(e.matched_term) >= 3
           and public.fn_term_matches(cl.clause, public.fn_norm_text(e.matched_term), 'en')
         group by c.trade_key
      ) t where t.pos > 0 group by t.trade_key having min(t.pos) > 0;

    if v_base is null and (v_umbrella or v_trades <> '{}'::jsonb) then v_base := 'included'; end if;
    if v_base is null then continue; end if;

    foreach v_comp in array (case when cardinality(v_comps) = 0
                                  then array['complete_trade_scope'] else v_comps end) loop
      -- named trades
      for v_tk, v_tpos in select key, value::int from jsonb_each_text(v_trades) loop
        v_disp := case when v_exc_pos is not null and v_tpos > v_exc_pos
                       then public.fn_scope_inverse(v_base) else v_base end;
        v_spec := 2 + (case when v_comp = 'complete_trade_scope' then 0 else 1 end);
        insert into public.inquiry_scope_disposition
          (group_id, trade_key, scope_component, disposition, specificity, source_kind,
           evidence_source, evidence_score, clause_index, clause_text, matched_marker, reason, actor)
        values (p_group_id, v_tk, v_comp, v_disp, v_spec, 'customer_text', 'customer_text', 0.950,
                cl.idx, cl.clause, v_base_marker,
                'Clause ' || cl.idx || ' names this trade' ||
                  case when v_comp <> 'complete_trade_scope' then ' and the ' || v_comp || ' component' else '' end ||
                  case when v_exc_pos is not null and v_tpos > v_exc_pos
                       then ', after an exception marker, so the clause disposition is inverted' else '' end ||
                  '. Marker: ' || coalesce(v_base_marker,'(none - default included)') || '.', p_actor);
        v_n := v_n + 1;
      end loop;

      -- umbrella: applies to the three CORE trades, and only where no named trade already
      -- carried the same clause at higher specificity
      if v_umbrella then
        insert into public.inquiry_scope_disposition
          (group_id, trade_key, scope_component, disposition, specificity, source_kind,
           evidence_source, evidence_score, clause_index, clause_text, matched_marker, reason, actor)
        select p_group_id, t.trade_key, v_comp,
               case when v_exc_pos is not null and v_umb_pos > v_exc_pos
                    then public.fn_scope_inverse(v_base) else v_base end,
               (case when v_comp = 'complete_trade_scope' then 0 else 1 end),
               'customer_text','customer_text', 0.900, cl.idx, cl.clause, v_base_marker,
               'Clause ' || cl.idx || ' uses an MEP umbrella term' ||
                 case when v_comp <> 'complete_trade_scope' then ' with the ' || v_comp || ' component' else '' end ||
                 '. Applied to the core trades at umbrella specificity, so any named-trade instruction outranks it. Marker: '
                 || coalesce(v_base_marker,'(none - default included)') || '.', p_actor
          from public.mep_trade t where t.is_core and not (v_trades ? t.trade_key);
        v_n := v_n + (select count(*) from public.mep_trade t where t.is_core and not (v_trades ? t.trade_key));
      end if;

      -- component-only clause with no trade and no umbrella: applies to the trades already in play
      if not v_umbrella and v_trades = '{}'::jsonb and v_comp <> 'complete_trade_scope' then
        select coalesce(array_agg(distinct c.trade_key), '{}') into v_active_trades
          from public.inquiry_trade_candidate c
         where c.group_id = p_group_id and c.status in ('confirmed','proposed');
        insert into public.inquiry_scope_disposition
          (group_id, trade_key, scope_component, disposition, specificity, source_kind,
           evidence_source, evidence_score, clause_index, clause_text, matched_marker, reason, actor)
        select p_group_id, t, v_comp, v_base, 1, 'customer_text','customer_text', 0.900,
               cl.idx, cl.clause, v_base_marker,
               'Clause ' || cl.idx || ' names the ' || v_comp || ' component with no trade, so it applies to the trades already in play.', p_actor
          from unnest(v_active_trades) t;
        v_n := v_n + coalesce(cardinality(v_active_trades),0);
      end if;
    end loop;
  end loop;

  return v_n;
end $fn$;

-- PRECEDENCE. Highest specificity wins. A tie between different dispositions is `conflicted`,
-- never "whichever sentence came last".
create or replace view public.v_scope_disposition_effective as
select d.group_id, d.trade_key, d.scope_component,
       max(d.specificity) as specificity,
       case when count(distinct d.disposition) filter (where d.specificity = mx.mx_spec) > 1
            then 'conflicted'
            else min(d.disposition) filter (where d.specificity = mx.mx_spec) end as disposition,
       count(distinct d.disposition) filter (where d.specificity = mx.mx_spec) as competing_dispositions,
       min(d.reason) filter (where d.specificity = mx.mx_spec) as reason,
       array_agg(distinct d.clause_index) filter (where d.specificity = mx.mx_spec) as clause_indexes
  from public.inquiry_scope_disposition d
  join lateral (select max(d2.specificity) as mx_spec from public.inquiry_scope_disposition d2
                 where d2.group_id = d.group_id and d2.trade_key is not distinct from d.trade_key
                   and d2.scope_component = d.scope_component) mx on true
 where d.specificity = mx.mx_spec
 group by d.group_id, d.trade_key, d.scope_component, mx.mx_spec;

create or replace view public.v_trade_scope_status as
select c.group_id, c.trade_key, c.status as candidate_status,
       coalesce(e.disposition,
                case when c.status = 'confirmed' then 'included'
                     when c.status = 'proposed'  then 'proposed'
                     when c.status = 'rejected'  then 'excluded'
                     else 'unknown' end) as disposition,
       coalesce(e.specificity, -1) as specificity,
       k.contributes, k.requires_clarification, k.is_conflict,
       e.reason, e.clause_indexes,
       w.id as workstream_id, w.active as workstream_active
  from public.inquiry_trade_candidate c
  left join public.v_scope_disposition_effective e
    on e.group_id = c.group_id and e.trade_key = c.trade_key
   and e.scope_component = 'complete_trade_scope'
  left join public.scope_disposition_kind k
    on k.disposition = coalesce(e.disposition,
         case when c.status='confirmed' then 'included' when c.status='proposed' then 'proposed'
              when c.status='rejected' then 'excluded' else 'unknown' end)
  left join public.inquiry_workstream w on w.id = c.workstream_id
union
-- trades with a disposition but no candidate at all (e.g. "MEP by others" with nothing activated)
select e.group_id, e.trade_key, null,
       e.disposition, e.specificity, k.contributes, k.requires_clarification, k.is_conflict,
       e.reason, e.clause_indexes, null, null
  from public.v_scope_disposition_effective e
  join public.scope_disposition_kind k on k.disposition = e.disposition
 where e.scope_component = 'complete_trade_scope'
   and not exists (select 1 from public.inquiry_trade_candidate c
                    where c.group_id = e.group_id and c.trade_key = e.trade_key);

comment on view public.v_trade_scope_status is
  'One row per trade the inquiry has any opinion about. contributes is the only thing dispatch reads: a trade contributes only when its effective complete-scope disposition is included or existing_only.';

-- Applying dispositions: a non-contributing trade loses its workstream. Answers and audit survive.
create or replace function public.fn_scope_apply(p_group_id bigint, p_actor text default 'system')
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare r record; v_deact text[] := '{}'; v_kept text[] := '{}';
begin
  for r in select * from public.v_trade_scope_status where group_id = p_group_id loop
    if r.workstream_id is not null and r.workstream_active and not coalesce(r.contributes,false) then
      perform public.fn_inquiry_workstream_deactivate(p_group_id, r.trade_key, p_actor);
      update public.inquiry_trade_candidate
         set status = case when r.disposition = 'conflicted' then 'proposed' else 'inactive' end,
             requires_confirmation = true
       where group_id = p_group_id and trade_key = r.trade_key and status = 'confirmed';
      v_deact := v_deact || r.trade_key;
      insert into public.inquiry_state_audit (group_id, event, detail, actor)
      values (p_group_id, 'scope_disposition_applied',
              jsonb_build_object('trade_key', r.trade_key, 'disposition', r.disposition,
                                 'specificity', r.specificity, 'action','deactivated',
                                 'reason', r.reason), p_actor);
    elsif r.workstream_id is not null and r.workstream_active then
      v_kept := v_kept || r.trade_key;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'deactivated', to_jsonb(v_deact), 'active', to_jsonb(v_kept));
end $fn$;

-- The single interpretation entry point: identify the trades, read the scope, apply it.
create or replace function public.fn_inquiry_interpret(
  p_group_id bigint, p_customer_text text default null, p_structured jsonb default null,
  p_documents jsonb default null, p_actor text default 'system')
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_id jsonb; v_n integer; v_apply jsonb; v_active text[]; v_conf boolean;
begin
  v_id := public.fn_trade_identify(p_group_id, p_customer_text, p_structured, p_documents, p_actor);
  if not coalesce((v_id->>'ok')::boolean,false) then return v_id; end if;

  v_n := public.fn_scope_detect(p_group_id, p_customer_text, p_actor);
  v_apply := public.fn_scope_apply(p_group_id, p_actor);

  select coalesce(array_agg(trade_key order by trade_key),'{}') into v_active
    from public.inquiry_workstream where group_id = p_group_id and active;
  select exists (select 1 from public.v_trade_scope_status
                  where group_id = p_group_id and is_conflict) into v_conf;

  -- Nothing active, or an unresolved scope conflict, must ask.
  if cardinality(v_active) = 0 or v_conf then
    insert into public.inquiry_trade_clarification (group_id, question_en, question_ar, options, reason)
    select p_group_id,
           case when v_conf then 'Two statements in your enquiry disagree about scope. Which applies?'
                else 'Which trades does this enquiry cover?' end,
           case when v_conf then 'هناك عبارتان متعارضتان بشأن نطاق العمل. أيهما ينطبق؟'
                else 'ما هي التخصصات التي يشملها هذا الطلب؟' end,
           coalesce((select array_agg(distinct trade_key) from public.v_trade_scope_status
                      where group_id = p_group_id and (is_conflict or not coalesce(contributes,false))),
                    array['hvac','electrical','plumbing','fire','elv']),
           case when v_conf then 'Contradictory scope statements of equal specificity. Resolved by asking, never by preferring the last sentence.'
                else 'Every detected trade is excluded, by others, optional, future-phase or unresolved.' end
    where not exists (select 1 from public.inquiry_trade_clarification c
                       where c.group_id = p_group_id and c.answered_at is null);
  end if;

  return jsonb_build_object('ok', true, 'identification', v_id, 'dispositions_recorded', v_n,
                            'scope_applied', v_apply,
                            'active_trades', to_jsonb(v_active),
                            'scope_conflict', v_conf,
                            'clarification_required',
                              exists (select 1 from public.inquiry_trade_clarification
                                       where group_id = p_group_id and answered_at is null));
end $fn$;

revoke all on function public.fn_scope_clauses(text) from public, anon, authenticated;
revoke all on function public.fn_scope_detect(bigint, text, text) from public, anon, authenticated;
revoke all on function public.fn_scope_apply(bigint, text) from public, anon, authenticated;
revoke all on function public.fn_inquiry_interpret(bigint, text, jsonb, jsonb, text) from public, anon, authenticated;
;