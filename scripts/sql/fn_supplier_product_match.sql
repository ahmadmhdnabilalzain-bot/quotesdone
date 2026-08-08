-- ROW #5 §8 — HOW WELL DOES EACH OF MY PRODUCTS FIT THIS ENQUIRY?
--
-- §7 gave the supplier a product store. §8 asks the next question: when a request arrives, which of
-- my products actually answers it, and how well? A product card showing a match percentage the
-- browser invented is a decoration; this computes it from the two things that exist — what the
-- customer wrote, and what the product record says.
--
-- ── THE ARITHMETIC, STATED ──────────────────────────────────────────────────────────────────────
--   category      the product's category against the enquiry's           weight 40
--   term overlap  significant words from the enquiry found in the        weight 60
--                 product's name, brand, model and description
--
-- match_pct is the weights that APPLIED over the weights that COULD apply — the same rule
-- fn_supplier_opportunities uses. A signal that cannot be asked leaves the denominator rather than
-- scoring zero, because a zero is a judgement and an absent signal is not.
--
-- ── AND IT IS LEXICAL, WHICH IS A CEILING WORTH NAMING ──────────────────────────────────────────
-- pgvector is installed and supplier_product carries no embedding, so this matches on words, not
-- meaning: a customer asking for "glazing" will not be matched to a product described only as
-- "fenestration". `basis` says so in the payload rather than letting a percentage imply more
-- understanding than the routine has. Embedding the product store is the upgrade, and it is a
-- different piece of work.
create or replace function public.fn_supplier_product_match(p_inquiry_id uuid, p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with inq as (
    -- EVERYTHING THE CUSTOMER SAID, not the first field that happens to be non-empty. The first
    -- version preferred raw_input and fell back to summary, and on the demo enquiry that discarded
    -- the only line describing the work — every product scored 0% while the store held a curtain
    -- wall profile and the enquiry was for curtain walling. A brief's title carries meaning too,
    -- and dropping it to honour a precedence rule loses signal for nothing.
    select lower(coalesce(category, '')) cat,
           lower(concat_ws(' ', coalesce(summary, ''), coalesce(raw_input, ''), coalesce(category, ''))) want
      from public.inquiries where id = p_inquiry_id
  ),
  -- Words worth matching on. Anything under four characters is noise ("we", "for", "the"), and a
  -- stop list would be a maintenance burden for no gain at this size.
  terms as (
    select distinct w from inq, unnest(regexp_split_to_array(inq.want, '[^a-z0-9]+')) w
     where length(w) >= 4
  ),
  prod as (
    select p.id, p.name, p.brand, p.model, p.category_slug,
           lower(concat_ws(' ', p.name, p.brand, p.model, p.description, p.category_slug)) hay
      from public.supplier_product p
     where p.supplier_id = p_lead_id
  ),
  -- ── THE DENOMINATOR IS THE PRODUCT, NOT THE BRIEF ──────────────────────────────────────────────
  -- Scoring matched-terms over ALL the brief's words made the exactly-right product read 6%:
  -- "Aluminium curtain wall profile" matched 2 of 32 words in a paragraph that also discussed
  -- square metres, retail units and powder coating. That understates as badly as an inflated score
  -- overstates, and a supplier seeing 6% on their best product would conclude the matching is
  -- broken — which it would be.
  --
  -- The question is not "how much of the brief does this product cover" (no single product covers
  -- a brief) but "how much of THIS PRODUCT does the brief ask for". Aluminium ✓ curtain ✓ wall ✓
  -- profile ✗ is a strong match, and reads as one.
  pterms as (
    select pr.id pid, w from prod pr,
      unnest(regexp_split_to_array(lower(concat_ws(' ', pr.name, pr.category_slug)), '[^a-z0-9]+')) w
     where length(w) >= 4
  ),
  hit as (
    select pr.id, pr.name, pr.brand, pr.model, pr.category_slug, pr.hay,
           (select count(*) from pterms pt, inq where pt.pid = pr.id and position(pt.w in inq.want) > 0) matched_terms,
           (select count(*) from pterms pt where pt.pid = pr.id) total_terms,
           (pr.category_slug is not null and pr.category_slug = (select cat from inq)) cat_hit,
           ((select cat from inq) <> '' and pr.category_slug is not null) cat_askable
      from prod pr
  ),
  scored as (
    select h.*,
      round(100.0 * (
          (case when h.cat_hit then 40 else 0 end)
        + (case when h.total_terms > 0 then 60.0 * h.matched_terms / h.total_terms else 0 end)
      ) / nullif((case when h.cat_askable then 40 else 0 end)
               + (case when h.total_terms > 0 then 60 else 0 end), 0)) match_pct
      from hit h
  )
  select jsonb_build_object(
    'inquiry_id', p_inquiry_id,
    'supplier_id', p_lead_id,
    'basis', 'lexical: the enquiry''s own words against the product record. Not semantic — supplier_product carries no embedding, so a synonym will not match.',
    'population', jsonb_build_object(
      'products', (select count(*) from prod),
      'terms_from_enquiry', (select count(*) from terms),
      'note', case when (select count(*) from prod) = 0
                   then 'you have no products yet — upload a catalog and these become matchable'
                   when (select count(*) from terms) = 0
                   then 'the enquiry has no description to match against, so only category could be asked'
                   else null end),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object(
          'product_id', s.id, 'name', s.name, 'brand', s.brand, 'model', s.model,
          'match_pct', s.match_pct,
          'matched_terms', s.matched_terms, 'terms_considered', s.total_terms,
          'category_match', s.cat_hit)
        order by s.match_pct desc nulls last, s.name)
      from scored s), '[]'::jsonb)
  );
$function$;
