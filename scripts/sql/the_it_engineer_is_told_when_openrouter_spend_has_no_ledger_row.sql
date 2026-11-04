-- THE IT ENGINEER IS TOLD WHEN OPENROUTER SPEND HAS NO LEDGER ROW (it_engineer, 3 Nov 2026)
--
-- MEASURED (openrouter_day): 2 Nov 2026 OpenRouter's meter moved USD 39.40 and ai_cost_log priced USD 34.06 of it, so
-- USD 5.34 (13.6%) had no row; over the 7 days to 3 Nov, USD 11.79. The accountant's daily ledger already computes
-- unattributed_usd every day, and nothing read it. The causes found and fixed with this file's pull request: streamed
-- replies without a usage chunk, failed attempts the provider still billed, and a laptop script calling OpenRouter direct.
--
-- WHAT THIS ADDS: seat_duty it_engineer.openrouter_unattributed (daily) -> fn_it_engineer_openrouter_unattributed(): every
-- reconciled day of the last 7 whose unattributed_usd is more than it_threshold openrouter_unattributed_share_max (0.05)
-- of the meter's authoritative_usd is ONE finding on the it_engineer's own list (fn_it_duty_settle, blast internal), with
-- the days as evidence; it clears itself when no day in the window is over. It never writes to the founder.
-- A day whose meter moved less than USD 1 is not judged: 5% of a few cents is rounding, not a leak.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_is_told_when_openrouter_spend_has_no_ledger_row.sql --apply --ddl

insert into public.it_threshold (key, value, unit, basis) values
  ('openrouter_unattributed_share_max', 0.05, 'ratio',
   'it_engineer, 3 Nov 2026: the share of a day''s OpenRouter meter (openrouter_day.authoritative_usd) that may have no ai_cost_log row. Measured 2 Nov 2026: 13.6% (USD 5.34 of 39.40).')
on conflict (key) do nothing;

create or replace function public.fn_it_engineer_openrouter_unattributed()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_max numeric := coalesce(public.fn_it_threshold('openrouter_unattributed_share_max'), 0.05);
        v_days jsonb; v_n int; v_items jsonb := '[]'::jsonb;
begin
  select count(*), coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'meter_usd', round(d.authoritative_usd, 2),
                                    'unattributed_usd', round(d.unattributed_usd, 2),
                                    'share', round(d.unattributed_usd / d.authoritative_usd, 3)) order by d.day desc), '[]')
    into v_n, v_days
    from public.openrouter_day d
   where d.day >= (now() at time zone 'Asia/Dubai')::date - 7
     and d.reconciled_at is not null and d.authoritative_usd >= 1
     and d.unattributed_usd > v_max * d.authoritative_usd;
  if v_n > 0 then
    v_items := jsonb_build_array(jsonb_build_object('item', 'over_share', 'owner_seat', 'it_engineer', 'blast', 'internal', 'affected', v_n,
      'title', v_n || ' day(s) of the last 7 had more than ' || round(v_max * 100) || '% of OpenRouter''s meter with no ai_cost_log row (latest '
               || (v_days -> 0 ->> 'day') || ': USD ' || (v_days -> 0 ->> 'unattributed_usd') || ' of ' || (v_days -> 0 ->> 'meter_usd') || ')',
      'evidence', jsonb_build_object('days', v_days, 'threshold', v_max,
        'where_to_look', 'openrouter_day.breakdown: unpriced calls, unattributed_functions; a caller outside ai_gateway; a stream or attempt with no usage')));
  end if;
  return jsonb_build_object('days_over', v_n, 'settled', public.fn_it_duty_settle('openrouter_unattributed', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_openrouter_unattributed() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_openrouter_unattributed() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.openrouter_unattributed', 'it_engineer', interval '1 day', 'fn_it_engineer_openrouter_unattributed',
   'Finds every day of the last 7 on which more than 5% of OpenRouter''s meter had no ai_cost_log row, as one finding on the it_engineer''s own list.',
   'scripts/sql/the_it_engineer_is_told_when_openrouter_spend_has_no_ledger_row.sql')
on conflict (duty) do nothing;

-- PROBE (verdict row; reads only): the duty is registered, the threshold is set, and the routine is service-role only.
select case
  when not exists (select 1 from public.seat_duty where duty = 'it_engineer.openrouter_unattributed' and routine = 'fn_it_engineer_openrouter_unattributed')
    then 'PROBE FAILED: the duty is not registered'
  when public.fn_it_threshold('openrouter_unattributed_share_max') is null then 'PROBE FAILED: no threshold'
  when has_function_privilege('anon', 'public.fn_it_engineer_openrouter_unattributed()', 'execute')
    then 'PROBE FAILED: anon can run the duty'
  else 'PROBE OK' end as verdict;
