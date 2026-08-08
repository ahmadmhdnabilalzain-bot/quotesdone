CREATE OR REPLACE FUNCTION public.fn_supplier_score_refresh()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  insert into supplier_score (lead_id, response_rate, avg_response_hours, quotes_submitted, quotes_won,
                              rejection_count, price_index, quality_rating, reliability, last_active, computed_at)
  select l.id,
         coalesce(l.rv_response_rate, 0),
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
         round(least(100, greatest(0,
             coalesce(l.rv_response_rate,0) * 0.55
           + (case when coalesce(q.submitted,0) > 0 then 100.0*coalesce(q.won,0)/q.submitted else 0 end) * 0.25
           + (case when l.verified then 20 else 0 end)
           - coalesce(q.rejected,0) * 2
           - coalesce(l.rv_nonresponse_refunds,0) * 5
         )), 1),
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
end; $function$
;
