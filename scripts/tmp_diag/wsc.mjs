import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);const r=await sql(t);console.log(JSON.stringify(r).slice(0,2600));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,250)}`)}};
await q('claim sig+body', `select pg_get_function_identity_arguments(p.oid) args, p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_workflow_step_claim'`);
await q('workflow_run cols', `select column_name, is_nullable, column_default is not null d from information_schema.columns where table_schema='public' and table_name='workflow_run' order by ordinal_position`);
await q('workflow_step_run cols', `select column_name, is_nullable, column_default is not null d from information_schema.columns where table_schema='public' and table_name='workflow_step_run' order by ordinal_position`);
await q('counts', `select (select count(*) from public.workflow_run) wr, (select count(*) from public.workflow_step_run) wsr`);
