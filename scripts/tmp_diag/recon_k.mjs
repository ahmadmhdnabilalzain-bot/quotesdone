import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{console.log('\n=== '+l);console.log(JSON.stringify(await sql(s),null,1));}catch(e){console.log('\n=== '+l+' ERR '+e.message);}};
await q('bindings of interest', `
select object_id, policy_family, canonical_relation, relation_kind, canonical_write_service, versioning, record_policy
from public.phase_d_business_object_binding
where object_id in ('customer_terms_acceptance','quotation_revision','supplier_assignment','notification','inquiry','quotation','review_verdict','founder_refund_decision')
order by 1`);
await q('tables named like review/verdict/completion', `select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and (c.relname ilike '%verdict%' or c.relname like 'phase_c_%review%' or c.relname like '%step_completion%') order by 1`);
await q('fn_kernel_step_successor def', `select pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_kernel_step_successor'`);
