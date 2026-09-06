import { sql } from '../phase_b/lib/db.mjs';
import { writeFileSync } from 'node:fs';
const r = await sql(`select pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='fn_phase_d_run_injected_defects'`);
writeFileSync(new URL('./decide_LIVE_body.sql', import.meta.url), r[0].def, 'utf8');
console.log('bytes', r[0].def.length);
