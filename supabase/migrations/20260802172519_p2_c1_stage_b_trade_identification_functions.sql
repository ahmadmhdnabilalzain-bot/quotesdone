-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802172519   name: p2_c1_stage_b_trade_identification_functions
-- SHA-256 of the applied SQL: da4447d0f471c5140234fbbfb8e18d2cba9b3d212ee7640e47dc50a392677904
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B (4/5) - the identification, confirmation, rejection and removal functions.

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
  v_conf        numeric;
  v_req         boolean;
  v_confirmed   text[] := '{}';
  v_proposed    text[] := '{}';
  v_clar_id     bigint;
  v_ws          jsonb;
begin
  if not exists (select 1 from public.inquiry_workstream_group where id = p_group_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_group');
  end if;

  -- structured customer selection is the highest authority and needs no confirmation
  if p_structured ? 'trades' then
    select array_agg(t) into v_structured
      from jsonb_array_elements_text(p_structured->'trades') t
     where t in (select trade_key from public.mep_trade);
  end if;
  v_structured := coalesce(v_structured, '{}');

  select coalesce(array_agg(distinct p.trade_key), '{}') into v_named
    from public.mep_trade_pattern p
   where p.kind = 'trade_name' and public.fn_text_matches_pattern(v_text, p.pattern);

  select bool_or(public.fn_text_matches_pattern(v_text, p.pattern)) into v_umbrella
    from public.mep_trade_pattern p where p.kind = 'umbrella';
  select bool_or(public.fn_text_matches_pattern(v_text, p.pattern)) into v_full
    from public.mep_trade_pattern p where p.kind = 'scope_full';
  select bool_or(public.fn_text_matches_pattern(v_text, p.pattern)) into v_only
    from public.mep_trade_pattern p where p.kind = 'scope_only';
  v_umbrella := coalesce(v_umbrella,false); v_full := coalesce(v_full,false); v_only := coalesce(v_only,false);

  -- Build the candidate set, strongest evidence first. A later, weaker source never downgrades
  -- an earlier, stronger one - fn_trade_upsert_candidate enforces that.
  for rec in
    -- 1. explicit structured selection
    select t as trade_key, 'structured_answer' as src, 1.000 as conf, false as req,
           'Customer selected this trade explicitly in a structured answer.' as reason,
           null::text as term, null::text as slug, null::integer as cat,
           null::text as doc, null::boolean as doc_ok
      from unnest(v_structured) t
    union all
    -- 2. explicit trade name in the customer's own words
    select p.trade_key, 'customer_text', 0.950, false,
           'Customer text names this trade explicitly.',
           p.pattern, null, null, null, null
      from public.mep_trade_pattern p
     where p.kind = 'trade_name' and public.fn_text_matches_pattern(v_text, p.pattern)
    union all
    -- 3. scope rule: umbrella term plus a completeness qualifier means the three CORE trades.
    --    Fire and ELV are deliberately excluded here - "full MEP package" does not order them.
    select t.trade_key, 'scope_rule', 0.900, false,
           'Umbrella MEP term with a completeness qualifier. Route 8 core trades only; fire and ELV are not implied.',
           null, null, null, null, null
      from public.mep_trade t
     where t.is_core and v_umbrella and v_full and cardinality(v_named) = 0 and cardinality(v_structured) = 0
    union all
    -- 4. corpus aliases appearing in the customer's text
    select am.trade_key, 'alias',
           case when am.n_trades = 1 then 0.750 else 0.400 end,
           (am.n_trades > 1),
           case when am.n_trades = 1
                then 'Customer text contains "' || am.term || '", a catalogue alias unique to this trade.'
                else 'Customer text contains "' || am.term || '", which is an alias of ' || am.n_trades || ' trades. Ambiguous.' end,
           am.term, am.subcategory_slug, am.catalog_num, null, null
      from (
        select x.a as term, tr.trade_key, s.subcategory_slug, m.catalog_num,
               count(distinct tr.trade_key) over (partition by x.a) as n_trades
          from kb_stage.subcategories s
          join public.kb_operational_route_map m on m.subcategory_slug = s.subcategory_slug
          join public.mep_trade_route tr on tr.catalog_num = m.catalog_num
          cross join lateral jsonb_array_elements_text(
                 coalesce(s.aliases_en,'[]'::jsonb) || coalesce(s.aliases_ar,'[]'::jsonb)) x(a)
         where length(x.a) >= 3
           and v_text like '%' || lower(x.a) || '%'
           and public.fn_text_matches_pattern(v_text, regexp_replace(lower(x.a), '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'))
      ) am
    union all
    -- 5. approved document extraction. Always PROPOSED, always needs a person.
    select am.trade_key, 'document_extraction', 0.600, true,
           'Detected in approved document ' || am.doc || ' via catalogue alias "' || am.term ||
             '". A document may propose a trade; it may never activate one.',
           am.term, am.subcategory_slug, am.catalog_num, am.doc, true
      from (
        select d->>'document_id' as doc, x.a as term, tr.trade_key,
               s.subcategory_slug, m.catalog_num
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
      -- never downgrade: a confirmed or rejected trade is not re-opened by weaker evidence
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

  -- Activate exactly the confirmed trades. Proposed trades get nothing - no workstream, no
  -- requirements, no influence on completeness.
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

  -- Ambiguous evidence asks exactly ONE clarification.
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

create or replace function public.fn_trade_confirm(
  p_group_id bigint, p_trade_key text, p_actor text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_cand public.inquiry_trade_candidate%rowtype; v_ws jsonb;
begin
  if coalesce(btrim(p_actor),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'actor_required');
  end if;
  select * into v_cand from public.inquiry_trade_candidate
   where group_id = p_group_id and trade_key = p_trade_key;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_candidate'); end if;
  if v_cand.status = 'confirmed' and v_cand.workstream_id is not null then
    return jsonb_build_object('ok', true, 'already_confirmed', true, 'workstream_id', v_cand.workstream_id);
  end if;

  v_ws := public.fn_inquiry_workstream_activate(p_group_id, p_trade_key, p_actor);
  update public.inquiry_trade_candidate
     set status = 'confirmed', requires_confirmation = false, confirmed_at = now(),
         confirmed_by = p_actor, activated_at = now(),
         workstream_id = (v_ws->>'workstream_id')::bigint,
         match_reason = match_reason || ' | Confirmed by ' || p_actor ||
                        coalesce(': ' || p_reason, '')
   where id = v_cand.id;

  insert into public.inquiry_state_audit (group_id, workstream_id, event, detail, actor)
  values (p_group_id, (v_ws->>'workstream_id')::bigint, 'trade_confirmed',
          jsonb_build_object('trade_key', p_trade_key, 'previous_status', v_cand.status,
                             'evidence_source', v_cand.evidence_source, 'reason', p_reason), p_actor);

  return jsonb_build_object('ok', true, 'trade_key', p_trade_key,
                            'workstream_id', (v_ws->>'workstream_id')::bigint,
                            'requirements', (v_ws->>'requirements')::integer);
end $fn$;

create or replace function public.fn_trade_reject(
  p_group_id bigint, p_trade_key text, p_actor text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_cand public.inquiry_trade_candidate%rowtype;
begin
  if coalesce(btrim(p_actor),'') = '' or coalesce(btrim(p_reason),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'who_and_why_required');
  end if;
  select * into v_cand from public.inquiry_trade_candidate
   where group_id = p_group_id and trade_key = p_trade_key;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_candidate'); end if;

  update public.inquiry_trade_candidate
     set status = 'rejected', rejected_at = now(), rejected_by = p_actor, rejection_reason = p_reason
   where id = v_cand.id;

  -- A rejected trade owns nothing. If it had been activated, it is deactivated - answers and
  -- audit survive, the roll-up does not see it.
  if v_cand.workstream_id is not null then
    perform public.fn_inquiry_workstream_deactivate(p_group_id, p_trade_key, p_actor);
  end if;

  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (p_group_id, 'trade_rejected',
          jsonb_build_object('trade_key', p_trade_key, 'previous_status', v_cand.status,
                             'evidence_source', v_cand.evidence_source, 'reason', p_reason), p_actor);

  return jsonb_build_object('ok', true, 'trade_key', p_trade_key, 'status', 'rejected');
end $fn$;

create or replace function public.fn_trade_remove(
  p_group_id bigint, p_trade_key text, p_actor text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_kept integer;
begin
  perform public.fn_inquiry_workstream_deactivate(p_group_id, p_trade_key, p_actor);
  update public.inquiry_trade_candidate
     set status = 'inactive', inactivated_at = now()
   where group_id = p_group_id and trade_key = p_trade_key;

  select count(*) into v_kept from public.inquiry_answer a
   where a.group_id = p_group_id
     and exists (select 1 from public.inquiry_answer_scope s
                  join public.inquiry_workstream w on w.id = s.workstream_id
                 where s.answer_id = a.id and w.trade_key = p_trade_key);

  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (p_group_id, 'trade_removed',
          jsonb_build_object('trade_key', p_trade_key, 'answers_preserved', v_kept,
                             'reason', p_reason), p_actor);

  return jsonb_build_object('ok', true, 'trade_key', p_trade_key, 'status', 'inactive',
                            'answers_preserved', v_kept);
end $fn$;

revoke all on function public.fn_trade_identify(bigint, text, jsonb, jsonb, text) from public, anon, authenticated;
revoke all on function public.fn_trade_confirm(bigint, text, text, text) from public, anon, authenticated;
revoke all on function public.fn_trade_reject(bigint, text, text, text) from public, anon, authenticated;
revoke all on function public.fn_trade_remove(bigint, text, text, text) from public, anon, authenticated;
revoke all on function public.fn_text_matches_pattern(text, text) from public, anon, authenticated;
;