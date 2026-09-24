-- QUOTE QUALITY, TRADE KEYS AND REPEAT REQUESTS ARE CODE, NOT THE MODEL.
-- Seat: it_engineer. 24 Sep 2026. Founder rules: routine work is code, the LLM only for real judgement; ledger 890:
-- no word matching to infer meaning (a field's structural presence, an exact key and trigram similarity are not that);
-- exact trade match or none. Prepared before the OpenRouter top-up on 25 Sep 2026.
--
-- WHAT WAS MEASURED (production htdblwldjkcgjvmqkbeh, reasoning_held_question, the 24 Sep 2026 inventory)
--   * sql.trg_quote_quality     52 held rows / 24h - one think() per quote save, to read which category aspects the text states.
--   * category.key_for_slug     40 held rows       - one think() per vocabulary word that category_route_map does not hold.
--   * inquiry.same_request       2 held rows       - one think() per differently worded repeat request.
--   model_policy 'duplicate_detection' is tier none, "SQL + pg_trgm". pg_trgm is installed (full_schema.sql line 22).
--
-- WHAT THIS CHANGES
--   1. trg_quote_quality scores completeness by structure only - the same points fn_quote_score_json gave (that routine
--      was dropped by retire_the_routines_no_seat_can_reach.sql; its body lives on here, unchanged). The category
--      aspects no longer gate a quote on a model reading: a reading already reasoned for this exact text is still used
--      (it was paid for); without one the category status is 'not_read' and the quote passes on its structural score.
--      supplier_api no longer calls reasonQuoteAspects. The 52 held questions are expired and the quotes they held
--      are re-scored now.
--   2. fn_category_key_ask files nothing. A trade word's key is category_route_map / catalog_supplier_categories.slug,
--      an exact lookup (fn_category_key_for_slug, unchanged); a word absent from both has no key - never a nearest
--      guess. A missing word is added as a category_route_map row. The 40 held questions are expired;
--      19 of their words are seeded as exact rows below, 21 named no single trade and stay unmapped (listed there).
--   3. trg_inquiry_enrich flags a differently worded repeat request by pg_trgm similarity of the two summaries
--      (same customer, same category, 30 minutes), no question filed. The 2 held questions are expired and their
--      inquiries flagged by the same rule now.
-- Nothing is dropped (the fn_reason_apply_ doors stay for rows already answered), so DROPPED.txt gets no line.
-- Canonical bodies started from: trg_quote_quality <- prices_supplier_profiles_and_quote_quality_are_read_by_reasoning.sql;
-- trg_inquiry_enrich, fn_category_key_ask <- routing_and_ceo_decisions_are_reasoned_not_word_matched.sql.
-- Pending: scripts/sql/pending/quote_quality_trade_keys_and_repeat_requests_are_code_not_the_model.txt.
-- Proved by: node --test scripts/checks/quote_quality_trade_keys_and_repeats_never_reach_the_model.test.mjs

-- ── 1. quote quality by structure ──────────────────────────────────────────────────────────────────────
create or replace function public.trg_quote_quality()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare cat text; grp text; v_md5 text; v_present text[]; v_cat_status text := null;
  n int; priced int; branded int; spec_n int; laboured int;
  pts int := 0; gmiss text[] := '{}'; cmiss jsonb := '[]'::jsonb; cmand_missing int := 0;
  r record; cat_pass boolean := true;
begin
  select category into cat from public.inquiries where id = NEW.inquiry_id;

  select count(*),
    count(*) filter (where coalesce(unit_price,0)>0 and coalesce(qty,0)>0),
    count(*) filter (where coalesce(brand,'')<>'' and coalesce(model,'')<>''),
    count(*) filter (where coalesce(specification,'')<>''),
    count(*) filter (where coalesce(labour,0)>0 or coalesce(install,0)>0)
    into n, priced, branded, spec_n, laboured
    from public.quote_items where quote_id = NEW.id::text;

  if coalesce(n,0)=0 then gmiss := array_append(gmiss,'an itemised breakdown (not just a lump sum)');
  else pts:=pts+15; if priced=n then pts:=pts+20; else gmiss:=array_append(gmiss,'a unit price on every line'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else gmiss:=array_append(gmiss,'the brand/model for each item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else gmiss:=array_append(gmiss,'the key specifications'); end if;
  if coalesce(laboured,0)>0 then pts:=pts+10; else gmiss:=array_append(gmiss,'the labour / installation cost'); end if;
  if coalesce(btrim(NEW.warranty),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the warranty period'); end if;
  if coalesce(btrim(NEW.lead_time),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the lead / delivery time'); end if;
  if coalesce(btrim(NEW.payment_terms),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the payment terms'); end if;
  if coalesce(btrim(NEW.exclusions),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'what is excluded'); end if;
  if coalesce(btrim(NEW.validity),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'how long the quote is valid'); end if;

  grp := public.fn_quote_spec_group(coalesce(cat,''));
  if grp is not null and exists (select 1 from public.category_quote_specs where spec_group=grp) then
    -- A reading already reasoned for this exact text is used. Without one nothing is asked (24 Sep 2026): the
    -- category status is 'not_read' and the quote is judged on its structural score alone.
    v_md5 := md5(coalesce(public.fn_quote_aspect_text(NEW), ''));
    select a.present into v_present from public.quote_aspect_reading a
     where a.quote_id = NEW.id and a.content_md5 = v_md5 and a.status = 'reasoned';
    if found then
      v_cat_status := 'reasoned';
      for r in select * from public.category_quote_specs where spec_group=grp order by mandatory desc, aspect loop
        if not (r.aspect = any(coalesce(v_present, '{}'::text[]))) then
          cmiss := cmiss || jsonb_build_object('label', r.label, 'mandatory', r.mandatory);
          if r.mandatory then cmand_missing := cmand_missing + 1; end if;
        end if;
      end loop;
      cat_pass := (cmand_missing = 0);
    else
      v_cat_status := 'not_read';
    end if;
  end if;

  NEW.quality := jsonb_build_object(
    'score', pts, 'pass', (pts >= 70 and cat_pass), 'submittable', (pts >= 70 and cat_pass),
    'missing', to_jsonb(gmiss),
    'category', case when grp is null then null else jsonb_build_object(
        'group', grp, 'status', v_cat_status, 'content_md5', v_md5, 'pass', cat_pass,
        'mandatory_missing', case when v_cat_status = 'reasoned' then cmand_missing end,
        'missing', case when v_cat_status = 'reasoned' then cmiss end) end,
    'scored_at', now());
  NEW.submittable := (pts >= 70 and cat_pass);
  return NEW;
end $fn$;
revoke execute on function public.trg_quote_quality() from public, anon, authenticated;
grant execute on function public.trg_quote_quality() to service_role;

-- The questions already waiting are expired, and the quotes they held are re-scored by structure now.
update public.reasoning_held_question set status = 'expired'
 where status = 'held' and surface = 'sql.trg_quote_quality';
update public.quotes set quality = quality where quality->'category'->>'status' = 'needs_reasoning';

-- ── 2. a trade word's key is an exact lookup, or none ───────────────────────────────────────────────────
create or replace function public.fn_category_key_ask(p_word text)
returns bigint
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  -- Files nothing (24 Sep 2026): the key is category_route_map / catalog_supplier_categories.slug or none.
  select null::bigint
$fn$;
revoke execute on function public.fn_category_key_ask(text) from public, anon, authenticated;
grant execute on function public.fn_category_key_ask(text) to service_role;

update public.reasoning_held_question set status = 'expired'
 where status = 'held' and surface = 'category.key_for_slug';

-- The 40 words held on category.key_for_slug (24 Sep 2026), classified once here by hand, no model call: a word gets a
-- row only where it names exactly ONE catalogue trade (catalog_supplier_categories.num). 19 mapped:
insert into public.category_route_map (category, catalog_num, note, decided_by) values
  ('waterproofing', 5, 'waterproofing-suppliers', 'it_engineer_24_sep_2026'),
  ('insulation', 6, 'insulation-suppliers', 'it_engineer_24_sep_2026'),
  ('roofing', 7, 'roofing-suppliers', 'it_engineer_24_sep_2026'),
  ('scaffolding', 4, 'formwork-and-scaffolding-suppliers', 'it_engineer_24_sep_2026'),
  ('structural-steel-fabrication', 2, 'steel-and-reinforcement-suppliers (as steel)', 'it_engineer_24_sep_2026'),
  ('mep', 8, 'mep-suppliers-electromechanical-suppliers', 'it_engineer_24_sep_2026'),
  ('hvac', 9, 'hvac-suppliers', 'it_engineer_24_sep_2026'),
  ('electrical', 10, 'electrical-suppliers', 'it_engineer_24_sep_2026'),
  ('smart-home', 15, 'smart-home-and-home-automation-suppliers', 'it_engineer_24_sep_2026'),
  ('commercial-retail-fitout', 16, 'fit-out-contractors-interior-fit-out-suppliers (as fitout)', 'it_engineer_24_sep_2026'),
  ('flooring', 18, 'flooring-suppliers', 'it_engineer_24_sep_2026'),
  ('tiling', 18, 'flooring-suppliers', 'it_engineer_24_sep_2026'),
  ('epoxy-flooring', 18, 'flooring-suppliers', 'it_engineer_24_sep_2026'),
  ('carpentry', 20, 'joinery-and-carpentry-suppliers', 'it_engineer_24_sep_2026'),
  ('carpentry-joinery', 20, 'joinery-and-carpentry-suppliers', 'it_engineer_24_sep_2026'),
  ('interior-design', 22, 'interior-decoration', 'it_engineer_24_sep_2026'),
  ('custom-furniture', 23, 'furniture-suppliers-ff-and-e-suppliers', 'it_engineer_24_sep_2026'),
  ('cleaning', 46, 'cleaning-companies', 'it_engineer_24_sep_2026'),
  ('facade-cleaning', 46, 'cleaning-companies', 'it_engineer_24_sep_2026')
on conflict (category) do nothing;
-- UNMAPPED (21), exact trade match or none - each names no single catalogue trade:
--   combined-mep                  spans mechanical, electrical and plumbing (kb_category_aliases lists 4 trades)
--   water-tank-cleaning           cleaning (46) or plumbing (11)
--   safety                        fire-fighting (12), fire-alarm/life-safety (13) or marine safety (65)
--   security                      guarding (47) or ELV/security systems (14)
--   general-building-contracting  no general-contractor trade in the catalogue
--   general                       names no trade
--   general-services-other        names no trade
--   blinds-curtains               interior decoration (22) or textile (70)
--   movers                        no removals trade; freight forwarding (49) is not the same job
--   engineering-and-architectural-consultancies  no design-consultancy trade in the catalogue
--   garage-doors                  aluminium (19), joinery (20) or automation (53)
--   landscaping                   no landscaping trade in the catalogue
--   marble-granite                flooring (18) or kitchen and bathroom (24)
--   acrylic                       a material: signage (85), fit-out (16) or construction materials (1)
--   generators                    electrical (10) or industrial equipment (52)
--   job-shop-manufacturing        no single trade
--   masonry                       construction materials (1) or a building trade the catalogue lacks
--   demolition                    no demolition trade in the catalogue
--   upholstery                    furniture (23) or textile (70)
--   tents-and-shade-structures    no shade-structure trade; aluminium (19) or textile (70)
--   pest                          no pest-control trade (77 is pet care)

-- ── 3. a repeat request by trigram similarity ───────────────────────────────────────────────────────────
create or replace function public.trg_inquiry_enrich()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
declare dup int; v_prev_id uuid; v_sim real;
  -- REPEAT_SIMILARITY: pg_trgm similarity() of the two summaries at or above which a differently worded request from
  -- the same customer, in the same category, within 30 minutes, is flagged possible_duplicate. 0.5 = half the
  -- trigrams shared; a flag only marks the inquiry for review, it never merges or drops one.
  c_repeat_similarity constant real := 0.5;
begin
  if NEW.urgency is null and NEW.spec is not null and (NEW.spec ? 'urgency') then NEW.urgency := NEW.spec->>'urgency'; end if;
  if NEW.plausibility is null and NEW.spec is not null and (NEW.spec ? 'plausibility') then NEW.plausibility := NEW.spec->'plausibility'; end if;
  if NEW.provenance is null and NEW.spec is not null and (NEW.spec ? 'provenance') then NEW.provenance := NEW.spec->'provenance'; end if;

  -- REMEMBERED PREFERENCE. Only fills a GAP — an emirate the customer stated on this RFQ always
  -- wins. `stated` beats `inferred`, and consent is re-checked on the read as well as the write.
  if NEW.emirate is null and NEW.customer_id is not null then
    select coalesce(p.preferences->'stated'->'emirates'->>0,
                    p.preferences->'inferred'->'emirates'->>0)
      into NEW.emirate
      from customer_preference p
      join customers c on c.id = p.customer_id
     -- Consent is read from customers.tos_accepted_at, where it actually lives, not from the copy
     -- on the preference row. A stale copy would keep a withdrawn profile readable.
     where p.customer_id = NEW.customer_id and c.tos_accepted_at is not null;
  end if;

  -- A REPEAT REQUEST. The very same summary is the same request (identity). A differently worded one is flagged
  -- by trigram similarity (model_policy duplicate_detection: SQL + pg_trgm, tier none; 24 Sep 2026), no question filed.
  select count(*) into dup from inquiries i
    where i.customer_id = NEW.customer_id and i.created_at > now() - interval '30 minutes'
      and coalesce(i.category,'') = coalesce(NEW.category,'')
      and i.summary = NEW.summary;
  if dup > 0 then
    NEW.plausibility := coalesce(NEW.plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true);
  elsif btrim(coalesce(NEW.summary, '')) <> '' then
    select i.id, public.similarity(i.summary, NEW.summary) into v_prev_id, v_sim from inquiries i
     where i.customer_id = NEW.customer_id and i.created_at > now() - interval '30 minutes'
       and coalesce(i.category,'') = coalesce(NEW.category,'')
       and btrim(coalesce(i.summary, '')) <> '' and i.id is distinct from NEW.id
     order by public.similarity(i.summary, NEW.summary) desc, i.created_at desc limit 1;
    if v_prev_id is not null and v_sim >= c_repeat_similarity then
      NEW.plausibility := coalesce(NEW.plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true,
        'duplicate_of', v_prev_id, 'duplicate_by', 'trigram', 'similarity', round(v_sim::numeric, 3));
    end if;
  end if;
  return NEW;
end $function$;
revoke execute on function public.trg_inquiry_enrich() from public, anon, authenticated;
grant execute on function public.trg_inquiry_enrich() to service_role;

-- The questions already waiting: expired, and each inquiry flagged now by the same rule.
do $blk$
declare h record; v_sim real;
begin
  for h in update public.reasoning_held_question set status = 'expired'
            where status = 'held' and surface = 'inquiry.same_request' returning subject
  loop
    select public.similarity(a.summary, b.summary) into v_sim
      from public.inquiries a, public.inquiries b
     where a.id::text = h.subject->>'inquiry_id' and b.id::text = h.subject->>'earlier_id';
    if v_sim >= 0.5 then
      update public.inquiries
         set plausibility = coalesce(plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true,
               'duplicate_of', h.subject->>'earlier_id', 'duplicate_by', 'trigram', 'similarity', round(v_sim::numeric, 3))
       where id::text = h.subject->>'inquiry_id';
    end if;
  end loop;
end $blk$;

-- ── probe ────────────────────────────────────────────────────────────────────────────────────────────────
select case when position('fn_reason_route_ask' in pg_get_functiondef('public.trg_inquiry_enrich()'::regprocedure)) = 0
             and position('similarity(' in pg_get_functiondef('public.trg_inquiry_enrich()'::regprocedure)) > 0
             and position('fn_reason_route_ask' in pg_get_functiondef('public.fn_category_key_ask(text)'::regprocedure)) = 0
             and position('''needs_reasoning''' in pg_get_functiondef('public.trg_quote_quality()'::regprocedure)) = 0
             and not exists (select 1 from public.reasoning_held_question where status = 'held'
                              and surface in ('sql.trg_quote_quality', 'category.key_for_slug', 'inquiry.same_request'))
            then 'PROBE OK' else 'PROBE FAILED' end as verdict;
