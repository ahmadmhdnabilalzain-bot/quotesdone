-- NO RIVAL'S PRICE CAN BE WORKED OUT, AND THE CUSTOMER SEES THE QUOTED PRICE.
-- Seat: sales_engineer. 19 Nov 2026. Founder rulings 1683 (anonymity is the most important thing on the platform), 1686 (an old
-- supplier's prices never reach new suppliers) and 1687 (VAT is the suppliers'; we collect none; the reveal fee is always
-- calculated on the quotation excluding VAT).
--
-- WHAT WAS MEASURED (origin/main 9d82984d4 and production, read-only, 19 Nov 2026; quotes 0, inquiries 0 on production, so no
-- live row is affected today and the evidence is the code and the probe below):
--   1. fn_supplier_stats.price_positioning sent a supplier avg_pct_above_lowest and avg_pct_vs_average to 0.1%, from a floor of
--      2 quotes per inquiry, counting drafts and withdrawn quotes. With one rival, the rival's price = mine / (1 + pct/100).
--      Served raw: supplier_portal/overview.ts buildDashboard, actions/dashboard.ts 'overview', insights_summary.ts.
--   2. fn_supplier_market.avg_market_price sent mean, median, p25, p75, low and high of every quote in the supplier's category
--      over 28 days, with no floor, no status filter and the asker's own quotes included. Two quotes = both exact prices.
--   3. fn_customer_decision_support ranked and printed quotes.customer_price, which is GENERATED with the retired tiered margin
--      (public.margin_rate: 10% under AED 2,000 ... 5% at 10,000-19,999 ... 3% from 50,000). The portal said "The cheapest is
--      AED 10,500" for a quotation of AED 10,000. Today the customer pays the supplier the quotation and our fee is 3% of it ex
--      VAT (supabase/functions/_shared/reveal_fee.ts). It also named a DRAFT as the cheapest, which no customer surface shows.
--   4. Every other live reader of customer_price or margin_rate (pg_proc.prosrc, 19 Nov): trg_version_quote (history only),
--      fn_ws_marketplace (the workspace UI renders no such field: grep of src/), fn_inquiry_conversation_summary_build (the
--      stored record of an inquiry, both figures labelled), and two that reach a person through a seat: fn_pool_say, the line
--      every seat reads ("a quotation of AED <customer_price> arrived"), and fn_company_self_knowledge_sync, whose
--      'quotation-format' record told every seat "the price the customer sees includes the platform margin".
--
-- WHAT THIS CHANGES (each routine is its pg_get_functiondef of 19 Nov 2026 with only the named lines changed; signatures,
-- search_path and ACLs are kept, and the revokes below restate them):
--   1. fn_supplier_stats: only submitted/revealed quotes on ENDED requests (completed, closed, cancelled, expired, lost), mine
--      against each OTHER company's lowest, an inquiry counts only with 3+ other companies on it, nothing is sent until 5
--      inquiries count ("not enough comparisons yet"), 5-point steps, the band read from the rounded average, times_lowest
--      null. Review of c1d1fd657: on an OPEN request a supplier can re-send his own price and binary-search it until
--      times_lowest flips, which gave the lowest rival on that request to 0.01% through any rounding.
--   2. fn_supplier_market: only other suppliers' submitted/revealed quotes; at least 5 quotes from 3 companies, or no price; low,
--      high and mean are gone; the median and the middle half, each on a step of half an order of magnitude (AED 100 at least).
--   3. fn_customer_decision_support: quote_amount (the quotation excluding VAT), drafts and held quotes left out.
--   4. fn_pool_say: "a quotation of AED <quote_amount> excluding VAT arrived".
--   5. fn_company_self_knowledge_sync: the quotation-format record says the price is the supplier's quotation ex VAT and that our
--      only charge is the 3% reveal fee; the one stored ops_knowledge row is corrected here so it is right before the next sync.
--   6. fn_inquiry_conversation_summary_build: the stored record of an inquiry keeps quote_amount, labelled excluding VAT, and no
--      longer the marked-up generated column. Summaries already stored are not rewritten (inquiry_conversation_summary: 0 rows
--      on 19 Nov 2026, as inquiries are 0).
-- The portal (DecisionSupport.tsx, MarketIntelligence.tsx, workspaceCopy.ts) and customer_api my_inquiries (jobs and match
-- banded through _shared/pre_reveal_bands.ts) change in the same commit.
--
-- HOW TO APPLY: node scripts/apply_sql.mjs scripts/sql/no_rival_price_can_be_worked_out_and_the_customer_sees_the_quoted_price.sql --apply --ddl
--   then append this file to the END of scripts/sql/MANIFEST.txt and delete its pending note in the same commit. The probe at the
--   end builds ZZ DEMO fixtures inside a sub-block that always rolls back, and RAISES if any property fails, which takes every
--   change in this file back with it: a failed probe deploys nothing. Run on the local database first (scripts/db/local_pg16.mjs).
--   RE-READ fn_company_self_knowledge_sync, fn_pool_say AND fn_inquiry_conversation_summary_build BEFORE APPLYING: this file carries their whole bodies, so a newer
--   definition applied after 19 Nov would be replaced by this one.
-- ROLLBACK: re-apply the previous canonical definitions (scripts/sql/MANIFEST.txt order): fn_supplier_stats from
--   a_supplier_rating_comes_from_quotesdone_customers_only.sql, fn_supplier_market from
--   the_supplier_portal_tells_one_truth_in_every_panel.sql, fn_customer_decision_support from fn_customer_decision_support.sql,
--   fn_pool_say from every_seat_reads_one_pool_and_every_hand_over_comes_back.sql, fn_company_self_knowledge_sync from the last
--   file in MANIFEST that defines it, fn_inquiry_conversation_summary_build from
--   a_closed_inquiry_quiet_for_ninety_days_gets_a_structured_summary_of_its_conversation.sql. Rolling back re-opens the leaks above; it needs the founder's word.
--
-- Pending: scripts/sql/pending/no_rival_price_can_be_worked_out_and_the_customer_sees_the_quoted_price.txt
-- Prevented by: supabase/functions/customer_api/no_badge_is_an_exact_fingerprint_before_the_reveal.test.ts,
--   supabase/functions/supplier_portal/insights_summary.test.ts, scripts/checks/no_rival_price_can_be_worked_out.test.mjs,
--   and the probe at the end of this file.

set local lock_timeout = '5s';

-- 1. fn_supplier_stats (live body of 19 Nov 2026; the price_positioning block is the change)
CREATE OR REPLACE FUNCTION public.fn_supplier_stats(p_supplier_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v jsonb; v_quotes int; v_reveals int; v_hired int; v_lost int;
  v_qd_rev numeric; v_deal_val numeric; v_avg_lead numeric;
  v_pos jsonb; v_hist jsonb; v_rating numeric; v_rating_pct numeric; v_resp numeric;
  v_pending_reviews int; v_active_rfqs int;
begin
  select count(*) into v_quotes from quotes where supplier_id=p_supplier_id;
  select count(*) into v_reveals from transactions where supplier_id=p_supplier_id;
  select count(*) into v_hired from inquiries where hired_supplier_id=p_supplier_id;
  select count(*) into v_lost from inquiries i
     where i.hired_supplier_id is not null and i.hired_supplier_id<>p_supplier_id
       and exists (select 1 from quotes q where q.inquiry_id=i.id and q.supplier_id=p_supplier_id);
  select coalesce(sum(coalesce(reveal_fee,0)+coalesce(app_fee,0)),0),
         coalesce(sum(coalesce(quote_amount,0)),0)
    into v_qd_rev, v_deal_val
    from transactions where supplier_id=p_supplier_id and coalesce(refund_status,'')<>'approved';
  select round(avg(nullif(regexp_replace(coalesce(lead_time,''),'[^0-9.]','','g'),'')::numeric),1)
    into v_avg_lead from quotes where supplier_id=p_supplier_id and lead_time ~ '[0-9]';
  select app_rating, rv_response_rate into v_rating, v_resp from leads where id=p_supplier_id;
  if v_rating is not null then
    select round(100.0*(count(*) filter (where l2.app_rating <= v_rating))/nullif(count(*),0),0)
      into v_rating_pct
      from leads l2 where l2.sector = (select sector from leads where id=p_supplier_id) and l2.app_rating is not null;
  end if;
  select count(*) into v_pending_reviews from quotes where supplier_id=p_supplier_id and coalesce(review_status,'')='pending';
  select count(distinct q.inquiry_id) into v_active_rfqs from quotes q join inquiries i on i.id=q.inquiry_id
    where q.supplier_id=p_supplier_id and coalesce(i.status,'') in ('open','active','collecting','live');
  -- PRICE POSITIONING WITHOUT A RIVAL'S PRICE (19 Nov 2026, sales_engineer; founder rulings 1683, 1686). The block this
  -- replaces compared every quote of mine with every quote on the inquiry, ANY status (drafts and withdrawn ones too), from
  -- a floor of two quotes, and sent avg_pct_above_lowest and avg_pct_vs_average to 0.1%. On one inquiry with one rival the
  -- rival's price was mine / (1 + pct_above_lowest/100) to the fils, served raw by supplier_portal (overview.ts
  -- buildDashboard, actions/dashboard.ts 'overview', insights_summary.ts). Now:
  --   * only SUBMITTED or REVEALED quotes count (a draft is not a bid; a withdrawn quote is no longer one);
  --   * only ENDED requests count (completed, closed, cancelled, expired, lost: _shared/request_closed.ts, the one list).
  --     On a request still taking quotes the supplier can re-send his own price (supplier_api/actions/quotes.ts) and read
  --     how the answer moves: review of #c1d1fd657 binary-searched his amount until times_lowest flipped, and recovered the
  --     lowest rival to 0.01% through the 5-point rounding (two neighbouring flips are 20 x his step / N apart);
  --   * my side is my lowest such quote per inquiry, the other side each OTHER company's lowest, so three options from one
  --     rival are one rival;
  --   * an inquiry counts only with at least 3 other companies on it, and no figure at all is sent until 5 inquiries count;
  --   * every percentage is rounded to a 5-point step, and the band is read from the ROUNDED average, so it says nothing the
  --     rounded figure does not; times_lowest is no longer sent (null), lowest_rate is a 5-point share.
  with myq as (select q.inquiry_id, min(q.quote_amount) quote_amount
                 from quotes q join inquiries i on i.id = q.inquiry_id
                where q.supplier_id=p_supplier_id and q.status in ('submitted','revealed') and q.quote_amount>0
                  and i.status in ('completed','closed','cancelled','expired','lost')
                group by q.inquiry_id),
  rival as (select q.inquiry_id, q.supplier_id, min(q.quote_amount) amt
              from quotes q join myq m using (inquiry_id)
             where q.supplier_id is distinct from p_supplier_id
               and q.status in ('submitted','revealed') and q.quote_amount>0
             group by q.inquiry_id, q.supplier_id),
  peer as (select inquiry_id, min(amt) lo, avg(amt) av, count(*) n from rival group by inquiry_id),
  pos as (select m.quote_amount, p.lo, p.av,
                 (m.quote_amount-p.lo)/p.lo*100 pct_low,
                 (m.quote_amount-p.av)/p.av*100 pct_avg,
                 (m.quote_amount<=p.lo*1.0001) as is_lowest
            from myq m join peer p using(inquiry_id) where p.n>=3),
  agg as (select count(*) n,
                 round(100.0*count(*) filter (where is_lowest)/nullif(count(*),0)/5)*5 lowest_rate,
                 round(avg(pct_low)/5)*5 pct_low5,
                 round(avg(pct_avg)/5)*5 pct_avg5
            from pos)
  select case when n < 5 then jsonb_build_object('ready', false, 'competitive_rfqs', n,
    'min_comparisons', 5, 'min_other_suppliers', 3, 'step_pct', 5,
    'times_lowest', null, 'lowest_rate', null, 'avg_pct_above_lowest', null, 'avg_pct_vs_average', null,
    'band', 'not enough comparisons yet')
  else jsonb_build_object('ready', true, 'competitive_rfqs', n,
    'min_comparisons', 5, 'min_other_suppliers', 3, 'step_pct', 5,
    'times_lowest', null, 'lowest_rate', lowest_rate,
    'avg_pct_above_lowest', pct_low5, 'avg_pct_vs_average', pct_avg5,
    'band', case when pct_avg5 <= -5 then 'below market average'
                 when pct_avg5 < 5 then 'around market average' else 'above market average' end)
  end into v_pos from agg;
  with months as (select date_trunc('month', (now() - (n||' month')::interval)) m from generate_series(0,11) n),
  qb as (select date_trunc('month',created_at) m, count(*) c from quotes where supplier_id=p_supplier_id group by 1),
  rb as (select date_trunc('month',revealed_at) m, count(*) c from transactions where supplier_id=p_supplier_id group by 1)
  select jsonb_agg(jsonb_build_object('month', to_char(months.m,'Mon YY'),'quotes', coalesce(qb.c,0), 'reveals', coalesce(rb.c,0)) order by months.m)
    into v_hist from months left join qb on qb.m=months.m left join rb on rb.m=months.m;
  v := jsonb_build_object('supplier_id', p_supplier_id,'quotes_total', v_quotes,'reveals', v_reveals,'hired', v_hired,
    'lost_to_others', v_lost,'win_ratio', round(100.0*v_hired/nullif(v_quotes,0),1),'reveal_ratio', round(100.0*v_reveals/nullif(v_quotes,0),1),
    'qd_revenue', v_qd_rev,'deal_value_awarded', v_deal_val,'avg_lead_time_days', v_avg_lead,'rating', v_rating,
    'rating_percentile', v_rating_pct,'response_rate', v_resp,'pending_reviews', v_pending_reviews,'active_rfqs', v_active_rfqs,
    'price_positioning', v_pos,'history_12m', v_hist,'document_expiries', fn_supplier_expiries(p_supplier_id));
  return v;
end $function$;

-- 2. fn_supplier_market (live body of 19 Nov 2026; priced and money_obj are the change)
CREATE OR REPLACE FUNCTION public.fn_supplier_market(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),
  -- This supplier's trades: what it CONFIRMED in supplier_capabilities, plus its sector code.
  mine as (
    select array_remove(array_cat(coalesce((select trades from public.supplier_capabilities where supplier_id = p_lead_id), '{}'::text[]),
                                  array[(select sector from me)]), null) as trades
  ),
  -- Competitors: any lead whose confirmed trades overlap this supplier's (the population
  -- fn_customer_decision_support counts as "suppliers covering this trade"), or whose sector string
  -- equals this supplier's. Same side of the demo fence, never self.
  peers as (
    select l.*
    from public.leads l, me, flag, mine
    where l.id <> me.id
      and coalesce(l.permanently_closed, false) = false
      and (coalesce(l.source, '') = 'qd_demo_fixture') = flag.is_demo
      and ((l.sector is not null and me.sector is not null and l.sector = me.sector)
           or exists (select 1 from public.supplier_capabilities sc where sc.supplier_id = l.id and sc.trades && mine.trades))
  ),
  peers_here as (
    select p.* from peers p, me
    where me.service_emirates is null
       or coalesce(array_length(me.service_emirates, 1), 0) = 0
       or p.emirate is null
       or exists (select 1 from unnest(me.service_emirates) e where p.emirate ilike '%' || e || '%')
  ),
  demand_all as (
    select i.* from public.inquiries i, flag
    where (coalesce(i.brief_source, '') = 'qd_demo_fixture') = flag.is_demo
      and i.created_at >= now() - interval '28 days'
  ),
  -- An enquiry in this supplier's category: its trades overlap, or its category names one of them.
  demand_mine as (
    select d.* from demand_all d, mine, me
    where (d.trades is not null and d.trades && mine.trades)
       or (d.category is not null and (d.category = any (mine.trades) or public.fn_norm_trades(d.category) && mine.trades))
  ),
  -- THE MARKET PRICE IS OTHER SUPPLIERS' SUBMITTED QUOTES ONLY (19 Nov 2026, sales_engineer; founder rulings 1683, 1686):
  -- the asking supplier's own quotes are left out, and so are drafts and withdrawn quotes. With no floor, a cell of two
  -- quotes sent "low" and "high", which were the two companies' exact prices.
  priced as (
    select q.quote_amount amt, q.supplier_id
    from public.quotes q join demand_mine d on d.id = q.inquiry_id, flag
    where (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
      and q.supplier_id is distinct from p_lead_id
      and q.status in ('submitted', 'revealed')
      and q.quote_amount is not null and q.quote_amount > 0
  ),
  figures as (
    select
      (with c as (
         select count(*) filter (where created_at >= now() - interval '14 days') as recent,
                count(*) filter (where created_at <  now() - interval '14 days') as earlier
         from demand_mine)
       select case when c.recent = 0 and c.earlier = 0
         then jsonb_build_object(
                'available', false, 'value', null, 'direction', null,
                'basis', 'enquiries in your category over the last 28 days',
                'population', 0,
                'note', 'no enquiries in your category yet, so there is no series to trend')
         else jsonb_build_object(
                'available', true,
                'category', (select sector from me),
                'value', c.recent,
                'prior', c.earlier,
                'direction', case when c.recent > c.earlier then 'up'
                                  when c.recent < c.earlier then 'down' else 'flat' end,
                'pct', case when c.earlier > 0
                            then round(((c.recent - c.earlier)::numeric / c.earlier) * 100, 1)
                            else null end,
                'from_zero', c.earlier = 0,
                'share_pct', case when (select count(*) from demand_all) > 0
                             then round((c.recent::numeric
                                  / nullif((select count(*) from demand_all), 0)) * 100, 1)
                             else null end,
                'series', (
                  select coalesce(jsonb_agg(jsonb_build_object('week', w.wk, 'count', w.c) order by w.wk), '[]'::jsonb)
                  from (select date_trunc('week', created_at)::date wk, count(*) c
                        from demand_mine group by 1) w),
                'basis', 'enquiries in your category, two 14-day halves',
                'population', (select count(*) from demand_mine),
                'note', case when c.earlier = 0
                        then 'first activity in this window, so there is no prior period to take a percentage against'
                        else null end)
         end from c) as trend_obj,
      (with r as (select category cat, count(*) c from demand_all
                  where category is not null group by 1 order by count(*) desc limit 1)
       select case when not exists (select 1 from r)
         then jsonb_build_object(
                'available', false, 'value', null,
                'basis', 'enquiries over the last 28 days',
                'population', (select count(*) from demand_all),
                'note', 'that is a fact about requests, and none have been made')
         else jsonb_build_object(
                'available', true,
                'value', (select cat from r),
                'count', (select c from r),
                'basis', 'enquiries over the last 28 days, grouped by category',
                'population', (select count(*) from demand_all))
         end) as topcat_obj,
      -- AT LEAST 5 QUOTES FROM AT LEAST 3 OTHER COMPANIES, OR NO PRICE. No low, no high and no mean leave this routine:
      -- the lowest and the highest are each one company's quote, and a mean over a known few is one subtraction from one.
      -- What leaves is the median and the middle half, each on a step of half an order of magnitude of the median (AED 100
      -- at the least): median to the nearest step, p25 down to a step, p75 up to one. With 5 quotes p25, the median and
      -- p75 ARE the 2nd, 3rd and 4th quotes, so unrounded they would be three companies' prices.
      (with s as (
         select count(*) n, count(distinct supplier_id) n_sup,
                percentile_cont(0.5)  within group (order by amt)::numeric mid,
                percentile_cont(0.25) within group (order by amt)::numeric q1,
                percentile_cont(0.75) within group (order by amt)::numeric q3
         from priced),
       r as (select s.*, case when s.mid > 0 then round(greatest(100, power(10, floor(log(s.mid)))::numeric / 2)) end step from s)
       select case when r.n < 5 or r.n_sup < 3
         then jsonb_build_object(
                'available', false, 'value', null, 'currency', 'AED',
                'basis', 'other suppliers'' submitted quotes on enquiries in your category over the last 28 days',
                'population', r.n, 'suppliers', r.n_sup, 'min_quotes', 5, 'min_suppliers', 3,
                'note', case when r.n = 0
                        then 'nothing in your category has been priced by another supplier, so there is no market price'
                        else 'not enough quotes from other suppliers yet: a market price needs at least 5 quotes from 3 suppliers, '
                             || 'so that no single competitor''s price can be read from it' end)
         else jsonb_build_object(
                'available', true, 'currency', 'AED',
                'value', round(round(r.mid / r.step) * r.step), 'median', round(round(r.mid / r.step) * r.step),
                'p25', round(floor(r.q1 / r.step) * r.step), 'p75', round(ceil(r.q3 / r.step) * r.step),
                'rounded_to', r.step,
                'basis', 'other suppliers'' submitted quotes on enquiries in your category over the last 28 days',
                'population', r.n, 'suppliers', r.n_sup)
         end from r) as money_obj
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'sector', (select sector from me),
    'trades', (select to_jsonb(trades) from mine),
    'population', case when (select is_demo from flag) then 'demo' else 'live' end,
    'competitors', jsonb_build_object(
      'available', true,
      'basis', 'suppliers whose confirmed trades overlap yours, or share your sector',
      'total', (select count(*) from peers),
      'in_my_area', (select count(*) from peers_here),
      'matchable', (
        select count(*) from peers p
        where public.fn_is_matchable(p.verified, p.banned, p.matching_blocked,
                                     p.approval_status, p.permanently_closed, p.chat_strikes)
          and exists (select 1 from public.supplier_capabilities sc
                      where sc.supplier_id = p.id and sc.confirmed_at is not null)
      ),
      'me_matchable', (
        select public.fn_is_matchable(m.verified, m.banned, m.matching_blocked,
                                      m.approval_status, m.permanently_closed, m.chat_strikes)
           and exists (select 1 from public.supplier_capabilities sc
                       where sc.supplier_id = m.id and sc.confirmed_at is not null)
        from public.leads m where m.id = p_lead_id
      ),
      'by_emirate', (
        select coalesce(jsonb_agg(jsonb_build_object('emirate', s.em, 'count', s.c) order by s.c desc), '[]'::jsonb)
        from (
          select p.emirate as em, count(*) as c
          from peers p where p.emirate is not null
          group by p.emirate order by count(*) desc limit 8
        ) s
      )
    ),
    'market_composition', jsonb_build_object(
      'available', true,
      'basis', 'competitors, grouped by category',
      'segments', (
        select coalesce(jsonb_agg(jsonb_build_object('name', s.nm, 'count', s.c) order by s.c desc), '[]'::jsonb)
        from (
          select coalesce(nullif(btrim(split_part(p.categories, ',', 1)), ''), coalesce(p.sector, 'Uncategorised')) as nm,
                 count(*) as c
          from peers p group by 1 order by count(*) desc limit 8
        ) s
      )
    ),
    'demand_trend',     (select trend_obj  from figures),
    'most_requested',   (select topcat_obj from figures),
    'avg_market_price', (select money_obj  from figures)
  );
$function$;

-- 3. fn_customer_decision_support (live body of 19 Nov 2026; the price column, the status list and price_basis)
CREATE OR REPLACE FUNCTION public.fn_customer_decision_support(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  -- A median over fewer than this many quotes is an anecdote wearing a statistic's clothes.
  MIN_PRICE_N constant int := 5;
  v_recommend jsonb;
  v_chase     jsonb;
  v_market    jsonb;
begin
  if p_customer is null then return jsonb_build_object('error','no_customer'); end if;

  -- ── 1. WHICH QUOTE, AND WHY ────────────────────────────────────────────────────────────────
  -- lead_time is free text ('3 weeks', '10-14 days', 'ASAP'). The first integer is taken and
  -- scaled by the unit word; anything that yields no integer is UNKNOWN and never claimed as fast.
  -- A quote with no parseable lead time cannot win the speed comparison, which is the honest
  -- outcome: we would be guessing on the customer's behalf.
  with q as (
    -- THE SUPPLIER'S QUOTED PRICE, EXCLUDING VAT (19 Nov 2026, sales_engineer; founder ruling 1687). This was
    -- the quotes column GENERATED as quote_amount * (1 + the margin function), with quote_amount only as its fallback: the
    -- retired tiered margin (10% under AED 2,000 down to 3% from 50,000), so the portal printed "The cheapest is AED 10,500"
    -- for a quotation of AED 10,000. The customer pays the supplier the quotation; our fee is 3% of it ex VAT, separately.
    -- A draft or a held quote is not in front of the customer, so it is not named as the cheapest either.
    select i.id inq, i.summary, i.category, q.id qid, q.supplier_id,
           q.quote_amount price,
           q.lead_time,
           case
             when q.lead_time ~ '\d' then
               (regexp_match(q.lead_time, '(\d+)'))[1]::int
               * case when q.lead_time ~* 'week' then 7 when q.lead_time ~* 'month' then 30 else 1 end
             else null
           end days
    from inquiries i
    join quotes q on q.inquiry_id = i.id
    where i.customer_id = p_customer
      and coalesce(q.status,'') not in ('withdrawn','expired','rejected','draft','held','cancelled')
      and q.quote_amount is not null
  ),
  agg as (
    select inq, min(summary) summary, min(category) category, count(*) n,
           min(price) lo, max(price) hi,
           (array_agg(qid order by price asc))[1]                       cheapest_id,
           (array_agg(price order by price asc))[1]                     cheapest_price,
           (array_agg(price order by price asc))[2]                     next_price,
           (array_agg(qid  order by days asc) filter (where days is not null))[1] fastest_id,
           (array_agg(days order by days asc) filter (where days is not null))[1] fastest_days,
           (array_agg(days order by price asc))[1]                      cheapest_days,
           count(*) filter (where days is not null)                     n_with_days
    from q group by inq
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'inquiry_id', inq, 'summary', summary, 'category', category, 'quotes', n,
           'cheapest_quote_id', cheapest_id, 'cheapest_price', cheapest_price, 'price_basis', 'quote_amount_excluding_vat',
           'saving_vs_next', case when next_price is not null then next_price - cheapest_price end,
           'fastest_quote_id', fastest_id, 'fastest_days', fastest_days,
           'same_quote_wins', (fastest_id is not null and fastest_id = cheapest_id),
           -- Only a real trade-off gets a trade-off sentence. Null here means either one quote
           -- won both ways, or too few lead times were stated to compare speed at all.
           'days_sooner', case when fastest_id is distinct from cheapest_id and fastest_days is not null
                                 and cheapest_days is not null then cheapest_days - fastest_days end,
           'spread', hi - lo,
           'lead_times_stated', n_with_days
         ) order by n desc), '[]'::jsonb)
    into v_recommend from agg where n >= 2;

  -- ── 2. WHAT A JOB LIKE THIS NORMALLY COSTS ─────────────────────────────────────────────────
  -- Answered per category the customer actually uses, or - for a customer with no requests yet -
  -- left empty rather than filled with the platform average of nothing.
  -- fn_norm_trades is resolved ONCE PER CATEGORY here, not inside the correlated subqueries below.
  -- Called per row it is re-evaluated against all 15,306 supplier_capabilities rows twice over and
  -- the whole function times out - measured, it did.
  with cats as (
    select distinct i.category, i.emirate, public.fn_norm_trades(i.category) norm from inquiries i
    where i.customer_id = p_customer and i.category is not null
  ),
  m as (
    select c.category, c.emirate,
           s.n price_n, s.median, s.p25, s.p75,
           -- THROUGH THE LEXICON, NOT THE RAW CATEGORY. A probe with category 'marble' counted 0
           -- suppliers against 15,306 capability rows, because no supplier lists a trade called
           -- "marble" - fn_norm_trades('marble') is {flooring}, and that is the vocabulary the
           -- capability rows are written in. Comparing the customer's word directly against the
           -- supplier's word is the same defect that left discover() returning nothing while
           -- route_inquiry worked: one path got the lexicon and its sibling did not.
           (select count(*) from supplier_capabilities sc
             where (sc.trades && c.norm or sc.services && c.norm)
               and (c.emirate is null or sc.coverage_emirates && array[c.emirate])) suppliers_covering,
           (select count(*) from supplier_capabilities sc
             where (sc.trades && c.norm or sc.services && c.norm)
               and (c.emirate is null or sc.coverage_emirates && array[c.emirate])
               and sc.review_status = 'confirmed')                                  suppliers_confirmed,
           (select round(avg(extract(epoch from (q.created_at - i2.created_at))/86400)::numeric, 1)
              from inquiries i2 join quotes q on q.inquiry_id = i2.id
             where i2.category = c.category)                                        avg_days_to_quote
    from cats c left join category_price_stats s on s.category = c.category
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'category', category, 'emirate', emirate,
           -- The price block is present ONLY when it rests on enough quotes to mean something.
           -- Absent is a statement; a median over two quotes is a different and false one.
           'price_known', (coalesce(price_n,0) >= MIN_PRICE_N),
           'price_n', coalesce(price_n,0),
           'median', case when coalesce(price_n,0) >= MIN_PRICE_N then median end,
           'p25',    case when coalesce(price_n,0) >= MIN_PRICE_N then p25 end,
           'p75',    case when coalesce(price_n,0) >= MIN_PRICE_N then p75 end,
           'suppliers_covering', suppliers_covering,
           'suppliers_confirmed', suppliers_confirmed,
           'avg_days_to_quote', avg_days_to_quote
         )), '[]'::jsonb)
    into v_market from m;

  -- ── 3. A REQUEST HAS GONE QUIET ────────────────────────────────────────────────────────────
  -- One state per open request, each with the action that actually moves it. The thresholds are
  -- deliberately generous: telling somebody their request is stalled on day one is noise, and a
  -- portal that cries stalled is one a customer stops reading.
  with open_i as (
    select i.id, i.summary, i.category, i.created_at,
           extract(epoch from (now() - i.created_at))/86400 age_days,
           (select count(*) from inquiry_matches m where m.inquiry_id = i.id) invited,
           (select count(*) from quotes q where q.inquiry_id = i.id
              and coalesce(q.status,'') not in ('withdrawn','expired','rejected')) quotes
    from inquiries i
    where i.customer_id = p_customer
      and coalesce(i.status,'open') not in ('closed','cancelled','completed','archived')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'inquiry_id', id, 'summary', summary, 'category', category,
           'age_days', round(age_days::numeric,1), 'invited', invited, 'quotes', quotes,
           -- QUOTE-BEARING STATES ARE TESTED FIRST. Written the other way round, a request that had
           -- collected two quotes but no inquiry_matches row reported 'not_yet_sent' - the portal
           -- telling a customer we had not reached any supplier while two of their quotes sat on
           -- the screen. A quote is proof of delivery; the absence of a match row is only proof
           -- that one path recorded it. Caught by an aborted-transaction probe that seeded exactly
           -- that shape; an empty result would have proved nothing.
           'state', case
             when quotes >= 2 and age_days >= 7              then 'undecided'
             when quotes  = 1 and age_days >= 5              then 'only_one'
             when quotes  = 0 and invited = 0 and age_days >= 1 then 'not_yet_sent'
             when quotes  = 0 and age_days >= 3              then 'no_replies'
             else 'healthy' end
         ) order by age_days desc), '[]'::jsonb)
    into v_chase
    from open_i
   where case
           when quotes >= 2 and age_days >= 7 then true
           when quotes  = 1 and age_days >= 5 then true
           when quotes  = 0 and invited = 0 and age_days >= 1 then true
           when quotes  = 0 and age_days >= 3 then true
           else false end;

  return jsonb_build_object(
    'recommend', v_recommend,
    'market',    v_market,
    'chase',     v_chase,
    'min_price_n', MIN_PRICE_N,
    'as_of', now()
  );
end $function$;

-- 4. fn_pool_say (live body of 19 Nov 2026; the quote.received line)
CREATE OR REPLACE FUNCTION public.fn_pool_say(p_type text, p_entity_type text, p_entity_id text, p_payload jsonb, p_with_name boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d jsonb := case when jsonb_typeof(p_payload) = 'object' then p_payload else '{}'::jsonb end;
        v_tx text; v_inq text; v_amt numeric; v_req text := ''; v_fee numeric; v_refund numeric; v_tinq text;
        v_cat text; v_emi text; v_rfq text; v_sector text; v_lemi text; v_company text;
begin
  if p_type like 'handoff.%' and p_entity_type = 'agent_actions' and p_entity_id ~ '^\d+$' then
    select a.detail into d from public.agent_actions a where a.id = p_entity_id::bigint;
    d := coalesce(d, '{}'::jsonb);
  end if;
  v_tx := coalesce(d->>'transaction_id', case when coalesce(d->>'subject_table', p_entity_type) in ('transactions', 'transaction')
                                               then split_part(coalesce(d->>'subject_id', p_entity_id), '#', 2) end);
  if v_tx = '' then v_tx := coalesce(d->>'subject_id', p_entity_id); end if;
  select coalesce(t.reveal_fee, t.app_fee), t.refund_amount_aed, t.inquiry_id::text into v_fee, v_refund, v_tinq
    from public.transactions t where t.id::text = v_tx;
  if v_tinq is null and public.fn_pool_kind(p_entity_type) = 'quote' then
    select q.inquiry_id::text into v_tinq from public.quotes q where q.id::text = p_entity_id;
  end if;
  v_inq := coalesce(d->>'inquiry_id', v_tinq, case when public.fn_pool_kind(p_entity_type) = 'inquiry' then p_entity_id end);
  if v_inq is not null then
    select i.category, i.emirate, i.rfq_no::text into v_cat, v_emi, v_rfq from public.inquiries i where i.id::text = v_inq;
    v_req := ' on request ' || coalesce(v_rfq, left(v_inq, 8)) || coalesce(' (' || nullif(concat_ws(', ', v_cat, v_emi), '') || ')', '');
  end if;
  case
    when p_type in ('supplier.approved', 'supplier.applied') then
      select l.sector, l.emirate, l.company_name into v_sector, v_lemi, v_company from public.leads l where l.id::text = p_entity_id;
      return case when p_type = 'supplier.approved' then 'a supplier was approved' else 'a supplier applied' end
        || case when p_with_name and v_company is not null then ': ' || v_company else '' end
        || coalesce(' (' || nullif(concat_ws(', ', nullif(v_sector, ''), nullif(v_lemi, '')), '') || ')', '')
        || case when d->>'verified' = 'false' then ', licence not verified' else '' end;
    when p_type = 'customer.registered' then return 'a customer registered';
    when p_type = 'customer.verified' then
      return 'a customer finished verifying (' || coalesce(d->>'verified_by', 'the platform') || ')'
             || coalesce('; ' || nullif(d->>'told_by', '') || ' told him his account is active', '');
    when p_type in ('payment.received', 'payment.failed') then
      return case when p_type = 'payment.received' then 'a payment was received' else 'a payment failed' end
             || coalesce(' of AED ' || to_char(coalesce(v_fee, (d->>'reveal_fee')::numeric, (d->>'amount_aed')::numeric), 'FM999,990.00'), '') || v_req;
    when p_type in ('rfq.created', 'rfq.classified') then return 'a request was ' || case when p_type = 'rfq.created' then 'posted' else 'classified' end || v_req;
    when p_type = 'quote.received' then
      -- quote_amount, ex VAT (19 Nov 2026, ruling 1687): the event's marked-up price field carried the retired tiered margin.
      return 'a quotation' || coalesce(' of AED ' || to_char(round((d->>'quote_amount')::numeric), 'FM999,999,990') || ' excluding VAT', '') || ' arrived' || v_req;
    when p_type like 'handoff.reveal.paid.%' or p_type like 'handoff.reveal.reconcile.%' then
      v_amt := v_fee;
      return 'a customer paid the reveal fee' || coalesce(' of AED ' || to_char(v_amt, 'FM999,990.00'), '') || v_req;
    when p_type like 'handoff.refund.%' then
      return 'refund ' || split_part(p_type, '.', 3) || coalesce(': AED ' || to_char(v_refund, 'FM999,990.00'), '') || v_req;
    when p_type like 'handoff.sale.made.%' then
      return 'a sale was booked' || coalesce(': AED ' || to_char(v_fee, 'FM999,990.00'), '') || v_req;
    when p_type like 'handoff.payment.%' then
      return 'a payment needs a decision (' || split_part(p_type, '.', 3) || ')' || v_req;
    when p_type like 'request.%' then
      return 'request ' || replace(split_part(p_type, '.', 2), '_', ' ') || coalesce(': ' || nullif(concat_ws(', ', d->>'state', d->>'outcome'), ''), '') || v_req;
    when p_type = 'handoff.overdue.escalated' then
      -- d is the hand-over's detail here (read above): the silent seat is in detail.silence, the event's payload has it
      -- at the top (review of 13 Nov evening: "? owes the next move" was printed)
      return coalesce(d->>'type', p_payload->>'type', 'a hand-over') || ' from ' || coalesce(d->>'from', p_payload->>'from', 'a seat')
             || ' to ' || coalesce(d->>'to', p_payload->>'to', 'a seat') || ' is overdue; '
             || coalesce(nullif(d->'silence'->>'silent_seat', '') || ' owes the next move', nullif(p_payload->>'silent_seat', '') || ' owes the next move',
                         'no seat has taken it');
    else return replace(regexp_replace(p_type, '^handoff\.(.*)\.sent$', '\1'), '_', ' ');
  end case;
end $function$;

-- 5. fn_company_self_knowledge_sync (live body of 19 Nov 2026; the quotation-format record's last sentence)
CREATE OR REPLACE FUNCTION public.fn_company_self_knowledge_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_state jsonb := public.fn_company_state();
  v_snap  jsonb := public.fn_company_snapshot();
  -- 16 NOV 2026 (ceo, wave D): fn_company_brief printed a department roster; the seats are read from org_role below.
  v_seats text; v_seat_n int; v_open_at int; v_cat_n int;
  v_fee   numeric; v_sup_fee numeric; v_charge date; v_refund_wd int; v_cur text; v_free_n int; v_cat_min int;
  v_chase_wd int; v_bank_min int; v_bank_max int; v_admin numeric; v_pct numeric;
  v_target text; v_deadline text;
  v_social text; v_social_at text; v_blog text; v_blog_at text;
  v_founder text;
  v_tmpl text;
  v_rev numeric; v_exp numeric; v_pnl text;
  v_stance record; v_decisions text; v_cat_open text;
  v_records jsonb; r jsonb; v_rid text; v_n int := 0;
  reg public.company_registration%rowtype;
  -- 6 SEP 2026: the two supplier loops (acquisition, sanctions screening) — live values for the record below
  v_golive boolean; v_reg_target text; v_reg_month text; v_supply_owner text; v_co text; v_last_un text; v_last_uae text;
  v_hits_open int; v_invited int; v_registered int; v_followups int; v_intake int;
begin
  v_golive := public.fn_supplier_outreach_golive();
  select coalesce(target_value::text, '300') into v_reg_target from public.company_goals where key = 'suppliers_registered_monthly';
  select coalesce(actual_value::text, '0') || ' (measured ' || coalesce(to_char(measured_at, 'DD Mon YYYY HH24:MI'), 'not yet') || ' UTC)'
    into v_reg_month from public.employee_kpi where agent_key = 'sales_engineer' and kpi = 'Suppliers registered per month' and active;
  select display_name into v_supply_owner from public.org_role where role_id = 'sales_engineer';
  select display_name into v_co from public.org_role where role_id = 'ceo';
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_un from public.screening_run where source = 'un_consolidated' and run_tag is null order by id desc limit 1;
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_uae from public.screening_run where source = 'uae_local_terrorist_list' and run_tag is null order by id desc limit 1;
  select count(*) into v_hits_open from public.supplier_screening_hit where status = 'open';
  select count(*) filter (where invite_status is not null), count(*) filter (where lifecycle_stage = 'registered'), coalesce(sum(invite_followups), 0)
    into v_invited, v_registered, v_followups from public.leads where coalesce(email, '') not ilike '%@example.invalid';
  select count(*) into v_intake from public.supplier_lead_intake where run_tag is null;
  select * into reg from public.company_registration order by recorded_at desc limit 1;
  -- the founder identity (who leads the company). 9 SEP 2026 -- PHASE MACHINERY REMOVED: this read
  -- the founder-identity register, which is deleted in this sweep. It was never an authority
  -- check here, only the address printed in the "who we are" knowledge record, so it is read from
  -- app_secrets.founder_email -- the same place fn_page_high_agent_action already reads it -- and
  -- falls back to the same literal the record already carried.
  select value into v_founder from public.app_secrets where key = 'founder_email';
  -- the live P&L (financial state beyond headline revenue)
  select coalesce(sum(amount) filter (where type='revenue'),0), coalesce(sum(amount) filter (where type='expense'),0),
         string_agg(case when amount <> 0 then '  - '||type||': '||name||' = AED '||amount::text else null end, E'\n' order by type, code)
    into v_rev, v_exp, v_pnl from public.gl_pnl;
  select standard_reveal_rate, supplier_reg_fee, supplier_charging_starts, refund_window_working_days,
         coalesce(reveal_currency,'AED'), chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max,
         coalesce(supplier_free_count,1000), coalesce(category_open_min_suppliers,10)
    into v_fee, v_sup_fee, v_charge, v_refund_wd, v_cur, v_chase_wd, v_bank_min, v_bank_max, v_free_n, v_cat_min
    from public.pricing_config order by id limit 1;
  -- 6 SEP 2026: the refund ladder's money side and the founder's own words, from decision_policy
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_pct   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);
  -- 6 SEP 2026: the founder's budget stance and his decisions on record (company_financial_stance,
  -- company_policy_decision), and the category-open count (v_category_open)
  select * into v_stance from public.company_financial_stance where id = 1;
  select string_agg('- ' || upper(decision_key) || ' (decided ' || to_char(decided_on,'DD Mon YYYY') || ' by the ' || decided_by
                    || case when never_ask_again then '; NEVER ask about it again' else '' end || '): ' || decision_text
                    || case when cardinality(applies_to) > 0 then ' [applies to: ' || array_to_string(applies_to, ', ') || ']' else '' end,
                    E'\n' order by decision_key)
    into v_decisions from public.company_policy_decision;
  select count(*) filter (where is_open) || ' of ' || count(*) || ' categories are OPEN today (' ||
         coalesce(max(verified_registered_suppliers),0) || ' is the highest verified-registered count in any category)'
    into v_cat_open from public.v_category_open;

  -- the six seats (rulings of 7 Sep 2026 and 907: seats, no departments), live from org_role
  select count(*), string_agg('  - ' || r.role_id || ' (' || coalesce(r.display_name, r.role_id) || '): ' || left(coalesce(r.responsibilities, ''), 320), E'\n' order by r.role_id)
    into v_seat_n, v_seats from public.org_role r where r.status = 'active';
  -- the CEO-tuned opening level (ruling 1614: trade by trade), else the platform's own level
  select t.open_at_suppliers into v_open_at from public.trade_opening_rule t order by t.id limit 1;
  v_open_at := coalesce(v_open_at, v_cat_min);
  select count(*) into v_cat_n from public.catalog_supplier_categories;

  select coalesce(target_value::text,'1000000'), coalesce(to_char(deadline,'DD Mon YYYY'),'31 Aug 2027')
    into v_target, v_deadline
    from public.company_goals
   where active and (lower(coalesce(key,'')) like '%revenue%' or lower(coalesce(goal,'')) like '%revenue%'
                     or category = 'Financial')
   order by sort nulls last limit 1;

  select left(coalesce(content->>'text', content->>'body', content::text), 240), to_char(created_at,'DD Mon YYYY')
    into v_social, v_social_at from public.social_posts order by created_at desc limit 1;
  select title, to_char(coalesce(published_at, updated_at),'DD Mon YYYY')
    into v_blog, v_blog_at from public.blog_posts where published order by published_at desc nulls last limit 1;

  -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. v_funnel was a listing of W04..W18 read from
  -- the programme workflow registry, appended to the marketplace knowledge record as "The 30 workflows
  -- that run this". The workflow registry is deleted in this sweep and the company is two agents
  -- with no departments and no W-numbered programme, so the sentence is dropped rather than left
  -- describing an organisation that no longer exists. The prose above still explains the funnel in
  -- plain words, which is what an agent answering a question actually needs.

  -- 6 SEP 2026: the WhatsApp template ledger (messaging_template), one line per template, live.
  select coalesce(string_agg('  - ' || template_key || ' [' || lang || ']: ' || upper(status) || ' (' || sid
           || coalesce(', ' || category, '') || coalesce(', submitted ' || to_char(submitted_at, 'DD Mon YYYY'), '')
           || coalesce(', approved (first seen ' || to_char(approved_at, 'DD Mon YYYY') || ')', '')
           || coalesce(', reason: ' || left(rejection_reason, 90), '') || coalesce(', ' || note, '') || ')',
           E'\n' order by template_key, lang), '  (no templates recorded)')
    into v_tmpl from public.messaging_template where channel = 'whatsapp';

  v_records := jsonb_build_array(

    -- 6 SEP 2026: the company's registration and tax status, from company_registration (the founder
    -- supplied the trade licence and ruled on VAT, Corporate Tax and the auditor that day; all are
    -- closed facts, never questions).
    jsonb_build_object('rid','registration','module','company_registration',
      'title','QuotesDone — Trade licence, registration and tax status',
      'kw', to_jsonb(array['trade licence','trade license','licence number','license number','DET','department of economy and tourism',
        'issuing authority','licence expiry','renewal','activity code','portal','software design','trader licence','e-trader',
        'VAT','vat registered','TRN','tax registration number','FTA','federal tax authority','threshold','375,000','corporate tax',
        'corporate tax registration','CT registration','small business relief','auditor','external auditor','audit firm','who audits us',
        'are we vat registered','do we charge vat','company registration','legal entity','owner','who owns the licence']),
      'content',
        case when reg.license_no is null then 'REGISTRATION: not recorded.' else
        'TRADE LICENCE: ' || reg.authority || ' ' || reg.license_type || ' no. ' || reg.license_no || ', trade name "' || reg.trade_name || '"; issued ' ||
        to_char(reg.issued_on,'DD Mon YYYY') || ', expires ' || to_char(reg.expires_on,'DD Mon YYYY') || ' (renew before then; renewal is a company task, not a founder question).' || E'\n' ||
        'OWNER: ' || reg.owner_name || ' (' || reg.owner_share || '); licensed activities: ' || reg.activities || '.' || E'\n' ||
        'REGISTERED CONTACT: ' || reg.registered_email || ', ' || reg.registered_mobile || '; e-stores on the licence: ' || reg.e_stores || '.' || E'\n' ||
        'LICENCE CLASS: ' || reg.license_class_note || E'\n' ||
        'TAX STATUS: ' || case when reg.vat_registered then 'VAT-registered, TRN ' || coalesce(reg.trn,'?') else
          'NOT VAT-registered (founder ruling ' || to_char(reg.vat_ruling_on,'DD Mon YYYY') || '): no VAT is charged or shown on any QuotesDone invoice until taxable supplies reach the FTA mandatory registration threshold of AED ' ||
          to_char(reg.vat_threshold_aed,'FM999,999,999') || ' in a rolling 12 months. Do not ask the founder about VAT or the TRN; when revenue approaches the threshold the accountant opens a registration task.' end || E'\n' ||
        'CORPORATE TAX: ' || coalesce(reg.corporate_tax_note,'registration status not recorded.') || E'\n' ||
        'AUDITOR: ' || coalesce(reg.auditor,'not recorded.')
        end),

    jsonb_build_object('rid','identity','module','company_identity',
      'title','QuotesDone — Identity, Vision and Mission',
      'kw', to_jsonb(array['vision','mission','what is quotesdone','who are we','company','marketplace','target','revenue goal','anonymous','uae','b2b',
        'who is the founder','company founder','who owns quotesdone','founder name','ahmad alzain','the owner',
        'company target and deadline','revenue target','what is our goal','aed 1 million target','1000000 by 2027','when is the deadline']),
      'content',
        'WHO WE ARE. ' || coalesce(v_state->>'mission','') || E'\n' ||
        'VISION: ' || coalesce(v_state->>'vision','') || E'\n' ||
        'TARGET: AED ' || v_target || ' in revenue by ' || v_deadline ||
          ' — every seat''s objectives trace to this one number.' || E'\n' ||
        'HOW IT WORKS IN ONE LINE: an anonymous UAE B2B quotation marketplace — buyers post an RFQ, verified UAE '
        'suppliers submit quotes, and the buyer pays a small reveal fee to unlock and contact a chosen supplier. '
        'Six AI seats (ceo, sales_engineer, customer_support, accountant, it_engineer, marketing; no departments) plan and execute toward the vision.' || E'\n' ||
        'FOUNDER / OWNER: Ahmad Alzain (' || coalesce(v_founder,'management@quotesdone.com') || '). The company is '
        'founder-led: he sets the vision, the target and the boundaries. The CEO seat has full authority within them and decides '
        'every approval, refunds of any amount included (rulings of 8 Sep 2026, 1696 and 1710); the founder is told the result and is never waited on.'),

    jsonb_build_object('rid','financials','module','financials',
      'title','QuotesDone — Our Financials (live P&L) and the Budget Policy',
      'kw', to_jsonb(array['financials','finance','p&l','profit and loss','expenses','costs','revenue','how much did we spend','what were our expenses','net','burn','money','accounting','are we profitable',
        'budget','budget limit','budget policy','do we have a budget','budget variance','over budget','spending limit','when do we set budgets','profitable']),
      'content',
        'LIVE FINANCIAL STATE (from the general ledger; refreshes):' || E'\n' ||
        '  Total revenue: AED ' || round(coalesce(v_rev,0),2)::text || '  ·  Total expenses: AED ' || round(coalesce(v_exp,0),2)::text ||
        '  ·  Net: AED ' || round(coalesce(v_rev,0)-coalesce(v_exp,0),2)::text || E'\n' ||
        'By account (non-zero lines):' || E'\n' || coalesce(v_pnl,'  (no posted amounts yet)') || E'\n' ||
        'Read it honestly: revenue is ' || case when coalesce(v_rev,0)=0 then 'AED 0 because the marketplace is pre-launch' else 'as above' end ||
        '; the spend so far is mostly software and AI infrastructure while the company is being built.' || E'\n' ||
        'BUDGET POLICY (founder, ' || coalesce(to_char(v_stance.decided_on,'DD Mon YYYY'),'6 Sep 2026') || '): ' ||
          coalesce(v_stance.policy_text, 'No budget limit while costs are subscriptions; budgets come with profitability.') ||
          ' Current stance: ' || case when coalesce(v_stance.is_profitable,false) then 'PROFITABLE - budgets apply and budget-variance alerts are live.'
                                     else 'NOT YET PROFITABLE - budget_mode ' || coalesce(v_stance.budget_mode,'unlimited_until_profitable') ||
                                          '; there is no budget limit, and budget-variance alerts and budget-limit checks are inert. Do not ask the founder for a budget.' end),

    jsonb_build_object('rid','operating-model','module','operating_model',
      'title','QuotesDone — How the Marketplace Works, End to End',
      'kw', to_jsonb(array['funnel','operating model','how it works','journey','inquiry','rfq','routing','packaging','dispatch','reveal','pipeline','workflow']),
      'content',
        'THE FUNNEL. A customer''s job travels the pipeline autonomously:' || E'\n' ||
        '  W04 register/onboard the customer → W05 intake and qualify the inquiry (RFQ) → W06 route it to the right '
        'category → W07 process any drawings/BOQ/documents → W08 build and approve a supplier-SAFE package (customer '
        'identity and any contact details stripped) → W09/W10 onboard and verify suppliers → W12 match and dispatch to '
        'enough confirmed suppliers → W13 notify them → W14 suppliers submit and we evaluate quotations → W15 build the '
        'top-3 comparison and reveal path → W16 the customer pays the reveal fee and gets supplier contact → W17 handles '
        'any refund/dispute, W18 support and retention.' || E'\n' ||
        'ANONYMITY: buyers and suppliers never see each other until the buyer pays to reveal. Quotes are anonymized/'
        'masked until then.' ),

    jsonb_build_object('rid','commercials','module','commercials',
      'title','QuotesDone — Fees, Pricing and Refund Terms (live)',
      'kw', to_jsonb(array['fee','reveal fee','review fee','pricing','how much','commission','refund','supplier fee','registration fee','late fee','cost','price','supplier charging','when does supplier charging start','how much do suppliers pay','are suppliers charged','supplier registration','supplier pays',
        'discount','promo','promotion','coupon','free reveal','cap','fee cap','maximum fee','first 1000','first 1,000','open category','category open','when is a category open','how many suppliers to open a category']),
      'content',
        'REVEAL FEE (what the customer pays to unlock a supplier): ' || round(v_fee*100,2) || '% of the deal, in ' || v_cur ||
          ' — read live from pricing_config, so this figure is always the current one. NO cap, NO discount, NO promotional rate, '
          'NO coupon and NO free reveal exist or may be offered (founder, 6 Sep 2026; pricing_config forbids them by constraint).' || E'\n' ||
        'SUPPLIERS: ' || case when v_charge is null
          then 'registration is FREE for the first ' || v_free_n || ' registrations (those suppliers are exempt permanently); every registration after them pays ' ||
               coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year. There is NO calendar start date and never will be: charging begins with registration ' ||
               (v_free_n + 1) || ', whenever that happens (founder, 6 Sep 2026). Never state a date; never ask the founder for one.'
          else 'registration is FREE until ' || to_char(v_charge,'DD Mon YYYY') || ', then ' || coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year.' end ||
          ' Suppliers are auto-approved on a verified file.' || E'\n' ||
        'TRADE OPENING: a trade opens to customers trade by trade once it has ' || v_open_at || ' verified registered suppliers, the level the CEO tunes weekly (trade_opening_rule, ruling 1614); ' ||
          coalesce(v_cat_open, '') || '. Matching an RFQ still needs at least one confirmed supplier.' || E'\n' ||
        'REFUNDS: the supplier has ' || coalesce(v_refund_wd::text,'5') || ' UAE working days from the customer''s payment (Mon-Fri; Sat+Sun off; public holidays excluded). '
        'No response by working day ' || coalesce(v_chase_wd::text,'3') || ': the sales engineer chases the supplier through customer support, customer copied. Still silent on working day ' || coalesce(v_refund_wd::text,'5') ||
        ': the sales engineer makes the final call and the CEO seat decides. No response to that: the customer is refunded the FULL reveal fee (the 3% paid, no deduction) - EVERY refund of any amount is the CEO''s decision (8 Sep 2026), the founder is told the result - and told banks take '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. The supplier then owes the exact amount refunded (the 3%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED ' || v_admin::text || ' administrative fee + '
        || v_pct::text || '% p.a. simple interest (the agreed rate of v14; 9% under v13 or earlier), per the Supplier Agreement version it had accepted at the reveal (fn_accountant_nonresponse_charge). Full record: qd-company:refunds.' || E'\n' ||
        'LATE FEE on overdue recoverables: ' || v_pct::text || '% per annum simple, the rate agreed in Supplier Agreement v14 clause 31 (Federal Decree-Law 50/2022 Arts. 73 and 84; 9% for amounts due under v13 or earlier).'),

    jsonb_build_object('rid','comparison-report','module','comparison_report',
      'title','QuotesDone — The Top-3 Comparison Report',
      'kw', to_jsonb(array['comparison report','compare','top 3','top three','quote comparison','ranking','shortlist','quote_compare','how do we compare','side by side']),
      'content',
        'THE COMPARISON REPORT IS ALWAYS THE TOP 3. However many quotations arrive — 3 or 100 — quote_compare ranks '
        'them ALL and returns the top three (ranks 1, 2, 3). It is NOT cheapest-wins: quotes are scored across multiple '
        'technical and commercial factors — price positioned across the range of offers, lead time, warranty, scope match, '
        'payment terms — so the strongest overall quote wins, not merely the lowest. The ranking is deterministic; the model '
        'writes the plain-language explanation of why the top three are the top three. The customer sees an anonymized '
        'side-by-side comparison table, saveable as a PDF, and only then decides whom to reveal.'),

    jsonb_build_object('rid','quotation-format','module','quotation_format',
      'title','QuotesDone — What a Supplier Quotation Contains',
      'kw', to_jsonb(array['quotation format','quote format','what is in a quote','quote fields','lead time','validity','payment terms','warranty','scope','exclusions','anonymized']),
      'content',
        'A supplier quotation carries: the quote amount, lead time, validity period, payment terms, warranty, scope of '
        'supply, conditions, exclusions, and notes. It may be typed or extracted from an uploaded file, then structured '
        'and committed (hashed) so it cannot be silently changed. BEFORE the customer sees it, the supplier''s identity '
        'and any contact details are anonymized/masked. The price the customer sees is the supplier''s own quotation '
        'excluding VAT (quote_amount): the customer pays the supplier that amount, and VAT is the supplier''s. QuotesDone adds '
        'no margin to it; our only charge is the reveal fee, 3% of the quotation excluding VAT, paid separately.'),

    jsonb_build_object('rid','terms','module','terms_and_conditions',
      'title','QuotesDone — Terms, Anonymity and Working Days',
      'kw', to_jsonb(array['terms','conditions','t&c','anonymous','reveal','working days','jurisdiction','policy','rules','uae']),
      'content',
        'QuotesDone is an ANONYMOUS UAE B2B marketplace. Suppliers are verified before they can quote. Buyer and supplier '
        'identities are hidden from each other until the buyer pays the reveal fee to contact a chosen supplier. All time '
        'windows use UAE working days (Asia/Dubai; Friday is a working day; the weekend is Saturday and Sunday; public '
        'holidays excluded). The reveal refund ladder is ' || coalesce(v_refund_wd::text,'5') || ' working days from payment: chase at '
        || coalesce(v_chase_wd::text,'3') || ', the CEO''s decision on day ' || coalesce(v_refund_wd::text,'5') || ', refund in full on no response, banks '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. Late fees '
        'follow UAE Federal Decree-Law 50/2022 (9% p.a.). The platform mediates disputes through a defined escalation ladder.'),

    jsonb_build_object('rid','governance','module','governance',
      'title','QuotesDone — How the Company Governs Itself',
      'kw', to_jsonb(array['governance','who approves','who decides','autonomy','refund approval','founder','ceo authority','escalation','boundaries','decisions','authority','seats']),
      'content',
        'QuotesDone runs as ' || coalesce(v_seat_n, 6) || ' AI seats and no departments (rulings of 7 Sep 2026 and 907): '
        'ceo, sales_engineer, customer_support, accountant, it_engineer and marketing. The CEO seat has full authority to reach '
        'the company target and is responsible for its decisions and their outcomes (ruling 1696): it decides every approval '
        'a seat needs, refunds of any amount included (8 Sep 2026), and the marketing month (15 Nov 2026), and it does not '
        'wait on the founder (ruling 1710). The founder sets the vision, the target and the boundaries, keeps his emergency '
        'stops and is told results; he is asked only what is truly his, such as a fact or a credential only he holds (ruling 1706). '
        'Seats hand work to one another through defined handoffs; nothing is left unowned.'),

    -- DYNAMIC: regenerated from the live org every run.
    jsonb_build_object('rid','organization','module','organization',
      'title','QuotesDone — The Organization: the Seats, Colleagues and Roles',
      'kw', to_jsonb(array['organization','org chart','seats','how many agents','who works here','colleagues','roles','team','who does what','are there departments','departments','list the seats','who decides']),
      'content', 'THE COMPANY YOU WORK IN (live roster from org_role — these are your colleagues; know who does what).' || E'\n' ||
        'THERE ARE NO DEPARTMENTS: the company is ' || coalesce(v_seat_n, 0) || ' seats (rulings of 7 Sep 2026 and 907). The CEO seat leads and decides (ruling 1696).' || E'\n' ||
        coalesce(v_seats, '  (org_role is empty)')),

    -- DYNAMIC: the live snapshot every run.
    jsonb_build_object('rid','live-state','module','live_state',
      'title','QuotesDone — Live Company State (current)',
      'kw', to_jsonb(array['live','current','right now','revenue','last month revenue','how much revenue','customers','suppliers','open tasks','kpi','last social post','last blog','latest post','state','status','how are we doing']),
      'content',
        'LIVE STATE as of ' || to_char(now(),'DD Mon YYYY HH24:MI') || ' UTC (this refreshes; if a figure is 0 the company '
        'is pre-launch, not broken):' || E'\n' ||
        '  Revenue (last 30 days): ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' AED' || E'\n' ||
        '  Customers: ' || coalesce(v_snap->>'customers','0') || ' (with an inquiry: ' || coalesce(v_snap->>'customers_with_inquiry','0') || ')' || E'\n' ||
        '  Approved suppliers: ' || coalesce(v_snap->>'approved_suppliers','0') || ' · Sendable supplier pool: ' || coalesce(v_snap->>'sendable_pool','0') || E'\n' ||
        '  Seats: ' || coalesce(v_seat_n::text, v_snap->>'employees', '6') || ' (no departments)' || E'\n' ||
        '  KPIs tracked: ' || coalesce(v_snap->>'kpis','0') || ' (open gaps: ' || coalesce(v_snap->>'kpi_gaps_open','0') || ')' || E'\n' ||
        '  Open tasks: ' || coalesce(v_snap->>'open_tasks','0') || E'\n' ||
        '  AI spend (last 30 days): ' || coalesce(v_snap->>'ai_cost_30d_aed','0') || ' AED' || E'\n' ||
        '  Last social post: ' || coalesce(nullif(v_social,''),'(none yet)') || case when v_social_at is not null then ' [' || v_social_at || ']' else '' end || E'\n' ||
        '  Last blog post: ' || coalesce(nullif(v_blog,''),'(none yet)') || case when v_blog_at is not null then ' [' || v_blog_at || ']' else '' end),

    jsonb_build_object('rid','stage','module','company_stage',
      'title','QuotesDone — What Stage the Company Is At',
      'kw', to_jsonb(array['stage','pre-launch','have we launched','are we live','do we have customers','how many customers','are we operating','company status','how far along','launched yet','traction','are we making money']),
      'content',
        'COMPANY STAGE — READ THIS BEFORE ANSWERING ANYTHING ABOUT TRACTION. QuotesDone is PRE-LAUNCH. The '
        'platform and the AI organization are built and being readied; there are ' || coalesce(v_snap->>'customers','0') ||
        ' real customers and AED ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' revenue so far. What is already in place: '
        || coalesce(v_seat_n, 6) || ' AI seats (no departments), ' || coalesce(v_cat_n, 0) || ' supplier categories, '
        'the knowledge base and ' || coalesce(v_snap->>'approved_suppliers','0') || ' approved supplier(s); paid model inference is on (ruling 1175). '
        'The order is: enough registered suppliers first, then a customer campaign (ruling 1701). '
        'NEVER claim customers, revenue, or results the numbers above do not show — we are building toward AED 1,000,000 by 31 Aug 2027, not there yet.'),

    -- 6 SEP 2026 (added at the END: sibling files restate this function; keep this the last element): the
    -- refund ladder, from pricing_config + decision_policy, the founder's ruling verbatim. Never re-ask him.
    jsonb_build_object('rid','refunds','module','refunds',
      'title','QuotesDone — The Refund Ladder (live): 5 working days, chase at 3, the CEO decides at 5',
      'kw', to_jsonb(array['refund','refund ladder','refund policy','refund window','non-response','supplier not responding','not responding','no response',
        'chase','chase the supplier','final call','who decides a refund','ceo decides the refund','working days','5 working days','five working days','3 working days',
        'bank','7-14 working days','how long does a refund take','admin fee','administrative fee','250','9%','interest','9% per annum',
        'who chases','who owns refunds','refund amount','how much is refunded','supplier charge','non-response charge','fn_refund_amount_aed','fn_refund_state','refund_ladder_sweep']),
      'content',
        'THE REFUND LADDER (the founder''s ruling of 6 Sep 2026 for the days and the money; the authority is the CEO''s since 8 Sep 2026; read live from pricing_config and decision_policy):' || E'\n' ||
        '  Day 0: the customer pays the reveal fee (' || round(v_fee*100,2) || '% of the quotation, no cap). The clock starts at PAYMENT; nothing the customer does or does not do moves it.' || E'\n' ||
        '  Working day ' || coalesce(v_chase_wd::text,'3') || ' with no supplier response: the sales engineer writes the chase and customer support delivers it to the supplier, customer copied, WhatsApp when opted in. Deterministic: fn_refund_ladder_sweep, cron refund_ladder_sweep_hourly.' || E'\n' ||
        '  Working day ' || coalesce(v_refund_wd::text,'5') || ' with still no response: the refund request is filed through fn_refund_request (the ONE door), the sales engineer makes the final call through customer support, and the CEO seat decides on what comes back.' || E'\n' ||
        '  No response to that call: the CEO approves the refund (fn_refund_decide; every refund, any amount, is the CEO''s decision, never automatic; public.refunds refuses a refund without a ceo_approval row). The founder is told the result, never asked (8 Sep 2026; rulings 1696, 1710).' || E'\n' ||
        '  The customer is refunded the FULL fee paid - no deduction - and told that banks take ' || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days to show it.' || E'\n' ||
        '  The supplier whose silence caused it owes: the exact amount refunded (the 3%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED ' || v_admin::text || ' administrative fee + ' || v_pct::text || '% per annum simple interest (the rate agreed in v14; 9% under v13 or earlier), and is blocked from matching until settled. One function states the arithmetic: fn_refund_amount_aed(paid, paid_at, refund_at).' || E'\n' ||
        '  Working days are Monday to Friday, UAE public holidays excluded (fn_is_working_day). fn_refund_state(transaction) says where any case stands.' || E'\n' ||
        'WHO OWNS WHAT: chase and final call = the sales engineer, delivered by customer support; the decision = the CEO; execution on Stripe, reconciliation and recovery from the supplier = the accountant. Never ask the founder about refunds.'),

    -- 6 SEP 2026: the brand kit, from company_brand (the founder attached the kit that day: "make sure it's
    -- in company knowledge so you never ask me about it again"). Appended LAST on purpose: sibling files add
    -- qd-company:decisions and qd-company:refunds to this same array; they merge ahead of this record.
    jsonb_build_object('rid','brand','module','brand',
      'title','QuotesDone — Brand Kit: colours, typography, logo rules, voice and asset files',
      'kw', to_jsonb(array['brand','brand kit','brand guide','brand guidelines','logo','logo files','lockup','wordmark','mark','favicon','app icon',
        'colour','color','colours','colors','hex','palette','teal','gold','navy','ink','brand colours','what are our colours','primary colour','primary color',
        'font','typeface','typography','poppins','plus jakarta sans','tajawal','arabic font','type scale',
        'tagline','clear space','minimum size','logo usage','social image size','cover size','avatar','banner','post template',
        'tone of voice','voice','wording','bilingual','arabic','rtl','email template','pdf header','letterhead','business card','trademark','ip filing','vector','svg',
        'where is the logo','which logo file','brand assets','brand bucket','contrast','wcag','accessibility','button colour','link colour']),
      'content',
        'THE BRAND KIT IS ON FILE (the founder attached QuotesDone_Brand_Kit.zip on 6 Sep 2026 and ruled it company knowledge: never ask him for a logo, a colour or a font again). '
        || 'Files: ' || (select count(*) from public.brand_assets where bucket = 'brand')::text
        || ' assets in the public brand bucket under kit/ (public.brand_assets holds kind, platform, path, size and usage per file; WHERE_TO_USE.txt is the kit index). '
        || 'The full guide is docs/brand/QUOTESDONE_BRAND_GUIDE.md and the "QuotesDone Brand Guide" PDF in the OS Reports panel.' || E'\n'
        || coalesce((select string_agg(g.block, E'\n' order by g.grp_sort)
                       from (select cb."group", min(cb.sort) as grp_sort,
                                    upper(cb."group") || ':' || E'\n'
                                    || string_agg('  - ' || cb.key || ': ' || cb.value || coalesce(' — ' || cb.note, ''), E'\n' order by cb.sort) as block
                               from public.company_brand cb group by cb."group") g),
                    '  (company_brand is empty)')),

    -- 6 SEP 2026: the founder's decisions, verbatim in substance, from company_policy_decision. Added at the
    -- END on purpose: the renderer is code-driven and sibling packets (the refund ladder and the brand kit
    -- above, messaging) add their records before it. Whichever packet lands last keeps its record last;
    -- order carries no meaning here.
    jsonb_build_object('rid','decisions','module','founder_decisions',
      'title','QuotesDone — The Founder''s Standing Decisions (never ask about these again)',
      'kw', to_jsonb(array['founder decision','founder decisions','standing decision','ruling','policy decision','what did the founder decide','never ask again',
        'corporate tax','auditor','meta token','daily budget cap','30 aed','cost per lead target','cpl target','openrouter','open router credit','recharge','receipts','expenses email',
        'discount','no discounts','reveal cap','category open','10 suppliers','finance budget','budget limit','profitable','supplier registration fee','first 1000','1000 aed per year','no deadline','no date']),
      'content',
        'THE FOUNDER''S STANDING DECISIONS. Each line is final. None is a question; none is asked again; every table, document and agent head is kept in sync with them.' || E'\n' ||
        coalesce(v_decisions, '(none recorded)'))
,

    -- 6 SEP 2026 (appended at the END, code-driven): the two supplier loops the founder decided on that day.
    jsonb_build_object('rid','supplier-loops','module','supplier_loops',
      'title','QuotesDone — Supplier acquisition loop and weekly sanctions screening (owners, cadence, switch)',
      'kw', to_jsonb(array['supplier acquisition','invite campaign','supplier invites','follow-up','follow up','300 suppliers','suppliers per month',
        'registered suppliers target','lead intake','inbound email','new leads','lead sourcing','supplier_outreach_golive','outreach switch','is outreach on',
        'sanctions','sanctions screening','UN consolidated list','UAE terrorist list','local terrorist list','screening hit','banned supplier',
        'who owns supplier acquisition','who screens suppliers','compliance officer','business development manager','weekly screening','when do we screen']),
      'content',
        'SUPPLIER ACQUISITION LOOP (founder decision 6 Sep 2026). Owner: ' || coalesce(v_supply_owner, 'Sales Engineer') || ' (org_agents.sales_engineer; there are no departments) — '
        'no new employee was created; this is that role''s existing responsibility. Target: at least ' || v_reg_target || ' suppliers registered every month '
        '(company_goals.suppliers_registered_monthly; the BD scorecard KPI "Suppliers registered per month", measured from leads registration timestamps). '
        'This month so far: ' || coalesce(v_reg_month, '0 (not measured yet)') || '. Sources: the leads we already hold (' || v_invited || ' invited to date, '
        || v_registered || ' registered), inbound e-mail (senders on business domains become leads; supplier-intent replies are classified by keyword — no model — into '
        'register / question / document / decline / bounce and become ONE reply task on the sales engineer; ' || v_intake || ' classified so far), and the staged directory '
        'promoted daily by supplier_discovery_daily. No scraping (Apify paused) and no paid inference anywhere in the loop. Cadence: supplier_invites_daily 09:00 UTC '
        '(the invitation batch, capped, deliverability-guarded) and supplier_outreach_daily 05:30 UTC (follow-ups at +3 and +7 WORKING days after a delivered '
        'invitation, at most two, never to a lead that replied, registered, bounced or is suppressed; ' || v_followups || ' follow-ups sent to date; inbox intake). New leads are sourced once a month by Claude on the subscription and ingested (ruling 1205), not by an automated job. '
        'THE SWITCH: app_secrets.supplier_outreach_golive is ' || case when v_golive then 'TRUE — outreach is LIVE.' else 'FALSE — every part of the loop is HELD and records "held" on each run; the founder flips it when the app is ready ("none of this will run till the app is perfect").' end
        || ' Both it and invite_enabled must be true before an invitation is written.' || E'\n\n' ||
        'WEEKLY SANCTIONS SCREENING (founder decision 6 Sep 2026). Owner: ' || coalesce(v_co, 'Chief Executive (AI)') || ' (org_agents.ceo — a confirmed hit removes a supplier and every approval is the CEO''s; '
        'the sales engineer holds the outreach while the decision is open). Cadence: sanctions_screen_weekly, Mondays 03:00 UTC (07:00 Dubai). '
        'Sources: the UN Security Council consolidated list (XML; last: ' || coalesce(v_last_un, 'not fetched yet') || ') and the UAE Local Terrorist List from the Executive Office '
        'for Control & Non-Proliferation (published as PDF and legacy Excel only — the Excel is parsed, the PDF is not; last: ' || coalesce(v_last_uae, 'not fetched yet') || '). '
        'Every registered supplier is screened on legal name, licence name, owner, contact and e-mail domain by normalised exact match and conservative token overlap. '
        'A hit opens ONE decision task on the ceo with the evidence and ONE hold on the sales engineer — the team is updated, never the founder — and NOBODY is removed automatically: '
        'the ceo decides (fn_supplier_screening_decide), and a CONFIRMED hit moves the supplier through the existing status path (banned, matching blocked, approval withdrawn). '
        'Open hits right now: ' || v_hits_open || '. Records: screening_run (source, entries, fetched_at, sha256), screening_entry, supplier_screening_hit.'),

    -- 6 SEP 2026 (LAST on purpose — every sibling file of the day restates this function and the last record
    -- is the one a later restatement can carry forward without touching the others): the WhatsApp templates
    -- and their Meta approval status, live from messaging_template (the founder said "fix the template
    -- yourself"; the status is company knowledge, never his question).
    jsonb_build_object('rid','messaging-templates','module','messaging_templates',
      'title','QuotesDone — WhatsApp templates and their Meta approval status (live)',
      'kw', to_jsonb(array['whatsapp template','whatsapp templates','template approval','meta approval','twilio','content sid','contentsid',
        'founder alert whatsapp','whatsapp alert','whatsapp alerts to the founder','is the whatsapp template approved','pending template',
        'template pending','template rejected','63016','utility template','messaging template','messaging_template','wa_template_sids',
        'can we send whatsapp','why did the whatsapp not arrive','send_whatsapp','wa_template_setup','business-initiated message','24-hour session']),
      'content',
        'WHATSAPP TEMPLATES (Twilio Content API, approved by Meta; live from messaging_template):' || E'\n' || v_tmpl || E'\n' ||
        'THE RULES. A business-initiated WhatsApp (an alert to the founder, a job / quote / reveal / document notice to a supplier or '
        'customer) is deliverable ONLY through a Meta-APPROVED template sent by ContentSid; a freeform body is delivered only inside the '
        '24-hour session the recipient opened by messaging us first (Twilio error 63016 otherwise). A template still pending approval is a '
        'HELD message, never a failed one: send_whatsapp keeps supplier and customer rows queued until the template lands, marks founder-alert '
        'rows skipped with the reason (the email already carried the alert), and refuses a direct send with the reason instead of erroring. '
        'Templates are created and submitted by the wa_template_setup function (category UTILITY, language en/ar, the body opens AND closes '
        'with literal text because Meta rejects a variable at the start or end); the sender refreshes each pending status from Twilio at most '
        'every ten minutes and only ever sends with a status of APPROVED. The sender number is registered with Meta as "QuotesDone" '
        '(quality rating and messaging tier are read from Twilio, not assumed). Nobody asks the founder about WhatsApp templates: the '
        'status above is the answer, and a pending line means Meta has not answered yet.')
  );

  for r in select * from jsonb_array_elements(v_records) loop
    v_rid := 'qd-company:' || (r->>'rid');
    insert into public.ops_knowledge(
      record_id, scope_type, scope_key, layer, module, record_type, title, content,
      structured_data, source_ids, implementation_status, validation_status, authority_tier,
      risk_level, version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness,
      confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status,
      effective_date)
    values (
      v_rid, 'company', 'company_core', 'company_core', r->>'module', 'md', r->>'title',
      -- fold the keyword vocabulary into the content so the generated tsv (title+content) indexes the
      -- phrasings agents actually ask in, not only the prose. This is what makes deep questions match.
      (r->>'content') || E'\n\nYou can answer questions about: ' ||
        array_to_string(array(select jsonb_array_elements_text(r->'kw')), ', ') || '.',
      '{}'::jsonb, array['fn_company_self_knowledge_sync'], 'active', 'validated', 'autonomous',
      'low', '1', array(select jsonb_array_elements_text(r->'kw')), '{}'::text[], '{}'::jsonb, 'UAE', 'current',
      'internal', true, true, 'current', 'pending', current_date)
    on conflict (record_id) do update set
      module = excluded.module, title = excluded.title, content = excluded.content,
      keywords = excluded.keywords, effective_date = excluded.effective_date,
      supersession_state = 'current', embedding_status = 'pending';
    v_n := v_n + 1;
  end loop;

  -- The org directory (everyone knows everyone: role, line manager, KPI, live rating) and the
  -- published content (FAQ, social, blog, website) are recomposed in the same refresh.
  perform public.fn_company_org_directory_sync();

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now(),
    'revenue_30d_aed', v_snap->>'revenue_30d_aed', 'reveal_fee_pct', round(v_fee*100,2),
    'employees', v_snap->>'employees');
end $function$;

-- 6. fn_inquiry_conversation_summary_build (live body of 19 Nov 2026; the quotes amounts line)
CREATE OR REPLACE FUNCTION public.fn_inquiry_conversation_summary_build(p_inquiry uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with i as (select * from public.inquiries where id = p_inquiry),
  msg as (select v.source_table, v.source_id, v.channel, v.direction, v.occurred_at
            from public.v_conversation_message v where v.inquiry_id = p_inquiry::text),
  q as (select qu.*, l.company_name from public.quotes qu left join public.leads l on l.id = qu.supplier_id
         where qu.inquiry_id = p_inquiry),
  t as (select * from public.transactions where inquiry_id = p_inquiry),
  rq as (select * from q where q.id in (select quote_id from t))
  select jsonb_build_object(
    'inquiry', (select jsonb_build_object('id', i.id, 'rfq_no', i.rfq_no, 'category', i.category, 'trades', i.trades,
                  'emirate', i.emirate, 'summary', i.summary, 'budget', i.budget, 'required_by', i.required_by,
                  'status', i.status) from i),
    'parties', jsonb_build_object(
       'customer_id', (select customer_id from i),
       'suppliers', (select coalesce(jsonb_agg(distinct jsonb_build_object('supplier_id', q.supplier_id, 'company', q.company_name)), '[]') from q)),
    'spec_decisions', jsonb_build_object(
       'clarifications', (select coalesce(jsonb_agg(jsonb_build_object('asked_at', r.asked_at, 'kind', r.kind,
                            'question', r.question, 'answer', r.answer) order by r.asked_at), '[]')
                            from public.rfq_clarification r where r.inquiry_id = p_inquiry),
       'accepted_alternatives', (select accepted_alternatives from i)),
    -- quote_amount, labelled ex VAT (19 Nov 2026, ruling 1687); the marked-up generated column is no longer stored here.
    'amounts', jsonb_build_object(
       'quotes', (select coalesce(jsonb_agg(jsonb_build_object('supplier_id', q.supplier_id, 'quote_amount', q.quote_amount,
                    'quote_amount_basis', 'excluding VAT', 'status', q.status, 'at', q.created_at) order by q.created_at), '[]') from q),
       'transactions', (select coalesce(jsonb_agg(jsonb_build_object('quote_id', t.quote_id, 'quote_amount', t.quote_amount,
                    'reveal_fee', t.reveal_fee, 'total_charged', t.total_charged, 'revealed_at', t.revealed_at,
                    'refund_status', t.refund_status, 'refund_amount_aed', t.refund_amount_aed)), '[]') from t)),
    'dates', jsonb_build_object(
       'created', (select created_at from i), 'first_quote', (select min(created_at) from q),
       'revealed', (select min(revealed_at) from t), 'completed', (select completed_at from i),
       'first_message', (select min(occurred_at) from msg), 'last_message', (select max(occurred_at) from msg)),
    'commitments', (select coalesce(jsonb_agg(jsonb_build_object('supplier_id', rq.supplier_id, 'lead_time', rq.lead_time,
                      'validity', rq.validity, 'payment_terms', rq.payment_terms, 'warranty', rq.warranty,
                      'scope', rq.scope, 'exclusions', rq.exclusions)), '[]') from rq),
    'disputes', jsonb_build_object(
       'post_reveal', (select coalesce(jsonb_agg(jsonb_build_object('raised_by', d.raised_by, 'stage', d.stage,
                        'outcome', d.outcome, 'decided_at', d.decided_at)), '[]') from public.post_reveal_dispute d where d.inquiry_id = p_inquiry),
       'refunds', (select coalesce(jsonb_agg(jsonb_build_object('status', r.status, 'reason_code', r.reason_code,
                    'amount_fils', r.amount_fils, 'settled_at', r.settled_at)), '[]') from public.refunds r where r.inquiry_id = p_inquiry),
       'complaints', (select coalesce(jsonb_agg(jsonb_build_object('ticket_no', ct.ticket_no, 'status', ct.status,
                       'at', ct.created_at)), '[]')
                       from public.complaint_tickets ct join public.customers c on lower(c.email) = lower(ct.email)
                      where c.id = (select customer_id from i))),
    'outcome', (select jsonb_build_object('outcome', i.outcome, 'lost_reason', i.lost_reason, 'status', i.status,
                  'hired_supplier_id', i.hired_supplier_id) from i),
    'conversation', jsonb_build_object(
       'messages', (select count(*) from msg),
       'by_channel', (select coalesce(jsonb_object_agg(channel, n), '{}') from (select channel, count(*) n from msg group by 1) c),
       'sources', (select coalesce(jsonb_agg(source_table || ':' || source_id order by occurred_at), '[]') from msg)),
    'originals', 'kept: Cabinet Decision 74/2023 Art. 3(1)(b) requires the records for 5 years from the end of the year of creation; this summary is an index');
$function$;

-- CREATE OR REPLACE keeps each ACL (service_role and postgres only, read 19 Nov 2026); the revokes restate it, one signature each
-- (one overload of every routine above: pg_proc, 19 Nov 2026).
revoke execute on function public.fn_supplier_stats(bigint) from public, anon, authenticated;
revoke execute on function public.fn_supplier_market(bigint) from public, anon, authenticated;
revoke execute on function public.fn_customer_decision_support(uuid) from public, anon, authenticated;
revoke execute on function public.fn_pool_say(text, text, text, jsonb, boolean) from public, anon, authenticated;
revoke execute on function public.fn_company_self_knowledge_sync() from public, anon, authenticated;
revoke execute on function public.fn_inquiry_conversation_summary_build(uuid) from public, anon, authenticated;

-- The one stored copy of the quotation-format record (ops_knowledge 'qd-company:quotation-format', 1 row carrying the sentence on
-- 19 Nov 2026), corrected now rather than at the next sync, which writes the same text. Re-running finds nothing to change.
update public.ops_knowledge
   set content = replace(content,
         'The price the customer sees (customer_price) includes the platform margin/app fee on top of the supplier''s amount.',
         'The price the customer sees is the supplier''s own quotation excluding VAT (quote_amount): the customer pays the supplier '
         || 'that amount, and VAT is the supplier''s. QuotesDone adds no margin to it; our only charge is the reveal fee, 3% of the '
         || 'quotation excluding VAT, paid separately.'),
       embedding_status = 'pending'
 where record_id = 'qd-company:quotation-format' and content like '%(customer_price) includes the platform margin%';

-- ── PROBE ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Seven ZZ DEMO suppliers (leads.source 'qd_demo_fixture', company 'ZZ DEMO …', no e-mail, no phone, unclaimed), one ZZ DEMO
-- customer (no e-mail, no phone) and seven ZZ DEMO enquiries in a trade nobody else has ('zzprobe_trade'), all inside a sub-block
-- that always ends in a raise, so every row is rolled back and nothing can be sent to anyone. [1] is the asking supplier.
--   A. one enquiry: [1] 10,000 submitted, [2] 8,000 submitted, [3] 9,000 DRAFT, [4] 9,500 WITHDRAWN.
--      The old fn_supplier_stats said avg_pct_above_lowest 25.0 here, and 10,000 / 1.25 = 8,000: [2]'s price exactly.
--      Expect: no positioning figure, no market price, decision support's cheapest = 8,000 (quote_amount, not the 8,480 the
--      margin column holds) over 2 quotes (the draft is not one).
--   B. five more enquiries with [1] 10,000 and [2] 9,000, [3] 10,500, [4] 12,000 submitted, all five still OPEN: nothing counts
--      (a request taking quotes lets [1] move his own price and watch the answer). Four of them closed: 4 comparisons, nothing.
--   C. the fifth closed: 5 comparisons. Expect avg_pct_above_lowest 10 (11.1 to a 5-point step), avg_pct_vs_average -5 (-4.8),
--      the band 'below market average' read from the rounded -5, times_lowest null, and a market price over 16 other quotes from
--      3 companies: median 10,000, middle half 5,000-15,000 on a 5,000 step, with no low, no high, no mean and none of the
--      amounts anywhere in the payload.
--   D. a seventh enquiry, OPEN, where [1] at 10,000 is the lowest against three rivals at 20,000: positioning must not move.
--      Counted, it would read times_lowest 1 and a different average.
create temp table zz_price_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  v_cust uuid := gen_random_uuid();
  sup bigint[]; inq uuid[] := array[]::uuid[]; qs uuid[]; v_i uuid; k int;
  s_thin jsonb; m_thin jsonb; s_open jsonb; s_four jsonb; s_ok jsonb; s_d jsonb; m_ok jsonb; d_ok jsonb; d_one jsonb; v_say text;
  v_err text; v_amounts int; v_summ jsonb; v_ok boolean; v_detail text;
  b_q bigint; b_l bigint; b_i bigint; b_c bigint; b_h bigint; a_q bigint; a_l bigint; a_i bigint; a_c bigint; a_h bigint;
begin
  select count(*) into b_q from public.quotes;      select count(*) into b_l from public.leads;
  select count(*) into b_i from public.inquiries;   select count(*) into b_c from public.customers;
  select count(*) into b_h from public.quote_quality_hold;
  begin
    insert into public.customers (id, full_name) values (v_cust, 'ZZ DEMO Price Probe Customer');
    with ins as (
      insert into public.leads (company_name, source, sector)
      select 'ZZ DEMO Price Probe Supplier ' || g, 'qd_demo_fixture', 'zzprobe_trade' from generate_series(1, 7) g
      returning id)
    select array_agg(id order by id) into sup from ins;
    if coalesce(array_length(sup, 1), 0) <> 7
       or exists (select 1 from public.leads where id = any(sup) and not is_demo)
       or not exists (select 1 from public.customers where id = v_cust and is_demo) then
      raise exception 'fixture: the ZZ DEMO suppliers or customer did not land as demo';
    end if;

    for k in 1..7 loop
      insert into public.inquiries (customer_id, brief_source, category, trades, summary, status)
      values (v_cust, 'qd_demo_fixture', 'zzprobe_trade', array['zzprobe_trade'], 'ZZ DEMO price probe enquiry ' || k, 'open')
      returning id into v_i;
      inq := inq || v_i;
    end loop;

    -- A quote is SENT the way the estate sends one (a_supplier_sees_only_the_jobs_it_was_matched_to_probe.sql): the quality
    -- gate holds a figure-only quote as a draft, the probe releases the hold as its 24 h clock would, and submits it again.
    qs := array[gen_random_uuid(), gen_random_uuid()];
    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status) values
      (qs[1], inq[1], sup[1], 10000, 'qd_demo_fixture', 1, 'draft'),
      (qs[2], inq[1], sup[2],  8000, 'qd_demo_fixture', 1, 'draft');
    insert into public.quotes (inquiry_id, supplier_id, quote_amount, source, option_no, status) values
      (inq[1], sup[3], 9000, 'qd_demo_fixture', 1, 'draft');
    insert into public.quotes (inquiry_id, supplier_id, quote_amount, source, option_no, status) values
      (inq[1], sup[4], 9500, 'qd_demo_fixture', 1, 'withdrawn');
    update public.quotes set status = 'submitted' where id = any(qs);
    update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = any(qs) and released_at is null;
    update public.quotes set status = 'submitted' where id = any(qs);
    if (select count(*) from public.quotes where id = any(qs) and status = 'submitted') <> 2 then
      raise exception 'fixture: the two quotes of stage A were not submitted';
    end if;
    s_thin := public.fn_supplier_stats(sup[1])->'price_positioning';
    m_thin := public.fn_supplier_market(sup[1])->'avg_market_price';
    d_one  := (select e from jsonb_array_elements(public.fn_customer_decision_support(v_cust)->'recommend') e
                where e->>'inquiry_id' = inq[1]::text);

    for k in 2..6 loop
      qs := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
      insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status) values
        (qs[1], inq[k], sup[1], 10000, 'qd_demo_fixture', 1, 'draft'),
        (qs[2], inq[k], sup[2],  9000, 'qd_demo_fixture', 1, 'draft'),
        (qs[3], inq[k], sup[3], 10500, 'qd_demo_fixture', 1, 'draft'),
        (qs[4], inq[k], sup[4], 12000, 'qd_demo_fixture', 1, 'draft');
      update public.quotes set status = 'submitted' where id = any(qs);
      update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = any(qs) and released_at is null;
      update public.quotes set status = 'submitted' where id = any(qs);
    end loop;
    s_open := public.fn_supplier_stats(sup[1])->'price_positioning';
    update public.inquiries set status = 'closed' where id = any(inq[2:5]);
    s_four := public.fn_supplier_stats(sup[1])->'price_positioning';
    update public.inquiries set status = 'closed' where id = inq[6];
    if (select count(*) from public.inquiries where id = any(inq[2:6]) and status = 'closed') <> 5 then
      raise exception 'fixture: the five enquiries of stage C did not close';
    end if;
    s_ok := public.fn_supplier_stats(sup[1])->'price_positioning';
    m_ok := public.fn_supplier_market(sup[1])->'avg_market_price';

    qs := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status) values
      (qs[1], inq[7], sup[1], 10000, 'qd_demo_fixture', 1, 'draft'),
      (qs[2], inq[7], sup[5], 20000, 'qd_demo_fixture', 1, 'draft'),
      (qs[3], inq[7], sup[6], 20000, 'qd_demo_fixture', 1, 'draft'),
      (qs[4], inq[7], sup[7], 20000, 'qd_demo_fixture', 1, 'draft');
    update public.quotes set status = 'submitted' where id = any(qs);
    update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = any(qs) and released_at is null;
    update public.quotes set status = 'submitted' where id = any(qs);
    s_d := public.fn_supplier_stats(sup[1])->'price_positioning';
    d_ok := public.fn_customer_decision_support(v_cust);
    select count(*) into v_amounts from unnest(array['8000', '9000', '9500', '10500', '12000']) x
     where position(x in m_ok::text) > 0 or position(x in m_thin::text) > 0;
    v_summ := public.fn_inquiry_conversation_summary_build(inq[1]);
    v_say := public.fn_pool_say('quote.received', 'quote', gen_random_uuid()::text,
                                jsonb_build_object('quote_amount', 10000, 'customer_price', 10500), false);
    raise exception 'ZZPROBE rollback';
  exception when others then
    v_err := sqlerrm;
  end;

  select count(*) into a_q from public.quotes;      select count(*) into a_l from public.leads;
  select count(*) into a_i from public.inquiries;   select count(*) into a_c from public.customers;
  select count(*) into a_h from public.quote_quality_hold;
  v_ok := v_err = 'ZZPROBE rollback'
    -- A: two quotes on an enquiry give no figure, and the draft and the withdrawn quote are no bids
    and (s_thin->>'ready')::boolean = false and (s_thin->>'competitive_rfqs')::int = 0
    and s_thin->>'avg_pct_above_lowest' is null and s_thin->>'avg_pct_vs_average' is null and s_thin->>'lowest_rate' is null
    and s_thin->>'band' = 'not enough comparisons yet'
    and (m_thin->>'available')::boolean = false and m_thin->'low' is null and m_thin->'high' is null and m_thin->>'value' is null
    and (d_one->>'cheapest_price')::numeric = 8000 and (d_one->>'quotes')::int = 2
    and d_one->>'price_basis' = 'quote_amount_excluding_vat'
    -- B: open requests count for nothing, and four comparisons are still not enough
    and (s_open->>'ready')::boolean = false and (s_open->>'competitive_rfqs')::int = 0
    and (s_four->>'ready')::boolean = false and (s_four->>'competitive_rfqs')::int = 4 and s_four->>'avg_pct_vs_average' is null
    -- C: five give a band on 5-point steps
    and (s_ok->>'ready')::boolean = true and (s_ok->>'competitive_rfqs')::int = 5
    and (s_ok->>'avg_pct_above_lowest')::numeric = 10 and (s_ok->>'avg_pct_vs_average')::numeric = -5
    and (s_ok->>'lowest_rate')::numeric = 0 and s_ok->>'band' = 'below market average' and s_ok->'times_lowest' = 'null'::jsonb
    -- D: an open request where [1] is the lowest moves nothing
    and s_d = s_ok
    and (m_ok->>'available')::boolean = true and (m_ok->>'population')::int = 16 and (m_ok->>'suppliers')::int = 3
    and (m_ok->>'median')::numeric = 10000 and (m_ok->>'value')::numeric = 10000
    and (m_ok->>'p25')::numeric = 5000 and (m_ok->>'p75')::numeric = 15000 and (m_ok->>'rounded_to')::numeric = 5000
    and m_ok->'low' is null and m_ok->'high' is null and m_ok->'mean' is null
    and v_amounts = 0
    and position('customer_price' in coalesce(d_ok::text, '')) = 0
    and v_summ is not null and position('customer_price' in v_summ::text) = 0
    and v_summ#>>'{amounts,quotes,0,quote_amount_basis}' = 'excluding VAT'
    and v_say like 'a quotation of AED 10,000 excluding VAT arrived%'
    and position('includes the platform margin' in (select prosrc from pg_proc where oid = 'public.fn_company_self_knowledge_sync()'::regprocedure)) = 0
    and not exists (select 1 from public.ops_knowledge where record_id = 'qd-company:quotation-format' and content like '%includes the platform margin%')
    and a_q = b_q and a_l = b_l and a_i = b_i and a_c = b_c and a_h = b_h;
  v_detail := format('A: stats=%s market=%s decision=%s; B: open=%s four_closed=%s; C: stats=%s market=%s; D: stats=%s; amounts_in_payload=%s; summary_quotes=%s; pool=%s; '
                     || 'rows before/after quotes %s/%s leads %s/%s inquiries %s/%s customers %s/%s holds %s/%s; block ended with: %s',
                     s_thin, m_thin, d_one, s_open, s_four, s_ok, m_ok, s_d, v_amounts, v_summ#>'{amounts,quotes}', v_say, b_q, a_q, b_l, a_l, b_i, a_i, b_c, a_c, b_h, a_h, v_err);
  if not coalesce(v_ok, false) then
    raise exception 'PROBE FAILED: %', v_detail;
  end if;
  insert into zz_price_probe_verdict values ('PROBE OK: two quotes give no figure, an open request counts for nothing, five closed '
    || 'comparisons give a 5-point band, '
    || 'the market price has no low or high, and decision support returns quote_amount', v_detail);
end $probe$;
select * from zz_price_probe_verdict;
