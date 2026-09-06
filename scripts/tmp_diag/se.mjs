import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);const r=await sql(t);console.log(JSON.stringify(r).slice(0,2200));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,300)}`)}};
await q('append only body', `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='fn_phase_c_system_execution_append_only'`);
await q('triggers on phase_c_system_execution', `select tgname, pg_get_triggerdef(oid) from pg_trigger where tgrelid='public.phase_c_system_execution'::regclass and not tgisinternal`);
await q('fk', `select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid='public.phase_c_system_execution'::regclass and contype='f'`);
await q('counts', `select (select count(*) from public.phase_c_system_execution) se, (select count(*) from public.phase_c_trace) tr`);
