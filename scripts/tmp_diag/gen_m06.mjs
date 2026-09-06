// Merge every injected-defect branch patch set onto the LIVE body and write the migration.
//   node scripts/tmp_diag/gen_m06.mjs
import { sql } from '../phase_b/lib/db.mjs';
import { writeFileSync, existsSync, readFileSync } from 'node:fs';

let body = (await sql(`select pg_get_functiondef('public.fn_phase_d_run_injected_defects()'::regprocedure) def`))[0].def;

const SETS = [
  ['scripts/tmp_diag/fourmore_patch.mjs', 'PATCHES'],
  ['scripts/tmp_diag/decide_patch.mjs', 'PATCHES'],
  ['scripts/tmp_diag/eight_patch.mjs', 'PATCHES'],
];
let applied = 0, skipped = [];
for (const [file] of SETS) {
  if (!existsSync(file)) { skipped.push(file + ' (absent)'); continue; }
  const mod = await import('../../' + file.replace('scripts/', 'scripts/'));
  for (const p of mod.PATCHES) {
    const n = body.split(p.find).length - 1;
    if (n !== 1) { console.error(`ANCHOR ${n === 0 ? 'MISSING' : 'AMBIGUOUS(' + n + ')'} in ${file}: ${p.name}`); process.exit(1); }
    body = body.replace(p.find, p.replace);
    applied++;
  }
}
// The whole-function candidate from the eight-branch agent, if it produced one instead of patches.
const CAND = 'scripts/tmp_diag/m03_injected_defects_candidate.sql';
if (existsSync(CAND) && !existsSync('scripts/tmp_diag/eight_patch.mjs')) {
  skipped.push(CAND + ' (whole-function candidate; merged by hand, not here)');
}
console.log(`patches applied ${applied}; skipped: ${skipped.join(', ') || '(none)'}`);
writeFileSync('scripts/tmp_diag/m06_merged_body.sql', body);
console.log('merged body length ' + body.length);
