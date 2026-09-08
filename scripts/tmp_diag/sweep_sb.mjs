import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t)).slice(0,900));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,200)}`)}};
await q('cron failures last 24h', `select j.jobname, count(*) n from cron.job_run_details d join cron.job j on j.jobid=d.jobid where d.start_time > now() - interval '24 hours' and d.status <> 'succeeded' group by 1 order by 2 desc limit 10`);
await q('agent_runs errors 24h', `select agent, count(*) n from public.agent_runs where started_at > now() - interval '24 hours' and status='error' group by 1 order by 2 desc limit 10`);
await q('dead_letter 24h', `select count(*) n from public.dead_letter where created_at > now() - interval '24 hours'`);
await q('doc_backups failing', `select status, count(*) n from public.doc_backups group by 1`);
