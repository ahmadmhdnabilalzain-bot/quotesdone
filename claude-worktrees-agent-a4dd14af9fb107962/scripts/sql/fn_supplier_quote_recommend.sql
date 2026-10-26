-- ==============================================================================================
-- ROW #5 §11 — THE AI QUOTE BUILDER. The supplier writes nothing; the routine proposes the terms.
--
-- ── WHAT THIS IS NOT, BECAUSE THE ESTATE ALREADY HAS BOTH OF THEM ───────────────────────────────
-- fn_quote_coach GRADES a quote the supplier already wrote. fn_supplier_negotiation READS one back
-- and drafts a reply about it. Both live near the words "recommend" and "price" and neither one
-- proposes a quote. §11's premise is the opposite of both: nothing exists yet, and the routine
-- produces the price, the delivery, the warranty and the risk from the market around the enquiry.
--
-- ── EVERY FIGURE COMES FROM THE COMPETING BIDS ON THIS ENQUIRY, NOT FROM A CATEGORY AVERAGE ──────
-- The first design took the median of every quote in the category. That is wrong in a way that
-- looks right: the category holds a 268,000 restaurant extract and a 1,333,400 tower FCU package,
-- so its median is a number no individual project has any reason to be near. What a supplier
-- actually needs to know is what the OTHER suppliers bid on THIS enquiry, and that is a population
-- of four here — small, but exactly the right four.
--
-- When that population is empty the routine returns available:false and names it. It does not fall
-- back to a category average and call it a recommendation, because a supplier cannot tell the
-- difference on screen between a figure derived from this project and one derived from a different
-- project of a different size.
--
-- ── WHY THE MEDIAN, AND WHY THE SPREAD IS RETURNED WITH IT ──────────────────────────────────────
-- The recommendation is the midpoint of the competing bids. Undercutting is a decision with
-- consequences for the supplier's margin and it is theirs to take, not the routine's to take for
-- them — so the full range and both quartiles come back with the number and the surface shows them.
-- A single figure with no spread around it would hide how much disagreement there is about scope.
--
-- ── DEMO AND LIVE ARE PARTITIONED, AS THEY ARE IN fn_supplier_market ─────────────────────────────
-- Same symmetric predicate. A demo fixture prices against demo bids; a real supplier prices against
-- real ones. A fixture can never move the price a real supplier is advised to charge.
create or replace function public.fn_supplier_quote_recommend(p_lead_id bigint, p_inquiry_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),
  inq as (select * from public.inquiries where id = p_inquiry_id),

  -- The competing bids: what every OTHER supplier has priced this same enquiry at.
  bids as (
    select q.quote_amount amt, q.lead_time, q.warranty, q.payment_terms
    from public.quotes q, flag
    where q.inquiry_id = p_inquiry_id
      and q.supplier_id is distinct from p_lead_id
      and q.quote_amount is not null and q.quote_amount > 0
      and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  stat as (
    select count(*) n,
           round(percentile_cont(0.5)  within group (order by amt)) mid,
           round(percentile_cont(0.25) within group (order by amt)) lo,
           round(percentile_cont(0.75) within group (order by amt)) hi,
           min(amt) lowest, max(amt) highest
    from bids
  ),

  -- The supplier's own habit, measured rather than assumed: across every enquiry they have priced,
  -- where did they sit against the midpoint of that enquiry's other bids? An index of 1.04 means
  -- this company prices 4% above the middle of the market, and it is computed from their own rows.
  habit as (
    select round(avg(ratio)::numeric, 3) idx, count(*) n
    from (
      select q.quote_amount / nullif((
               select percentile_cont(0.5) within group (order by o.quote_amount)
               from public.quotes o
               where o.inquiry_id = q.inquiry_id and o.supplier_id is distinct from q.supplier_id
                 and o.quote_amount > 0), 0) as ratio
      from public.quotes q, flag
      where q.supplier_id = p_lead_id and q.quote_amount > 0
        and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
    ) r where r.ratio is not null
  ),

  -- ── DELIVERY, WARRANTY AND TERMS ARE TEXT, SO THEY ARE PICKED, NOT AVERAGED ───────────────────
  -- The average of "8-10 weeks" and "12-14 weeks" is not a promise anybody made, so the routine
  -- returns an answer a real supplier actually gave.
  --
  -- WHICH answer took two attempts, and the first one was wrong in a way worth recording. Taking
  -- `order by count(*) desc, <text>` looks like "the most common", but when all four bids are
  -- distinct every count is 1 and the tie breaks ALPHABETICALLY — which recommended "12-14 weeks",
  -- the slowest delivery on the board, and "12 months on equipment", the weakest warranty. A
  -- tie-break is not a market consensus, and dressing one up as the modal answer is the same defect
  -- class as an invented percentage: arithmetic that ran correctly over the wrong population.
  --
  -- So: when a value genuinely repeats, that mode is the answer and `agreed_by` says how many said
  -- it. When nothing repeats there IS no consensus, and the answer is the MIDDLE of the observed
  -- range ranked by its leading number — a real bid, neither the fastest nor the slowest — with
  -- `consensus` false so the surface can say the suppliers disagreed.
  ranked as (
    select 'lead' kind, lead_time v, count(*) c,
           min(coalesce(substring(lead_time from '\d+')::int, 999)) ord
    from bids where lead_time is not null group by 1, 2
    union all
    select 'warranty', warranty, count(*),
           min(coalesce(substring(warranty from '\d+')::int, 999))
    from bids where warranty is not null group by 1, 2
    union all
    select 'terms', payment_terms, count(*),
           min(coalesce(substring(payment_terms from '\d+')::int, 999))
    from bids where payment_terms is not null group by 1, 2
  ),
  picked as (
    select kind, v, c, has_mode from (
      select r.kind, r.v, r.c,
             max(r.c) over (partition by r.kind) >= 2 as has_mode,
             row_number() over (partition by r.kind order by r.c desc, r.ord) rn_mode,
             row_number() over (partition by r.kind order by r.ord) rn_ord,
             count(*) over (partition by r.kind) tot
      from ranked r
    ) z
    where (z.has_mode and z.rn_mode = 1)
       or (not z.has_mode and z.rn_ord = (z.tot + 1) / 2)
  ),
  lead_pick  as (select v, c, has_mode from picked where kind = 'lead'),
  warr_pick  as (select v, c, has_mode from picked where kind = 'warranty'),
  terms_pick as (select v, c, has_mode from picked where kind = 'terms'),

  -- ── RISK, AS NAMED SIGNALS RATHER THAN A MOOD ─────────────────────────────────────────────────
  -- Each signal is a condition on a real column, each carries the sentence a supplier would need to
  -- act on it, and the level is the count. A risk score with no reasons attached is a number the
  -- supplier can neither check nor fix.
  risk as (
    select coalesce(jsonb_agg(jsonb_build_object('signal', s.k, 'detail', s.d)) filter (where s.hit), '[]'::jsonb) items,
           count(*) filter (where s.hit) n
    from (
      select 'not_matchable' k,
             not public.fn_is_matchable(m.verified, m.banned, m.matching_blocked,
                                        m.approval_status, m.permanently_closed, m.chat_strikes) hit,
             'Your account cannot currently receive work, so a quote sent now may not reach the customer.' d
      from me m
      union all
      select 'licence_missing',
             (select license_expiry is null from me),
             'No licence expiry is on file, and approval depends on it.'
      union all
      select 'licence_expired',
             (select coalesce(license_expiry < current_date, false) from me),
             'Your trade licence has expired.'
      union all
      select 'brief_incomplete',
             coalesce(((select completeness->>'score' from inq))::int < 60, true),
             'The customer brief is incomplete, so the scope you price may move after you send this.'
      union all
      select 'thin_market',
             (select n from stat) < 3,
             'Fewer than three other suppliers have priced this, so the midpoint is a weak signal.'
      union all
      select 'wide_spread',
             (select case when mid > 0 then (highest - lowest) / mid > 0.4 else false end from stat),
             'The other bids disagree by more than 40%, which usually means the scope is being read differently.'
    ) s
  )

  select case when (select n from stat) = 0
    then jsonb_build_object(
      'available', false,
      'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id,
      'basis', 'quotes from other suppliers on this enquiry',
      'population', 0,
      'note', 'no other supplier has priced this enquiry yet, so there is no market midpoint to '
              'recommend against. A figure taken from a different project of a different size '
              'would look identical on screen and mean nothing.')
    else jsonb_build_object(
      'available', true,
      'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id,
      'summary', (select summary from inq),
      'population', (select n from stat),
      'basis', 'the midpoint of every other supplier''s bid on this enquiry',

      -- The recommended price, with the spread it came from.
      'recommended_price', jsonb_build_object(
        'value', (select mid from stat), 'currency', 'AED',
        'p25', (select lo from stat), 'p75', (select hi from stat),
        'low', (select lowest from stat), 'high', (select highest from stat),
        'basis', 'median of ' || (select n from stat)::text || ' competing bid(s) on this enquiry'),

      -- Where that recommendation sits, and where this supplier usually sits.
      'market_position', jsonb_build_object(
        'verdict', 'at the market midpoint',
        'your_index', (select idx from habit),
        'your_quotes_measured', (select n from habit),
        'detail', case when (select idx from habit) is null
                  then 'You have not priced enough enquiries yet for us to know where you usually sit.'
                  when (select idx from habit) > 1.02
                  then 'You normally price about ' || round(((select idx from habit) - 1) * 100)::text
                       || '% above the middle of the market, so this suggestion is lower than your habit.'
                  when (select idx from habit) < 0.98
                  then 'You normally price about ' || round((1 - (select idx from habit)) * 100)::text
                       || '% below the middle of the market, so this suggestion is higher than your habit.'
                  else 'You normally price close to the middle of the market, in line with this suggestion.' end),

      -- Delivery, suggested from what the competition actually promised.
      'delivery_estimate', jsonb_build_object(
        'value', (select v from lead_pick),
        'agreed_by', (select c from lead_pick),
        'consensus', (select has_mode from lead_pick),
        'observed', (select coalesce(jsonb_agg(distinct lead_time), '[]'::jsonb) from bids where lead_time is not null),
        'basis', case when (select has_mode from lead_pick)
                 then 'the lead time most of the competing bids gave'
                 else 'no two bids gave the same lead time, so this is the middle of the range' end),

      -- Warranty, picked the same way and with the same honesty about disagreement.
      'warranty', jsonb_build_object(
        'value', (select v from warr_pick),
        'agreed_by', (select c from warr_pick),
        'consensus', (select has_mode from warr_pick),
        'observed', (select coalesce(jsonb_agg(distinct warranty), '[]'::jsonb) from bids where warranty is not null),
        'basis', case when (select has_mode from warr_pick)
                 then 'the warranty most of the competing bids offered'
                 else 'no two bids offered the same warranty, so this is the middle of the range' end),

      'payment_terms', jsonb_build_object(
        'value', (select v from terms_pick),
        'agreed_by', (select c from terms_pick),
        'consensus', (select has_mode from terms_pick),
        'basis', case when (select has_mode from terms_pick)
                 then 'the payment terms most of the competing bids asked for'
                 else 'no two bids asked for the same terms, so this is the middle of the range' end),

      -- ── RISK: A LEVEL, ITS REASONS, AND WHAT TO DO ABOUT IT ───────────────────────────────────
      -- The first version returned a level and its signals and stopped there, which leaves the
      -- supplier holding the word "high" and no next move. Every other figure on this screen is a
      -- proposal, and the risk should be one too: the routine names the single action that would
      -- most reduce it, drawn from the same signals rather than from a phrasebook.
      'risk_level', jsonb_build_object(
        'value', case when (select n from risk) >= 3 then 'high'
                      when (select n from risk) >= 1 then 'medium' else 'low' end,
        'count', (select n from risk),
        'signals', (select items from risk),
        'recommended_action', case
          when (select n from risk) = 0
            then 'Nothing is working against this quote. We suggest sending it as proposed.'
          when exists (select 1 from jsonb_array_elements((select items from risk)) e
                       where e->>'signal' in ('not_matchable', 'licence_expired', 'licence_missing'))
            then 'We suggest fixing your account before you send this: a quote from an account that '
                 || 'cannot be matched may never reach the customer, whatever price is on it.'
          when exists (select 1 from jsonb_array_elements((select items from risk)) e
                       where e->>'signal' = 'wide_spread')
            then 'We suggest asking the customer to confirm the scope before you commit to a price. '
                 || 'The other bids disagree enough that they are probably not all pricing the same job.'
          when exists (select 1 from jsonb_array_elements((select items from risk)) e
                       where e->>'signal' = 'brief_incomplete')
            then 'We suggest putting your assumptions in writing with this quote, so a change of '
                 || 'scope later is a variation rather than an argument.'
          else 'We suggest treating the suggested price as indicative until more suppliers have priced this.'
          end,
        'basis', 'six checked signals on your account, the brief and the shape of the competing bids'))
  end;
$function$;

comment on function public.fn_supplier_quote_recommend(bigint, uuid) is
  'Row #5 §11. Proposes a price, a delivery estimate, a warranty, payment terms, a market position '
  'and a risk level for one supplier on one enquiry, computed from the competing bids on that same '
  'enquiry. Returns available:false naming the empty population when nobody else has priced it. '
  'Demo and live rows are partitioned symmetrically.';
