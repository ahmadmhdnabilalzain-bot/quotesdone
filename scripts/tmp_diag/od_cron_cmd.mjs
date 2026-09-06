import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`
select j.jobid, j.jobname, j.schedule, w.component_id, replace(w.original_command, E'\\n', ' ') as cmd
  from cron.job j
  left join public.phase_c_system_execution_wrapper w on w.jobid = j.jobid
 where j.active
 order by j.jobid`);
for (const x of r) console.log([x.jobid, x.jobname, x.schedule, x.component_id, String(x.cmd || '').replace(/\s+/g, ' ').slice(0, 400)].join(' | '));
