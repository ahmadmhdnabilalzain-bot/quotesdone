import { sql } from '../lib/db.mjs';
const p = (t, r) => { console.log('=== ' + t + ' (' + (r ? r.length : 0) + ') ==='); console.log(JSON.stringify(r, null, 1)); };

p('phase_b tables', await sql(`select table_name from information_schema.tables where table_schema='public' and table_name like 'phase_b%' order by 1`));
p('phase_d tables', await sql(`select table_name from information_schema.tables where table_schema='public' and table_name like 'phase_d%' order by 1`));
