import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select pg_get_function_identity_arguments(p.oid) a, pg_get_function_result(p.oid) rt, p.prosecdef
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_c_task_create'`);
console.log(JSON.stringify(r,null,1));
const s = await sql(`select left(prosrc, 2500) s from pg_proc where proname='fn_phase_c_task_create'`);
console.log(s[0].s);
