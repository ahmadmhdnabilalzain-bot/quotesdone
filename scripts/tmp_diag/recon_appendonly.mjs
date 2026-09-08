import { sql } from '../lib/db.mjs';
const q = async (label, s) => { try { console.log('\n=== '+label); console.log(JSON.stringify(await sql(s), null, 1)); } catch(e){ console.log('\n=== '+label+' ERROR '+e.message); } };
await q('tables matching founder/refund/terms/verdict/trace', `
select c.relname, c.relkind, n.nspname
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind in ('r','v','m')
  and (c.relname ilike '%founder%' or c.relname ilike '%refund%' or c.relname ilike '%terms_accept%'
       or c.relname ilike '%verdict%' or c.relname ilike '%review%' or c.relname ilike '%trace%')
order by 1`);
await q('triggers on those tables', `
select c.relname as tbl, t.tgname, p.proname, pg_get_triggerdef(t.oid) as def
from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
join pg_proc p on p.oid=t.tgfoid
where not t.tgisinternal and n.nspname='public'
  and (c.relname ilike '%founder%' or c.relname ilike '%refund%' or c.relname ilike '%terms_accept%'
       or c.relname ilike '%verdict%' or c.relname ilike '%review%' or c.relname ilike '%trace%')
order by 1,2`);
