import { sql } from '../phase_b/lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,6000));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,400));}};
await q('compliance steps', `select step_id, step_name, actor_role from public.phase_b_workflow_step where step_name ~* 'complian' or actor_role ~* 'complian' limit 20`);
await q('compliance roles', `select role_id from public.org_role where role_id ~* 'complian' limit 20`);
await q('phase_c_task cols', `select column_name, is_nullable, column_default, data_type from information_schema.columns where table_schema='public' and table_name='phase_c_task' order by ordinal_position`);
await q('phase_c_task triggers', `select tgname, tgfoid::regproc::text f from pg_trigger where tgrelid='public.phase_c_task'::regclass and not tgisinternal order by tgname`);
await q('external_deliver pii', `select (p.prosrc ~* 'br-011|br011|customer identity|pii') hit, length(p.prosrc) len from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_external_deliver'`);
await q('schema_validate sig', `select pg_get_function_identity_arguments(p.oid) a, pg_get_function_result(p.oid) r from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_schema_validate'`);
