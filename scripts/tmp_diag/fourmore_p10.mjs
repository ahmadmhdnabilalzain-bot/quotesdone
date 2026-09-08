import { sql } from '../lib/db.mjs';
const r = await sql(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='fn_phase_d_handler_execute'`);
process.stdout.write(r[0].d);
