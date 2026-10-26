-- Twenty thousand suppliers rated zero for work never offered — 12 Aug 2026
--
-- fn_supplier_score_refresh writes `coalesce(l.rv_response_rate, 0)` as response_rate, and derives
-- reliability from that same coalesced value. A supplier who has never been sent an RFQ therefore
-- carries a 0% response rate and 0.0 reliability — the arithmetic of 0/0 resolved as if it were 0/n.
--
-- Measured on production before changing anything:
--
--   supplier_score            20,470 rows
--   response_rate = 0         20,468
--   reliability   = 0.0       20,468
--   leads with a non-null rv_response_rate        3 of 20,471
--   inquiry_supplier_brief rows EVER              0
--   inquiry_matches rows EVER                     0
--
-- Not one supplier has ever been sent anything. Every one of those zeros is a verdict on a request
-- that was never made.
--
-- THE PRINCIPLE IS ALREADY IN THIS FUNCTION, three lines below, and was simply not applied to these
-- two columns. quality_rating carries a founder decision from 8 Aug in its own comment: "an unrated
-- supplier is unrated, and must never look like one every customer disliked." A supplier nobody has
-- asked is not a supplier who ignores you. Same reasoning, same treatment.
--
-- WHY IT MATTERS NOW RATHER THAN LATER. SupplierRelationship.tsx and SupplierTwin.tsx render these
-- to the SUPPLIER'S OWN PORTAL. Lead 30466 is the first real registered supplier and has no score
-- row yet only because the nightly refresh ran at 03:40 and they confirmed at 11:36; tonight's run
-- would have introduced them to the platform with a 0% response rate for RFQs that do not exist.
-- The invite ramp is about to put thousands more in the same position.
--
-- NULL, not zero, and only where there is NO evidence either way: a supplier with a real response
-- rate, or with quotes submitted, keeps the existing formula unchanged and byte-identical. This is
-- the supply-side twin of the employee `unmeasured` tier shipped this morning — absence of evidence
-- gets its own value rather than borrowing the worst one.
--
-- The UI needs no change: both components already guard with `typeof x === 'number'` / `!= null`,
-- so a NULL hides the tile instead of drawing a zero. Verified by reading both call sites.

create or replace function public.fn_supplier_score_refresh()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare n integer;
begin
  insert into supplier_score (lead_id, response_rate, avg_response_hours, quotes_submitted, quotes_won,
                              rejection_count, price_index, quality_rating, reliability, last_active, computed_at)
  select l.id,
         -- NO COALESCE. A null rv_response_rate means nobody has asked this supplier for anything,
         -- and 0% is a different claim entirely.
         l.rv_response_rate,
         null,
         coalesce(q.submitted, 0),
         coalesce(q.won, 0),
         coalesce(q.rejected, 0),
         q.price_index,
         -- QUALITY RATING IS EARNED ON THE PLATFORM, NOT SCRAPED FROM GOOGLE.
         -- Founder decision, 2026-08-08: rating exists only for VERIFIED suppliers, and comes from
         -- the customer's own 1-5 review after a job. leads.rating is the Google Maps star rating of
         -- a business we have never worked with; presenting it as a QuotesDone quality rating is a
         -- claim the platform has not earned. NULL when unverified or unreviewed -- an unrated
         -- supplier is unrated, and must never look like one every customer disliked.
         case when not coalesce(l.verified, false) then null
              else (select round(avg(rv.rating)::numeric * 20, 1)
                      from reviews rv where rv.supplier_id = l.id) end,
         -- Reliability: response behaviour dominates, win rate confirms it, rejections and refunds subtract.
         -- UNMEASURED IS NOT UNRELIABLE (12 Aug 2026). With no response history AND no quotes there is
         -- nothing to score, so this is NULL rather than 0 -- the same call the quality_rating comment
         -- above makes, and the same one fn_reputation_recompute now makes for employees. Note that
         -- verification alone must not manufacture a score either: the +20 below is a bonus on top of
         -- evidence, not evidence.
         case when l.rv_response_rate is null and coalesce(q.submitted, 0) = 0 then null
              else round(least(100, greatest(0,
                     coalesce(l.rv_response_rate,0) * 0.55
                   + (case when coalesce(q.submitted,0) > 0 then 100.0*coalesce(q.won,0)/q.submitted else 0 end) * 0.25
                   + (case when l.verified then 20 else 0 end)
                   - coalesce(q.rejected,0) * 2
                   - coalesce(l.rv_nonresponse_refunds,0) * 5
                 )), 1)
         end,
         greatest(l.portal_updated_at, l.approved_at, l.scraped_at),
         now()
  from leads l
  left join (
    select q.supplier_id,
           count(*) as submitted,
           count(*) filter (where q.status = 'won')      as won,
           count(*) filter (where q.status = 'rejected') as rejected,
           round(avg(q.quote_amount) filter (where q.quote_amount > 0), 2) as price_index
    from quotes q group by q.supplier_id
  ) q on q.supplier_id = l.id
  where l.id is not null
  on conflict (lead_id) do update set
    response_rate = excluded.response_rate, quotes_submitted = excluded.quotes_submitted,
    quotes_won = excluded.quotes_won, rejection_count = excluded.rejection_count,
    price_index = excluded.price_index, quality_rating = excluded.quality_rating,
    reliability = excluded.reliability, last_active = excluded.last_active, computed_at = now();
  get diagnostics n = row_count;
  return n;
end; $function$;
