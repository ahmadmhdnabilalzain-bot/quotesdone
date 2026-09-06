import { sql } from '../phase_b/lib/db.mjs';
const q = async (label, s) => { try { console.log('\n=== '+label); console.log(JSON.stringify(await sql(s), null, 1)); } catch(e){ console.log('\n=== '+label+' ERROR '+e.message); } };
await q('sealed_at columns anywhere', `
select table_schema, table_name, column_name, data_type
from information_schema.columns where column_name in ('sealed_at','sealed_by','sealed')
order by 1,2,3`);
await q('terms acceptance tables', `
select c.relname, c.relkind from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname ilike '%acceptance%' or (n.nspname='public' and c.relname ilike '%terms%') order by 1`);
await q('function bodies (short)', `
select p.proname, p.prosecdef, pg_get_functiondef(p.oid) as def
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
 'fn_phase_c_require_founder','fn_phase_c_refund_decision_immutable','fn_refund_founder_decision_only',
 'fn_phase_c_founder_identity_human_only','fn_phase_c_refund_decision_guard','fn_phase_c_founder_approval_immutable')
order by 1`);
