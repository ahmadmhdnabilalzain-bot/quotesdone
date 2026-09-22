-- PROBE: A SUPPLIER SEES ONLY THE JOBS IT WAS MATCHED TO — the database half of the supplier-portal
-- audit of 22 Sep 2026 (findings SP-N-02, SP-N-03, SP-N-05). Assigned: sales_engineer.
--
-- Pure probe: no DDL, nothing survives it. Run AFTER a_supplier_sees_only_the_jobs_it_was_matched_to.sql,
-- as ONE query through the Management API; never applied. Every write happens inside a block that always
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
--   3. with THREE competing bids it recommends the median, and carries no 'low', no 'high' and no
--      'observed' key — each of those is one named competitor's figure or promise;
--   4. a DRAFT bid is not counted in the population;
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
  r_nomatch jsonb; r_thin jsonb; r_ok jsonb; o_me jsonb; o_none jsonb; ws jsonb;
  leaked    int := 0; checked int := 0; names text[]; v_err text;
begin
  begin
    r_nomatch := public.fn_supplier_quote_recommend(me, nope);

    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status)
    values (gen_random_uuid(), inq, 129660, 50000, 'form', 9, 'submitted');
    r_thin := public.fn_supplier_quote_recommend(me, inq);

    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status) values
      (gen_random_uuid(), inq, 129676, 61000, 'form', 9, 'submitted'),
      (gen_random_uuid(), inq, 129775, 72000, 'form', 9, 'submitted'),
      (gen_random_uuid(), inq, 129660, 999999, 'form', 8, 'draft');   -- a draft is not a bid
    r_ok   := public.fn_supplier_quote_recommend(me, inq);
    o_me   := public.fn_supplier_opportunities(me);
    o_none := public.fn_supplier_opportunities(129660);
    ws     := public.fn_supplier_workspaces(me);

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
  insert into zz_probe_verdict
  select case when v_err = 'ZZPROBE rollback'
                   and r_nomatch->>'available' = 'false' and r_nomatch->>'reason' = 'not_found'
                   and r_thin->>'available' = 'false' and r_thin->>'reason' = 'thin_market'
                   and (r_thin->>'population')::int = 1 and position('50000' in r_thin::text) = 0
                   and r_ok->>'available' = 'true' and (r_ok->>'population')::int = 3
                   and (r_ok#>>'{recommended_price,value}')::numeric = 61000
                   and r_ok#>'{recommended_price,low}' is null and r_ok#>'{recommended_price,high}' is null
                   and r_ok#>'{delivery_estimate,observed}' is null
                   and position('999999' in r_ok::text) = 0
                   and (o_me#>>'{population,matched_to_me}')::int = 3
                   and o_me#>'{population,open_inquiries}' is null
                   and (o_none->>'count')::int = 0 and (o_none#>>'{population,matched_to_me}')::int = 0
                   and leaked = 0
              then 'PROBE OK' else 'PROBE FAILED' end,
         format('no_match=%s/%s; one_rival=%s/%s pop=%s rival_price_in_payload=%s; three_rivals=%s pop=%s median=%s '
                || 'low=%s high=%s observed=%s draft_counted=%s; opportunities_me count=%s matched=%s estate_open_key=%s; '
                || 'opportunities_unmatched count=%s matched=%s; workspaces count=%s names_checked=%s leaked=%s; block ended with: %s',
                r_nomatch->>'available', r_nomatch->>'reason',
                r_thin->>'available', r_thin->>'reason', r_thin->>'population', position('50000' in r_thin::text) > 0,
                r_ok->>'available', r_ok->>'population', r_ok#>>'{recommended_price,value}',
                r_ok#>'{recommended_price,low}' is not null, r_ok#>'{recommended_price,high}' is not null,
                r_ok#>'{delivery_estimate,observed}' is not null, position('999999' in r_ok::text) > 0,
                o_me->>'count', o_me#>>'{population,matched_to_me}', o_me#>'{population,open_inquiries}' is not null,
                o_none->>'count', o_none#>>'{population,matched_to_me}',
                ws->>'count', checked, leaked, v_err);
end $probe$;
select * from zz_probe_verdict;
