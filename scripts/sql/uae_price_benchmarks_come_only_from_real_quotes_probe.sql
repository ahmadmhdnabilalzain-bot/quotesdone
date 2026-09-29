-- PROBE: UAE PRICE BENCHMARKS COME ONLY FROM REAL QUOTES. Founder instruction 1009, upgrade 4. Seat: sales_engineer.
--
-- Pure probe, nothing survives it. It ends in `raise exception 'CHK<<...>>'` ALWAYS, so the whole
-- request rolls back. Until uae_price_benchmarks_come_only_from_real_quotes.sql is applied, run it
-- with the DDL in front of it, as ONE request (one implicit transaction, so the raise takes the
-- routines with it and production is left untouched):
--   cat scripts/sql/uae_price_benchmarks_come_only_from_real_quotes.sql \
--       scripts/sql/uae_price_benchmarks_come_only_from_real_quotes_probe.sql > <scratch>/p.sql
--   node scripts/qsql.mjs <scratch>/p.sql        -> must print CHK<<PROBE OK ...>>
-- After the apply, run this file alone the same way.
--
-- Rows: ZZ DEMO leads 129923 / 130029 / 130110 / 134369 bid on the ZZ DEMO gypsum enquiries
-- 8b287960 (the "market") and d958e1ea (the one being compared). Demo leads on demo enquiries is
-- what fn_demo_and_real_never_pair requires. No real party is touched; nothing notifies anybody.
--
-- VERDICT: PROBE OK only if
--   1. the public read (demo excluded) has exactly as many ranges after the demo quotes as before;
--   2. 4 quotes from 2 suppliers, and 5 quotes from 2 suppliers, publish NO range;
--   3. 5 quotes from 3 suppliers publish median 45, p25 42, p75 48, count 5, suppliers 3, accepted 1;
--   4. on the compared enquiry: 120/m2 is well_above, 44/m2 within, 10/m2 well_below, an item nobody
--      else priced is no_benchmark_yet, and every 'reason' is non-empty;
--   5. with demo excluded every compared line answers no_benchmark_yet (never an invented price);
--   6. the payload carries no min/max key and neither extreme market price (40.00, 50.00).
do $probe$
declare
  mkt uuid := '8b287960-ce32-4a2d-9b79-0cfa8804514a';
  cmp uuid := 'd958e1ea-54f4-45a1-9214-d622ac52dce1';
  base_real int; after_real int; n4 int; n5two int; b record; f jsonb; f_real jsonb;
  q uuid; qs uuid[] := '{}'; cq text[] := '{}'; fails text := '';
  sup bigint[] := array[129923, 129923, 130029, 130029, 129923];
  px numeric[] := array[40, 42, 45, 48, 50];
  st text;
begin
  select count(*) into base_real from public.fn_price_benchmarks(false, null);

  for k in 1..5 loop
    q := gen_random_uuid(); qs := qs || q;
    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status)
    values (q, mkt, sup[k], px[k] * 100, 'form', 14 + k, case when k = 3 then 'revealed' else 'submitted' end);
    insert into public.quote_items (quote_id, line_no, description, specification, qty, unit, unit_price, amount)
    values (q::text, 1, 'Gypsum board partition', '12.5mm ZZPROBE', 100, 'm2', px[k], px[k] * 100);
    if k = 4 then
      select count(*) into n4 from public.fn_price_benchmarks(true, cmp) where item_key like '%zzprobe%';
    end if;
  end loop;
  select count(*) into n5two from public.fn_price_benchmarks(true, cmp) where item_key like '%zzprobe%';
  -- A quote never changes hands (fn_quote_supplier_is_immutable), so the fifth becomes a third company's.
  delete from public.quote_items where quote_id = qs[5]::text;
  delete from public.quotes where id = qs[5];
  q := gen_random_uuid();
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status)
  values (q, mkt, 130110, 5000, 'form', 19, 'submitted');
  insert into public.quote_items (quote_id, line_no, description, specification, qty, unit, unit_price, amount)
  values (q::text, 1, 'Gypsum board partition', '12.5mm ZZPROBE', 100, 'm2', 50, 5000);

  select * into b from public.fn_price_benchmarks(true, cmp) where item_key like '%zzprobe%';
  select count(*) into after_real from public.fn_price_benchmarks(false, null);

  foreach st in array array['134369:120', '130110:44', '129923:10'] loop
    q := gen_random_uuid();
    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, source, option_no, status)
    values (q, cmp, split_part(st, ':', 1)::bigint, 9999, 'form', 19, 'submitted');
    cq := cq || q::text;
    insert into public.quote_items (quote_id, line_no, description, specification, qty, unit, unit_price, amount) values
      (q::text, 1, 'Gypsum board partition', '12.5mm ZZPROBE', 10, 'M2', split_part(st, ':', 2)::numeric, 0),
      (q::text, 2, 'ZZPROBE item nobody else priced', null, 1, 'each', 77, 77);
  end loop;
  -- The compared enquiry already carries other ZZ DEMO quote lines; judge only this probe's own three quotes.
  select jsonb_agg(e) into f from jsonb_array_elements(public.fn_price_benchmark_flags_for_inquiry(cmp, true)) e
   where e->>'quote_id' = any(cq);
  select jsonb_agg(e) into f_real from jsonb_array_elements(public.fn_price_benchmark_flags_for_inquiry(cmp, false)) e
   where e->>'quote_id' = any(cq);

  if after_real <> base_real then fails := fails || ' 1:demo_leaked(' || base_real || '->' || after_real || ')'; end if;
  if n4 <> 0 or n5two <> 0 then fails := fails || ' 2:published_below_threshold(' || n4 || ',' || n5two || ')'; end if;
  if b.median is distinct from 45 or b.p25 is distinct from 42 or b.p75 is distinct from 48
     or b.quote_count <> 5 or b.supplier_count <> 3 or b.accepted_count <> 1 then
    fails := fails || ' 3:stats(' || coalesce(row_to_json(b)::text, 'none') || ')'; end if;
  if (select count(*) from jsonb_array_elements(f) e where e->>'description' like 'Gypsum%') <> 3
     or not exists (select 1 from jsonb_array_elements(f) e where (e->>'line_no') = '1' and e->>'status' = 'well_above')
     or not exists (select 1 from jsonb_array_elements(f) e where (e->>'line_no') = '1' and e->>'status' = 'within')
     or not exists (select 1 from jsonb_array_elements(f) e where (e->>'line_no') = '1' and e->>'status' = 'well_below')
     or (select count(*) from jsonb_array_elements(f) e where (e->>'line_no') = '2' and e->>'status' = 'no_benchmark_yet') <> 3
     or exists (select 1 from jsonb_array_elements(f) e where coalesce(e->>'reason', '') = '') then
    fails := fails || ' 4:flags(' || left(f::text, 600) || ')'; end if;
  if exists (select 1 from jsonb_array_elements(f_real) e where e->>'status' <> 'no_benchmark_yet')
     or jsonb_array_length(f_real) <> 6 then fails := fails || ' 5:real_not_empty'; end if;
  if f::text ~ '"(min|max|low|high)"' or f::text like '%40.00%' or f::text like '%50.00%' then
    fails := fails || ' 6:extreme_leaked'; end if;

  raise exception 'CHK<<%>>', case when fails = '' then
    'PROBE OK median=' || b.median || ' p25=' || b.p25 || ' p75=' || b.p75 || ' n=' || b.quote_count
    || ' suppliers=' || b.supplier_count || ' accepted=' || b.accepted_count || ' real_ranges=' || after_real
    || ' | ' || (select string_agg(e->>'status', ',') from jsonb_array_elements(f) e)
    else 'PROBE FAILED:' || fails end;
end $probe$;
