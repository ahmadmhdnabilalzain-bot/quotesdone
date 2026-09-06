import { sql } from '../phase_b/lib/db.mjs';
const d = (await sql(`select substring(prosrc from position('routines_that_write_a_protected_table_with_no_authority' in prosrc)-200 for 2400) src
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='fn_kernel_write_guard_state'`))[0].src;
console.log(d);
