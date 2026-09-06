import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select t.tgname, p.proname, pg_get_triggerdef(t.oid) def from pg_trigger t join pg_proc p on p.oid=t.tgfoid where t.tgrelid='public.inquiries'::regclass and not t.tgisinternal order by t.tgname`),null,1));
