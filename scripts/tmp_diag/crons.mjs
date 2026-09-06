import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select jobid, jobname, schedule, active, left(command, 220) cmd from cron.job where active order by jobname`);
for (const j of r) console.log(`${j.jobid}\t${j.jobname}\t${j.schedule}\t${j.cmd.replace(/\s+/g,' ')}`);
console.log('active=' + r.length);
