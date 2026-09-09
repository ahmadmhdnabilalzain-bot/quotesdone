-- THE VISITOR ASKED WHAT IT COSTS, AND THE ESTATE KNEW.
--
-- MEASURED, 10 September 2026. A real visitor asked the homepage widget:
--
--     "what should a gypsum false ceiling cost per square metre in Dubai"
--
-- The widget refused and filed it as knowledge gap #12. At that moment
-- public.price_benchmark held 27 rows in category 'gypsum', including a published company cost
-- guide row "Plain gypsum ceiling (per sqm)" at AED 35-70 dated 28 June 2026, a grid/mineral-fibre
-- tile ceiling at AED 45-90, and a designed/cove/tray ceiling at AED 60-120.
--
-- The company had the answer, in AED, sourced and dated, and the seat that faced the customer
-- could not see it.
--
-- WHY NOT, measured rather than assumed: exactly ONE routine in the database reads
-- price_benchmark, fn_price_confidence, and exactly one edge function does, negotiation_assistant.
-- Neither is the customer-facing widget. fn_price_confidence is also the wrong shape for this
-- question -- it answers "is THIS amount fair?" and requires p_amount to get in the door. The
-- visitor asked the opposite question and had no amount to offer.
--
-- This is the founder's instruction of 9 September -- "Those knowledge gaps, you need to fill them
-- properly -- no pricing at all" -- built but not connected. 1,086 UAE rates across 52 trades were
-- gathered, and the one seat a customer actually talks to was never given them.
--
-- -- WHAT THIS ROUTINE WILL NOT DO --------------------------------------------------------------
--
-- 1. IT WILL NOT RETURN A NEAREST NEIGHBOUR. This estate has been bitten before by retrieval that
--    always finds something: a nearest match is always available and is silently wrong. Every
--    answer here requires LEXICAL CORROBORATION -- at least one substantive word from the visitor's
--    own question must literally appear in the trade or the item. No corroboration, no answer.
--
-- 2. IT WILL NOT QUOTE A PRICE AS THE PRICE. QuotesDone does not sell the work; suppliers do. A
--    published cost-guide range is orientation, and the routine says so in every payload rather
--    than leaving the model to remember. The real number comes from supplier quotes.
--
-- 3. IT WILL NOT GUESS A TRADE THE ESTATE DOES NOT COVER. Four categories carry a deliberate `gap`
--    row -- elevators, combined-mep, water-tank-cleaning, engineering-and-architectural-
--    consultancies -- recorded precisely so that silence is distinguishable from ignorance. Those
--    return the refusal and its reason, never a substituted trade.
--
-- 4. IT WILL NOT PRETEND A TRADE MATCH IS AN ITEM MATCH. "HVAC chiller replacement" matches the
--    hvac trade; the estate holds no chiller row at all. The payload carries item_specific=false in
--    that case, so the answer can say "here is what HVAC work runs at, but I have nothing specific
--    on chillers" instead of implying the chiller figure exists.

create or replace function public.fn_price_guidance(p_question text, p_limit int default 6)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_terms   text[];
  v_cat     text;
  v_gap     text;
  v_items   jsonb;
  v_hit     boolean;
  v_matched   text[];
  v_unmatched text[];
begin
  -- THE VISITOR'S OWN WORDS, reduced to substantive ones. Four characters is the floor because
  -- 'ac' and 'mep' would otherwise match half the estate, and the question words ('what', 'cost',
  -- 'much', 'price', 'should') are dropped explicitly -- they are what makes it a price question,
  -- not what makes it a gypsum question.
  select array_agg(distinct t)
    into v_terms
    from regexp_split_to_table(lower(coalesce(p_question, '')), '[^a-z0-9]+') as t
   where length(t) >= 4
     and t not in ('what','cost','costs','much','price','prices','pricing','should','would','does',
                   'about','around','many','rate','rates','average','typical','range','dubai','uae',
                   'emirates','abu','dhabi','sharjah','from','with','that','this','have','need',
                   'your','you','per','the','and','for','square','metre','meter','sqft','feet');

  if v_terms is null or array_length(v_terms, 1) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'no_substantive_terms',
      'note', 'The question carried no trade word to look up. Ask the visitor which trade they mean.');
  end if;

  -- WHICH TRADE, scored by how many of the visitor's own words appear in it.
  --
  -- A MATCH ON THE TRADE NAME IS WORTH TEN TIMES A MATCH IN ITEM TEXT, and that weighting is not
  -- taste -- the first version of this file scored them equally and the probe below caught it
  -- immediately: "how much does an elevator installation cost" came back as FLOORING. Both trades
  -- scored 1 (elevators on the word 'elevator', flooring on the word 'installation', which appears
  -- in its item text), and the tie broke toward flooring because it holds 60 rows to elevators' 1.
  -- A generic verb the visitor happened to use outvoted the name of the trade they asked about, and
  -- the deliberate elevators gap row was skipped entirely. Ties still break toward the trade with
  -- more evidence, but only among trades that matched the same way.
  select r.category
    into v_cat
    from (
      select c.category, c.n,
             10 * (select count(distinct x) from unnest(v_terms) x
                    where replace(c.category, '-', ' ') like '%' || x || '%')::int
                + (select count(distinct x) from unnest(v_terms) x
                    where c.items like '%' || x || '%')::int as score
        from (select pb.category,
                     count(*) as n,
                     lower(string_agg(coalesce(pb.item, ''), ' ')) as items
                from public.price_benchmark pb
               group by pb.category) c
    ) r
   where r.score > 0
   order by r.score desc, r.n desc
   limit 1;

  -- NO CORROBORATION, NO ANSWER. This is the whole guard against a confident wrong trade.
  if v_cat is null then
    return jsonb_build_object('ok', false, 'reason', 'no_trade_matched',
      'terms_tried', to_jsonb(v_terms),
      'note', 'No trade in the estate shares a word with this question. Do not substitute a nearby '
           || 'trade; say the platform holds no published range for it and offer to collect quotes.');
  end if;

  -- A DELIBERATE GAP IS AN ANSWER. It is the difference between "we have not got it" and "we do
  -- not know", and the row was written to preserve exactly that difference.
  select pb.gap_reason into v_gap
    from public.price_benchmark pb
   where pb.category = v_cat and pb.source_kind = 'gap'
   limit 1;
  if v_gap is not null then
    return jsonb_build_object('ok', false, 'reason', 'trade_has_a_recorded_gap',
      'trade', v_cat, 'gap_reason', v_gap,
      'note', 'Tell the visitor plainly that we publish no range for this trade rather than '
           || 'estimating one, and offer to put it out to suppliers.');
  end if;

  -- DID ANY ITEM MATCH THE VISITOR'S OWN WORDS, or only the trade name? A trade-level answer to an
  -- item-level question is honest only when it says which it is.
  select bool_or(q.hit) into v_hit
    from (select exists (select 1 from unnest(v_terms) x
                          where lower(coalesce(pb.item, '')) like '%' || x || '%') as hit
            from public.price_benchmark pb
           where pb.category = v_cat and pb.source_kind <> 'gap' and pb.item is not null) q;
  v_hit := coalesce(v_hit, false);

  -- THE NAMED BANDS. When items matched, only the matching items come back; otherwise the trade's
  -- bands come back flagged as trade-level.
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', i.item, 'unit', i.unit, 'basis', i.basis_kind,
           'low', i.low, 'high', i.high, 'currency', coalesce(i.currency, 'AED'),
           'evidence', left(i.evidence, 180),
           'source', i.source_kind || coalesce(':' || i.source_ref, ''),
           'as_of', i.as_of) order by i.low), '[]'::jsonb)
    into v_items
    from (
      select distinct on (pb.item, pb.unit)
             pb.item, pb.unit, pb.basis_kind, pb.low, pb.high, pb.currency, pb.evidence,
             pb.source_kind, pb.source_ref, pb.as_of
        from public.price_benchmark pb
       where pb.category = v_cat and pb.source_kind <> 'gap' and pb.item is not null
         and (not v_hit
              or exists (select 1 from unnest(v_terms) x
                          where lower(coalesce(pb.item, '')) like '%' || x || '%'))
       order by pb.item, pb.unit, (case when pb.source_kind = 'blog_post' then 0 else 1 end)
    ) i;

  select array_agg(distinct x) into v_matched
    from unnest(v_terms) x
   where replace(v_cat, '-', ' ') like '%' || x || '%'
      or exists (select 1 from public.price_benchmark pb
                  where pb.category = v_cat and lower(coalesce(pb.item, '')) like '%' || x || '%');

  -- THE WORDS THE ESTATE HAD NOTHING FOR. This is the field that keeps the answer honest, and it
  -- exists because item_specific alone was not enough: "what does an HVAC chiller replacement cost"
  -- sets item_specific=true on the strength of the word 'replacement' appearing in hvac item text,
  -- while the estate holds no chiller row at all. A caller reading only item_specific would present
  -- HVAC replacement rates as though they answered the chiller question.
  --
  -- Naming the unmatched word is better than trying to classify 'replacement' as too generic to
  -- count -- that classifier would need a list of every generic construction verb, and would be
  -- wrong the first time a trade legitimately contained one. This says exactly what happened: we
  -- matched on these words, we hold nothing under this one.
  select array_agg(distinct x) into v_unmatched
    from unnest(v_terms) x
   where not (replace(v_cat, '-', ' ') like '%' || x || '%')
     and not exists (select 1 from public.price_benchmark pb
                      where pb.category = v_cat and lower(coalesce(pb.item, '')) like '%' || x || '%');

  return jsonb_build_object(
    'ok', true,
    'trade', v_cat,
    'item_specific', v_hit,
    'matched_terms', to_jsonb(coalesce(v_matched, '{}'::text[])),
    'unmatched_terms', to_jsonb(coalesce(v_unmatched, '{}'::text[])),
    'band_count', jsonb_array_length(v_items),
    'bands', case when jsonb_array_length(v_items) > greatest(1, coalesce(p_limit, 6))
                  then (select jsonb_agg(s.e)
                          from (select e from jsonb_array_elements(v_items) e
                                 limit greatest(1, coalesce(p_limit, 6))) s)
                  else v_items end,
    -- SAID IN THE PAYLOAD, NOT LEFT TO THE MODEL. A rule that lives only in a prompt is a rule the
    -- model may drop under length pressure; this one travels with the numbers it governs.
    'how_to_use', 'These are PUBLISHED GUIDE RANGES in AED for the UAE market, with their source '
               || 'and date. They are orientation, never a quotation. QuotesDone does not price the '
               || 'work - suppliers do. Give the range, name it as a guide, and offer to collect '
               || 'real quotes. Never present a single figure as the price, never average a band '
               || 'into one number, and never state a figure that is not in bands above. If '
               || 'unmatched_terms is not empty, say plainly that the platform publishes no range '
               || 'for that specific thing, rather than letting the trade-level bands stand in for '
               || 'it.');
end $fn$;
revoke execute on function public.fn_price_guidance(text, int) from public, anon, authenticated;

-- -- PROVE IT ON THE QUESTION THAT WAS ACTUALLY REFUSED -------------------------------------------
-- This file defines a routine, so the probe must NOT end in `raise exception` -- that would roll the
-- create back with it, and the apply would report success over an un-built function. It reads only;
-- there is nothing to clean up.
do $do$
declare v jsonb; g jsonb; n jsonb; h jsonb;
begin
  -- 1. THE REAL REFUSED QUESTION, verbatim from sales_knowledge_gap #12.
  v := public.fn_price_guidance('what should a gypsum false ceiling cost per square metre in Dubai');
  if not (v->>'ok')::boolean then
    raise exception 'the question that started this still cannot be answered: %', v->>'reason';
  end if;
  if v->>'trade' <> 'gypsum' then
    raise exception 'matched trade % instead of gypsum', v->>'trade';
  end if;
  if not (v->>'item_specific')::boolean then
    raise exception 'the ceiling items did not match, so the answer would be trade-level only';
  end if;
  if jsonb_array_length(v->'bands') = 0 then
    raise exception 'gypsum matched but returned no bands';
  end if;

  -- 2. A TRADE WITH A DELIBERATE GAP must refuse and say why, never substitute a neighbour.
  g := public.fn_price_guidance('how much does an elevator installation cost');
  if (g->>'ok')::boolean then
    raise exception 'elevators has a recorded gap and was answered anyway, as trade %', g->>'trade';
  end if;
  if g->>'reason' <> 'trade_has_a_recorded_gap' then
    raise exception 'elevators refused for the wrong reason: %', g->>'reason';
  end if;

  -- 3. NO CORROBORATION, NO ANSWER. The nearest neighbour is always there; it must not be returned.
  n := public.fn_price_guidance('how much does it cost to charter a helicopter to the moon');
  if (n->>'ok')::boolean then
    raise exception 'answered a trade the estate does not hold, as %', n->>'trade';
  end if;

  -- 4. A TRADE MATCH THAT IS NOT AN ITEM MATCH must say so. The estate holds 33 hvac rows and no
  --    chiller row at all -- measured. An answer that hid that distinction would imply a chiller
  --    figure exists.
  h := public.fn_price_guidance('what does an HVAC chiller replacement cost');
  if not (h->>'ok')::boolean then
    raise exception 'hvac did not match at all: %', h->>'reason';
  end if;
  if not (h->'unmatched_terms' @> '["chiller"]'::jsonb) then
    raise exception 'the estate holds no chiller row, but chiller was not reported as unmatched: %',
      h->>'unmatched_terms';
  end if;

  raise notice 'THE SEAT CAN ANSWER A PRICE QUESTION NOW. Gap #12 (gypsum false ceiling) resolves to trade=% with % band(s), item-specific. Elevators refuses with its recorded gap reason. An off-estate question returns no trade rather than a nearest neighbour. HVAC matches the trade but returns chiller in unmatched_terms, because the estate holds no chiller row anywhere.',
    v->>'trade', jsonb_array_length(v->'bands');
end
$do$;
