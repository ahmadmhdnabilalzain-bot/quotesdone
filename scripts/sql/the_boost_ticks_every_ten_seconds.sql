-- THE BOOST TICKS EVERY TEN SECONDS (6 Sep 2026). Corrects the_embedding_crons_stop_stampeding.sql.
--
-- MEASURED two minutes after that file: job 242 ran for 35.1 s and its six kb_embed responses still
-- arrived in the same second (13:55:35Z, 13:56:35Z), with a 546 in the next minute. pg_net queues
-- net.http_post() rows inside the calling transaction and its worker sends them after COMMIT, so
-- pg_sleep() between the rows of a generate_series only delays the burst; it cannot spread it.
--
-- pg_cron here is 1.6.4, which accepts interval schedules. The boost becomes one post every ten
-- seconds — six a minute, evenly spaced, from the scheduler rather than from inside a transaction.
-- The two live schedule parsers tolerate the form: v_cron_stale falls to its 1-day default for a
-- schedule whose second field is not '*', and fn_agent_silence_watch to its 336-hour tier; neither
-- can call a job that fires every ten seconds silent. Net cadence: 108 (1) + 242 (6, spaced) +
-- 271 (1) + 315 (1) = 9 posts a minute, at most two in any one second.
--
--   node scripts/apply_sql.mjs scripts/sql/the_boost_ticks_every_ten_seconds.sql --apply --ddl

begin;

update public.phase_c_system_execution_wrapper
   set original_command = $cmd$
select net.http_post(
  url := 'https://' || (select value from public.app_secrets where key = 'project_ref') || '.supabase.co/functions/v1/kb_embed',
  headers := '{"Content-Type":"application/json"}'::jsonb,
  body := jsonb_build_object('__secret', (select value from app_secrets where key = 'cred_cron_knowledge'), 'limit', 5));
$cmd$
 where jobid = 242;

select cron.alter_job(242, schedule := '10 seconds');

update public.cron_registry
   set purpose = regexp_replace(purpose, ' 6 Sep 2026: the six posts are seven seconds apart.*$', '')
               || ' 6 Sep 2026: one post every ten seconds from the scheduler (pg_cron 1.6 interval schedule) — six a minute, never simultaneous; pg_net sends after commit, so spacing inside one transaction was impossible.'
 where jobname = 'kb_embed_backfill_boost'
   and purpose not like '%one post every ten seconds%';

do $$
declare v_sched text; v_cmd text;
begin
  select schedule into v_sched from cron.job where jobid = 242;
  select original_command into v_cmd from public.phase_c_system_execution_wrapper where jobid = 242;
  if v_sched <> '10 seconds' then raise exception 'job 242 schedule is %, expected 10 seconds', v_sched; end if;
  if v_cmd like '%generate_series%' or v_cmd like '%pg_sleep%' then raise exception 'job 242 command still bursts'; end if;
end $$;

commit;
