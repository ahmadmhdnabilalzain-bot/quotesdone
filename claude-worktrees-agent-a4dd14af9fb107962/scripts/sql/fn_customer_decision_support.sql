-- THE PORTAL TOLD A CUSTOMER WHAT HAPPENED AND NEVER HELPED THEM DECIDE.
--
-- 13 Aug 2026, the founder's own framing of the gap: "the comparison exists but nothing tells them
-- which quote to take and why, in their own terms; nothing shows them what a job like theirs
-- normally costs in the UAE before they get quotes; nothing follows up: a request goes quiet and
-- the portal never says what to do about it."
--
-- Three answers, one query, all computed from this customer's own rows. Every one of them has an
-- honest empty state, because on the day this shipped the estate held 0 inquiries and 0 quotes and
-- a panel that invents a number to look finished is worse than one that says what it does not know.
--
-- WHAT THIS DELIBERATELY DOES NOT DO: it does not print a price range for a category with no
-- quoted history. category_price_stats is empty (0 rows) because no QuotesDone job has been quoted
-- yet. A "typical UAE price" derived from nothing is a fabrication, and the founder's standing rule
-- is that we never state what we have not measured. So the market answer prints what IS known - how
-- many suppliers can actually quote this trade in this emirate, and how long first quotes have
-- historically taken - and says plainly that there is no price history yet. It lights up on its own
-- the moment MIN_PRICE_N quotes exist in a category.
--
-- IT ALSO DOES NOT RANK QUOTES BEHIND A SCORE. A single "best" number would hide the trade-off the
-- customer is actually making. It names the cheapest and the fastest, and when they are different
-- quotes it states the cost of choosing one over the other in dirhams and in days - which is the
-- decision, in their terms. Where the two coincide it says so, because that is the one case where
-- there is no trade-off to weigh.

create or replace function public.fn_customer_decision_support(p_customer uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
    select i.id inq, i.summary, i.category, q.id qid, q.supplier_id,
           coalesce(q.customer_price, q.quote_amount) price,
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
      and coalesce(q.status,'') not in ('withdrawn','expired','rejected')
      and coalesce(q.customer_price, q.quote_amount) is not null
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
           'cheapest_quote_id', cheapest_id, 'cheapest_price', cheapest_price,
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
end $$;

-- CREATE (not CREATE OR REPLACE of a pre-existing routine) grants EXECUTE to PUBLIC, and this
-- function takes a customer id and returns that customer's commercial position. It must never be
-- callable by anon. customer_portal reaches it with the service role.
revoke all on function public.fn_customer_decision_support(uuid) from public, anon, authenticated;
