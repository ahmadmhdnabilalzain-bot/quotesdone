-- THE BOOST EMBEDS THREE AT A TIME (6 Sep 2026). Follows the_boost_ticks_every_ten_seconds.sql.
--
-- MEASURED after the ten-second schedule: the posts are spaced (14:00:25, :35, :45, :55 ...) and
-- SINGLE calls still answer 546 — 10 in five minutes. function_edge_logs 13:00-14:05Z for
-- /functions/v1/kb_embed: 200 × 1,001 (p50 2.3 s wall, p90 8.6 s: the long ones wait on the
-- database, not the CPU), 546 × 52 (p50 2.95 s, p90 3.3 s, max 5.6 s). The 546 is not concurrency:
-- it is the edge runtime's CPU budget per request, which a call that embeds five chunks with
-- gte-small crosses about one time in twenty, at ~3 s of wall. The registry already recorded that
-- a batch of 8 "returns HTTP 546 on this edge worker"; 5 is the same wall, met less often.
--
-- Three chunks per call, a tick every six seconds: 3 × 10 + 5 (job 108) = 35 rows a minute offered.
-- cron_history_prune keeps 14 days of job_run_details; 14,400 rows a day for this job is within
-- what the table already holds (255k).
--
-- MEASURED five minutes after applying: 57 × 200 and 3 × 546 in five minutes, 168 rows embedded
-- (34 a minute, against ~31 before), job 242 20 runs in two minutes, 0 failed. The 546 share is
-- still one call in twenty (it was 52 of 1,053 at five chunks, 3 of 60 at three), so it is not the
-- batch size either: the edge isolate is retired once its cumulative CPU quota is spent and the
-- request in flight is the one that answers 546. Its rows are re-claimed after the three-minute
-- claim window. That is the runtime's cost of embedding on the edge, not a defect to chase further;
-- this file stands for the lower absolute loss (3 a five-minute window instead of 10) and the
-- higher throughput.
--
--   node scripts/apply_sql.mjs scripts/sql/the_boost_embeds_three_at_a_time.sql --apply --ddl

begin;

update public.phase_c_system_execution_wrapper
   set original_command = $cmd$
select net.http_post(
  url := 'https://' || (select value from public.app_secrets where key = 'project_ref') || '.supabase.co/functions/v1/kb_embed',
  headers := '{"Content-Type":"application/json"}'::jsonb,
  body := jsonb_build_object('__secret', (select value from app_secrets where key = 'cred_cron_knowledge'), 'limit', 3));
$cmd$
 where jobid = 242;

select cron.alter_job(242, schedule := '6 seconds');

update public.cron_registry
   set purpose = regexp_replace(purpose, ' 6 Sep 2026: one post every ten seconds.*$', '')
               || ' 6 Sep 2026: one post of three chunks every six seconds — five chunks crossed the edge CPU budget (546) one call in twenty; three stays under it at the same offered throughput.'
 where jobname = 'kb_embed_backfill_boost'
   and purpose not like '%three chunks every six seconds%';

do $$
declare v_sched text; v_cmd text;
begin
  select schedule into v_sched from cron.job where jobid = 242;
  select original_command into v_cmd from public.phase_c_system_execution_wrapper where jobid = 242;
  if v_sched <> '6 seconds' then raise exception 'job 242 schedule is %, expected 6 seconds', v_sched; end if;
  if v_cmd not like '%''limit'', 3)%' then raise exception 'job 242 command does not carry limit 3'; end if;
end $$;

commit;
