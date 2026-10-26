-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802205500   name: p2_c1_stage_b7_operator_rollback
-- SHA-256 of the applied SQL: 837cf29ad6a3f997edffa1ee1ff4c702e0dc5d3eb0db7d9c75daa8616ffc25fd
-- Recovered by scripts/recover_one.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.7 (6/6) - operator rollback for Part 3.
--   select public.fn_p2c1_rollback_stage_b7('rehearse','ops:you');
--   select public.fn_p2c1_rollback_stage_b7('commit','ops:you');
-- Roll back B.7 BEFORE B.6: B.7 replaces B.6 function bodies rather than sitting beside them.
--
-- Same contract as the B.6 rollback, including the parts that are easy to skip: it names what it
-- deliberately does NOT remove, it proves the restored functions really are the prior-stage form
-- by probing behaviour rather than trusting the DDL, and it asserts that holdout v1 returns to
-- exactly its result of record - 49 of 54. A rollback that leaves the measurement somewhere else
-- has not restored the prior stage, whatever the object count says.
--
-- DECLARED SURVIVORS
--   inquiry_scope_disposition.classification_basis / responsible_party / party_class /
--   party_role / party_clause_index / sentence_index  -> class B, permanent evidence.
--     The table is append-only and these columns hold WHY each historical classification was made.
--     Dropping them would delete audit history to undo a code change, which is the wrong trade in
--     every direction. They are additive, nullable, and read by nothing after the B.6 functions
--     are restored, so they cost nothing.
--   scope_marker.party_class / resolution -> the same, minus the history: additive, defaulted, and
--     inert once the B.7 marker rows are gone and the B.6 check constraints are back.

create or replace function public.fn_p2c1_rollback_stage_b7(
  p_mode text default 'rehearse', p_actor text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_before int; v_after int; v_markers_before int; v_markers_after int;
  v_a text; v_b text; v_lang text; v_scope text; v_disp text;
  v_h_exec int; v_h_pass int; v_h_fp int; v_h_fn int;
  v_detect_b6 boolean; v_mfs_b6 boolean; v_pkg_back boolean;
  v_report jsonb;
  c_funcs text[] := array['fn_scope_party','fn_scope_supply_attribution','fn_scope_clause_map',
                          'fn_scope_sentences','fn_p2c1_b7_regression'];
begin
  if p_mode not in ('rehearse','commit') then
    return jsonb_build_object('ok', false, 'error','mode must be rehearse or commit'); end if;
  if coalesce(btrim(p_actor),'') = '' then
    return jsonb_build_object('ok', false, 'error','actor_required'); end if;
  if to_regclass('public.p2c1_b7_case') is null then
    return jsonb_build_object('ok', false, 'error','stage_b7_not_present'); end if;

  select (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and c.relname = 'p2c1_b7_case')
       + (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname = any(c_funcs))
    into v_before;
  select count(*) into v_markers_before from public.scope_marker
   where marker_type in ('party','attribution','supply_anchor');

  ---------------------------------------------------------------- remove stage-owned objects
  drop table if exists public.p2c1_b7_case cascade;
  drop function if exists public.fn_p2c1_b7_regression() cascade;
  drop function if exists public.fn_scope_supply_attribution(text) cascade;
  drop function if exists public.fn_scope_party(text) cascade;
  drop function if exists public.fn_scope_clause_map(text) cascade;
  drop function if exists public.fn_scope_sentences(text) cascade;

  ---------------------------------------------------------------- remove B.7 vocabulary
  delete from public.scope_marker where marker_type in ('party','attribution','supply_anchor');
  delete from public.scope_marker where marker_type = 'disposition' and resolution = 'party_dependent'
    and pattern not in ('not in our scope','outside our scope','ليست ضمن نطاق','خارج نطاق');
  delete from public.scope_marker where marker_type = 'disposition' and disposition = 'client_supplied'
    and pattern in ('supply by client','supply by the client','supplied by the owner',
      'supplied by the employer','supplied by the customer','client to supply','client will supply',
      'client shall supply','client to provide','client will provide','owner to supply',
      'employer to supply','customer to supply','free issue by the employer','free issue by the client',
      'free issued by the client','free issue material','employer supplied','customer supplied',
      'توريد صاحب العمل','توريد الزبون','يوفرها العميل','يوردها المالك','العميل يورد','العميل يوفر',
      'من توريد العميل','توريد من العميل');
  update public.scope_marker set disposition = 'by_others', resolution = 'fixed', priority = 20
   where marker_type = 'disposition'
     and pattern in ('not in our scope','outside our scope','ليست ضمن نطاق','خارج نطاق');

  delete from public.mep_trade_pattern where kind = 'trade_hint'
    and pattern in ('ac','a/c','a\.c');
  delete from public.mep_trade_pattern where kind = 'trade_name'
    and pattern in ('central ac','central a/c','central a\.c','central air conditioner',
      'central cooling','ac unit','a/c unit','ac system','split ac','split a/c','window ac',
      'ducted ac','package ac','packaged ac','مكيفات مركزيه','تبريد مركزي');
  delete from public.mep_trade_pattern where kind = 'scope_container' and pattern <> 'package';
  delete from public.mep_trade_pattern where kind = 'scope_full'
    and pattern in ('متكامله','متكامل','تسليم مفتاح');
  update public.mep_trade_pattern set kind = 'scope_full'
   where kind = 'scope_container' and pattern = 'package';

  alter table public.mep_trade_pattern drop constraint if exists mep_trade_pattern_kind_check;
  alter table public.mep_trade_pattern add constraint mep_trade_pattern_kind_check
    check (kind in ('trade_name','trade_hint','mep_anchor','mep_full_phrase','scope_full','scope_only'));
  alter table public.scope_marker drop constraint if exists scope_marker_marker_type_check;
  alter table public.scope_marker add constraint scope_marker_marker_type_check
    check (marker_type in ('disposition','component','exception','modification'));

  ---------------------------------------------------------------- restore the Stage B.6 bodies
  execute $q1$
    create or replace function public.fn_mep_full_scope(p_text_norm text)
    returns jsonb language plpgsql stable security definer set search_path to 'public' as $i$
    declare r record; v_re text; v_sep text := '[^[:alnum:].;,،؛' || chr(10) || ']+';
    begin
      for r in select pattern_norm, lang from public.mep_trade_pattern where kind = 'mep_full_phrase' loop
        if public.fn_term_matches(p_text_norm, r.pattern_norm, r.lang) then
          return jsonb_build_object('matched', true, 'basis', 'explicit_full_mep_phrase',
                                    'anchor', r.pattern_norm, 'modifier', null);
        end if;
      end loop;
      for r in
        select a.pattern_norm as anchor, m.pattern_norm as modifier, a.lang
          from public.mep_trade_pattern a
          join public.mep_trade_pattern m on m.kind = 'scope_full'
         where a.kind = 'mep_anchor'
      loop
        v_re := '(^|[^[:alnum:]])' || r.anchor || '(' || v_sep || '[[:alnum:]]+){0,2}' || v_sep
                || r.modifier || '($|[^[:alnum:]])';
        if p_text_norm ~ v_re then
          return jsonb_build_object('matched', true, 'basis', 'anchor_plus_modifier',
                                    'anchor', r.anchor, 'modifier', r.modifier);
        end if;
        v_re := '(^|[^[:alnum:]])' || r.modifier || '(' || v_sep || '[[:alnum:]]+){0,2}' || v_sep
                || r.anchor || '($|[^[:alnum:]])';
        if p_text_norm ~ v_re then
          return jsonb_build_object('matched', true, 'basis', 'modifier_plus_anchor',
                                    'anchor', r.anchor, 'modifier', r.modifier);
        end if;
      end loop;
      return jsonb_build_object('matched', false, 'basis', null);
    end $i$
  $q1$;

  execute $q2$
    create or replace function public.fn_scope_detect(
      p_group_id bigint, p_customer_text text, p_actor text default 'system')
    returns integer language plpgsql security definer set search_path to 'public' as $i$
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
    end $i$
  $q2$;

  ---------------------------------------------------------------- verify: nothing removable left
  select (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and c.relname = 'p2c1_b7_case')
       + (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname = any(c_funcs))
    into v_after;
  if v_after <> 0 then
    raise exception 'ROLLBACK ABORTED: % removable Stage B.7 objects survived', v_after; end if;
  select count(*) into v_markers_after from public.scope_marker
   where marker_type in ('party','attribution','supply_anchor');
  if v_markers_after <> 0 then
    raise exception 'ROLLBACK ABORTED: % Stage B.7 marker rows survived', v_markers_after; end if;

  ---------------------------------------------------------------- verify: the B.6 bodies are back
  -- probed by behaviour and by source, never by assuming the DDL took
  select p.prosrc not like '%fn_scope_party%' into v_detect_b6
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_scope_detect';
  select p.prosrc not like '%scope_container%' into v_mfs_b6
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_mep_full_scope';
  select exists (select 1 from public.mep_trade_pattern
                  where kind='scope_full' and pattern='package') into v_pkg_back;
  if not coalesce(v_detect_b6,false) then
    raise exception 'ROLLBACK ABORTED: fn_scope_detect still calls the B.7 party detector'; end if;
  if not coalesce(v_mfs_b6,false) then
    raise exception 'ROLLBACK ABORTED: fn_mep_full_scope still reads the B.7 container class'; end if;
  if not v_pkg_back then
    raise exception 'ROLLBACK ABORTED: `package` was not returned to the scope_full class'; end if;

  ---------------------------------------------------------------- verify: the B.6 measurements
  select count(*) filter (where passed)||'/'||count(*) into v_a from public.fn_p2c1_stage_a_selftest();
  select count(*) filter (where passed)||'/'||count(*) into v_b from public.fn_p2c1_stage_b_selftest();
  select count(*) filter (where verdict='PASS')||'/'||count(*) into v_lang from public.fn_p2c1_lang_parity_suite();
  select count(*) filter (where passed)||'/'||count(*) into v_scope from public.fn_p2c1_scope_rule_tests();
  select count(*) filter (where passed)||'/'||count(*) into v_disp from public.fn_p2c1_disposition_tests();
  select count(*), count(*) filter (where verdict='PASS'),
         coalesce(sum(cardinality(en_false_pos))+sum(cardinality(ar_false_pos)),0),
         coalesce(sum(cardinality(en_false_neg))+sum(cardinality(ar_false_neg)),0)
    into v_h_exec, v_h_pass, v_h_fp, v_h_fn from public.fn_p2c1_holdout_run();

  if v_a <> '14/14' or v_b <> '14/14' then
    raise exception 'ROLLBACK ABORTED: Stage A %, Stage B % after rollback', v_a, v_b; end if;
  if v_lang <> '23/23' or v_scope <> '12/12' or v_disp <> '22/22' then
    raise exception 'ROLLBACK ABORTED: lang parity %, scope negatives %, disposition % after rollback',
      v_lang, v_scope, v_disp; end if;
  if v_h_exec <> 54 or v_h_pass <> 49 or v_h_fp <> 0 or v_h_fn <> 5 then
    raise exception 'ROLLBACK ABORTED: holdout v1 is %/% with % false positives and % false negatives; the result of record is 49/54, 0, 5',
      v_h_pass, v_h_exec, v_h_fp, v_h_fn; end if;

  v_report := jsonb_build_object(
    'ok', true, 'mode', p_mode, 'actor', p_actor,
    'removable_objects', jsonb_build_object('before', v_before, 'after', v_after,
                                            'inventory', to_jsonb(c_funcs || array['p2c1_b7_case'])),
    'b7_marker_rows', v_markers_before || ' -> ' || v_markers_after,
    'restored', jsonb_build_object(
      'fn_scope_detect','Stage B.6 body verified: no party detector',
      'fn_mep_full_scope','Stage B.6 body verified: reads scope_full only',
      'mep_trade_pattern','`package` returned to scope_full; B.7 HVAC phrases, hints and containers deleted',
      'scope_marker','removal phrases returned to fixed by_others; party, attribution and supply_anchor rows deleted'),
    'intentional_survivors', jsonb_build_array(
      jsonb_build_object('object','inquiry_scope_disposition.classification_basis and the four party columns',
        'class','B','reason','permanent evidence on an append-only table: why each historical classification was made. Dropping them would delete audit history to undo a code change.',
        'rows_carrying_evidence', (select count(*) from public.inquiry_scope_disposition where classification_basis is not null)),
      jsonb_build_object('object','scope_marker.party_class, scope_marker.resolution','class','additive',
        'reason','nullable and defaulted; inert once the B.7 marker rows are gone and the B.6 check constraints are restored'),
      jsonb_build_object('object','fn_p2c1_rollback_stage_b7(text,text)','class','instrument',
        'reason','the tool performing this rollback; returns stage_b7_not_present if re-run')),
    'tests', jsonb_build_object('stage_a', v_a, 'stage_b', v_b, 'lang_parity', v_lang,
                                'scope_negatives', v_scope, 'disposition', v_disp,
                                'holdout_v1', v_h_pass || '/' || v_h_exec,
                                'holdout_false_positives', v_h_fp, 'holdout_false_negatives', v_h_fn),
    'verdict','stage b7 removed; stage b6 interpretation restored; holdout v1 back at its result of record');

  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (null, 'p2c1_stage_b7_rollback_' || p_mode, v_report, p_actor);

  if p_mode = 'rehearse' then
    raise exception 'REHEARSAL COMPLETE (nothing committed): %', v_report::text; end if;
  return v_report;
end $fn$;

revoke all on function public.fn_p2c1_rollback_stage_b7(text, text) from public, anon, authenticated;

comment on function public.fn_p2c1_rollback_stage_b7(text, text) is
  'Operator rollback for P2-C1 Stage B.7 (Part 3). Removes the B.7 tests, party and supply detectors and vocabulary, restores the Stage B.6 bodies of fn_scope_detect and fn_mep_full_scope, and asserts that every prior suite returns to its prior number - including holdout v1 at exactly 49/54 with 0 false positives and 5 false negatives. Aborts on any deviation. Deliberately retains the evidence columns on the append-only disposition table, which it names in its report.';
;