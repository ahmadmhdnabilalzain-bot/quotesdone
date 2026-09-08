import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,3000));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,300));}};
await q('self loops', `select count(*) n from public.phase_b_event where emitted_by = primary_consumer_role_id`);
await q('event total', `select count(*) from public.phase_b_event`);
await q('outbox cron', `select jobname, schedule, active, left(command,90) c from cron.job where command ~* 'outbox' `);
await q('read only trace exemption', `select p.proname, substring(p.prosrc from '.{0,110}read[_ ]only.{0,80}') f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc ~* 'read[_ ]only' and p.proname ~* 'trace|kernel' limit 6`);
await q('trace policy table', `select table_name from information_schema.tables where table_schema='public' and table_name ~* 'trace_polic'`);
