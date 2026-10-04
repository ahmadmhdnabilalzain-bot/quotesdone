-- THE CEO WRITES AN INTERNAL UAE MARKET REPORT EVERY MONTH (backlog T5, ledger 1019). INTERNAL ONLY: for the
-- founder and the CEO, never published.
-- Assigned: ceo.
--
-- Measured 5 Oct 2026 before writing this: the monthly strategy memo (fn_ceo_strategy_memo, ceo.strategy_memo)
-- carries a "market changes" section (competitor pages and trends) and category growth, but nothing reported
-- the market itself: where supply is short against demand per trade and emirate, the price bands on file,
-- quotes and conversion for the month. This report reuses the memo's measured facts
-- (fn_ceo_strategy_memo_facts) rather than counting them a second way, and adds the rest.
--
-- IT ACTS: the binding finding - the trade and area furthest below its supplier target against measured
-- demand - becomes a CEO improvement for the sales engineer on the existing path (fn_ceo_improvement_open:
-- a CEO task and a handoff), and the next month's report closes last month's improvement when that gap is
-- closed. The founder is NOTIFIED (founder_mail_policy kind ceo_market_report); nothing waits on him.
--
-- NEVER PUBLISHED, BY CONSTRUCTION: ceo_market_report has RLS with no readable policy, no anon/authenticated
-- grant, audience is CHECKed 'internal', and scripts/checks/the_market_report_is_never_published.test.mjs fails
-- if any publishing surface (blog, social, articles, public_site, sitemap, exports) names the table.
-- NEVER NAMES A SUPPLIER: the body is run through the #1164 guard (fn_supplier_named_in) before it is stored or
-- mailed; a hit withholds the detail from the mail and records why.
-- The narrative ("what this means") is filed for the CEO's reasoning and HELD while the model hold is on.

create table if not exists public.ceo_market_report (
  month        date not null,
  audience     text not null default 'internal' check (audience = 'internal'),
  facts        jsonb not null,
  binding      jsonb,
  body         text not null,
  named_check  text,
  improvement_id bigint,
  closed_last  jsonb,
  held_id      bigint,
  notify       jsonb,
  include_demo boolean not null default false,
  created_at   timestamptz not null default now(),
  primary key (month, include_demo)   -- a demo run never takes the real month's slot (review of #1192)
);
alter table public.ceo_market_report enable row level security;
drop policy if exists ceo_market_report_service_role_only on public.ceo_market_report;
create policy ceo_market_report_service_role_only on public.ceo_market_report as permissive for all to public using (false) with check (false);
revoke all on public.ceo_market_report from anon, authenticated;

-- the daily export is the company's own backup (Dropbox), not a publication
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('ceo_market_report', true, 'decision', 'the CEO''s monthly internal UAE market report (backlog T5): internal only, backed up with the company''s decisions', 'ceo')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason, added_by = excluded.added_by;

alter table public.ceo_improvement drop constraint if exists ceo_improvement_source_kind_check;
alter table public.ceo_improvement add constraint ceo_improvement_source_kind_check check (source_kind = any (array[
  'recurring_miss', 'month_miss', 'lesson', 'recurring_finding', 'binding_constraint', 'marketing_plan_late',
  'seat_audit', 'funnel_stage_drop', 'weekly_review', 'self_review', 'market_report']));

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('ceo_market_report', true,
  'the CEO''s monthly internal UAE market report (backlog T5, ledger 1019): internal only, for the founder and the CEO; a notice, never an approval',
  'ceo')
on conflict (kind) do update set allowed_to_email = true, reason = excluded.reason, owner_role = 'ceo';

create or replace function public.fn_ceo_market_report(p_month date default null, p_include_demo boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_m date := date_trunc('month', coalesce(p_month, (v_today - interval '1 month')::date))::date;
  v_e date := (date_trunc('month', coalesce(p_month, (v_today - interval '1 month')::date)) + interval '1 month')::date;
  f jsonb; v_gaps jsonb; v_prices jsonb; v_quotes jsonb; v_conv jsonb; v_fc jsonb := null; v_bind jsonb; v_closed jsonb := '[]'::jsonb;
  v_body text; v_named text; v_impr bigint; v_held bigint; v_n jsonb; r record;
begin
  if v_m >= date_trunc('month', v_today)::date then
    raise exception 'month % has not ended; the market report is written for a month that is over', to_char(v_m, 'YYYY-MM');
  end if;
  if exists (select 1 from public.ceo_market_report where month = v_m and include_demo = p_include_demo) then
    return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'already', true);
  end if;

  f := public.fn_ceo_strategy_memo_facts(v_m, p_include_demo);   -- requests and suppliers per category, competitors, trends

  select coalesce(jsonb_agg(x order by (x->>'shortfall')::int desc, x->>'trade', x->>'emirate'), '[]'::jsonb) into v_gaps
    from (select jsonb_build_object('trade', g.trade, 'emirate', g.emirate, 'matchable', g.matchable, 'target', g.target,
                   'demand_90d', g.demand_90d, 'shortfall', g.target - g.matchable, 'status', g.status) x
            from public.supply_gap g where g.matchable < g.target and g.demand_90d > 0
           order by g.demand_90d desc, g.target - g.matchable desc limit 15) z;

  select jsonb_build_object('benchmarks', count(*), 'categories', count(distinct category), 'newest', max(as_of),
           'stale_over_180d', count(*) filter (where as_of < v_today - 180)) into v_prices
    from public.price_benchmark;

  with q as (
    select i.category, q.quote_amount from public.quotes q join public.inquiries i on i.id = q.inquiry_id
      left join public.customers c on c.id = i.customer_id
     where q.created_at >= v_m and q.created_at < v_e and (p_include_demo or not coalesce(c.is_demo, false))
  )
  select jsonb_build_object('quotes', count(*),
           'by_category', coalesce((select jsonb_agg(jsonb_build_object('category', category, 'quotes', n, 'median_aed', med) order by n desc)
              from (select category, count(*) n, percentile_cont(0.5) within group (order by quote_amount) med from q group by category) s), '[]'::jsonb))
    into v_quotes from q;

  select jsonb_build_object('requests', count(*),
           'quoted', count(*) filter (where exists (select 1 from public.quotes q where q.inquiry_id = i.id)),
           'revealed', count(*) filter (where i.status = 'revealed')) into v_conv
    from public.inquiries i left join public.customers c on c.id = i.customer_id
   where i.created_at >= v_m and i.created_at < v_e and i.parent_inquiry_id is null and (p_include_demo or not coalesce(c.is_demo, false));

  if to_regclass('public.demand_forecast') is not null then   -- the sales engineer's estimate, when it is on file
    execute $q$select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
               select trade, emirate, forecast_30d, forecast_90d, searches_30d, sufficient_data, basis from public.demand_forecast
                where run_on = (select max(run_on) from public.demand_forecast) and emirate = 'UAE'
                order by forecast_90d desc, searches_30d desc limit 10) x$q$ into v_fc;
  end if;

  -- CLOSE last months' findings whose gap is now closed. A demo run acts on nothing real: no close, no open,
  -- no handoff (review of #1192).
  for r in select i.id, i.evidence from public.ceo_improvement i
            where not p_include_demo and i.source_kind = 'market_report' and i.status in ('open', 'assigned') loop
    if exists (select 1 from public.supply_gap g where g.trade = r.evidence->>'trade' and g.emirate = r.evidence->>'emirate' and g.matchable >= g.target) then
      perform public.fn_ceo_improvement_close(r.id, format('%s in %s reached its supplier target (market report %s).',
        r.evidence->>'trade', r.evidence->>'emirate', to_char(v_m, 'YYYY-MM')));
      v_closed := v_closed || jsonb_build_object('improvement_id', r.id, 'trade', r.evidence->>'trade', 'emirate', r.evidence->>'emirate');
    end if;
  end loop;

  -- THE BINDING FINDING and the act on it
  v_bind := v_gaps->0;
  if v_bind is not null and not p_include_demo then
    v_impr := public.fn_ceo_improvement_open('market_report', to_char(v_m, 'YYYY-MM'), 'sales_engineer',
      format('Market report %s: %s in %s has %s matchable suppliers against a target of %s while %s requests came in over 90 days. Recruit until it reaches the target.',
             to_char(v_m, 'Mon YYYY'), v_bind->>'trade', v_bind->>'emirate', v_bind->>'matchable', v_bind->>'target', v_bind->>'demand_90d'),
      v_bind || jsonb_build_object('report_month', v_m));
  end if;

  v_body := 'INTERNAL UAE MARKET REPORT - ' || to_char(v_m, 'FMMonth YYYY') || ' (internal only, never published)' || E'\n\n'
    || '1. DEMAND' || E'\n'
    || format('  Requests %s, quoted %s, revealed %s.', v_conv->>'requests', v_conv->>'quoted', v_conv->>'revealed') || E'\n'
    || coalesce((select string_agg(format('  %-40s requests %s (month before %s)', x->>'category', x->>'requests', x->>'requests_prior'), E'\n')
                   from (select x from jsonb_array_elements(f->'categories') x where (x->>'requests')::int > 0 or (x->>'requests_prior')::int > 0 limit 10) z) || E'\n', '')
    || coalesce((select E'  Forecast (estimate, the sales engineer''s), next 90 days:\n' || string_agg(format('    %-38s %s (searches 30d %s%s)',
                   x->>'trade', x->>'forecast_90d', x->>'searches_30d', case when (x->>'sufficient_data')::boolean then '' else ', thin data' end), E'\n')
                   from jsonb_array_elements(coalesce(v_fc, '[]'::jsonb)) x) || E'\n', '')
    || E'\n2. SUPPLY AGAINST DEMAND (below target with demand)\n'
    || coalesce((select string_agg(format('  %-30s %-16s %s of %s suppliers, demand %s', x->>'trade', x->>'emirate', x->>'matchable', x->>'target', x->>'demand_90d'), E'\n')
                   from (select x from jsonb_array_elements(v_gaps) x limit 10) z), '  no trade with demand is below target') || E'\n\n'
    || '3. PRICES' || E'\n'
    || format('  %s benchmarks over %s categories, newest %s, %s older than 180 days. Quotes this month: %s.',
              v_prices->>'benchmarks', v_prices->>'categories', coalesce(v_prices->>'newest', '-'), v_prices->>'stale_over_180d', v_quotes->>'quotes') || E'\n'
    || coalesce((select string_agg(format('  %-40s %s quotes, median AED %s', x->>'category', x->>'quotes', round((x->>'median_aed')::numeric)), E'\n')
                   from jsonb_array_elements(v_quotes->'by_category') x) || E'\n', '')
    || E'\n4. COMPETITORS AND TRENDS\n'
    || format('  Watched %s, pages changed %s, trends %s.', f#>>'{market,competitors_watched}',
              jsonb_array_length(coalesce(f#>'{market,competitor_pages_changed}', '[]')), jsonb_array_length(coalesce(f#>'{market,relevant_trends}', '[]'))) || E'\n\n'
    || '5. THE BINDING FINDING' || E'\n'
    || case when v_bind is null then '  none: no trade with measured demand is below its supplier target.'
            else format('  %s in %s: %s of %s suppliers against %s requests. Improvement #%s assigned to the sales engineer.',
                        v_bind->>'trade', v_bind->>'emirate', v_bind->>'matchable', v_bind->>'target', v_bind->>'demand_90d', coalesce(v_impr::text, '(already open)')) end
    || case when jsonb_array_length(v_closed) > 0 then E'\n  Closed: ' || jsonb_array_length(v_closed) || ' earlier finding(s) whose gap reached target.' else '' end
    || E'\n\nEvery figure is measured from the live tables. The commentary is filed for the CEO''s reasoning and held while the model hold is on.';

  v_named := public.fn_supplier_named_in(v_body);   -- #1164: nothing that leaves the database names a supplier

  v_held := public.fn_reason_hold('ceo', 'ceo.market_report',
    'Monthly internal UAE market report for ' || to_char(v_m, 'Mon YYYY') || '. What do these figures mean for the plan, and what should the company do differently next month? Never name a supplier. ' || left(v_body, 6000),
    jsonb_build_object('seat', 'ceo', 'surface', 'ceo.market_report', 'stakes', 'normal', 'context', jsonb_build_object('audience', 'internal'),
                       'subject', jsonb_build_object('month', v_m), 'dedupeKey', 'ceo_market_report:' || to_char(v_m, 'YYYY-MM')),
    jsonb_build_object('filed_by', 'ceo.market_report'), jsonb_build_object('month', v_m),
    'seat_duty', 'ceo_market_report:' || to_char(v_m, 'YYYY-MM') || case when p_include_demo then ':zz-demo' else '' end);

  insert into public.ceo_market_report (month, facts, binding, body, named_check, improvement_id, closed_last, held_id, include_demo)
  values (v_m, jsonb_build_object('memo_facts', f, 'gaps', v_gaps, 'prices', v_prices, 'quotes', v_quotes, 'conversion', v_conv, 'forecast', v_fc),
          v_bind, v_body, v_named, v_impr, v_closed, v_held, p_include_demo);

  v_n := public.fn_notify_founder(p_event => 'Internal UAE market report - ' || to_char(v_m, 'FMMonth YYYY'),
    p_detail => case when v_named is null then v_body
                     else 'The report for ' || to_char(v_m, 'FMMonth YYYY') || ' is on file (ceo_market_report). Its detail is withheld from this mail because a line matched a registered supplier''s name.' end,
    p_level => 'info', p_kind => 'ceo_market_report',
    p_dedupe_key => 'ceo_market_report:' || to_char(v_m, 'YYYY-MM') || case when p_include_demo then ':zz-demo' else '' end,
    p_owner_agent => 'ceo');
  update public.ceo_market_report set notify = v_n where month = v_m and include_demo = p_include_demo;

  return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'binding', v_bind, 'improvement_id', v_impr,
    'closed', v_closed, 'held_id', v_held, 'named', v_named is not null, 'notify', v_n);
end $fn$;
revoke execute on function public.fn_ceo_market_report(date, boolean) from public, anon, authenticated;

-- The duty: from the 3rd (Dubai; the strategy memo is the 2nd) for the month that ended; first report September 2026.
create or replace function public.fn_ceo_market_report_now(p_today date default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_today date := coalesce(p_today, (now() at time zone 'Asia/Dubai')::date);
  v_month date := date_trunc('month', v_today - interval '1 month')::date;
begin
  if extract(day from v_today) < 3 then
    return jsonb_build_object('due', false, 'reason', 'the market report is written from the 3rd (Dubai) for the month that ended', 'today', v_today);
  end if;
  if v_month < date '2026-09-01' then
    return jsonb_build_object('due', false, 'reason', 'the first report is for September 2026');
  end if;
  return jsonb_build_object('due', true) || public.fn_ceo_market_report(v_month, false);
end $fn$;
revoke execute on function public.fn_ceo_market_report_now(date) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled)
values ('ceo.market_report', 'ceo', '1 day', 'fn_ceo_market_report_now',
  'The monthly internal UAE market report (demand, supply against demand, prices, competitors), from the 3rd (Dubai): internal only, never published; its binding finding becomes an improvement for the sales engineer and the founder is notified.',
  'scripts/sql/the_ceo_writes_an_internal_uae_market_report_every_month.sql', true)
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file, enabled = true;
