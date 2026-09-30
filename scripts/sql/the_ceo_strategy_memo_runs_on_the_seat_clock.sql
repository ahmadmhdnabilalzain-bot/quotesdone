-- THE CEO'S MONTHLY STRATEGY MEMO RUNS ON THE SEAT CLOCK, NOT ON PG_CRON (30 Sep 2026). Seat: it_engineer (the
-- scheduling); the duty is the ceo's.
--
-- MEASURED on production, 30 Sep 2026 00:47Z (ledger reconciliation, finding F12):
--   * cron.job held ONE job: 354 'ceo-strategy-memo-monthly', '0 2 2 * *', select public.fn_ceo_strategy_memo(),
--     scheduled by scripts/sql/the_ceo_writes_a_one_page_strategy_memo_every_month.sql (29 Sep). Its first run would be
--     2 Oct 2026, 06:00 Dubai.
--   * cron.job_run_details: newest row 7 Sep 2026 17:51Z (jobs 242, 255, 278, since unscheduled). So "no run since 7 Sep"
--     is not a dead scheduler: from 7 Sep until job 354 no job was scheduled at all, and 354 has not yet come due.
--   * pg_stat_activity: the 'pg_cron launcher' background worker is up (backend_start 21 Sep 2026 17:44Z, the last
--     restart); cron.database_name = postgres.
--   * public.seat_duty (83 duties, run by fn_seat_duties_tick) is the clock every seat's work runs on; the CEO already
--     has 18 duties there. The memo was the only piece of seat work outside it, with nobody watching it: a pg_cron job
--     that fails or never fires raises no finding, while fn_seat_duty_health files one for any overdue or failing duty.
--
-- THE FIX. One duty, ceo.strategy_memo, every day on the seat clock, calling fn_ceo_strategy_memo_now(): it writes the
-- memo for the month that has ended once the 2nd (Dubai) has come, and on every later day finds it already written
-- (fn_ceo_strategy_memo returns 'already' for a month on file). So the cadence stays monthly - one memo a month, on the
-- 2nd - and a missed day is caught up the next day instead of waiting a month. The first memo is September 2026's, as
-- it would have been under pg_cron: an August memo is never written late. The pg_cron job is unscheduled, so nothing
-- the seats do depends on pg_cron (cron.job is empty after this file), and the writer_seat row that named the job goes.
--
-- prevented by: scripts/checks/the_ceo_strategy_memo_runs_on_the_seat_clock.test.mjs

create or replace function public.fn_ceo_strategy_memo_now(p_today date default null, p_first_month date default date '2026-09-01')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Dubai')::date);
  v_month date := date_trunc('month', v_today - interval '1 month')::date;
begin
  if extract(day from v_today) < 2 then
    return jsonb_build_object('due', false, 'reason', 'the memo is written from the 2nd (Dubai) for the month that ended', 'today', v_today);
  end if;
  -- the first month the memo exists for: pg_cron would first have fired on 2 Oct 2026, for September. A parameter only
  -- so the check can drive the write path in an aborted transaction before October; the duty never passes it.
  if v_month < date_trunc('month', p_first_month)::date then
    return jsonb_build_object('due', false, 'reason', 'the first memo is for September 2026', 'month', to_char(v_month, 'YYYY-MM'));
  end if;
  return jsonb_build_object('due', true) || public.fn_ceo_strategy_memo(v_month, false);
end
$fn$;
revoke execute on function public.fn_ceo_strategy_memo_now(date, date) from public, anon, authenticated;
grant execute on function public.fn_ceo_strategy_memo_now(date, date) to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled)
values ('ceo.strategy_memo', 'ceo', interval '1 day', 'fn_ceo_strategy_memo_now',
        'The one-page monthly strategy memo (instruction 1013): written once a month from the 2nd (Dubai) for the month that ended; every other day it is found already written.',
        'scripts/sql/the_ceo_strategy_memo_runs_on_the_seat_clock.sql', true)
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file, enabled = true;

select cron.unschedule(jobid) from cron.job where jobname = 'ceo-strategy-memo-monthly';
delete from public.writer_seat where kind = 'cron_job' and name = 'ceo-strategy-memo-monthly';

select case
  when exists (select 1 from cron.job where jobname = 'ceo-strategy-memo-monthly') then 'PROBE FAILED: the pg_cron job is still scheduled'
  when not exists (select 1 from public.seat_duty where duty = 'ceo.strategy_memo' and enabled and public.fn_seat_duty_routine_exists(routine))
    then 'PROBE FAILED: the duty is not registered or its routine is not callable'
  when (public.fn_ceo_strategy_memo_now(date '2026-10-01')->>'due')::boolean then 'PROBE FAILED: due before the 2nd'
  when (public.fn_ceo_strategy_memo_now(date '2026-09-30')->>'due')::boolean then 'PROBE FAILED: an August memo would be written late'
  else 'PROBE OK' end as verdict;
