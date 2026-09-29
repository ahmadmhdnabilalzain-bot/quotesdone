-- THE IT ENGINEER HOLDS THE PUBLIC SITE TO ITS UPTIME TARGET, MEASURED FROM OUTSIDE SUPABASE.
-- Seat: it_engineer. 28 Sep 2026. Needs every_seat_duty_has_an_owner_a_clock_and_a_check.sql (seat_duty)
-- and fn_it_duty_settle.
--
-- THE GAP: there was no external uptime SLI. it_watch_tick.site_ms times the home page, but from pg_cron,
--   so a Supabase outage stops the measurement with the thing it measures, and nothing judged availability
--   against the job description's 99.9%.
--
-- WHAT THIS ADDS:
--   * The Vercel cron /api/resilience-ping (every 15 min, outside Supabase) writes one edge_health_probe row per
--     public origin per run: fn_key 'uptime:<url>', verdict 'up' or 'down' (src/lib/uptime.ts isUp).
--   * seat_duty it_engineer.uptime_slo (1 hour): per origin over 30 days, up / all samples. Under 99.9% with at
--     least 96 samples (a day) is a finding duty:uptime_slo:<url>; recovery closes it (fn_it_duty_settle).
--     2,880 slots a month means 2 failed slots pass and 3 breach (src/lib/uptime.test.mjs pins the same maths).
--   * Pruning: edge_health_probe rows older than 90 days, at most 5,000 per hourly run (the integration probe of
--     PR #993 adds ~5,800 a day, so 120,000 a day of headroom drains any backlog without one big delete —
--     a 50k batch delete restarted production on 21 Sep).
--
-- WHAT THIS DOES NOT DO: count a slot with NO row as down. If the Vercel cron itself stops, uptime is computed
--   over fewer samples; the resilience_ping watchdog and the daily GitHub cross-check own that failure.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_holds_the_public_site_to_its_uptime_target.sql --apply --ddl
--   then set SUPABASE_SERVICE_ROLE_KEY (server env, not NEXT_PUBLIC_) on the Vercel project and deploy.

create index if not exists edge_health_probe_checked_at_idx on public.edge_health_probe (checked_at);

create or replace function public.fn_it_engineer_uptime_slo()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare x record; v_items jsonb := '[]'::jsonb; v_out jsonb := '[]'::jsonb; v_pruned int;
begin
  for x in
    select substring(fn_key from 8) url, count(*) n, count(*) filter (where verdict = 'up') up
      from public.edge_health_probe
     where fn_key like 'uptime:%' and checked_at > now() - interval '30 days'
     group by 1
  loop
    v_out := v_out || jsonb_build_object('url', x.url, 'samples', x.n, 'up', x.up,
                                         'uptime_pct', round(100.0 * x.up / x.n, 3));
    if x.n >= 96 and x.up::numeric / x.n < 0.999 then
      v_items := v_items || jsonb_build_object('item', x.url, 'subject', 'website', 'blast', 'customer_facing',
        'owner_seat', 'it_engineer', 'affected', x.n - x.up,
        'title', x.url || ' was up ' || round(100.0 * x.up / x.n, 3) || '% of ' || x.n
                 || ' external checks over 30 days; the target is 99.9%',
        'evidence', jsonb_build_object('samples', x.n, 'up', x.up, 'down', x.n - x.up, 'target', 0.999, 'window', '30 days'));
    end if;
  end loop;

  delete from public.edge_health_probe
   where id in (select id from public.edge_health_probe where checked_at < now() - interval '90 days' limit 5000);
  get diagnostics v_pruned = row_count;

  return jsonb_build_object('urls', v_out, 'pruned', v_pruned, 'settled', public.fn_it_duty_settle('uptime_slo', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_uptime_slo() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_uptime_slo() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.uptime_slo', 'it_engineer', interval '1 hour', 'fn_it_engineer_uptime_slo',
   '30-day uptime per public URL from the external 15-minute checks against 99.9%; below target is a finding. Prunes edge_health_probe past 90 days.',
   'scripts/sql/the_it_engineer_holds_the_public_site_to_its_uptime_target.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- PROBE. Seeds a fictional origin (https://zz-demo-uptime.example.invalid) with 2,880 samples, 44 down, and a second
-- with 1 down; runs the routine; asserts the first is a finding and the second is not; removes every row and finding
-- it made. Real 'uptime:https://quotesdone...' rows are counted before and after and must not change.
-- prevented by: without the < 0.999 comparison (or with the verdict filter wrong) the 44-down origin raises nothing,
-- and without the settle the 1-down origin would stay a finding.
create temporary table _uptime_probe on commit drop as
  select (select count(*) from public.edge_health_probe where fn_key like 'uptime:https://%quotesdone%') real_before;

insert into public.edge_health_probe (fn_key, checked_at, verdict, note)
select 'uptime:https://zz-demo-uptime-' || o || '.example.invalid', now() - (g * interval '15 minutes'),
       case when g <= case o when 'a' then 44 else 1 end then 'down' else 'up' end, 'ZZ DEMO probe'
  from generate_series(1, 2880) g, unnest(array['a', 'b']) o;

select public.fn_it_engineer_uptime_slo();

create temporary table _uptime_verdict on commit drop as
select exists (select 1 from public.it_engineer_finding
                where issue_key = 'duty:uptime_slo:https://zz-demo-uptime-a.example.invalid' and closed_at is null) a_raised,
       not exists (select 1 from public.it_engineer_finding
                    where issue_key = 'duty:uptime_slo:https://zz-demo-uptime-b.example.invalid' and closed_at is null) b_clear;

delete from public.edge_health_probe where fn_key like 'uptime:https://zz-demo-uptime-%.example.invalid';
delete from public.it_engineer_finding where issue_key like 'duty:uptime_slo:https://zz-demo-uptime-%.example.invalid';

select case
  when not (select a_raised from _uptime_verdict) then 'PROBE FAILED: 44 down slots in 2,880 raised no finding'
  when not (select b_clear from _uptime_verdict) then 'PROBE FAILED: 1 down slot in 2,880 raised a finding'
  when exists (select 1 from public.edge_health_probe where fn_key like 'uptime:https://zz-demo-uptime-%')
    or exists (select 1 from public.it_engineer_finding where issue_key like 'duty:uptime_slo:https://zz-demo-uptime-%')
    then 'PROBE FAILED: the probe left rows behind'
  when (select count(*) from public.edge_health_probe where fn_key like 'uptime:https://%quotesdone%')
       < (select real_before from _uptime_probe)
    then 'PROBE FAILED: real uptime rows were disturbed'
  when to_regprocedure('public.fn_it_engineer_uptime_slo()') is null
    or not exists (select 1 from public.seat_duty where duty = 'it_engineer.uptime_slo')
    then 'PROBE FAILED: the uptime duty is not registered'
  else 'PROBE OK' end as verdict;
