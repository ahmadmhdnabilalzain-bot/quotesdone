-- CUSTOMERS ARE GIVEN THE PUBLISHED FAQ AND THE PUBLISHED PRICES AGAIN. Seat: customer_support (what a customer or a
-- supplier is told: the portal chat, the portal corpus and think()'s retrieval). 27 Oct 2026. A DATA file: it defines
-- nothing, it changes 20 rows, matched by record_id literals (never by id ranges), and it refuses if any is not as measured.
--
-- WHY. #1660 (founder ruling 1338, "Withhold from customers") gives a customer, supplier or visitor an ops_knowledge row
-- only when confidentiality = 'public', and never a support_knowledge row that is tagged 'audience:internal' or
-- 'kind:company' or cites an internal:founder_instruction/... or internal:memory/... source. Today no ops row is public.
-- The independent review of #1660 (review 5671611417, section (c)) measured what customers lose and named the rows that
-- are safe to give them; the coordinator recommended exactly these and the founder pre-approved it (ledger 1348).
--
-- WHAT THIS CHANGES
--   1. 16 ops_knowledge rows 'qd-company:faq-<section>' -> confidentiality 'public'. Each is a copy of the PUBLISHED FAQ:
--      fn_company_org_directory_sync composes one per company_faq section from the rows that are public, and
--      fn_company_knowledge_upsert's `on conflict` rewrites module, title, content, keywords, effective_date,
--      supersession_state and embedding_status, never confidentiality, so the promotion survives every refresh. BEFORE a
--      row is promoted this file recomposes its text from company_faq rows with public = true (strictly true, not the
--      composer's coalesce(public, true); 0 rows are NULL, measured) and requires it to be byte-equal to what is stored.
--      Measured 27 Oct 2026: 16 of 16 equal, 302 public FAQ rows, 0 public sections without a row.
--   2. 4 support_knowledge rows retagged: 'customer_support:company-pricing' and '...:company-hard-rules-marketplace',
--      each in English and in its Arabic twin '<id>@ar' (the pack loader writes every entry twice; retagging only the
--      English row would leave an Arabic-speaking customer without it). #1660 excludes them on THREE grounds, not one,
--      measured on the live rows: the tag 'kind:company', the tag 'audience:internal', and source_ids citing
--      internal:memory/... . Removing 'kind:company' alone (what the review suggested) changes nothing they are served.
--      So: both tags come off, 'kind:published_terms' goes on (the kind tag only narrows a TRADE question, never a
--      support row, so no retrieval keys on it), and source_ids are re-cited to the published pages that state the same
--      facts. The internal citations are not lost: they are kept in structured_data->'retag'->'was_source_ids'.
--      Every fact in both bodies was checked against what is published (27 Oct 2026, read-only):
--        company-pricing: 3% of the selected quotation before VAT, no cap, no card fee or surcharge, QuotesDone bears the
--          processor's charges (/terms clause 4); no VAT while not VAT-registered (FAQ 93); no supplier commission, first
--          1,000 suppliers free permanently, then AED 1,000 a year, 30 days' notice (/supplier-agreement, FAQ 50, 95, 500).
--        company-hard-rules-marketplace: sign-up by one-time code with date of birth, 18 or over (/portal, /terms, site
--          copy messages/en.json); the top-three comparison report plus every other quote, all selectable, and every
--          trade except food & beverage (/how-it-works, site copy messages/en.json); incomplete quotes held, never rejected (FAQ 76); AED 20,000 per incident or five
--          times the fee (/supplier-agreement); quotation validity 30 days (FAQ 46, 78); introducer, no guarantee (/terms).
--      The bodies are pinned by body_sha256: if either text changes, this file refuses and the check must be redone.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE
--   - 'customer_support:what-does-it-cost-published-prices' (and @ar) is NOT retagged, although the brief named it. Its
--     worked example says the customer pays the AED 600 Reveal Fee "plus the processing charge shown at payment". The
--     published Terms (clause 4) say QuotesDone adds no card fee or surcharge and bears the processor's charges, and the
--     site says "no card fee on top". Giving it to customers would publish a charge that does not exist. It is also tagged
--     kind:decision_rule, not kind:company: its exclusion is audience:internal and its internal:memory sources. Its one
--     clause must be corrected in knowledge/seats/customer_support.json first; company-pricing carries the same price facts.
--   - qd-company:categories, quotation-format, operating-model, comparison-report, identity, terms, commercials and refunds
--     stay internal: they await the founder's wording decision.
--   - No body, title or embedding is touched, so no vector goes stale.
--
-- KNOWN LIMIT, said plainly: support rows are DERIVED from knowledge/seats/customer_support.json by
-- scripts/kb/load_verified_packs.mjs, whose upsert rewrites tags and source_ids (verified_packs.mjs rowsOf: kind 'company'
-- or an internal:memory source => 'audience:internal'). A re-load of that pack puts both entries back behind the filter
-- until the pack itself carries the published kind and sources. The FAQ promotion has no such limit.
--
-- ORDER: apply AFTER #1640 (knowledge_the_ai_wrote_itself_is_withheld_from_customers.sql) and AFTER #1660
-- (customers_and_suppliers_are_never_given_internal_knowledge.sql). Before #1660 nothing reads confidentiality for an
-- outside audience, so applying this first would change nothing anyone sees; the order keeps the audit trail honest.
-- PROVED (rolled back, on production, the three files then this one in one request):
--   scripts/sql/customers_are_given_the_published_faq_and_the_published_prices_again_probe.sql -> PROBE OK (27 Oct 2026:
--   16 public, all 16 reach a visitor, 0 ops rows outside the 16 to any outside caller, internal callers still served).
--   Without this file the same probe prints PROBE FAILED. A changed public FAQ answer or a changed support body makes
--   this file refuse (both run, rolled back).
-- Prevented by: the probe above and this file's own refusals.

do $apply$
declare
  c_faq constant text[] := array[
    'qd-company:faq-arabic', 'qd-company:faq-company-identity', 'qd-company:faq-company-policies',
    'qd-company:faq-customer', 'qd-company:faq-documents', 'qd-company:faq-financial', 'qd-company:faq-future-vision',
    'qd-company:faq-integrations', 'qd-company:faq-marketplace', 'qd-company:faq-operations', 'qd-company:faq-quotation',
    'qd-company:faq-rfq', 'qd-company:faq-security', 'qd-company:faq-smart-engine', 'qd-company:faq-supplier',
    'qd-company:faq-technical'];
  -- record_id -> the body_sha256 whose text was checked against the published pages on 27 Oct 2026
  c_sup constant jsonb := jsonb_build_object(
    'customer_support:company-pricing',                 'e9ab4488cd258d0214c0a83be64ca6c557d611bf62498d0479ed0e241cb0871a',
    'customer_support:company-pricing@ar',              '36b800c3adba5aced6bad6624dd7e27babc072bd3735f2855a237034cc762f33',
    'customer_support:company-hard-rules-marketplace',    'f045b2c3632d9b65a6f64d46ac5d80c7e7ac59f971b2343e49409cf1b309a3e9',
    'customer_support:company-hard-rules-marketplace@ar', 'f131278a81ef28e4dfb36331d3dc57e355fcba24ce4a5af1227c4e4829b801a5');
  c_src_pricing constant text[] := array['https://quotesdone.com/terms', 'https://quotesdone.com/supplier-agreement',
    'https://quotesdone.com/faq'];
  c_src_rules constant text[] := array['https://quotesdone.com/terms', 'https://quotesdone.com/supplier-agreement',
    'https://quotesdone.com/how-it-works', 'https://quotesdone.com/faq'];
  v_sup text[];
  n int;
  bad text;
begin
  select array_agg(k order by k) into v_sup from jsonb_object_keys(c_sup) k;

  -- 1a. exactly the 16 FAQ rows, each the composer's copy of the published FAQ
  select count(*) into n from public.ops_knowledge
   where record_id = any (c_faq) and module = 'faq' and 'fn_company_org_directory_sync' = any (source_ids);
  if n <> 16 then raise exception 'REFUSED: expected 16 qd-company:faq-* rows from fn_company_org_directory_sync, found %', n; end if;

  -- 1b. each one's text must still equal the published FAQ: recomposed exactly as fn_company_org_directory_sync and
  --     fn_company_knowledge_upsert write it, from company_faq rows with public = true only
  with pub as (
    select 'qd-company:faq-' || regexp_replace(lower(sec), '[^a-z0-9]+', '-', 'g') as record_id,
           'QuotesDone FAQ — ' || sec as title,
           'FREQUENTLY ASKED (published answers — you may give these to customers and suppliers):' || E'\n' || left(qa, 6000)
           || E'\n\nYou can answer questions about: '
           || array_to_string(array['faq', 'frequently asked', sec, 'question', 'answer', 'how do i', 'what is',
                                    'customer question', 'supplier question'], ', ') || '.' as content
      from (select coalesce(nullif(btrim(section), ''), 'general') as sec,
                   string_agg('Q: ' || question || E'\n' || 'A: ' || coalesce(answer, ''), E'\n' order by sort nulls last, id) as qa
              from public.company_faq
             where public = true and coalesce(status, 'approved') <> 'rejected'
             group by 1) s)
  select string_agg(o.record_id, ', ' order by o.record_id) into bad
    from public.ops_knowledge o left join pub p on p.record_id = o.record_id
   where o.record_id = any (c_faq) and (p.record_id is null or o.content is distinct from p.content or o.title is distinct from p.title);
  if bad is not null then
    raise exception 'REFUSED: these FAQ rows no longer equal the published company_faq (public = true): %. Run fn_company_org_directory_sync() and re-check before promoting.', bad;
  end if;

  -- 2a. exactly the 4 support rows, with the bodies that were checked against the published pages
  select count(*) into n from public.support_knowledge s
   where s.record_id = any (v_sup) and s.pack_id = 'verified:seat:customer_support' and s.body_sha256 = c_sup ->> s.record_id;
  if n <> 4 then
    raise exception 'REFUSED: expected 4 customer_support rows (company-pricing, company-hard-rules-marketplace, en + @ar) with the verified bodies, found %', n;
  end if;

  -- 1c. promote
  update public.ops_knowledge set confidentiality = 'public'
   where record_id = any (c_faq) and confidentiality is distinct from 'public';
  select count(*) into n from public.ops_knowledge where record_id = any (c_faq) and confidentiality = 'public';
  if n <> 16 then raise exception 'REFUSED: % of 16 FAQ rows are public after the update', n; end if;

  -- 2b. retag (idempotent: the provenance recorded the first time is kept on a re-run)
  update public.support_knowledge s set
    tags = array(select t from unnest(s.tags) with ordinality u(t, o)
                  where t not in ('kind:company', 'audience:internal', 'kind:published_terms') order by o)
           || array['kind:published_terms'],
    domain = 'published_terms',
    source_ids = case when s.record_id like 'customer_support:company-pricing%' then c_src_pricing else c_src_rules end,
    source_path = 'https://quotesdone.com/terms',
    structured_data = coalesce(s.structured_data, '{}'::jsonb) || jsonb_build_object('retag', coalesce(s.structured_data -> 'retag',
      jsonb_build_object('on', '2026-10-27', 'by', 'customer_support', 'approved', 'founder ledger 1348',
        'reason', 'published content; facts checked against /terms, /supplier-agreement, /how-it-works and the public FAQ',
        'was_tags', to_jsonb(s.tags), 'was_source_ids', to_jsonb(s.source_ids), 'was_domain', s.domain)))
   where s.record_id = any (v_sup);

  -- 2c. none of the 4 may still match #1660's outside-audience exclusion
  select count(*) into n from public.support_knowledge s
   where s.record_id = any (v_sup)
     and not (s.tags && array['audience:internal', 'kind:company']
              or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'));
  if n <> 4 then raise exception 'REFUSED: % of 4 retagged rows clear the outside-audience exclusion', n; end if;
end $apply$;

select 'APPLIED: 16 published-FAQ ops rows public; 4 customer_support rows (2 entries, en + ar) retagged' as verdict;
