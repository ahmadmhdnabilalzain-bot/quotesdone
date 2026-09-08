import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{console.log('\n=== '+l);console.log(JSON.stringify(await sql(s),null,1));}catch(e){console.log('\n=== '+l+' ERR '+e.message);}};
await q('phase_d bindings for the subjects of these defects', `
select object_id, policy_family, table_name, coalesce(write_routine,'') as write_routine
from public.phase_d_business_object_binding
where object_id in ('customer_terms_acceptance','quotation_revision','supplier_assignment','notification','inquiry','quotation')
order by 1`);
await q('binding columns', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_d_business_object_binding' order by ordinal_position`);
await q('kernel review verdict table', `select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and (c.relname ilike '%verdict%' or c.relname ilike 'phase_c_review%' or c.relname ilike '%step_completion%') order by 1`);
