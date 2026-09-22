-- A SUPPLIER SEES ONLY THE JOBS IT WAS MATCHED TO — and never a competitor's bid.
-- Seat: sales_engineer. Audit of 22 Sep 2026, findings SP-N-02 (P0), SP-N-03 (P0), SP-N-05 (P1).
--
-- WHAT WAS MEASURED, AND WHY EACH ONE IS A LEAK.
--
--   SP-N-02  fn_supplier_quote_recommend took (p_lead_id, p_inquiry_id) and asked NOTHING about whether
--            the two belong together, then returned, for that enquiry: the median of the other
--            suppliers' bids, their 25th and 75th percentiles, the LOWEST and HIGHEST bid on the board,
--            and `observed` — the distinct lead times and warranties those competitors had typed, word
--            for word. With one competing bid the median, the lowest and the highest are all that one
--            company's price: the routine handed a supplier its rival's quotation. It counted quotes in
--            EVERY status, so an abandoned draft moved the "market midpoint" a real supplier prices
--            against. And it read `summary` from public.inquiries, the raw row, so the customer's own
--            words reached the supplier around the inbox's scrubbers and around the reveal gate.
--
--   SP-N-03  fn_supplier_opportunities listed EVERY open enquiry in the estate, each with its
--            inquiry_id — its own reason line said "Outside your registered trade" — which is both a
--            disclosure and the supply of the uuid that made the submit_quote / extract_quote doors
--            reachable (fixed in supabase/functions/supplier_api/index.ts in the same change).
--            Matching is exact-trade or none (founder's rule, never a nearest mapping), so the list is
--            now the matcher's own output: the enquiries in public.inquiry_matches for this supplier.
--
--   SP-N-05  fn_supplier_workspaces titled each workspace with i.summary — the raw column — before the
--            reveal had been paid for. It now reads summary_masked and passes it through the same seed
--            scrub the inbox applies, and shows the unmasked summary only once this supplier has a
--            transactions row for that job (the definition supplier_api `inbox` already uses).
--
-- THE SEED SCRUB. public.mask_project_identity removes what a pattern can recognise. A customer's NAME
-- and a PROJECT's name are not patterns, which is why the supplier inbox carries a seed list
-- (_shared/anonymise.ts seedTerms: the buyer's name, e-mail, phone and the project name) and removes
-- those values wherever they appear. fn_supplier_safe_text is that idea in SQL, so these three routines
-- and the edge function cannot disagree about what a supplier may read. It is NOT a copy of the
-- TypeScript: it matches whole seed values of four characters or more, case-insensitively, and does not
-- do the token-level Arabic normalisation seedTerms does. The masked_* columns it is applied to have
-- already had contacts removed at write time, so this is the second layer, not the first.

-- ── The seed scrub ────────────────────────────────────────────────────────────────────────────────
-- SECURITY DEFINER because it reads public.customers to learn the seeds; a caller who could not read
-- that table would otherwise get their text back with nothing removed, which is a fail-OPEN. EXECUTE is
-- revoked from PUBLIC, anon and authenticated below: only the routines here, which run as the owner,
-- call it.
create or replace function public.fn_supplier_safe_text(p_inquiry uuid, p_text text)
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_out   text := p_text;
  v_seeds text[];
  v_seed  text;
begin
  if p_text is null or btrim(p_text) = '' then return p_text; end if;

  select array_remove(array[
           nullif(btrim(c.full_name), ''),
           nullif(btrim(c.email), ''),
           nullif(btrim(c.phone), ''),
           nullif(btrim(pr.name), '')
         ], null)
    into v_seeds
    from public.inquiries i
    left join public.customers c on c.id = i.customer_id
    left join public.projects  pr on pr.id = i.project_id
   where i.id = p_inquiry;

  foreach v_seed in array coalesce(v_seeds, array[]::text[]) loop
    -- Four characters is the floor _shared/anonymise.ts uses: below it a "seed" is a fragment that
    -- would mangle ordinary trade words rather than hide anybody.
    if length(v_seed) >= 4 then
      v_out := regexp_replace(v_out, regexp_replace(v_seed, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'), '[hidden]', 'gi');
    end if;
  end loop;

  return public.mask_project_identity(v_out);
end $fn$;

revoke execute on function public.fn_supplier_safe_text(uuid, text) from public;
revoke execute on function public.fn_supplier_safe_text(uuid, text) from anon;
revoke execute on function public.fn_supplier_safe_text(uuid, text) from authenticated;
comment on function public.fn_supplier_safe_text(uuid, text) is
  'The seed scrub of _shared/anonymise.ts in SQL: removes this inquiry''s customer name, e-mail, phone and project name (>= 4 chars, case-insensitive) and then mask_project_identity. Used by the supplier-facing fn_supplier_* routines so they cannot disagree with the inbox about what a supplier may read. Audit 22 Sep 2026, SP-N-02 / SP-N-05.';

-- ── SP-N-02: the recommender never shows a competitor's quotation ─────────────────────────────────
create or replace function public.fn_supplier_quote_recommend(p_lead_id bigint, p_inquiry_id uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),
  -- THE MATCH IS THE PERMISSION. Without a row here this enquiry does not exist for this supplier,
  -- and nothing below is computed for them.
  matched as (
    select exists (select 1 from public.inquiry_matches m
                    where m.inquiry_id = p_inquiry_id and m.supplier_id = p_lead_id) as ok
  ),
  inq as (select * from public.inquiries_supplier_safe where id = p_inquiry_id),

  -- The competing bids. A DRAFT IS NOT A BID: a quote that was never sent to the customer is a figure
  -- somebody was still typing, and counting it moved the midpoint a real supplier prices against.
  bids as (
    select q.supplier_id, q.quote_amount amt, q.lead_time, q.warranty, q.payment_terms
    from public.quotes q, flag, matched
    where matched.ok
      and q.inquiry_id = p_inquiry_id
      and q.supplier_id is distinct from p_lead_id
      and q.status in ('submitted', 'revealed')
      and q.quote_amount is not null and q.quote_amount > 0
      and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  -- n IS A COUNT OF COMPANIES, not of rows (review of #854). count(*) let ONE rival submitting three
  -- priced options clear a three-bid floor by itself, and the median of those three is that rival's
  -- middle option. lowest and highest are computed for the wide_spread signal only; neither, and no
  -- percentile, ever leaves this routine.
  stat as (
    select count(distinct supplier_id) n,
           count(*) n_rows,
           percentile_cont(0.5) within group (order by amt) mid_raw,
           min(amt) lowest, max(amt) highest
    from bids
  ),
  -- THE BRACKET, AND WHY A BRACKET RATHER THAN A FIGURE (review of #854, and one correction on top).
  --
  -- The first version published the median with its p25 and p75. For three sorted bids a < b < c that
  -- is p25 = (a+b)/2 and p75 = (b+c)/2, so a = 2*p25 - median and c = 2*p75 - median: all three bids
  -- recovered to the fils out of the very payload whose comment promised none of them. An ODD
  -- population also makes the median itself one company's exact number, so no raw statistic can carry
  -- the guarantee at all.
  --
  -- Rounding the median was the next attempt and it failed on its own probe: the fixtures
  -- 50000 / 61000 / 72000 have a median of 61000, which is already a multiple of a thousand, so
  -- "rounded to the nearest AED 1,000" published bid b unchanged. A SYMMETRIC band fails the same way
  -- for the same reason — its own midpoint is the number it was meant to hide.
  --
  -- What leaves this routine is therefore the BRACKET the midpoint falls in: [floor(mid/step)*step,
  -- +step), step being half an order of magnitude and never less than AED 1,000 (AED 5,000 wide around
  -- 61,000; AED 50,000 wide around 610,000). A bracket has no centre to invert and states only that
  -- the middle of the market is somewhere inside it.
  --
  -- THE GUARANTEE, STATED AS IT ACTUALLY HOLDS: this routine publishes no statistic of the competing
  -- bids finer than one bracket. It does not promise that no bid EQUALS a bracket edge — a rival whose
  -- price happens to be exactly AED 60,000 shares that number with the edge by coincidence, and
  -- nothing in the payload says which.
  band as (
    select lo, lo + step as hi, step
    from (select floor(mid_raw / step) * step as lo, step
            from (select mid_raw, greatest(1000, power(10, floor(log(mid_raw)))::numeric / 2) as step
                    from stat) q) b
  ),

  -- The supplier's own habit, measured rather than assumed: across every enquiry they have priced,
  -- where did they sit against the midpoint of that enquiry's other bids? An index of 1.04 means
  -- this company prices 4% above the middle of the market, and it is computed from their own rows.
  -- ITS OWN FLOOR, AND THE SAME STATUS RULE (review of #854). This index was the leak the headline
  -- figure no longer is: idx = avg(my price / the median of the others') to three decimal places, with
  -- your_quotes_measured naming the denominator, so on a single measured enquiry a supplier could
  -- recover that median to about a tenth of a percent. It is now computed ONLY over enquiries where at
  -- least three OTHER COMPANIES submitted, rounded to two places, and published only when three or
  -- more enquiries went into it. The supplier's own drafts are excluded too: the outer query had no
  -- status filter at all, which contradicted this file's own rule that a draft is not a bid.
  habit as (
    select round(avg(ratio)::numeric, 2) idx, count(*) n
    from (
      select q.quote_amount / nullif((
               select percentile_cont(0.5) within group (order by o.quote_amount)
               from public.quotes o
               where o.inquiry_id = q.inquiry_id and o.supplier_id is distinct from q.supplier_id
                 and o.status in ('submitted', 'revealed') and o.quote_amount > 0
                 and (select count(distinct o2.supplier_id) from public.quotes o2
                       where o2.inquiry_id = q.inquiry_id and o2.supplier_id is distinct from q.supplier_id
                         and o2.status in ('submitted', 'revealed') and o2.quote_amount > 0) >= 3), 0) as ratio
      from public.quotes q, flag
      where q.supplier_id = p_lead_id and q.quote_amount > 0
        and q.status in ('submitted', 'revealed')
        and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
    ) r where r.ratio is not null
  ),
  habit_out as (select case when n >= 3 then idx else null end idx, n from habit),

  -- ── DELIVERY, WARRANTY AND TERMS ARE TEXT, SO THEY ARE PICKED, NOT AVERAGED ───────────────────
  -- The average of "8-10 weeks" and "12-14 weeks" is not a promise anybody made.
  --
  -- WHAT THIS RETURNS AND WHAT IT NO LONGER RETURNS (22 Sep 2026, SP-N-02). It used to return
  -- `observed` — the distinct lead times and warranties every competitor had typed — and, when no two
  -- bids agreed, "the middle of the range", which is one named competitor's exact promise. A value
  -- only two or more suppliers independently gave is a market norm and may be suggested; anything
  -- else is a rival's answer and is now withheld, with `consensus` false saying so.
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
    select kind, v, c from (
      select r.kind, r.v, r.c,
             row_number() over (partition by r.kind order by r.c desc, r.ord) rn
      from ranked r
      where r.c >= 2
    ) z where z.rn = 1
  ),
  lead_pick  as (select v, c from picked where kind = 'lead'),
  warr_pick  as (select v, c from picked where kind = 'warranty'),
  terms_pick as (select v, c from picked where kind = 'terms'),

  -- ── RISK, AS NAMED SIGNALS RATHER THAN A MOOD ─────────────────────────────────────────────────
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
      -- The spread is computed here and the BOOLEAN leaves the routine; the two bids it is computed
      -- from never do.
      select 'wide_spread',
             (select case when mid_raw > 0 then (highest - lowest) / mid_raw > 0.4 else false end from stat),
             'The other bids disagree by more than 40%, which usually means the scope is being read differently.'
    ) s
  )

  select case
    when not (select ok from matched)
      -- Not 'forbidden': a job this supplier was not matched to must not be confirmed to exist.
      then jsonb_build_object(
        'available', false, 'reason', 'not_found',
        'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id,
        'note', 'this enquiry is not one of yours')
    when (select n from stat) < 3
      -- THE THIN-MARKET FLOOR. With one competing company the midpoint IS its bid; with two, the pair
      -- brackets it. Three separate COMPANIES is the smallest population from which a rounded band
      -- describes a market rather than a named rival's quotation.
      then jsonb_build_object(
        'available', false, 'reason', 'thin_market',
        'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id,
        'basis', 'quotes submitted by other suppliers on this enquiry',
        'population', (select n from stat),
        'note', 'fewer than three other companies have submitted a price for this enquiry, so there is '
                'no market midpoint to recommend against. With one or two, any figure we showed you '
                'would be their quotation, which is theirs and not ours to share.')
    else jsonb_build_object(
      'available', true,
      'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id,
      -- The supplier-safe projection, scrubbed again: the raw inquiries.summary used to be read here,
      -- which walked around the inbox entirely (SP-N-02).
      'summary', public.fn_supplier_safe_text(p_inquiry_id, (select summary from inq)),
      'population', (select n from stat),
      'basis', 'the bracket the midpoint of every other company''s submitted bid on this enquiry falls in',

      -- The recommendation, as the bracket the market midpoint falls in. No median, no percentile, no
      -- lowest and no highest: every one of those is, or reconstructs, a figure a named competitor
      -- typed. `value` is the bottom of the bracket, because the portal's one-click accept has to send
      -- a number and that number must be one the routine derived from a bracket, not from a bid.
      'recommended_price', jsonb_build_object(
        'value', (select lo from band), 'currency', 'AED',
        'range_low', (select lo from band), 'range_high', (select hi from band),
        'bracket', (select step from band),
        'basis', 'the AED ' || (select step from band)::text || ' bracket the middle of '
                 || (select n from stat)::text || ' competing companies'' bids falls in'),

      -- Where that recommendation sits, and where this supplier usually sits.
      'market_position', jsonb_build_object(
        'verdict', 'at the market midpoint',
        'your_index', (select idx from habit_out),
        'your_quotes_measured', (select n from habit_out),
        'detail', case when (select idx from habit_out) is null
                  then 'You have not priced enough enquiries yet for us to know where you usually sit.'
                  when (select idx from habit_out) > 1.02
                  then 'You normally price about ' || round(((select idx from habit_out) - 1) * 100)::text
                       || '% above the middle of the market, so this suggestion is lower than your habit.'
                  when (select idx from habit_out) < 0.98
                  then 'You normally price about ' || round((1 - (select idx from habit_out)) * 100)::text
                       || '% below the middle of the market, so this suggestion is higher than your habit.'
                  else 'You normally price close to the middle of the market, in line with this suggestion.' end),

      'delivery_estimate', jsonb_build_object(
        'value', (select v from lead_pick),
        'agreed_by', (select c from lead_pick),
        'consensus', (select count(*) from lead_pick) > 0,
        'basis', case when (select count(*) from lead_pick) > 0
                 then 'the lead time two or more of the competing bids gave'
                 else 'no two bids gave the same lead time, so there is no norm to suggest' end),

      'warranty', jsonb_build_object(
        'value', (select v from warr_pick),
        'agreed_by', (select c from warr_pick),
        'consensus', (select count(*) from warr_pick) > 0,
        'basis', case when (select count(*) from warr_pick) > 0
                 then 'the warranty two or more of the competing bids offered'
                 else 'no two bids offered the same warranty, so there is no norm to suggest' end),

      'payment_terms', jsonb_build_object(
        'value', (select v from terms_pick),
        'agreed_by', (select c from terms_pick),
        'consensus', (select count(*) from terms_pick) > 0,
        'basis', case when (select count(*) from terms_pick) > 0
                 then 'the payment terms two or more of the competing bids asked for'
                 else 'no two bids asked for the same terms, so there is no norm to suggest' end),

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
        'basis', 'five checked signals on your account, the brief and the shape of the competing bids'))
  end;
$function$;

comment on function public.fn_supplier_quote_recommend(bigint, uuid) is
  'The quote builder''s proposal for ONE enquiry this supplier was matched to. Reads only bids in status submitted/revealed, refuses below three competing COMPANIES, publishes the bracket the midpoint falls in rather than a median or a percentile (three sorted bids are fully recoverable from median + p25 + p75, and an odd-population median IS one company''s bid), never returns the lowest, highest or verbatim observed terms, and reads the summary through inquiries_supplier_safe + fn_supplier_safe_text. Audit 22 Sep 2026, SP-N-02.';

-- ── SP-N-03: the opportunities list is the matcher's output, not the estate's ──────────────────────
create or replace function public.fn_supplier_opportunities(p_lead_id bigint)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with me as (
    select l.id, lower(coalesce(l.sector, '')) sector, l.emirate,
           coalesce(l.service_emirates, '{}'::text[]) service_emirates,
           lower(coalesce(l.capability_summary, l.services, l.description, '')) capability,
           l.verified
      from public.leads l where l.id = p_lead_id
  ),
  -- ONLY THE ENQUIRIES WE SENT THIS SUPPLIER. Until 22 Sep this read every open row in
  -- public.inquiries and handed back each one's inquiry_id with a reason line that could read
  -- "Outside your registered trade" — the list itself said the job was not theirs. Matching is exact
  -- trade or none (the founder's rule: never a nearest mapping), so public.inquiry_matches IS the
  -- answer to "what may this supplier quote for", and asking anything else invents a second matcher.
  cand as (
    select i.id, i.category, i.emirate, i.summary_masked as summary, i.scope_type, i.created_at, i.budget_masked as budget,
           nullif(btrim(coalesce(i.raw_input_masked, '')), '') requirement,
           lower(coalesce(i.category, '')) cat
      from public.inquiries i
     where coalesce(i.status, 'open') = 'open'
       and exists (select 1 from public.inquiry_matches m
                    where m.inquiry_id = i.id and m.supplier_id = p_lead_id)
  ),
  scored as (
    select c.*,
      (c.cat = me.sector and me.sector <> '')                                    as trade_hit,
      (c.emirate is not null and (c.emirate = me.emirate
        or c.emirate = any(me.service_emirates)))                                as location_hit,
      (me.capability <> '')                                                      as capacity_known,
      (me.capability <> '' and c.cat <> '' and position(c.cat in me.capability) > 0) as capacity_hit,
      (select count(*) from public.quotes q
         join public.inquiries qi on qi.id = q.inquiry_id
        where q.supplier_id = p_lead_id and lower(coalesce(qi.category,'')) = c.cat) as similar_jobs
      from cand c cross join me
  ),
  ranked as (
    select s.*,
      round(100.0 * (
        (case when s.trade_hit then 40 else 0 end)
      + (case when s.location_hit then 30 else 0 end)
      + (case when s.capacity_known and s.capacity_hit then 30 else 0 end)
      ) / nullif(40 + 30 + (case when s.capacity_known then 30 else 0 end), 0)) as fit_score
      from scored s
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'count', (select count(*) from ranked),
    'ordered_by', 'fit_score desc — a ranked list, never chronological',
    -- The population is the supplier's OWN matches. The estate-wide count of open enquiries used to be
    -- published here, which told every supplier how much work it was not being shown.
    'population', jsonb_build_object(
      'matched_to_me', (select count(*) from public.inquiry_matches where supplier_id = p_lead_id),
      'open_for_me', (select count(*) from cand),
      'my_quotes', (select count(*) from public.quotes where supplier_id = p_lead_id)
    ),
    'note', case when (select count(*) from ranked) = 0
                 then 'no open opportunities yet — nothing has been matched to you'
                 else null end,
    'opportunities', coalesce((
      select jsonb_agg(x order by x->>'fit_score' desc) from (
        select jsonb_build_object(
          'inquiry_id', r.id,
          -- The masked columns, through the same seed scrub the inbox applies (SP-F-04's rule: the
          -- customer's project name is not a pattern anything can recognise).
          'project_title', coalesce(nullif(btrim(coalesce(public.fn_supplier_safe_text(r.id, r.summary), '')), ''), r.category, 'Untitled project'),
          'category', r.category,
          'emirate', r.emirate,
          'requirement', public.fn_supplier_safe_text(r.id, r.requirement),
          'estimated_value', public.fn_supplier_safe_text(r.id, r.budget),
          'fit_score', r.fit_score,
          'match_pct', r.fit_score,
          'reasons', jsonb_build_array(
            jsonb_build_object(
              'key', 'trade',
              'applies', r.trade_hit,
              'text', case when r.trade_hit
                           then 'This is your trade — ' || coalesce(r.category,'the same category')
                           else 'Matched to you on capability rather than on your registered sector' end),
            jsonb_build_object(
              'key', 'location',
              'applies', r.location_hit,
              'text', case when r.location_hit
                           then 'Nearby location — ' || coalesce(r.emirate,'your service area')
                           else 'Outside the emirates you serve' end),
            jsonb_build_object(
              'key', 'capacity',
              'applies', r.capacity_known and r.capacity_hit,
              'available', r.capacity_known,
              'text', case when not r.capacity_known
                           then 'Your capacity fits: not assessable — you have not described your capability yet'
                           when r.capacity_hit
                           then 'Your capacity fits — you list this work in your capability'
                           else 'Not in your described capability' end),
            jsonb_build_object(
              'key', 'history',
              'applies', r.similar_jobs > 0,
              'available', (select count(*) from public.quotes where supplier_id = p_lead_id) > 0,
              'similar_jobs', r.similar_jobs,
              'text', case when (select count(*) from public.quotes where supplier_id = p_lead_id) = 0
                           then 'Previous similar project: you have not quoted on QuotesDone yet'
                           when r.similar_jobs > 0
                           then 'You worked on ' || r.similar_jobs || ' previous similar project(s)'
                           else 'No previous similar project on record' end)
          )
        ) x from ranked r
      ) s
    ), '[]'::jsonb)
  )
$function$;

comment on function public.fn_supplier_opportunities(bigint) is
  'The open enquiries THIS supplier was matched to (public.inquiry_matches), ranked by fit. Until 22 Sep 2026 it listed every open enquiry in the estate with its uuid. Customer text comes from the masked columns through fn_supplier_safe_text. Audit 22 Sep 2026, SP-N-03.';

-- ── SP-N-05: a workspace is titled with what the supplier is allowed to read ──────────────────────
create or replace function public.fn_supplier_workspaces(p_lead_id bigint)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with rel as (
    select distinct i.id as inquiry_id
    from public.inquiries i
    where exists (select 1 from public.inquiry_matches m
                  where m.inquiry_id = i.id and m.supplier_id = p_lead_id)
       or exists (select 1 from public.messages g
                  where g.inquiry_id = i.id and g.supplier_id = p_lead_id)
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'count', (select count(*) from rel),
    -- MATCHED TO ME, and nothing about the estate (review of #854: the same estate-wide count that was
    -- removed from fn_supplier_opportunities was still published here).
    'population', jsonb_build_object(
      'matches_for_me', (select count(*) from public.inquiry_matches where supplier_id = p_lead_id),
      'messaged_me', (select count(distinct inquiry_id) from public.messages where supplier_id = p_lead_id)
    ),
    'note', case when (select count(*) from rel) = 0
                 then 'no customer relationships yet — nothing has been matched or messaged'
                 else null end,
    'workspaces', (
      select coalesce(jsonb_agg(w order by w->>'last_activity' desc nulls last), '[]'::jsonb)
      from (
        select jsonb_build_object(
          'inquiry_id', i.id,
          'project', jsonb_build_object(
            -- THE TITLE IS A CUSTOMER'S OWN SENTENCE (22 Sep 2026, SP-N-05). It used to be i.summary,
            -- the raw column, printed at the top of the workspace before the reveal was paid for —
            -- the one place in the portal that read around the masking and the reveal gate at once.
            -- Post-reveal this supplier has paid for the customer's identity, so the unmasked summary
            -- is theirs to read; before it, the masked column through the inbox's seed scrub.
            'title', case when exists (select 1 from public.transactions t
                                        where t.inquiry_id = i.id and t.supplier_id = p_lead_id)
                          then coalesce(nullif(btrim(coalesce(i.summary, '')), ''), i.category,
                                        'RFQ ' || coalesce(i.rfq_no::text, i.id::text))
                          else coalesce(nullif(btrim(coalesce(public.fn_supplier_safe_text(i.id, i.summary_masked), '')), ''), i.category,
                                        'RFQ ' || coalesce(i.rfq_no::text, i.id::text)) end,
            'category', i.category,
            'emirate', i.emirate,
            'status', i.status,
            'created_at', i.created_at
          ),
          'files', (
            select coalesce(jsonb_agg(jsonb_build_object(
              'name', d.file_name, 'kind', d.kind, 'created_at', d.created_at,
              'category', case
                when d.kind ~* 'drawing|dwg|plan|layout'        then 'drawings'
                when d.kind ~* 'spec|datasheet|boq|schedule'    then 'specifications'
                when d.kind ~* 'contract|agreement|po|purchase' then 'contracts'
                else 'other' end
            ) order by d.created_at desc), '[]'::jsonb)
            from public.documents d
            where d.ref_table = 'inquiries' and d.ref_id = i.id::text
          ),
          'file_categories', (
            select jsonb_build_object(
              'drawings', count(*) filter (where d.kind ~* 'drawing|dwg|plan|layout'),
              'specifications', count(*) filter (where d.kind ~* 'spec|datasheet|boq|schedule'),
              'contracts', count(*) filter (where d.kind ~* 'contract|agreement|po|purchase'),
              'other', count(*) filter (where d.kind !~* 'drawing|dwg|plan|layout|spec|datasheet|boq|schedule|contract|agreement|po|purchase')
            )
            from public.documents d
            where d.ref_table = 'inquiries' and d.ref_id = i.id::text
          ),
          'message_count', (
            select count(*) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id and not coalesce(g.blocked, false)
          ),
          'unread', (
            select count(*) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id
              and g.sender = 'customer' and not coalesce(g.read_by_supplier, false)
              and not coalesce(g.blocked, false)
          ),
          'last_activity', (
            select max(g.created_at) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id
          ),
          'timeline', (
            select jsonb_build_object(
              'pct', case when total = 0 then null else round(100.0 * hit / total) end,
              'stages', jsonb_build_object(
                'matched', matched, 'messaged', messaged, 'quoted', quoted, 'awarded', awarded)
            )
            from (
              select 4 as total,
                (exists (select 1 from public.inquiry_matches m where m.inquiry_id = i.id and m.supplier_id = p_lead_id))::int
                  as matched,
                (exists (select 1 from public.messages g where g.inquiry_id = i.id and g.supplier_id = p_lead_id))::int
                  as messaged,
                (exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = p_lead_id))::int
                  as quoted,
                (exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = p_lead_id
                         and q.status = 'won'))::int as awarded
            ) s, lateral (select (s.matched + s.messaged + s.quoted + s.awarded) as hit) h
          )
        ) as w
        from rel r join public.inquiries i on i.id = r.inquiry_id
      ) t
    )
  );
$function$;

comment on function public.fn_supplier_workspaces(bigint) is
  'A supplier''s customer relationships. The workspace title is the masked summary through fn_supplier_safe_text before the reveal is paid for, and the raw summary after. Audit 22 Sep 2026, SP-N-05.';
