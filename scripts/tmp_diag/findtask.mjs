import { sql } from '../phase_b/lib/db.mjs';
const s = (await sql(`select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_run_injected_defects'`))[0].prosrc;
const re = /(insert\s+into|update|delete\s+from)\s+(public\.)?phase_c_task\b/gi;
let m; while ((m = re.exec(s))) console.log('...' + s.slice(Math.max(0,m.index-140), m.index+160).replace(/\s+/g,' '));
