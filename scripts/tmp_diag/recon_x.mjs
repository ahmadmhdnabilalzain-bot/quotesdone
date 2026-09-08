import { sql } from '../lib/db.mjs';
const r = await sql(`select p.oid::regprocedure::text sig, length(pg_get_functiondef(p.oid)) len, right(pg_get_functiondef(p.oid), 900) tail from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('fn_phase_d_drive_workflow','fn_phase_d_test_context_open') order by 1`);
for (const x of r) console.log('\n==== '+x.sig+' len='+x.len+'\n'+x.tail);
