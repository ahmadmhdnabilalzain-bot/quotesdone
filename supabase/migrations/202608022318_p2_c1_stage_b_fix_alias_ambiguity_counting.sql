-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802172746   name: p2_c1_stage_b_fix_alias_ambiguity_counting
-- SHA-256 of the applied SQL: 283b64e2f71535539ba125d24d97c173b74ceac2909ab0e1289a3caf9a251925
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- Postgres has no count(distinct ...) over (). Dedupe to one row per (term, trade) first, then a
-- plain count over the term partition IS the number of distinct trades that term belongs to.
-- Same shape for documents, which also keeps evidence to one row per (document, term, trade)
-- instead of one per matching subcategory.

create or replace function public.fn_trade_identify(
  p_group_id    bigint,
  p_customer_text text default null,
  p_structured  jsonb default null,
  p_documents   jsonb default null,
  p_actor       text default 'system'
) returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_text        text := lower(coalesce(p_customer_text, ''));
  v_umbrella    boolean := false;
  v_full        boolean := false;
  v_only        boolean := false;
  v_named       text[] := '{}';
  v_structured  text[] := '{}';
  rec           record;
  v_cand        public.inquiry_trade_candidate%rowtype;
  v_cand_id     bigint;
  v_status      text;
  v_confirmed   text[] := '{}';
  v_proposed    text[] := '{}';
  v_clar_id     bigint;
  v_ws          jsonb;
begin
  if not exists (select 1 from public.inquiry_workstream_group where id = p_group_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_group');
  end if;

  if p_structured ? 'trades' then
    select array_agg(t) into v_structured
      from jsonb_array_elements_text(p_structured->'trades') t
     where t in (select trade_key from public.mep_trade);
  end if;
  v_structured := coalesce(v_structured, '{}');

  select coalesce(array_agg(distinct p.trade_key), '{}') into v_named
    from public.mep_trade_pattern p
   where p.kind = 'trade_name' and public.fn_text_matches_pattern(v_text, p.pattern);

  select coalesce(bool_or(public.fn_text_matches_pattern(v_text, p.pattern)),false) into v_umbrella
    from public.mep_trade_pattern p where p.kind = 'umbrella';
  select coalesce(bool_or(public.fn_text_matches_pattern(v_text, p.pattern)),false) into v_full
    from public.mep_trade_pattern p where p.kind = 'scope_full';
  select coalesce(bool_or(public.fn_text_matches_pattern(v_text, p.pattern)),false) into v_only
    from public.mep_trade_pattern p where p.kind = 'scope_only';

  for rec in
    select t as trade_key, 'structured_answer' as src, 1.000::numeric as conf, false as req,
           'Customer selected this trade explicitly in a structured answer.' as reason,
           null::text as term, null::text as slug, null::integer as cat,
           null::text as doc, null::boolean as doc_ok
      from unnest(v_structured) t
    union all
    select p.trade_key, 'customer_text', 0.950, false,
           'Customer text names this trade explicitly ("' || p.pattern || '").',
           p.pattern, null, null, null, null
      from public.mep_trade_pattern p
     where p.kind = 'trade_name' and public.fn_text_matches_pattern(v_text, p.pattern)
    union all
    select t.trade_key, 'scope_rule', 0.900, false,
           'Umbrella MEP term with a completeness qualifier. Route 8 core trades only; fire and ELV are not implied by "full MEP".',
           null, null, null, null, null
      from public.mep_trade t
     where t.is_core and v_umbrella and v_full
       and cardinality(v_named) = 0 and cardinality(v_structured) = 0
    union all
    select am.trade_key, 'alias',
           case when am.n_trades = 1 then 0.750 else 0.400 end,
           (am.n_trades > 1),
           case when am.n_trades = 1
                then 'Customer text contains "' || am.term || '", a catalogue alias unique to this trade.'
                else 'Customer text contains "' || am.term || '", an alias shared by ' || am.n_trades || ' trades. Ambiguous.' end,
           am.term, am.subcategory_slug, am.catalog_num, null, null
      from (
        select ah.term, ah.trade_key, ah.subcategory_slug, ah.catalog_num,
               count(*) over (partition by ah.term) as n_trades
          from (
            select x.a as term, tr.trade_key,
                   min(s.subcategory_slug) as subcategory_slug, min(m.catalog_num) as catalog_num
              from kb_stage.subcategories s
              join public.kb_operational_route_map m on m.subcategory_slug = s.subcategory_slug
              join public.mep_trade_route tr on tr.catalog_num = m.catalog_num
              cross join lateral jsonb_array_elements_text(
                     coalesce(s.aliases_en,'[]'::jsonb) || coalesce(s.aliases_ar,'[]'::jsonb)) x(a)
             where length(x.a) >= 3
               and v_text like '%' || lower(x.a) || '%'
               and public.fn_text_matches_pattern(v_text,
                     regexp_replace(lower(x.a), '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'))
             group by x.a, tr.trade_key
          ) ah
      ) am
    union all
    select am.trade_key, 'document_extraction', 0.600, true,
           'Detected in approved document ' || am.doc || ' via catalogue alias "' || am.term ||
             '". A document may propose a trade; it may never activate one.',
           am.term, am.subcategory_slug, am.catalog_num, am.doc, true
      from (
        select d->>'document_id' as doc, x.a as term, tr.trade_key,
               min(s.subcategory_slug) as subcategory_slug, min(m.catalog_num) as catalog_num
          from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb)) d
          join kb_stage.subcategories s on true
          join public.kb_operational_route_map m on m.subcategory_slug = s.subcategory_slug
          join public.mep_trade_route tr on tr.catalog_num = m.catalog_num
          cross join lateral jsonb_array_elements_text(
                 coalesce(s.aliases_en,'[]'::jsonb) || coalesce(s.aliases_ar,'[]'::jsonb)) x(a)
         where coalesce((d->>'approved')::boolean, false)
           and length(x.a) >= 3
           and lower(coalesce(d->>'text','')) like '%' || lower(x.a) || '%'
           and public.fn_text_matches_pattern(lower(coalesce(d->>'text','')),
                 regexp_replace(lower(x.a), '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'))
         group by d->>'document_id', x.a, tr.trade_key
      ) am
    order by 3 desc
  loop
    v_status := case when rec.src = 'document_extraction' or rec.req then 'proposed' else 'confirmed' end;

    select * into v_cand from public.inquiry_trade_candidate
     where group_id = p_group_id and trade_key = rec.trade_key;

    if not found then
      insert into public.inquiry_trade_candidate
        (group_id, trade_key, status, evidence_source, match_reason, confidence, requires_confirmation)
      values (p_group_id, rec.trade_key, v_status, rec.src, rec.reason, rec.conf,
              (v_status = 'proposed'))
      returning id into v_cand_id;
    else
      v_cand_id := v_cand.id;
      if v_cand.status = 'proposed' and v_status = 'confirmed' then
        update public.inquiry_trade_candidate
           set status = 'confirmed', evidence_source = rec.src, match_reason = rec.reason,
               confidence = greatest(confidence, rec.conf), requires_confirmation = false
         where id = v_cand_id;
      elsif v_cand.status = 'proposed' then
        update public.inquiry_trade_candidate
           set confidence = greatest(confidence, rec.conf) where id = v_cand_id;
      end if;
    end if;

    insert into public.inquiry_trade_candidate_evidence
      (candidate_id, evidence_source, matched_term, subcategory_slug, catalog_num,
       document_id, document_approved, confidence, detail)
    values (v_cand_id, rec.src, rec.term, rec.slug, rec.cat, rec.doc, rec.doc_ok, rec.conf,
            jsonb_build_object('reason', rec.reason));
  end loop;

  for rec in
    select * from public.inquiry_trade_candidate
     where group_id = p_group_id and status = 'confirmed' and workstream_id is null
  loop
    v_ws := public.fn_inquiry_workstream_activate(p_group_id, rec.trade_key, p_actor);
    update public.inquiry_trade_candidate
       set workstream_id = (v_ws->>'workstream_id')::bigint, activated_at = now()
     where id = rec.id;
  end loop;

  select coalesce(array_agg(trade_key order by trade_key),'{}') into v_confirmed
    from public.inquiry_trade_candidate where group_id = p_group_id and status = 'confirmed';
  select coalesce(array_agg(trade_key order by trade_key),'{}') into v_proposed
    from public.inquiry_trade_candidate where group_id = p_group_id and status = 'proposed';

  if cardinality(v_confirmed) = 0 then
    insert into public.inquiry_trade_clarification (group_id, question_en, question_ar, options, reason)
    select p_group_id,
           'Which trades does this enquiry cover?',
           'ما هي التخصصات التي يشملها هذا الطلب؟',
           coalesce(nullif(v_proposed,'{}'), array['hvac','electrical','plumbing','fire','elv']),
           case when v_umbrella and not v_full
                then 'An umbrella MEP term was used with no completeness qualifier and no trade named, so the scope is genuinely unknown.'
                when cardinality(v_proposed) > 0
                then 'Evidence exists but none of it is strong enough to activate a trade on its own.'
                else 'No trade evidence was found in the customer text, structured answers or approved documents.' end
    where not exists (select 1 from public.inquiry_trade_clarification c
                       where c.group_id = p_group_id and c.answered_at is null)
    returning id into v_clar_id;
  end if;

  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (p_group_id, 'trade_identification_run',
          jsonb_build_object('confirmed', v_confirmed, 'proposed', v_proposed,
                             'umbrella', v_umbrella, 'completeness_qualifier', v_full,
                             'exclusivity_qualifier', v_only,
                             'named_in_text', v_named, 'structured', v_structured,
                             'clarification_id', v_clar_id), p_actor);

  return jsonb_build_object('ok', true, 'confirmed', v_confirmed, 'proposed', v_proposed,
                            'clarification_id', v_clar_id,
                            'clarification_required', (v_clar_id is not null),
                            'umbrella_term', v_umbrella, 'completeness_qualifier', v_full,
                            'exclusivity_qualifier', v_only);
end $fn$;

revoke all on function public.fn_trade_identify(bigint, text, jsonb, jsonb, text) from public, anon, authenticated;
;