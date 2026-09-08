import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t)).slice(0,1800));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,250)}`)}};
await q('routines with for update over leads/tasks', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc ~* 'for update' and (p.prosrc ~* 'public\.leads|from leads' ) order by 1`);
await q('claim-ish routines', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname ~* 'claim' order by 1`);
await q('trace rows without a system execution', `select count(*) n from public.phase_c_trace t where not exists (select 1 from public.phase_c_system_execution e where e.trace_id=t.trace_id)`);
