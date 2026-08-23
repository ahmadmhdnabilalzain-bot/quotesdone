// node scripts/tmp_diag/dump_fn.mjs <proname> [outfile]
import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';
const name = process.argv[2];
const out = process.argv[3] || `scripts/tmp_diag/${name}.txt`;
const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='${name}'`);
if (!r.length) { console.error('no such function'); process.exit(1); }
writeFileSync(out, r.map((x) => x.def).join('\n\n-- ---- next overload ----\n\n'));
console.log(`${out}  ${r.length} definition(s)`);
