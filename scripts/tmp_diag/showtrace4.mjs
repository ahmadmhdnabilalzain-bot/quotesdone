import { sql } from '../lib/db.mjs';
const s = (await sql(`select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_run_injected_defects'`))[0].prosrc;
const at = s.indexOf("defect_id:='PD-TRACE-004'");
const prev = s.lastIndexOf('return next;', at);
console.log(s.slice(prev + 12, s.indexOf('return next;', at) + 12));
