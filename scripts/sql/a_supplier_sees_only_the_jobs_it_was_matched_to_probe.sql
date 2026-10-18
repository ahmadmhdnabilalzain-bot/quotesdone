-- PROBE: A SUPPLIER SEES ONLY THE JOBS IT WAS MATCHED TO — the database half of the supplier-portal
-- audit of 22 Sep 2026 (findings SP-N-02, SP-N-03, SP-N-05). Assigned: sales_engineer.
--
-- Pure probe: no DDL, nothing survives it. Run AFTER a_supplier_sees_only_the_jobs_it_was_matched_to.sql,
-- as ONE query THROUGH node scripts/qsql.mjs; never applied. `node scripts/apply_sql.mjs` on this file
-- prints "nothing to do" and exits 0 because it defines no routine — a silent pass, not a result. The
-- only run that means anything is the one that prints the verdict row.
--
-- THE BIDDERS ARE DEMO LEADS BECAUSE THE ESTATE SAYS SO. public.a01_quote_demo_and_real_never_pair
-- (fn_demo_and_real_never_pair) refuses a quote whose supplier and inquiry disagree about being demo,
-- so a probe bidding on a ZZ DEMO enquiry must use leads with leads.is_demo = true. Since the outcome audit of
-- 30 Sep 2026 the three bidders are CHOSEN AT RUN TIME (the three lowest-id is_demo 'ZZ DEMO%' demo_factory
-- leads other than the reader): the hard-coded 130027 had left the demo pool and a01 refused the set-up, so the
-- property went unproven. Reader 126512 and the enquiry are asserted demo before any write. Every write happens
-- inside a block that always raises, so all of it is rolled back; no real party is touched and nothing here can
-- notify anybody (quotes rows queue nothing, and pg_net sends only committed rows). Bids are sent through the
-- quote QC gate (z40) and released as its 24 h clock would, since a held draft is not a bid.
--
-- VERDICT: PROBE OK only if
--   1. an enquiry with no inquiry_matches row for this supplier answers available=false, reason=not_found
--      — not 'forbidden', which would confirm the uuid names a real job;
--   2. with ONE competing bid the answer is available=false, reason=thin_market, and that bidder's exact
--      price appears NOWHERE in the payload (before this change it was the median, the p25, the p75, the
--      'low' and the 'high', five times over);
--   3. with THREE competing COMPANIES it recommends the MIDDLE of the bracket the midpoint falls in and
--      carries no median, no percentile, no 'low', no 'high' and no 'observed' key — every one of
--      those is, or reconstructs, a figure a named competitor typed. NONE of the three bid amounts
--      (50000 / 61000 / 72000) may appear anywhere in the payload, and the first version of this probe
--      would have printed PROBE OK with all three of them recoverable, because it only looked for the
--      draft's 999999. The published figure is the bracket's middle, never its bottom edge, which was
--      up to a whole step low and made the one-click accept under-bid;
--   4. a DRAFT bid is not counted in the population, and three options from ONE company do not clear
--      the three-company floor;
--   4b. market_position.your_index is null below three measured enquiries, and rounded to ONE decimal
--      place with your_quotes_measured as a BAND above it: exact values let a supplier difference one
--      enquiry against the next and recover a median to ~3.5%, finer than a bracket. At three decimals on
--      one enquiry it recovered the others' median to a tenth of a percent;
--   5. fn_supplier_opportunities reports only this supplier's own matches and publishes no estate-wide
--      count of open enquiries; a supplier matched to nothing gets nothing;
--   6. no customer name behind a workspace this supplier has NOT paid to reveal appears in the
--      fn_supplier_workspaces payload.
--
-- MEASURED 22 Sep 2026, before the fix, against the same rows: 3 quotes in the estate and every priced
-- enquiry carried 1-2 bids, so every call this routine could serve returned a single rival's quotation.
create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  me        bigint := 126512;
  inq       uuid   := 'd958e1ea-54f4-45a1-9214-d622ac52dce1';
  nope      uuid   := '00000000-0000-0000-0000-000000000001';
  b         bigint[];   -- three ZZ DEMO bidders, chosen at run time (outcome audit 30 Sep 2026)
  qs        uuid[];
  r_nomatch jsonb; r_thin jsonb; r_ok jsonb; r_oneco jsonb; o_me jsonb; o_none jsonb; ws jsonb;
  leaked    int := 0; checked int := 0; names text[]; v_err text;
  q_before  bigint; q_after bigint; bids_in_payload int;
begin
  select count(*) into q_before from public.quotes;
  begin
    -- ALL ZZ DEMO, never a hard-coded id: the first version named 130027, which has since left the demo pool,
    -- and a01 (demo and real never pair) refused the set-up, so the property went unproven. The reader and the
    -- enquiry must be demo too, or nothing below runs.
    select array_agg(id order by id) into b
      from (select l.id from public.leads l
             where l.is_demo and l.company_name ilike 'ZZ DEMO%' and l.source = 'demo_factory' and l.id <> me
               -- b[1] must be matched to nothing (o_none asserts count 0), and no bidder may already bid here
               and not exists (select 1 from public.inquiry_matches m where m.supplier_id = l.id)
               and not exists (select 1 from public.quotes q where q.supplier_id = l.id and q.inquiry_id = inq)
             order by l.id limit 3) x;
    if coalesce(array_length(b, 1), 0) < 3 or not public.fn_inquiry_is_demo(inq)
       or not exists (select 1 from public.leads where id = me and is_demo and company_name ilike 'ZZ DEMO%') then
      raise exception 'fixture: ZZ DEMO bidders=%, enquiry demo=%, reader demo=%', coalesce(array_length(b, 1), 0),
        public.fn_inquiry_is_demo(inq), exists (select 1 from public.leads where id = me and is_demo);
    end if;

    r_nomatch := public.fn_supplier_quote_recommend(me, nope);

    -- A bid is SENT the way the estate sends it: z40 (the quote QC gate) holds a figure-only fixture as a draft,
    -- and the probe releases it as its 24 h clock would ('waited_24h'), then submits it again.
    qs := array[gen_random_uuid()];
    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status)
    values (qs[1], inq, b[1], 50000, 'form', 9, 'draft');
    update public.quotes set status = 'submitted' where id = any(qs);
    update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = any(qs) and released_at is null;
    update public.quotes set status = 'submitted' where id = any(qs);
    r_thin := public.fn_supplier_quote_recommend(me, inq);

    -- THREE OPTIONS FROM ONE COMPANY ARE ONE COMPANY. count(*) would clear a three-bid floor here.
    qs := array[gen_random_uuid(), gen_random_uuid()];
    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status) values
      (qs[1], inq, b[1], 50500, 'form', 10, 'draft'),
      (qs[2], inq, b[1], 51000, 'form', 11, 'draft');
    update public.quotes set status = 'submitted' where id = any(qs);
    update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = any(qs) and released_at is null;
    update public.quotes set status = 'submitted' where id = any(qs);
    r_oneco := public.fn_supplier_quote_recommend(me, inq);
    delete from public.quotes where id = any(qs);

    qs := array[gen_random_uuid(), gen_random_uuid()];
    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status) values
      (qs[1], inq, b[2], 61000, 'form', 9, 'draft'),
      (qs[2], inq, b[3], 72000, 'form', 9, 'draft'),
      (gen_random_uuid(), inq, b[1], 999999, 'form', 8, 'draft');   -- a draft is not a bid
    update public.quotes set status = 'submitted' where id = any(qs);
    update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = any(qs) and released_at is null;
    update public.quotes set status = 'submitted' where id = any(qs);
    r_ok   := public.fn_supplier_quote_recommend(me, inq);
    o_me   := public.fn_supplier_opportunities(me);
    o_none := public.fn_supplier_opportunities(b[1]);
    ws     := public.fn_supplier_workspaces(me);

    -- EVERY BID AMOUNT, looked for in the payload as a bare substring. The guarantee the file states is
    -- "no figure any supplier typed is reproduced", so this is the assertion that guarantee needs.
    select count(*) into bids_in_payload
      from unnest(array['50000', '61000', '72000', '999999']) x
     where position(x in r_ok::text) > 0;

    select array_agg(distinct c.full_name) into names
      from public.inquiry_matches m
      join public.inquiries i on i.id = m.inquiry_id
      join public.customers c on c.id = i.customer_id
     where m.supplier_id = me and coalesce(btrim(c.full_name), '') <> ''
       and not exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.supplier_id = me);
    checked := coalesce(array_length(names, 1), 0);
    if checked > 0 then select count(*) into leaked from unnest(names) n where position(n in ws::text) > 0; end if;

    raise exception 'ZZPROBE rollback';
  exception when others then
    v_err := sqlerrm;
  end;
  -- AFTER the subtransaction rolled back: the estate must hold exactly what it held before.
  select count(*) into q_after from public.quotes;
  insert into zz_probe_verdict
  select case when v_err = 'ZZPROBE rollback'
                   and r_nomatch->>'available' = 'false' and r_nomatch->>'reason' = 'not_found'
                   and r_thin->>'available' = 'false' and r_thin->>'reason' = 'thin_market'
                   and (r_thin->>'population')::int = 1 and position('50000' in r_thin::text) = 0
                   and r_oneco->>'available' = 'false' and r_oneco->>'reason' = 'thin_market'
                   and r_ok->>'available' = 'true' and (r_ok->>'population')::int = 3
                   and (r_ok#>>'{recommended_price,range_low}')::numeric = 60000 and (r_ok#>>'{recommended_price,range_high}')::numeric = 65000
                   and (r_ok#>>'{recommended_price,value}')::numeric = 62500
                   and r_ok#>>'{market_position,verdict}' not like '%at the market midpoint%'
                   and (r_ok#>>'{recommended_price,value}')::numeric = 62500
                   and r_ok#>>'{market_position,verdict}' not like '%at the market midpoint%'
                   and r_ok#>'{recommended_price,low}' is null and r_ok#>'{recommended_price,high}' is null
                   and r_ok#>'{recommended_price,p25}' is null and r_ok#>'{recommended_price,p75}' is null
                   and r_ok#>'{delivery_estimate,observed}' is null
                   and bids_in_payload = 0
                   and r_ok#>>'{market_position,your_index}' is null
                   and (o_me#>>'{population,matched_to_me}')::int = 3
                   and o_me#>'{population,open_inquiries}' is null
                   and (o_none->>'count')::int = 0 and (o_none#>>'{population,matched_to_me}')::int = 0
                   and leaked = 0 and q_after = q_before
              then 'PROBE OK' else 'PROBE FAILED' end,
         format('no_match=%s/%s; one_rival=%s/%s pop=%s rival_price_in_payload=%s; one_company_three_options=%s/%s pop=%s; '
                || 'three_companies=%s pop=%s band=%s (%s..%s) low=%s high=%s p25=%s p75=%s observed=%s bid_amounts_in_payload=%s your_index=%s; '
                || 'opportunities_me count=%s matched=%s estate_open_key=%s; opportunities_unmatched count=%s matched=%s; '
                || 'workspaces count=%s estate_inquiries_key=%s names_checked=%s leaked=%s; quotes before=%s after=%s; block ended with: %s',
                r_nomatch->>'available', r_nomatch->>'reason',
                r_thin->>'available', r_thin->>'reason', r_thin->>'population', position('50000' in r_thin::text) > 0,
                r_oneco->>'available', r_oneco->>'reason', r_oneco->>'population',
                r_ok->>'available', r_ok->>'population', r_ok#>>'{recommended_price,value}',
                r_ok#>>'{recommended_price,range_low}', r_ok#>>'{recommended_price,range_high}',
                r_ok#>'{recommended_price,low}' is not null, r_ok#>'{recommended_price,high}' is not null,
                r_ok#>'{recommended_price,p25}' is not null, r_ok#>'{recommended_price,p75}' is not null,
                r_ok#>'{delivery_estimate,observed}' is not null, bids_in_payload, r_ok#>>'{market_position,your_index}',
                o_me->>'count', o_me#>>'{population,matched_to_me}', o_me#>'{population,open_inquiries}' is not null,
                o_none->>'count', o_none#>>'{population,matched_to_me}',
                ws->>'count', ws#>'{population,inquiries}' is not null, checked, leaked, q_before, q_after, v_err);
end $probe$;
select * from zz_probe_verdict;
