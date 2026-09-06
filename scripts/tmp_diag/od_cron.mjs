import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select jobid, jobname, schedule, active, command from cron.job order by jobid`);
console.log('TOTAL', r.length, 'ACTIVE', r.filter(x => x.active === true || x.active === 't').length);
for (const x of r) console.log([x.jobid, x.active, x.schedule, x.jobname, String(x.command).replace(/\s+/g, ' ').slice(0, 300)].join('\t'));
