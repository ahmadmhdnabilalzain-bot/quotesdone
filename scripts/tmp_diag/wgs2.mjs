import { sql } from '../phase_b/lib/db.mjs';
const d = (await sql(`select substring(prosrc from 1 for 2600) src
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='fn_kernel_write_guard_state'`))[0].src;
const i = d.indexOf('writers as');
console.log(d.slice(Math.max(0, i - 300), i + 1400));
