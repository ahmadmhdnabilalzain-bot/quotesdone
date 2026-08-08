-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802182107   name: p2_c1_stage_b6_fix_regex_aware_term_position
-- SHA-256 of the applied SQL: 7d7a5bb4be82b0e9e63ef21b4ee271749589874eb64d68fcf774fe869678d9e7
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- DEFECT, and the subtlest one in Stage B.6. Matching used fn_term_matches, which is regex with
-- morphology, but ORDERING used position(), which is a literal substring search. So "التيار الخفيف"
-- matched the pattern تيار خفيف yet reported position 0 - the literal string is not there, because
-- the definite article sits inside the phrase. Position 0 was then filtered out as "not found",
-- and the trade silently vanished from the clause.
--
-- Every morphological tolerance we added made this worse: the better the matcher got, the more
-- often the positions lied. Positions must be computed by the same rule that decided the match.

create or replace function public.fn_term_position(
  p_text_norm text, p_pattern_norm text, p_lang text default 'en')
returns integer language sql immutable as $fn$
  select coalesce(nullif(regexp_instr(p_text_norm,
    case when p_lang = 'ar'
      then '(^|[^[:alnum:]])(وال|بال|فال|كال|ال|لل|و|ف|ب|ك|ل)?'
           || replace(p_pattern_norm, ' ', '[[:space:]]+(ال)?')
           || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])'
      else '(^|[^[:alnum:]])' || p_pattern_norm || '(es|s)?($|[^[:alnum:]])'
    end), 0), 0);
$fn$;

comment on function public.fn_term_position(text, text, text) is
  'Where a term matches, under the SAME rule that decides whether it matches. position() cannot be used for this: it is literal, and every morphological tolerance makes it wrong more often.';

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
  v_active_trades text[];
begin
  for cl in select * from public.fn_scope_clauses(v_norm) loop
    v_exc_pos := null;
    for m in select pattern_norm, lang from public.scope_marker where marker_type = 'exception' loop
      v_pos := public.fn_term_position(cl.clause, m.pattern_norm, m.lang);
      if v_pos > 0 and (v_exc_pos is null or v_pos < v_exc_pos) then v_exc_pos := v_pos; end if;
    end loop;

    v_base := null; v_base_marker := null;
    for m in select disposition, pattern_norm, lang, priority from public.scope_marker
              where marker_type = 'disposition' order by priority, length(pattern_norm) desc loop
      v_pos := public.fn_term_position(cl.clause, m.pattern_norm, m.lang);
      if v_pos > 0 and (v_exc_pos is null or v_pos < v_exc_pos) then
        v_base := m.disposition; v_base_marker := m.pattern_norm; exit;
      end if;
    end loop;

    select coalesce(array_agg(distinct m2.component), '{}') into v_comps
      from public.scope_marker m2
     where m2.marker_type = 'component'
       and public.fn_term_matches(cl.clause, m2.pattern_norm, m2.lang);

    select coalesce(bool_or(public.fn_term_position(cl.clause, p.pattern_norm, p.lang) > 0), false),
           min(nullif(public.fn_term_position(cl.clause, p.pattern_norm, p.lang), 0))
      into v_umbrella, v_umb_pos
      from public.mep_trade_pattern p where p.kind in ('mep_anchor','mep_full_phrase');

    select coalesce(jsonb_object_agg(z.tk, z.p), '{}'::jsonb) into v_trades
      from (
        select t.trade_key as tk, min(t.pos) as p
          from (
            select p.trade_key, public.fn_term_position(cl.clause, p.pattern_norm, p.lang) as pos
              from public.mep_trade_pattern p
             where p.kind in ('trade_name','trade_hint') and p.trade_key is not null
            union all
            select c.trade_key,
                   public.fn_term_position(cl.clause, public.fn_norm_text(e.matched_term), 'en')
              from public.inquiry_trade_candidate c
              join public.inquiry_trade_candidate_evidence e on e.candidate_id = c.id
             where c.group_id = p_group_id and e.matched_term is not null
               and e.evidence_source in ('alias','customer_text')
               and length(e.matched_term) >= 3
          ) t
         where t.pos > 0
         group by t.trade_key
      ) z;

    if v_base is null and (v_umbrella or v_trades <> '{}'::jsonb) then v_base := 'included'; end if;
    if v_base is null then continue; end if;

    foreach v_comp in array (case when cardinality(v_comps) = 0
                                  then array['complete_trade_scope'] else v_comps end) loop
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

insert into public.mep_trade_pattern (trade_key, kind, pattern, lang) values
  ('hvac','trade_name','وحدات مناوله الهواء','ar'),
  ('hvac','trade_name','فان كويل','ar'),
  ('hvac','trade_name','شيلر','ar')
on conflict (kind, pattern, lang) do nothing;

revoke all on function public.fn_term_position(text, text, text) from public, anon, authenticated;
revoke all on function public.fn_scope_detect(bigint, text, text) from public, anon, authenticated;
;