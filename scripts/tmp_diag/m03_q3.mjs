import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select t.tgname, p.proname, pg_get_functiondef(p.oid) def
 from pg_trigger t join pg_proc p on p.oid=t.tgfoid
 where t.tgrelid='public.phase_c_task'::regclass and not t.tgisinternal and t.tgname like 'z95%'`);
for (const x of r) console.log('== '+x.tgname+'\n'+x.def);
