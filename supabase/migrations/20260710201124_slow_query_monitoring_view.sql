-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710201124   name: slow_query_monitoring_view
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace view public.v_slow_queries as
select queryid,
       calls,
       round(total_exec_time::numeric, 1) as total_ms,
       round(mean_exec_time::numeric, 2)  as mean_ms,
       round(max_exec_time::numeric, 2)   as max_ms,
       rows,
       left(query, 240) as query
from extensions.pg_stat_statements
where calls > 1
order by mean_exec_time desc
limit 50;
revoke all on public.v_slow_queries from anon, authenticated;
