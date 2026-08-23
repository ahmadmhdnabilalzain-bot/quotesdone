// PHASE D DELIVERABLE — PHASE_D_INJECTED_DEFECT_EXEMPTION_REGISTER.csv
//
// The founder's ruling of 23 Aug 2026, section 4: "Classify every one as CLOSED or
// PERMANENT_EXEMPTION and write a committed register carrying, per case: the defect id, the
// disposition, the exact reason, and what would have to exist for it to become executable."
//
// The register itself is public.phase_d_injected_defect_disposition, applied in a migration and
// therefore committed. This is its readable face, exported mechanically so it cannot say something
// the table does not. Nothing here is typed: the row count is the table's, the categories are the
// table's, and build_injected_defect_result.mjs fails if a case that did not run is missing from it
// or if a row survives a case that has since closed.
//
//   node scripts/phase_d/build_exemption_register.mjs
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql } from '../phase_c/lib/db.mjs';

const rows = await sql(`select defect_id, category, disposition, reason,
                               what_would_make_it_executable, decided_at
                          from public.phase_d_injected_defect_disposition
                         order by defect_id`);

const q = (v) => {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const COLS = ['defect_id', 'category', 'disposition', 'reason',
              'what_would_make_it_executable', 'decided_at'];

const file = 'PHASE_D_INJECTED_DEFECT_EXEMPTION_REGISTER.csv';
const body = [COLS.join(',')]
  .concat(rows.map((r) => COLS.map((c) => q(r[c])).join(',')))
  .join('\n');

writeFileSync(outPath(file), provenance({
  command: 'node scripts/phase_d/build_exemption_register.mjs',
  numerator: rows.length,
  denominator: rows.length,
  of: 'rows of public.phase_d_injected_defect_disposition',
  attribution: 'one row per catalogued defect that did not execute; the reason names the object '
    + 'that refuses or the object that does not exist, and both text columns carry a length floor '
    + 'so a row cannot be satisfied by restating the defect id',
}) + body + '\n');

console.log(`${file}  ${rows.length} rows`);
const byDisp = rows.reduce((a, r) => { a[r.disposition] = (a[r.disposition] || 0) + 1; return a; }, {});
for (const [k, v] of Object.entries(byDisp)) console.log(`  ${k}  ${v}`);
