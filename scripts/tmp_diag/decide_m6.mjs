import { sql } from '../phase_b/lib/db.mjs';
const q = async (label, s) => { try { const r = await sql(s); console.log('=== ' + label); console.log(JSON.stringify(r).slice(0, 9000)); } catch(e){ console.log('=== '+label+' ERR '+String(e).slice(0,600)); } };

await q('quotes policies', `select polname, polcmd, pg_get_expr(polqual, polrelid) as using_x, pg_get_expr(polwithcheck, polrelid) as check_x, (select array_agg(rolname) from pg_roles where oid = any(polroles)) roles
 from pg_policy where polrelid='public.quotes'::regclass`);
await q('quotes rls on', `select relrowsecurity, relforcerowsecurity from pg_class where oid='public.quotes'::regclass`);
await q('quotes cols', `select column_name,is_nullable,data_type from information_schema.columns where table_schema='public' and table_name='quotes' order by ordinal_position`);
await q('phase_c_refund_decision cols', `select column_name,is_nullable,data_type from information_schema.columns where table_schema='public' and table_name='phase_c_refund_decision' order by ordinal_position`);
await q('phase_c_refund_decision constraints', `select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid='public.phase_c_refund_decision'::regclass`);
await q('phase_c_refund_decision triggers', `select tgname, pg_get_triggerdef(oid) from pg_trigger where tgrelid='public.phase_c_refund_decision'::regclass and not tgisinternal`);
await q('phase_c_refund_decision rowcount', `select count(*) from public.phase_c_refund_decision`);
