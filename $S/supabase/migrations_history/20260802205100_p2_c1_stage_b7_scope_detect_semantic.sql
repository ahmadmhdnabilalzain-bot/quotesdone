-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802205100   name: p2_c1_stage_b7_scope_detect_semantic
-- SHA-256 of the applied SQL: cb9ea8b87aed3d206ac5c673c825c5c8226beb0197510b7a786ab87364ba97bc
-- Recovered by scripts/recover_one.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.7 (2/6) - PART 3: clause/sentence map, party detection, supply attribution,
-- and the composed scope classifier.
--
-- fn_scope_clauses stays exactly as it was and is still what the rest of Stage B.6 sees. What is
-- new is that a clause now knows which SENTENCE it belongs to. That matters for exactly one rule:
-- "Fire fighting is not in our scope; the main contractor will do it." is one sentence and two
-- clauses, and the party in the second clause is the answer to the first. Across a full stop it is
-- not - "MEP is not in our scope. Civil works by the main contractor." names a party about
-- something else entirely. Clause for everything; sentence only for finding the responsible party.

create or replace function public.fn_scope_sentences(p_text_norm text)
returns table(sentence_idx integer, sentence text) language sql immutable as $fn$
  select s.sn::integer, btrim(s.st)
    from regexp_split_to_table(coalesce(p_text_norm,''), '[.!?؟' || chr(10) || ']')
         with ordinality as s(st, sn);
$fn$;

create or replace function public.fn_scope_clause_map(p_text_norm text)
returns table(idx integer, sentence_idx integer, clause text) language sql immutable as $fn$
  select (row_number() over (order by s.sn, c.cn))::integer, s.sn::integer, btrim(c.c)
    from regexp_split_to_table(coalesce(p_text_norm,''), '[.!?؟' || chr(10) || ']')
         with ordinality as s(st, sn)
    cross join lateral regexp_split_to_table(s.st, '[;,،؛]') with ordinality as c(c, cn)
   where btrim(c.c) <> '';
$fn$;

comment on function public.fn_scope_clause_map(text) is
  'The same clause sequence fn_scope_clauses produces, plus the sentence each clause came from. Sentence boundaries are the full stop, newline and the two question marks; clause boundaries add the semicolon and both commas.';

-- ---------------------------------------------------------------- is a responsible party named?
-- Mention is not attribution. The party has to be BOUND to the work, either by a connector
-- ("by the main contractor") or by standing as the actor ("the client will supply"). Anything
-- weaker - a possessive, an address, a company name in passing - identifies nobody, and the
-- correct answer for scope that leaves us with nobody named is `excluded`.
create or replace function public.fn_scope_party(p_clause_norm text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r record; v_re text; v_pos int;
        v_conn_en text; v_conn_ar text;
        v_best jsonb := null; v_best_pos int := null;
begin
  if coalesce(btrim(p_clause_norm),'') = '' then
    return jsonb_build_object('identified', false); end if;

  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_conn_en
    from public.scope_marker where marker_type = 'attribution' and lang = 'en';
  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_conn_ar
    from public.scope_marker where marker_type = 'attribution' and lang = 'ar';

  -- pass 1: attributed by a connector
  for r in select pattern_norm, lang, party_class from public.scope_marker
            where marker_type = 'party' order by priority, length(pattern_norm) desc loop
    v_re := case when r.lang = 'en'
      then '(^|[^[:alnum:]])(' || v_conn_en || ')[[:space:]]+(the[[:space:]]+)?'
           || replace(r.pattern_norm,' ','[[:space:]]+') || '(s)?($|[^[:alnum:]])'
      else '(^|[^[:alnum:]])(' || v_conn_ar || ')[[:space:]]+(ال)?'
           || replace(r.pattern_norm,' ','[[:space:]]+(ال)?') || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])'
    end;
    v_pos := coalesce(nullif(regexp_instr(p_clause_norm, v_re), 0), 0);
    if v_pos > 0 and (v_best_pos is null or v_pos < v_best_pos) then
      v_best := jsonb_build_object('identified', true, 'party', r.pattern_norm,
                                   'party_class', r.party_class, 'role', 'attributed');
      v_best_pos := v_pos;
    end if;
  end loop;
  if v_best is not null then return v_best; end if;

  -- pass 2: the party is the actor
  for r in select pattern_norm, lang, party_class from public.scope_marker
            where marker_type = 'party' order by priority, length(pattern_norm) desc loop
    v_re := case when r.lang = 'en'
      then '(^|[^[:alnum:]])(the[[:space:]]+)?' || replace(r.pattern_norm,' ','[[:space:]]+')
           || '(s)?[[:space:]]+(is[[:space:]]+to|are[[:space:]]+to|to|will|shall|would|is[[:space:]]+responsible|are[[:space:]]+responsible)($|[^[:alnum:]])'
      else '(^|[^[:alnum:]])(ال)?' || replace(r.pattern_norm,' ','[[:space:]]+(ال)?')
           || '[[:space:]]+(سيقوم|يقوم|مسؤول|سوف|سيتولي|يتولي)($|[^[:alnum:]])'
    end;
    v_pos := coalesce(nullif(regexp_instr(p_clause_norm, v_re), 0), 0);
    if v_pos > 0 and (v_best_pos is null or v_pos < v_best_pos) then
      v_best := jsonb_build_object('identified', true, 'party', r.pattern_norm,
                                   'party_class', r.party_class, 'role', 'subject');
      v_best_pos := v_pos;
    end if;
  end loop;

  return coalesce(v_best, jsonb_build_object('identified', false));
end $fn$;

comment on function public.fn_scope_party(text) is
  'The responsible party named in this clause, if any, with the role that binds it. `identified:false` is a positive finding: it is what makes removed scope `excluded` rather than `by_others`.';

-- ---------------------------------------------------------------- supply attributed to the buyer
-- "Supplied by the client", "the client will supply", "free issue by the employer", "توريد العميل".
-- All four say the same thing: the material comes from the other side of the contract. That is
-- client_supplied, and it lands on the SUPPLY component - not on the trade - because installation,
-- testing and commissioning are untouched by it and the trade must stay active for them.
--
-- Only a counterparty can trigger it. "Supply by the main contractor" is by_others: the main
-- contractor is not the buyer, and calling it client_supplied would tell the supplier that the
-- customer is handing over equipment when nobody is.
create or replace function public.fn_scope_supply_attribution(p_clause_norm text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r record; v_re text;
        v_sup_en text; v_sup_ar text; v_conn_en text; v_conn_ar text;
        v_has_en boolean := false; v_has_ar boolean := false;
begin
  if coalesce(btrim(p_clause_norm),'') = '' then
    return jsonb_build_object('matched', false); end if;

  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_sup_en
    from public.scope_marker where marker_type = 'supply_anchor' and lang = 'en';
  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_sup_ar
    from public.scope_marker where marker_type = 'supply_anchor' and lang = 'ar';
  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_conn_en
    from public.scope_marker where marker_type = 'attribution' and lang = 'en';
  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_conn_ar
    from public.scope_marker where marker_type = 'attribution' and lang = 'ar';

  v_sup_ar := '(وال|بال|فال|كال|ال|لل|و|ف|ب|ك|ل)?(' || v_sup_ar || ')';
  v_has_en := p_clause_norm ~ ('(^|[^[:alnum:]])(' || v_sup_en || ')(es|s|d|ing)?($|[^[:alnum:]])');
  v_has_ar := p_clause_norm ~ ('(^|[^[:alnum:]])' || v_sup_ar || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])');

  if not (v_has_en or v_has_ar) then return jsonb_build_object('matched', false); end if;

  for r in select pattern_norm, lang, party_class from public.scope_marker
            where marker_type = 'party' and party_class = 'counterparty'
            order by priority, length(pattern_norm) desc loop
    if r.lang = 'en' and v_has_en then
      v_re := '(^|[^[:alnum:]])(' || v_conn_en || ')[[:space:]]+(the[[:space:]]+)?'
              || replace(r.pattern_norm,' ','[[:space:]]+') || '(s)?($|[^[:alnum:]])';
      if p_clause_norm ~ v_re then
        return jsonb_build_object('matched', true, 'party', r.pattern_norm,
                                  'party_class', r.party_class, 'role', 'attributed'); end if;
      v_re := '(^|[^[:alnum:]])(the[[:space:]]+)?' || replace(r.pattern_norm,' ','[[:space:]]+')
              || '(s)?[[:space:]]+(is[[:space:]]+to|are[[:space:]]+to|to|will|shall|would)[[:space:]]+(be[[:space:]]+)?('
              || v_sup_en || ')(es|s|d|ing)?($|[^[:alnum:]])';
      if p_clause_norm ~ v_re then
        return jsonb_build_object('matched', true, 'party', r.pattern_norm,
                                  'party_class', r.party_class, 'role', 'subject'); end if;
    elsif r.lang = 'ar' and v_has_ar then
      v_re := '(^|[^[:alnum:]])(' || v_conn_ar || ')[[:space:]]+(ال)?'
              || replace(r.pattern_norm,' ','[[:space:]]+(ال)?') || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])';
      if p_clause_norm ~ v_re then
        return jsonb_build_object('matched', true, 'party', r.pattern_norm,
                                  'party_class', r.party_class, 'role', 'attributed'); end if;
      -- Arabic genitive: توريد العميل. Only the definite article is tolerated on the party here -
      -- توريد للعميل ("supply FOR the client") carries the ل proclitic and is not attribution.
      v_re := '(^|[^[:alnum:]])' || v_sup_ar || '(ات|ه)?[[:space:]]+(ال)?'
              || replace(r.pattern_norm,' ','[[:space:]]+(ال)?') || '($|[^[:alnum:]])';
      if p_clause_norm ~ v_re then
        return jsonb_build_object('matched', true, 'party', r.pattern_norm,
                                  'party_class', r.party_class, 'role', 'idafa'); end if;
      v_re := '(^|[^[:alnum:]])(ال)?' || replace(r.pattern_norm,' ','[[:space:]]+(ال)?')
              || '[[:space:]]+(سيقوم[[:space:]]+)?' || v_sup_ar || '($|[^[:alnum:]])';
      if p_clause_norm ~ v_re then
        return jsonb_build_object('matched', true, 'party', r.pattern_norm,
                                  'party_class', r.party_class, 'role', 'subject'); end if;
    end if;
  end loop;

  return jsonb_build_object('matched', false);
end $fn$;

comment on function public.fn_scope_supply_attribution(text) is
  'True when this clause says material or equipment comes from the counterparty. Requires a supply anchor AND a counterparty bound to it by a connector, as the actor, or by Arabic genitive attachment. A third party in the same position gives by_others, never client_supplied.';

-- ---------------------------------------------------------------- the composed classifier
-- Same clause walk as Stage B.6. What changed is the three lines that decide WHICH disposition a
-- clause carries, and that every row now records how it was decided.
create or replace function public.fn_scope_detect(
  p_group_id bigint, p_customer_text text, p_actor text default 'system')
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_norm text := public.fn_norm_text(p_customer_text);
  cl record; m record;
  v_exc_pos int; v_base text; v_base_marker text; v_base_res text; v_pos int;
  v_umbrella boolean; v_umb_pos int;
  v_comps text[]; v_comp text; v_n integer := 0;
  v_trades jsonb; v_tk text; v_tpos int; v_disp text; v_spec int;
  v_active_trades text[];
  v_party jsonb; v_supply jsonb; v_basis text;
  v_pty text; v_pcls text; v_prole text; v_pidx int;
  v_cdisp text; v_cbasis text; v_epty text; v_epcls text; v_eprole text;
  v_why text;
begin
  for cl in select * from public.fn_scope_clause_map(v_norm) loop
    v_exc_pos := null;
    for m in select pattern_norm, lang from public.scope_marker where marker_type = 'exception' loop
      v_pos := public.fn_term_position(cl.clause, m.pattern_norm, m.lang);
      if v_pos > 0 and (v_exc_pos is null or v_pos < v_exc_pos) then v_exc_pos := v_pos; end if;
    end loop;

    v_base := null; v_base_marker := null; v_base_res := 'fixed';
    for m in select disposition, pattern_norm, lang, priority, resolution from public.scope_marker
              where marker_type = 'disposition' order by priority, length(pattern_norm) desc loop
      v_pos := public.fn_term_position(cl.clause, m.pattern_norm, m.lang);
      if v_pos > 0 and (v_exc_pos is null or v_pos < v_exc_pos) then
        v_base := m.disposition; v_base_marker := m.pattern_norm; v_base_res := m.resolution; exit;
      end if;
    end loop;

    -- who, and whether material comes from the buying side. Clause-scoped, both of them.
    v_party  := public.fn_scope_party(cl.clause);
    v_supply := public.fn_scope_supply_attribution(cl.clause);
    v_pty := null; v_pcls := null; v_prole := null; v_pidx := null;
    if coalesce((v_party->>'identified')::boolean, false) then
      v_pty   := v_party->>'party';      v_pcls  := v_party->>'party_class';
      v_prole := v_party->>'role';       v_pidx  := cl.idx;
    end if;

    v_basis := 'fixed_marker';
    if v_base is not null and v_base_res = 'party_dependent' then
      if coalesce((v_party->>'identified')::boolean, false) then
        v_base := 'by_others'; v_basis := 'removal_attributed';
      else
        v_base := 'excluded';  v_basis := 'removal_unattributed';
      end if;
    elsif v_base = 'excluded' and coalesce((v_party->>'identified')::boolean, false) then
      v_base := 'by_others'; v_basis := 'excluded_upgraded_to_by_others';
    elsif v_base in ('by_others','client_supplied') and v_pty is null then
      v_prole := 'inline_marker';
    end if;

    select coalesce(array_agg(distinct m2.component), '{}') into v_comps
      from public.scope_marker m2
     where m2.marker_type = 'component'
       and public.fn_term_matches(cl.clause, m2.pattern_norm, m2.lang);

    -- "free issue by the employer" carries no component word, but it is unmistakably about supply.
    if coalesce((v_supply->>'matched')::boolean, false) and not ('supply' = any(v_comps)) then
      v_comps := array_append(v_comps, 'supply'::text);
    end if;

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

    if v_base is null and (v_umbrella or v_trades <> '{}'::jsonb) then
      v_base := 'included'; v_basis := 'clause_default'; end if;
    if v_base is null then continue; end if;

    foreach v_comp in array (case when cardinality(v_comps) = 0
                                  then array['complete_trade_scope'] else v_comps end) loop
      if v_comp = 'supply' and coalesce((v_supply->>'matched')::boolean, false) then
        v_cdisp := 'client_supplied'; v_cbasis := 'supply_attributed_counterparty';
        v_epty  := v_supply->>'party'; v_epcls := v_supply->>'party_class';
        v_eprole := v_supply->>'role';
      else
        v_cdisp := null; v_cbasis := v_basis;
        v_epty  := v_pty; v_epcls := v_pcls; v_eprole := v_prole;
      end if;

      v_why := case v_cbasis
        when 'removal_unattributed' then ' The clause removes this scope from us and identifies no other responsible party, so it is excluded rather than by others.'
        when 'removal_attributed' then ' The clause removes this scope from us and identifies "' || coalesce(v_epty,'?') || '" (' || coalesce(v_epcls,'?') || ', ' || coalesce(v_eprole,'?') || ') as responsible, so it is by others.'
        when 'excluded_upgraded_to_by_others' then ' Exclusion language with an identified responsible party "' || coalesce(v_epty,'?') || '", so it is by others rather than excluded.'
        when 'supply_attributed_counterparty' then ' Supply is attributed to the counterparty "' || coalesce(v_epty,'?') || '" (' || coalesce(v_eprole,'?') || '), so the supply component is client supplied. Work retained by us on this trade is unaffected.'
        else '' end;

      for v_tk, v_tpos in select key, value::int from jsonb_each_text(v_trades) loop
        v_disp := coalesce(v_cdisp,
                    case when v_exc_pos is not null and v_tpos > v_exc_pos
                         then public.fn_scope_inverse(v_base) else v_base end);
        v_spec := 2 + (case when v_comp = 'complete_trade_scope' then 0 else 1 end);
        insert into public.inquiry_scope_disposition
          (group_id, trade_key, scope_component, disposition, specificity, source_kind,
           evidence_source, evidence_score, clause_index, clause_text, matched_marker, reason, actor,
           classification_basis, responsible_party, party_class, party_role, party_clause_index,
           sentence_index)
        values (p_group_id, v_tk, v_comp, v_disp, v_spec, 'customer_text', 'customer_text', 0.950,
                cl.idx, cl.clause, v_base_marker,
                'Clause ' || cl.idx || ' names this trade' ||
                  case when v_comp <> 'complete_trade_scope' then ' and the ' || v_comp || ' component' else '' end ||
                  case when v_cdisp is null and v_exc_pos is not null and v_tpos > v_exc_pos
                       then ', after an exception marker, so the clause disposition is inverted' else '' end ||
                  '. Marker: ' || coalesce(v_base_marker,'(none - default included)') || '.' || v_why,
                p_actor, v_cbasis, v_epty, v_epcls, v_eprole,
                case when v_epty is null then null else cl.idx end, cl.sentence_idx);
        v_n := v_n + 1;
      end loop;

      if v_umbrella then
        insert into public.inquiry_scope_disposition
          (group_id, trade_key, scope_component, disposition, specificity, source_kind,
           evidence_source, evidence_score, clause_index, clause_text, matched_marker, reason, actor,
           classification_basis, responsible_party, party_class, party_role, party_clause_index,
           sentence_index)
        select p_group_id, t.trade_key, v_comp,
               coalesce(v_cdisp,
                 case when v_exc_pos is not null and v_umb_pos > v_exc_pos
                      then public.fn_scope_inverse(v_base) else v_base end),
               (case when v_comp = 'complete_trade_scope' then 0 else 1 end),
               'customer_text','customer_text', 0.900, cl.idx, cl.clause, v_base_marker,
               'Clause ' || cl.idx || ' uses an MEP umbrella term' ||
                 case when v_comp <> 'complete_trade_scope' then ' with the ' || v_comp || ' component' else '' end ||
                 '. Applied to the core trades at umbrella specificity, so any named-trade instruction outranks it. Marker: '
                 || coalesce(v_base_marker,'(none - default included)') || '.' || v_why, p_actor,
               v_cbasis, v_epty, v_epcls, v_eprole,
               case when v_epty is null then null else cl.idx end, cl.sentence_idx
          from public.mep_trade t where t.is_core and not (v_trades ? t.trade_key);
        v_n := v_n + (select count(*) from public.mep_trade t where t.is_core and not (v_trades ? t.trade_key));
      end if;

      if not v_umbrella and v_trades = '{}'::jsonb and v_comp <> 'complete_trade_scope' then
        select coalesce(array_agg(distinct c.trade_key), '{}') into v_active_trades
          from public.inquiry_trade_candidate c
         where c.group_id = p_group_id and c.status in ('confirmed','proposed');
        insert into public.inquiry_scope_disposition
          (group_id, trade_key, scope_component, disposition, specificity, source_kind,
           evidence_source, evidence_score, clause_index, clause_text, matched_marker, reason, actor,
           classification_basis, responsible_party, party_class, party_role, party_clause_index,
           sentence_index)
        select p_group_id, t, v_comp, coalesce(v_cdisp, v_base), 1, 'customer_text','customer_text', 0.900,
               cl.idx, cl.clause, v_base_marker,
               'Clause ' || cl.idx || ' names the ' || v_comp || ' component with no trade, so it applies to the trades already in play.' || v_why,
               p_actor, v_cbasis, v_epty, v_epcls, v_eprole,
               case when v_epty is null then null else cl.idx end, cl.sentence_idx
          from unnest(v_active_trades) t;
        v_n := v_n + coalesce(cardinality(v_active_trades),0);
      end if;
    end loop;
  end loop;

  return v_n;
end $fn$;

comment on function public.fn_scope_detect(bigint, text, text) is
  'Reads scope out of customer text clause by clause. Stage B.7: excluded and by_others are no longer separate phrase lists - a clause that removes scope is excluded unless it identifies a responsible party, in which case it is by others; and a supply anchor attributed to the counterparty makes the supply component client supplied without touching the trade. Every row records which rule fired and which party, if any, was found.';

revoke all on function public.fn_scope_sentences(text) from public, anon, authenticated;
revoke all on function public.fn_scope_clause_map(text) from public, anon, authenticated;
revoke all on function public.fn_scope_party(text) from public, anon, authenticated;
revoke all on function public.fn_scope_supply_attribution(text) from public, anon, authenticated;
revoke all on function public.fn_scope_detect(bigint, text, text) from public, anon, authenticated;
;