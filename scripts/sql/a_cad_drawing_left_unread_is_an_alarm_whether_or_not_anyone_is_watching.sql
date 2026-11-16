-- A CAD DRAWING LEFT UNREAD IS AN ALARM, WHETHER OR NOT ANYONE IS WATCHING (it_engineer for sales_engineer, 16 Nov 2026).
-- Founder ledgers 31 (the sales engineer reads every drawing format) and 1443 (recurring work off the Claude subscription).
-- Agent: L7_JOBS.
--
-- MEASURED (production SELECT, 16 Nov 2026 19:20Z): a DWG past the edge's ceiling is queued in public.cad_read_jobs and read
-- by scripts/cad_read_worker.ts, which runs ONLY as the Claude scheduled task "QuotesDone — CAD read worker" every 2 h on the
-- founder's subscription (docs/runbooks/release-without-ci.md 3b; 12 runs a day, each a no-op today: cad_read_jobs holds
-- 2 rows ever, 1 done 29 Sep, 1 failed 14 Oct). It cannot run in an edge function: a CPU kill ends the worker with no catch
-- and the cost of a DWG is not its size (cad_read_worker.ts header: 562 KB took 1.9 s of the edge's 2 s CPU). The only alarm
-- today is customer_api's cadReadHeld, raised while the customer's screen POLLS the job; a job whose customer closed the
-- page, or a routine that stopped, is silent: fn_claude_routine_outcomes judges no CAD run ("their silence is not a failure").
--
-- THE CHANGE: the duty sales_engineer.cad_read_wait (every 15 minutes) raises the finding duty:cad_read_wait:<job> for every
-- job still queued or running 135 minutes after it was queued (the reader's 2-hour interval + its :15 start), and for every
-- job the reader failed in the last 7 days, naming where the reader runs; it clears when the job is done. So when the Claude
-- task is retired before a company runner replaces it, the first unread drawing is a finding, not a customer left waiting.
-- Revoked from public, anon, authenticated; search_path pinned. No table. No deploy.
-- prevented by: scripts/sql/a_cad_drawing_left_unread_is_an_alarm_whether_or_not_anyone_is_watching_probe.sql (local), and the verdict row below.
set local lock_timeout = '3s';

create or replace function public.fn_sales_engineer_cad_read_wait()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', j.id::text, 'owner_seat', 'sales_engineer', 'subject', 'cad_read',
           'demo', coalesce(public.fn_is_demo_email(j.owner_email), false),
           'title', case when j.status = 'failed'
                         then 'A CAD drawing could not be read by the CAD reader (' || coalesce(left(j.error, 160), 'no reason') || ')'
                         else 'A CAD drawing has waited ' || floor(extract(epoch from now() - j.created_at) / 3600)::int
                              || ' h for the CAD reader (status ' || j.status || ', ' || j.attempts || ' attempt(s))' end,
           'evidence', jsonb_build_object('job', j.id, 'status', j.status, 'why', j.why, 'queued_at', j.created_at, 'attempts', j.attempts,
             'reader', 'scripts/cad_read_worker.ts runs outside the company (the Claude scheduled task "QuotesDone — CAD read worker", every 2 h); '
                       || 'an edge function cannot run it (2 s CPU cap)')) order by j.created_at), '[]'::jsonb)
    into v_items
    from public.cad_read_jobs j
   where (j.status in ('queued', 'running') and j.created_at < now() - interval '135 minutes')
      or (j.status = 'failed' and coalesce(j.finished_at, j.created_at) > now() - interval '7 days');
  return jsonb_build_object('waiting', jsonb_array_length(v_items), 'settle', public.fn_it_duty_settle('cad_read_wait', v_items));
end $fn$;
revoke execute on function public.fn_sales_engineer_cad_read_wait() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.cad_read_wait', 'sales_engineer', interval '15 minutes', 'fn_sales_engineer_cad_read_wait',
   'Every 15 minutes: a CAD drawing still unread 135 minutes after it was queued, or failed by the CAD reader in the last 7 days, is a finding '
   || '(duty:cad_read_wait:<job>) whether or not the customer''s screen is polling it; it clears when the job is done.',
   'scripts/sql/a_cad_drawing_left_unread_is_an_alarm_whether_or_not_anyone_is_watching.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

select case
  when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'fn_sales_engineer_cad_read_wait' and p.prosecdef
           and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
           and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')) <> 1
    then 'PROBE FAILED: the routine is missing, open or unpinned'
  when not exists (select 1 from public.seat_duty where duty = 'sales_engineer.cad_read_wait' and enabled and every = interval '15 minutes')
    then 'PROBE FAILED: the duty is not registered'
  else 'PROBE OK' end as verdict;
