-- PROBE, ROLLED BACK: the marketing KPIs count registrations by source, cost per supplier, posts, articles and rankings.
-- For scripts/sql/the_marketing_seat_measures_search_registrations_and_cost_per_supplier_every_day.sql. Seat: marketing.
-- Pure probe, no DDL: always ends in raise exception 'CHK<<...>>'. LOCAL Postgres 16 ONLY (it asserts on a local copy
-- built from the mirror, whose tables are empty); never run on production.
--   psql -1 -f <file>.sql -f <file>_probe.sql      (expect CHK<<PROBE OK ...>>)
-- It cannot reach a person: it sends nothing; its two suppliers are probe rows rolled back with the rest.
do $probe$
declare v_d date := (now() at time zone 'Asia/Dubai')::date; k jsonb; v_a bigint; v_b bigint; v_fail text := '';
begin
  if exists (select 1 from public.marketing_first_touch) or exists (select 1 from public.marketing_search_day) then
    raise exception 'CHK<<PROBE FAILED: not an empty local copy; this probe runs only on a local copy built from the mirror>>';
  end if;
  -- before any data: Search Console is named as missing, nothing fails
  k := public.fn_marketing_measurement_kpis(v_d);
  if k #>> '{search,unavailable}' is null or (k->>'suppliers_approved_30d')::int <> 0 then v_fail := v_fail || ' empty:' || left(k::text, 300) || ';'; end if;

  -- two registrations: one from the founder's tracked link (approved), one untagged (submitted)
  insert into public.leads (company_name, email, claimed, claimed_by, registration_submitted_at, approved_at, approval_status)
  values ('Probe Steel Trading LLC', 'owner@probe-steel.test', true, 'owner@probe-steel.test', now() - interval '3 days', now() - interval '1 day', 'approved')
  returning id into v_a;
  insert into public.leads (company_name, email, claimed, claimed_by, registration_submitted_at)
  values ('Probe Glass LLC', 'owner@probe-glass.test', true, 'owner@probe-glass.test', now() - interval '2 days') returning id into v_b;
  perform public.fn_marketing_first_touch_record(v_a, '{"utm_source":"founder","utm_medium":"whatsapp","utm_campaign":"2026-11","landing_path":"/portal"}'::jsonb);
  -- marketing cost: 300 booked to 6200; the seat's model spend 12.50; a test-tagged marketing call is not counted
  perform public.fn_gl_entry(v_d - 5, 'probe marketing', 'manual', 'probe:mkt', '[{"account":"6200","debit":300},{"account":"1000","credit":300}]'::jsonb, 'probe');
  insert into public.ai_cost_log (fn, model_used, cost_aed, e2e_run_tag) values ('marketing', 'probe', 12.50, null), ('marketing', 'probe', 99, 'probe-run');
  -- search: two days of totals, a query in the top 10, a blog page; one sitemap
  insert into public.marketing_search_day (day, dim, key, clicks, impressions, ctr, position) values
    (v_d - 3, 'total', '', 4, 100, 0.04, 14), (v_d - 2, 'total', '', 6, 100, 0.06, 10),
    (v_d - 2, 'query', 'steel supplier uae', 3, 50, 0.06, 7.5), (v_d - 2, 'query', 'glass dubai', 0, 20, 0, 31),
    (v_d - 2, 'page', 'https://quotesdone.com/blog/steel-prices', 2, 40, 0.05, 9);
  insert into public.marketing_search_sitemap (path, submitted, indexed) values ('https://quotesdone.com/sitemap.xml', 120, 45);

  k := public.fn_marketing_measurement_tick();
  if k #>> '{registrations_by_source,founder,approved}' <> '1' or k #>> '{registrations_by_source,untagged,submitted}' <> '1'
     or (k->>'registrations_submitted_30d')::int <> 2 or (k->>'suppliers_approved_30d')::int <> 1 then
    v_fail := v_fail || ' registrations:' || (k->'registrations_by_source')::text || ';';
  end if;
  if (k #>> '{cost_per_registered_supplier,aed}')::numeric <> 312.50 then v_fail := v_fail || ' cps:' || (k->'cost_per_registered_supplier')::text || ';'; end if;
  if (k #>> '{search,clicks_30d}')::int <> 10 or (k #>> '{search,avg_position_30d}')::numeric <> 12.0
     or (k #>> '{search,queries_in_top_10_last_7d}')::int <> 1 or (k #>> '{search,indexed_urls}')::int <> 45
     or (k #>> '{articles,blog_organic_clicks_30d}')::int <> 2 then
    v_fail := v_fail || ' search:' || (k->'search')::text || (k->'articles')::text || ';';
  end if;
  if not exists (select 1 from public.marketing_duty_record where duty = 'marketing.measurement_kpis' and period = v_d)
     or public.fn_marketing_measurement_reading() ->> 'seat' <> 'marketing' then
    v_fail := v_fail || ' record;';
  end if;
  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: registrations by source, cost per registered supplier, posts, articles and rankings are measured daily'
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
