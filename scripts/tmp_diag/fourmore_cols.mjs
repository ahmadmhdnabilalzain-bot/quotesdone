import { sql } from '../lib/db.mjs';
const r = await sql(`select table_name, string_agg(column_name, ', ' order by ordinal_position) cols
 from information_schema.columns where table_schema='public'
 and table_name in ('leads','supplier_accounts','inquiries','notifications')
 group by table_name order by table_name`);
for (const x of r) console.log('\n== '+x.table_name+'\n'+x.cols);
const b = await sql(`select object_id, policy_family, record_policy, ownership_scope, storage_kind, target_relation
 from public.phase_d_business_object_binding where object_id in ('customer_terms_acceptance','supplier_account','inquiry','customer_account')`);
console.log('\n== bindings\n'+JSON.stringify(b,null,1));
