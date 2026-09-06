import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select * from public.phase_d_business_object_binding where object_id in ('supplier_assignment','customer_terms_acceptance','inquiry','supplier_account','quotation')`),null,1));
console.log('--- distinct approval_status ---');
console.log(JSON.stringify(await sql(`select approval_status, count(*) from public.leads group by 1 order by 2 desc limit 15`)));
console.log('--- leads check constraints ---');
console.log(JSON.stringify(await sql(`select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid='public.leads'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%approval_status%'`),null,1));
