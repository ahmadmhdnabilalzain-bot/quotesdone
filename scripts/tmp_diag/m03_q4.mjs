import { sql } from '../lib/db.mjs';
const r = await sql(`select t.tgname, pg_get_triggerdef(t.oid) d
 from pg_trigger t where t.tgrelid in ('public.phase_c_task'::regclass,'public.phase_c_trace'::regclass) and not t.tgisinternal order by t.tgrelid::regclass::text, t.tgname`);
console.log(r.map(x=>x.d).join('\n'));
