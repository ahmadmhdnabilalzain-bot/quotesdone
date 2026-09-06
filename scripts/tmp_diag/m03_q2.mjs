import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select t.tgname, p.proname, pg_get_functiondef(p.oid) def
 from pg_trigger t join pg_proc p on p.oid=t.tgfoid
 where t.tgrelid='public.phase_c_trace'::regclass and not t.tgisinternal`);
for (const x of r) console.log('== '+x.tgname+' -> '+x.proname+'\n'+x.def+'\n');
const c = await sql(`select conname, pg_get_constraintdef(oid) d, condeferrable, condeferred from pg_constraint where conrelid in ('public.phase_c_trace'::regclass,'public.phase_c_task'::regclass) order by conrelid, conname`);
console.log(JSON.stringify(c,null,1));
