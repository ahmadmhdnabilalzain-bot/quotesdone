import { sql } from '../lib/db.mjs';
const q = async (label, s) => { const r = await sql(s); console.log('=== ' + label); console.log(JSON.stringify(r, null, 1).slice(0, 6000)); };

await q('phase_d functions', `select p.proname, pg_get_function_identity_arguments(p.oid) as args
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname like 'fn_phase_d%' order by 1`);

await q('phase_d tables', `select table_name from information_schema.tables
 where table_schema='public' and table_name like 'phase_d%' order by 1`);
