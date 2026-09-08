import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);const r=await sql(t);console.log(JSON.stringify(r,null,1).slice(0,6000));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,500)}`)}};
await q('phase C frozen subjects', `select subject_kind, subject_name from public.phase_c_freeze_subject order by 1,2`);
await q('who writes outbox', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc ilike '%phase_c_event_outbox%' and p.prosrc ~* 'insert into[[:space:]]+public\.phase_c_event_outbox|insert into[[:space:]]+phase_c_event_outbox' order by 1`);
