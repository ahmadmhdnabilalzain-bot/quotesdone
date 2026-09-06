-- THE EMBEDDING CRONS STOP STAMPEDING (6 Sep 2026). Follows the_embedding_picker_reads_a_partial_index.sql.
--
-- MEASURED 10:30-12:20Z in function_edge_logs: /functions/v1/kb_embed answered 546 WORKER_RESOURCE_LIMIT
-- 135 times (avg 3.0 s), the only function doing so. Four crons fire in the same second every minute:
-- job 108 (1 post), 242 boost (6 posts), 271 priority kinds (6 posts), 315 ops_knowledge (6 posts) =
-- 19 concurrent kb_embed workers, each loading gte-small. In the last 30 minutes 175 responses embedded
-- 5 rows and 168 answered {"done":true,"embedded":0}: jobs 271 and 315 were booting twelve workers a
-- minute for nothing — ops_knowledge has 0 rows without a vector (9,133 of 9,133 embedded) and the
-- priority kinds have 4 regulation rows left, which the FIFO backfill reaches on its own. The same
-- stampede is the select-stage statement timeouts the error ledger records at 12:49:03Z (2) and
-- 13:49:03Z (6): six claims in the same second under a busy minute.
--
-- Now: 242 keeps six posts a minute but seven seconds apart (pg_sleep between rows of the series, so
-- the pg_net worker sends them spaced); 271 and 315 drop to one post a minute each, which is a
-- cheap no-op once their sets are drained and still drains anything new. 1 + 6 + 1 + 1 = 9 posts a
-- minute, never more than two in the same second. The wrapper rows are the kernel's record of what a
-- cron does (fn_kernel_cron_exec executes original_command); the cron.job commands are unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/the_embedding_crons_stop_stampeding.sql --apply --ddl

begin;

update public.phase_c_system_execution_wrapper
   set original_command = $cmd$
select net.http_post(
  url := 'https://' || (select value from public.app_secrets where key = 'project_ref') || '.supabase.co/functions/v1/kb_embed',
  headers := '{"Content-Type":"application/json"}'::jsonb,
  body := jsonb_build_object('__secret', (select value from app_secrets where key = 'cred_cron_knowledge'), 'limit', 5)),
  pg_sleep(case when g < 6 then 7 else 0 end)
  from generate_series(1, 6) g;
$cmd$
 where jobid = 242;

update public.phase_c_system_execution_wrapper
   set original_command = $cmd$
select net.http_post(
  url := 'https://' || (select value from app_secrets where key = 'project_ref') || '.supabase.co/functions/v1/kb_embed',
  headers := '{"Content-Type":"application/json"}'::jsonb,
  body := jsonb_build_object('__secret', (select value from app_secrets where key = 'cred_cron_knowledge'), 'limit', 5, 'source_kinds', jsonb_build_array('company_faq','trade','regulation','material')));
$cmd$
 where jobid = 271;

update public.phase_c_system_execution_wrapper
   set original_command = $cmd$
select net.http_post(
  url := 'https://' || (select value from public.app_secrets where key = 'project_ref') || '.supabase.co/functions/v1/kb_embed',
  headers := '{"Content-Type":"application/json"}'::jsonb,
  body := jsonb_build_object('__secret', (select value from app_secrets where key = 'cred_cron_knowledge'), 'target', 'ops_knowledge', 'limit', 8));
$cmd$
 where jobid = 315;

update public.cron_registry
   set purpose = purpose || ' 6 Sep 2026: one post a minute (was six in the same second) — the set is drained; kept as a cheap no-op that still catches new rows.'
 where jobname in ('kb_embed_priority_kinds', 'kb_embed_ops_knowledge')
   and purpose not like '%6 Sep 2026: one post a minute%';

update public.cron_registry
   set purpose = purpose || ' 6 Sep 2026: the six posts are seven seconds apart, not simultaneous (WORKER_RESOURCE_LIMIT 135 times in 110 minutes when nineteen workers booted at once).'
 where jobname = 'kb_embed_backfill_boost'
   and purpose not like '%seven seconds apart%';

-- proof: the three wrapper rows carry the new commands
do $$
declare n int;
begin
  select count(*) into n from public.phase_c_system_execution_wrapper
   where (jobid = 242 and original_command like '%pg_sleep(case when g < 6 then 7 else 0 end)%')
      or (jobid in (271, 315) and original_command not like '%generate_series%');
  if n <> 3 then raise exception 'expected 3 rewritten wrapper rows, found %', n; end if;
end $$;

commit;
