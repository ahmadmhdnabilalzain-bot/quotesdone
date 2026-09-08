import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);const r=await sql(t);console.log(JSON.stringify(r,null,1).slice(0,4000));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,400)}`)}};
await q('outbox constraints', `select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid='public.phase_c_event_outbox'::regclass`);
await q('outbox status distribution', `select status, count(*) from public.phase_c_event_outbox group by 1 order by 2 desc`);
await q('outbox cols', `select column_name, data_type, is_nullable, column_default from information_schema.columns where table_schema='public' and table_name='phase_c_event_outbox' order by ordinal_position`);
await q('quarantine refs', `select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (prosrc ilike '%quarantin%') limit 20`);
