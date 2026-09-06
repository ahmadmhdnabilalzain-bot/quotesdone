-- THE EMBEDDING BACKFILL RUNS AGAIN, UNDER THE KERNEL (6 Sep 2026). Knowledge audit company_wide.md §3c, action #3.
--
-- MEASURED: kb_chunks ~2.65M rows (pg_class.reltuples 2,649,590), pg_stats null_frac(embedding_gte)
-- 0.9588 -> ~2.54M chunks with no embedding. Sampled id ranges 600k-2.62M: 0 embedded. The three
-- backfill jobs (108 kb_embed_backfill, 242 kb_embed_backfill_boost, 271 kb_embed_priority_kinds) were
-- active = false since the stand-down; the vector half of kb_search therefore saw only the first ~120k
-- ids. kb_embed itself logged 28 errors in 7 days: its end-of-run `count(*) ... embedding_gte is null`
-- is an exact count over 2.65M rows and hits the 8 s statement wall every time, after which the
-- function reported "done" over a backlog it had not measured.
--
-- THE FIX. (1) fn_kb_embed_backlog(): the backlog as planner statistics (reltuples x null_frac, with the
-- analyze timestamp that dates them) plus ONE index-bounded read - min(created_at) of an unembedded
-- chunk, the frontier the oldest-first picker is at (measured 0.77 s). Never a scan. kb_embed reads
-- this (edge change in the same commit) instead of counting. (2) The three jobs are wrapped by
-- fn_kernel_wrap_and_enable_cron under knowledge_director / data_intel, the same owner as
-- kb_embed_ops_knowledge (315), and registered in cron_registry and phase_d_committed_scenario_cron.
-- (3) Each is run once through fn_kernel_cron_exec so a trace exists before the first tick.
--
-- RATE. The embedder is the free in-region gte-small; the measured ceiling is 5 chunks per invocation
-- (8 returns HTTP 546). 108 posts once a minute, 242 six times, 271 six times but only for the finite
-- trade/regulation/material set and is a no-op once that is drained: <= 65 chunks/min requested,
-- ~1,200-2,000/hour delivered in the last measured run. No paid model is involved anywhere on this path.
--
-- PROOF of "falling": the frontier window - chunks created in the 2 h after the frontier and now
-- embedded - is measured twice 15 minutes apart in the commit message, beside llm_attempt (unchanged).
--   node scripts/apply_sql.mjs scripts/sql/the_embedding_backfill_runs_again_under_the_kernel.sql --apply --ddl

begin;

create or replace function public.fn_kb_embed_backlog()
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    'estimated_unembedded', (select round(c.reltuples * coalesce(s.null_frac, 0))::bigint
                               from pg_class c
                               left join pg_stats s on s.schemaname = 'public' and s.tablename = 'kb_chunks' and s.attname = 'embedding_gte'
                              where c.oid = 'public.kb_chunks'::regclass),
    'estimated_total', (select reltuples::bigint from pg_class where oid = 'public.kb_chunks'::regclass),
    'stats_as_of', (select greatest(last_analyze, last_autoanalyze) from pg_stat_user_tables where schemaname = 'public' and relname = 'kb_chunks'),
    'frontier_created_at', (select min(created_at) from public.kb_chunks where embedding_gte is null),
    'measured_at', now());
$function$;

revoke execute on function public.fn_kb_embed_backlog() from public, anon, authenticated;
grant execute on function public.fn_kb_embed_backlog() to service_role;

do $cron$
declare j record; v jsonb;
begin
  for j in select * from (values
      (108::bigint, 'kb_embed_backfill'),
      (242::bigint, 'kb_embed_backfill_boost'),
      (271::bigint, 'kb_embed_priority_kinds')) v(jobid, jobname)
  loop
    if not exists (select 1 from cron.job c where c.jobid = j.jobid and c.jobname = j.jobname) then
      raise exception 'cron job % is not % on this project; refusing to wrap the wrong job', j.jobid, j.jobname;
    end if;
    v := public.fn_kernel_wrap_and_enable_cron(j.jobid, 'knowledge_director', 'data_intel', 'routine_operational_decision');
    if coalesce((v->>'ok')::boolean, false) is not true then
      raise exception 'fn_kernel_wrap_and_enable_cron(%) refused: %', j.jobid, v;
    end if;
  end loop;

  insert into public.cron_registry (jobname, human_name, category, purpose) values
    ('kb_embed_backfill', 'Knowledge embedding backfill', 'knowledge',
     'Every minute: one kb_embed invocation at the safe batch of 5, oldest unembedded kb_chunks first (fair FIFO). Free in-region gte-small; no paid model. Re-enabled under the kernel 6 Sep 2026 after the stand-down left ~2.54M of 2.65M chunks without an embedding.')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (108, 'kb_embed_backfill',
     'POSTs to the kb_embed edge function through pg_net; the function UPDATEs public.kb_chunks.embedding_gte (oldest unembedded first) and INSERTs throttled progress rows into public.agent_runs. Reads nothing a scenario writes.',
     'kb_chunks and agent_runs are not scenario relations and carry no ZZ DEMO marker; a rehearsal creates no chunk. close() asserts scenario rows by id/marker.'),
    (242, 'kb_embed_backfill_boost',
     'Six POSTs a minute to the kb_embed edge function through pg_net; same writes as kb_embed_backfill (kb_chunks.embedding_gte, agent_runs progress rows). Reads nothing a scenario writes.',
     'kb_chunks and agent_runs are not scenario relations and carry no ZZ DEMO marker; a rehearsal creates no chunk.'),
    (271, 'kb_embed_priority_kinds',
     'Six POSTs a minute to kb_embed filtered to source_kind trade/regulation/material/company_faq; UPDATEs kb_chunks.embedding_gte for that finite set and INSERTs agent_runs progress rows. No-op once the set is drained.',
     'kb_chunks and agent_runs are not scenario relations and carry no ZZ DEMO marker; a rehearsal creates no chunk.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $cron$;

-- PROOF, in-file: the three jobs are wrapped and active, and one traced execution of each exists.
do $proof$
declare j bigint; t bigint; v_res text; n int;
begin
  foreach j in array array[108, 242, 271]::bigint[] loop
    select count(*) into n from cron.job c where c.jobid = j and c.active and c.command ilike '%fn_kernel_cron_exec%';
    if n <> 1 then raise exception 'cron job % is not wrapped and active after the wrap', j; end if;
    t := public.fn_kernel_cron_exec(j);
    select result into v_res from public.phase_c_system_execution where trace_id = t;
    if v_res is distinct from 'succeeded' then raise exception 'first traced run of cron % ended %', j, v_res; end if;
  end loop;
end $proof$;

commit;
