import { sql } from '../lib/db.mjs';
const q = async (label, text) => {
  try { const r = await sql(text); console.log(`\n### ${label}`); console.log(JSON.stringify(r).slice(0, 3000)); }
  catch (e) { console.log(`\n### ${label}\nERROR ${String(e.message).slice(0,600)}`); }
};
await q('now', `select now() at time zone 'utc' as utc_now`);
await q('phase A drift', `select count(*) n from public.fn_phase_a_baseline_drift()`);
await q('phase B drift', `select count(*) n from public.fn_phase_b_baseline_drift()`);
await q('phase C freeze', `select * from public.fn_phase_c_freeze_drift()`);
await q('fixture residue', `select public.fn_phase_d_fixture_residue() as residue`);
await q('llm_attempt', `select count(*) n from public.llm_attempt`);
await q('ai_cost today', `select count(*) n, coalesce(sum(cost_usd),0) usd from public.ai_cost_log where created_at >= current_date`);
await q('cron active', `select count(*) filter (where active) active, count(*) total from cron.job`);
await q('outcome_evaluate_daily', `select jobid, jobname, schedule, active from cron.job where jobname like '%outcome_evaluate%'`);
await q('net queue', `select count(*) n from net.http_request_queue`);
await q('business counts', `select (select count(*) from public.inquiries) inquiries, (select count(*) from public.customers) customers, (select count(*) from public.quotes) quotes, (select count(*) from public.transactions) transactions, (select count(*) from public.leads) leads, (select count(*) from public.documents) documents, (select count(*) from public.doc_backups) doc_backups, (select count(*) from public.company_event) company_event, (select count(*) from public.notifications) notifications`);
await q('phase_d tables', `select table_name from information_schema.tables where table_schema='public' and table_name like 'phase_d%' order by 1`);
await q('outbound door', `select * from public.phase_d_outbound_door limit 50`);
