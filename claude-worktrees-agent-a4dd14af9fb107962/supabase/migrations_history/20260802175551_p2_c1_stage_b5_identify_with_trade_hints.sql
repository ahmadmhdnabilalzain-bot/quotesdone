-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802175551   name: p2_c1_stage_b5_identify_with_trade_hints
-- SHA-256 of the applied SQL: eaf08287da7c849a121d685451450e202dfe4db0faf110686017d93bca9a0ea5
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

create or replace function public.fn_trade_identify(
  p_group_id    bigint,
  p_customer_text text default null,
  p_structured  jsonb default null,
  p_documents   jsonb default null,
  p_actor       text default 'system'
) returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_norm        text := public.fn_norm_text(p_customer_text);
  v_scope       jsonb; v_anchor boolean := false; v_only boolean := false;
  v_named       text[] := '{}'; v_structured text[] := '{}';
  rec           record; v_cand public.inquiry_trade_candidate%rowtype;
  v_cand_id     bigint; v_status text;
  v_confirmed   text[] := '{}'; v_proposed text[] := '{}';
  v_clar_id     bigint; v_ws jsonb;
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
   where p.kind = 'trade_name' and public.fn_term_matches(v_norm, p.pattern_norm, p.lang);

  select coalesce(bool_or(public.fn_term_matches(v_norm, p.pattern_norm, p.lang)), false) into v_anchor
    from public.mep_trade_pattern p where p.kind in ('mep_anchor','mep_full_phrase');
  select coalesce(bool_or(public.fn_term_matches(v_norm, p.pattern_norm, p.lang)), false) into v_only
    from public.mep_trade_pattern p where p.kind = 'scope_only';

  v_scope := public.fn_mep_full_scope(v_norm);

  for rec in
    select t as trade_key, 'structured_answer' as src, 'structured_answer' as wkey,
           1.000::numeric as score, false as ambiguous,
           'Customer selected this trade explicitly in a structured answer.' as reason,
           null::text as term, null::text as slug, null::integer as cat,
           null::text as doc, null::boolean as doc_ok
      from unnest(v_structured) t
    union all
    select p.trade_key, 'customer_text', 'customer_text.trade_name', 0.950, false,
           'Customer text names this trade explicitly ("' || p.pattern || '").',
           p.pattern, null, null, null, null
      from public.mep_trade_pattern p
     where p.kind = 'trade_name' and public.fn_term_matches(v_norm, p.pattern_norm, p.lang)
    union all
    select t.trade_key, 'scope_rule', 'scope_rule.mep_full_scope', 0.900, false,
           'Full-MEP scope established by ' || (v_scope->>'basis') ||
             coalesce(' (anchor "' || (v_scope->>'anchor') || '")','') ||
             '. Route 8 core trades; fire and ELV are never implied.',
           v_scope->>'anchor', null, null, null, null
      from public.mep_trade t
     where t.is_core and (v_scope->>'matched')::boolean and not v_only
    union all
    select am.trade_key, 'alias',
           case when am.n_trades = 1 then 'alias.unique' else 'alias.ambiguous' end,
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
              cross join lateral (
                select a, 'en' as lng from jsonb_array_elements_text(coalesce(s.aliases_en,'[]'::jsonb)) a
                union all
                select a, 'ar' from jsonb_array_elements_text(coalesce(s.aliases_ar,'[]'::jsonb)) a
              ) x(a, lng)
             where length(x.a) >= 3
               and v_norm like '%' || public.fn_norm_text(x.a) || '%'
               and public.fn_term_matches(v_norm,
                     regexp_replace(public.fn_norm_text(x.a), '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'),
                     x.lng)
             group by x.a, tr.trade_key
          ) ah
      ) am
    union all
    -- Conventional terms that imply a trade without naming it. Never confirm.
    select p.trade_key, 'customer_text', 'customer_text.trade_hint', 0.400, false,
           'Customer text uses "' || p.pattern || '", a term that conventionally implies this trade '
             || 'without naming it. Raised for confirmation, never activated on its own.',
           p.pattern, null, null, null, null
      from public.mep_trade_pattern p
     where p.kind = 'trade_hint' and public.fn_term_matches(v_norm, p.pattern_norm, p.lang)
    union all
    select am.trade_key, 'document_extraction', 'document_extraction', 0.600, false,
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
          cross join lateral (
            select a, 'en' as lng from jsonb_array_elements_text(coalesce(s.aliases_en,'[]'::jsonb)) a
            union all
            select a, 'ar' from jsonb_array_elements_text(coalesce(s.aliases_ar,'[]'::jsonb)) a
          ) x(a, lng)
         where coalesce((d->>'approved')::boolean, false)
           and length(x.a) >= 3
           and public.fn_norm_text(d->>'text') like '%' || public.fn_norm_text(x.a) || '%'
           and public.fn_term_matches(public.fn_norm_text(d->>'text'),
                 regexp_replace(public.fn_norm_text(x.a), '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'),
                 x.lng)
         group by d->>'document_id', x.a, tr.trade_key
      ) am
    order by 4 desc
  loop
    v_status := case
      when rec.ambiguous then 'proposed'
      when coalesce((select w.auto_confirms from public.mep_evidence_weight w
                      where w.weight_key = rec.wkey), false) then 'confirmed'
      else 'proposed' end;

    select * into v_cand from public.inquiry_trade_candidate
     where group_id = p_group_id and trade_key = rec.trade_key;

    if not found then
      insert into public.inquiry_trade_candidate
        (group_id, trade_key, status, evidence_source, match_reason, evidence_score,
         score_basis, requires_confirmation, confirmation_factors)
      values (p_group_id, rec.trade_key, v_status, rec.src, rec.reason, rec.score,
              'rule_weight_provisional', (v_status = 'proposed'),
              jsonb_build_object(
                'source_authority', (select w.source_authority from public.mep_evidence_weight w where w.weight_key = rec.wkey),
                'exactness',        (select w.exactness        from public.mep_evidence_weight w where w.weight_key = rec.wkey),
                'alias_specificity', case when rec.src <> 'alias' then 'not_applicable'
                                          when rec.ambiguous then 'shared_across_trades'
                                          else 'unique_to_trade' end,
                'ambiguous', rec.ambiguous,
                'customer_confirmation_required', (v_status = 'proposed'),
                'weight_key', rec.wkey, 'score_basis', 'rule_weight_provisional'))
      returning id into v_cand_id;
    else
      v_cand_id := v_cand.id;
      if v_cand.status = 'proposed' and v_status = 'confirmed' then
        update public.inquiry_trade_candidate
           set status = 'confirmed', evidence_source = rec.src, match_reason = rec.reason,
               evidence_score = greatest(evidence_score, rec.score), requires_confirmation = false,
               confirmation_factors = coalesce(confirmation_factors,'{}'::jsonb)
                 || jsonb_build_object('upgraded_by', rec.wkey, 'customer_confirmation_required', false)
         where id = v_cand_id;
      elsif v_cand.status = 'proposed' then
        update public.inquiry_trade_candidate
           set evidence_score = greatest(evidence_score, rec.score) where id = v_cand_id;
      end if;
    end if;

    insert into public.inquiry_trade_candidate_evidence
      (candidate_id, evidence_source, matched_term, subcategory_slug, catalog_num,
       document_id, document_approved, evidence_score, score_basis, detail)
    values (v_cand_id, rec.src, rec.term, rec.slug, rec.cat, rec.doc, rec.doc_ok, rec.score,
            'rule_weight_provisional',
            jsonb_build_object('reason', rec.reason, 'weight_key', rec.wkey));
  end loop;

  update public.inquiry_trade_candidate c
     set confirmation_factors = coalesce(c.confirmation_factors,'{}'::jsonb)
       || jsonb_build_object('runner_up_matches',
            (select count(*) from public.inquiry_trade_candidate o
              where o.group_id = c.group_id and o.id <> c.id
                and o.evidence_score >= c.evidence_score
                and o.status in ('proposed','confirmed')))
   where c.group_id = p_group_id;

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
           case when v_anchor and not (v_scope->>'matched')::boolean
                then 'An MEP umbrella term was used with no full-scope modifier beside it and no trade named, so the scope is genuinely unknown.'
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
                             'mep_anchor', v_anchor, 'full_scope', v_scope,
                             'exclusivity_qualifier', v_only,
                             'named_in_text', v_named, 'structured', v_structured,
                             'clarification_id', v_clar_id), p_actor);

  return jsonb_build_object('ok', true, 'confirmed', v_confirmed, 'proposed', v_proposed,
                            'clarification_id', v_clar_id,
                            'clarification_required', (v_clar_id is not null),
                            'mep_anchor', v_anchor, 'full_scope', v_scope,
                            'exclusivity_qualifier', v_only,
                            'score_basis', 'rule_weight_provisional');
end $fn$;

revoke all on function public.fn_trade_identify(bigint, text, jsonb, jsonb, text) from public, anon, authenticated;
;