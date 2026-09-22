-- PROBE: A SUPPLIER SEES ONLY THE JOBS IT WAS MATCHED TO — the database half of the supplier-portal
-- audit of 22 Sep 2026 (findings SP-N-02, SP-N-03, SP-N-05). Assigned: sales_engineer.
--
-- Pure probe: no DDL, nothing survives it. Run AFTER a_supplier_sees_only_the_jobs_it_was_matched_to.sql,
-- as ONE query THROUGH node scripts/qsql.mjs; never applied. `node scripts/apply_sql.mjs` on this file
-- prints "nothing to do" and exits 0 because it defines no routine — a silent pass, not a result. The
-- only run that means anything is the one that prints the verdict row. Every write happens inside a block that always
-- raises, so all of it is rolled back. The bidders are the reserved ZZ DEMO fixtures 129660 / 129676 /
-- 129775 and the reader is ZZ DEMO supplier 126512 on its own demo enquiry; no real party is touched and
-- nothing here can notify anybody (quotes rows queue nothing, and pg_net sends only committed rows).
--
-- VERDICT: PROBE OK only if
--   1. an enquiry with no inquiry_matches row for this supplier answers available=false, reason=not_found
--      — not 'forbidden', which would confirm the uuid names a real job;
--   2. with ONE competing bid the answer is available=false, reason=thin_market, and that bidder's exact
--      price appears NOWHERE in the payload (before this change it was the median, the p25, the p75, the
--      'low' and the 'high', five times over);
--   3. with THREE competing COMPANIES it recommends a band rounded to the nearest AED 1,000 and
--      carries no median, no percentile, no 'low', no 'high' and no 'observed' key — every one of
--      those is, or reconstructs, a figure a named competitor typed. NONE of the three bid amounts
--      (50000 / 61000 / 72000) may appear anywhere in the payload, and the first version of this probe
--      would have printed PROBE OK with all three of them recoverable, because it only looked for the
--      draft's 999999;
--   4. a DRAFT bid is not counted in the population, and three options from ONE company do not clear
--      the three-company floor;
--   4b. market_position.your_index is null below three measured enquiries — at three decimal places on
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
  r_nomatch jsonb; r_thin jsonb; r_ok jsonb; r_oneco jsonb; o_me jsonb; o_none jsonb; ws jsonb;
  leaked    int := 0; checked int := 0; names text[]; v_err text;
  q_before  bigint; q_after bigint; bids_in_payload int;
begin
  select count(*) into q_before from public.quotes;
  begin
    r_nomatch := public.fn_supplier_quote_recommend(me, nope);

    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status)
    values (gen_random_uuid(), inq, 129660, 50000, 'form', 9, 'submitted');
    r_thin := public.fn_supplier_quote_recommend(me, inq);

    -- THREE OPTIONS FROM ONE COMPANY ARE ONE COMPANY. count(*) would clear a three-bid floor here.
    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status) values
      (gen_random_uuid(), inq, 129660, 50500, 'form', 10, 'submitted'),
      (gen_random_uuid(), inq, 129660, 51000, 'form', 11, 'submitted');
    r_oneco := public.fn_supplier_quote_recommend(me, inq);
    delete from public.quotes where inquiry_id = inq and supplier_id = 129660 and option_no in (10, 11);

    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status) values
      (gen_random_uuid(), inq, 129676, 61000, 'form', 9, 'submitted'),
      (gen_random_uuid(), inq, 129775, 72000, 'form', 9, 'submitted'),
      (gen_random_uuid(), inq, 129660, 999999, 'form', 8, 'draft');   -- a draft is not a bid
    r_ok   := public.fn_supplier_quote_recommend(me, inq);
    o_me   := public.fn_supplier_opportunities(me);
    o_none := public.fn_supplier_opportunities(129660);
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
