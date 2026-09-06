import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select c.relname tbl, t.tgname, p.proname, pg_get_triggerdef(t.oid) def
from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid
where not t.tgisinternal and n.nspname='public' and c.relname='inquiries' order by 2`);
console.log(r.map(x=>x.tgname+'  ->  '+x.proname+'   ['+x.def.replace(/^.*?(BEFORE|AFTER)/,'$1').slice(0,90)+']').join('\n'));
const s = await sql(`select column_name from information_schema.columns where table_schema='public' and table_name='inquiries' and column_name in ('status','rfq_ready','customer_email','email','customer_id')`);
console.log('\nCOLS: '+JSON.stringify(s));
