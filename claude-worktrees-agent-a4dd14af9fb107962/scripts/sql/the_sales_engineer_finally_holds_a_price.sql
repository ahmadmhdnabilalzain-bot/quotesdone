-- THE SALES ENGINEER FINALLY HOLDS A PRICE (9 Sep 2026). Agent: ceo.
-- Third leg of founder instruction #15, and the leg that makes the other two matter.
--
-- MEASURED. sales_knowledge holds 1,136 rows and ZERO of them contain the string "AED". The seat
-- whose recorded purpose includes "whether an inquiry is quote-ready and on what quote basis" could
-- not sanity-check a single number. price_benchmark now holds 1,082 UAE rates, and
-- fn_price_confidence reads them -- but fn_price_confidence is called by the quote surfaces, not by
-- the seat's own retrieval. A fact the seat cannot RETRIEVE is a fact the seat does not have.
--
-- THE RETRIEVAL DISCIPLINE IS THE POINT. fn_sales_assist admits a row only if it clears cosine 0.86
-- AND corroborates lexically, or -- for a row with no embedding -- clears the stricter lexical-only
-- bar of 0.20 on its own. So these records are written to be admitted on their merits:
--   * one record per trade, not one per rate, so the trade name and the figures sit in the same row
--     and a question about that trade matches the row that answers it;
--   * the trade label, its category slug, "AED", "price", "rate" and the unit words are all present
--     as literal lexemes, because the lexical leg matches lexemes and not intentions;
--   * every band names its own source and date inline, so a passage quoted verbatim by
--     fn_sales_assist (which quotes, never restates) carries its provenance with it.
--
-- These rows land with embedding_gte NULL and are retrievable IMMEDIATELY through the lexical-only
-- route. `node scripts/kb/embed_sales_knowledge.mjs` then embeds them through the same free
-- in-region gte-small path and they become retrievable semantically as well.
--
-- NOT ONE FIGURE IS WRITTEN HERE. Every number is selected out of price_benchmark, which selected
-- it out of blog_posts and kb_chunks. The gap trades get a record too, and what that record says is
-- that the estate has no price for them -- because a seat that knows it does not know is worth more
-- than a seat that guesses, and because fn_sales_assist's whole design is built around a refusal
-- being a legitimate answer.
--
--   node scripts/apply_sql.mjs scripts/sql/the_sales_engineer_finally_holds_a_price.sql --apply --ddl

begin;

with band as (
  select distinct on (pb.category, pb.item, pb.unit)
         pb.category, pb.item, pb.unit, pb.low, pb.high, pb.source_kind, pb.source_ref, pb.as_of
    from public.price_benchmark pb
   where pb.source_kind <> 'gap' and pb.item is not null
   order by pb.category, pb.item, pb.unit,
            (case when pb.source_kind = 'blog_post' then 0 else 1 end), pb.low
), lines as (
  select b.category,
         string_agg(
           '  - ' || b.item || ': AED ' || trim(to_char(b.low, 'FM999,999,990.99'))
             || ' to ' || trim(to_char(b.high, 'FM999,999,990.99'))
             || ' per ' || b.unit
             || ' (source: ' || b.source_kind || ' ' || b.source_ref
             || coalesce(', as of ' || b.as_of::text, '') || ')',
           E'\n' order by b.low)                                      as body,
         count(*)                                                     as n_bands,
         string_agg(distinct b.unit, ', ' order by b.unit)            as units,
         array_agg(distinct b.source_kind || ':' || b.source_ref)     as srcs,
         max(b.as_of)                                                 as newest
    from band b group by b.category
), rec0 as (
  -- taxonomy_trade.aliases is the estate's existing record of what customers CALL a trade, and it
  -- is the difference between a record being found and not. Measured: "cost of a lift installation
  -- in Dubai" reached nothing, because category_specs calls that trade "Elevators" and no row said
  -- "lift". taxonomy_trade already held 'lift installation' as an alias of `elevators`. 27 of the
  -- 56 spec categories join to a trade code; the other 29 carry only their own label, and that is
  -- recorded as a gap rather than invented.
  select cs.category, cs.label, l.body, l.n_bands, l.units, l.srcs, l.newest,
         (select string_agg(distinct a, ', ' order by a)
            from public.taxonomy_trade t, unnest(t.aliases) a
           where t.active and (t.code = cs.category or t.code = replace(cs.category, '-', '_')
                               or cs.category = any(t.aliases))) as aliases
    from public.category_specs cs
    left join lines l on l.category = cs.category
), rec as (
  -- The content is assembled ONCE here, so the stored row and its sha256 cannot disagree: computing
  -- the digest over a second copy of the same expression is exactly how a checksum stops checking.
  select r.*,
         case when r.body is null then
           'Trade: ' || r.label || ' (category ' || r.category || '). UAE price benchmark, AED.' || E'\n\n'
           || 'THERE IS NO PRICE EVIDENCE FOR THIS TRADE IN THE ESTATE. Not in the 29 UAE cost guides '
           || 'QuotesDone has published, and not in the AED unit rates extractable from kb_chunks. '
           || 'No figure has been invented to fill the space. Do not quote a rate, a range or an order '
           || 'of magnitude for ' || r.label || ' from this record: say the benchmark is not held, ask '
           || 'the customer for their budget basis, or price it from a supplier submittal. '
           || 'The gap is recorded in price_benchmark where source_kind = ''gap''.' || E'\n\n'
           || 'COVERAGE. This trade covers the United Arab Emirates: Dubai, Abu Dhabi, Sharjah, '
           || 'Ajman, Ras Al Khaimah, Fujairah and Umm Al Quwain. '
           || coalesce('Also called: ' || r.aliases || '. ', '')
           || 'There is still no rate for it, in any emirate and under any of those names.'
         else
           'Trade: ' || r.label || ' (category ' || r.category || '). UAE price benchmark in AED, '
           || r.n_bands || ' rate bands, priced per ' || r.units || '.' || E'\n\n'
           || 'What a quote for this trade should cost in the UAE (indicative published ranges, AED):' || E'\n'
           || r.body || E'\n\n'
           || 'HOW TO USE THIS. These are published indicative ranges, not this company''s own '
           || 'transacted quotes -- QuotesDone has completed none yet, so category_price_stats is '
           || 'empty and every figure here comes from a published cost guide or from a sourced '
           || 'passage in the reference library. Match the customer''s scope to the NAMED band before '
           || 'judging a number: a category spans genuinely different products, and the spread within '
           || 'one trade is the specification, not a discount. A quote outside every band on this '
           || 'list is a question to ask the supplier, never on its own a finding. '
           || 'fn_price_confidence(category, amount, quantity, unit) returns the same bands with a '
           || 'fairness band attached.' || E'\n\n'
           -- MEASURED, and the reason this paragraph exists. fn_sales_assist corroborates on the
           -- ALL-TERMS websearch query, so every word of the question must appear literally
           -- somewhere in the row. Without this paragraph the gypsum record scored ts_rank 0.0000
           -- on "what should a gypsum false ceiling cost per square metre in Dubai" -- not because
           -- the subject was wrong but because the row said "UAE" where the customer said "Dubai"
           -- and "sqm" where the customer said "square metre". It answered "gypsum ceiling price
           -- per sqm UAE" at rank 1.0000 in the same breath. This is not keyword padding to get
           -- past a gate: it is the row stating, truthfully, which emirates its rates cover and
           -- what its own abbreviations mean. It is also exactly what the founder asked for on
           -- 9 Sep 2026 -- "you need to do it with keywords".
           || 'COVERAGE AND UNITS. These are UAE rates and are indicative across the United Arab '
           || 'Emirates: Dubai, Abu Dhabi, Sharjah, Ajman, Ras Al Khaimah, Fujairah and Umm Al '
           || 'Quwain. Abu Dhabi and the northern emirates typically differ from Dubai on '
           || 'mobilisation and access rather than on the rate itself. Units above read as '
           || 'follows: per sqm means per square metre, per square meter, per m2; per sqft means '
           || 'per square foot; per lm means per linear metre, per running metre; per each and per '
           || 'piece mean per item or per unit; per job means the whole job or project, not a rate. '
           || coalesce('This trade is also called: ' || r.aliases || '.', '')
         end as content_text
    from rec0 r
)
insert into public.sales_knowledge
  (record_id, record_type, domain, title, content, structured_data, source_ids, epistemic_status,
   jurisdiction, pack_id, pack_version, record_version, body_sha256, content_sha256,
   runtime_index_eligible, authority_effect, tags, updated_at, ingested_at)
select
  'QD-SE-PRICE-' || r.category,
  'price_benchmark',
  r.category,
  'UAE price benchmark: ' || r.label,
  r.content_text,
  jsonb_build_object('category', r.category, 'bands', coalesce(r.n_bands, 0),
                     'units', r.units, 'newest_evidence', r.newest,
                     'has_evidence', (r.body is not null)),
  coalesce(r.srcs, array['price_benchmark:gap']),
  'authored_guidance_not_expert_certified',
  'UAE',
  'QD-SALES-ENGINEER',
  '1.0.0',
  '1.0.0',
  encode(sha256(convert_to(r.content_text, 'UTF8')), 'hex'),
  encode(sha256(convert_to(r.content_text, 'UTF8')), 'hex'),
  true,
  'none',
  array['price', 'pricing', 'benchmark', 'rate', 'AED', 'UAE', 'cost', 'quote', r.category],
  now(), now()
  from rec r
on conflict (record_id) do update set
  content         = excluded.content,
  structured_data = excluded.structured_data,
  source_ids      = excluded.source_ids,
  tags            = excluded.tags,
  body_sha256     = excluded.body_sha256,
  content_sha256  = excluded.content_sha256,
  updated_at      = now(),
  -- The body changed, so any vector held for the old body is now wrong. Clearing it drops the row
  -- to the lexical-only route, which is stricter, until the embedder runs again. A stale vector
  -- would keep the row in the semantic index pointing at text that no longer exists.
  embedding_gte   = null;

commit;
