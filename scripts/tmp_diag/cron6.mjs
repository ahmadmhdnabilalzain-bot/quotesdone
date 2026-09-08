import { sql } from '../lib/db.mjs';
const r = await sql(`
with resolved as (
  select j.jobid, j.jobname,
         coalesce((select w.original_command from public.phase_c_system_execution_wrapper w
                    where j.command like '%fn_kernel_cron_exec(' || w.jobid || ')%' limit 1), j.command) as cmd
    from cron.job j where j.active and j.jobid in (214,213,172,179,92,215))
select r.jobid, r.jobname, left(r.cmd,90) cmd,
       (select string_agg(distinct p.proname||' -> '||t.relation, '; ')
          from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          join public.phase_d_committed_scenario_watch t on p.prosrc like '%'||replace(t.relation,'public.','')||'%'
         where n.nspname='public' and r.cmd like '%'||p.proname||'(%') hits
  from resolved r order by r.jobid`);
for (const x of r) console.log(`\n${x.jobid} ${x.jobname}\n  cmd: ${x.cmd}\n  hits: ${x.hits}`);
