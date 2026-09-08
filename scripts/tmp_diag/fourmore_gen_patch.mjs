// Generates scripts/tmp_diag/fourmore_patch.mjs from the LIVE function body plus
// scripts/tmp_diag/fourmore_branches.sql, so every `find` anchor is an exact substring of the live
// body rather than something retyped by hand.
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const live = (await sql(
  `select pg_get_functiondef('public.fn_phase_d_run_injected_defects()'::regprocedure) as d`))[0].d;
const branches = readFileSync(new URL('./fourmore_branches.sql', import.meta.url), 'utf8');

// The four values-list entries these branches replace, taken verbatim out of the live body.
const line = (id) => {
  const i = live.indexOf(`      ('${id}',`);
  if (i < 0) throw new Error(`no values entry for ${id}`);
  const j = live.indexOf('\n', i);
  return live.slice(i, j + 1);
};
const anchor = '  -- ---- Remaining rows whose subject exists but whose injection needs a committed run ------------';
if (live.split(anchor).length !== 2) throw new Error('insert anchor is not unique');

const PATCHES = [
  { name: 'PD-DISP-001 + PD-DISP-002 (drop the two NOT_RUN blockers)',
    find: line('PD-DISP-001') + line('PD-DISP-002'), replace: '' },
  { name: 'PD-DISP-004 (drop the NOT_RUN blocker)', find: line('PD-DISP-004'), replace: '' },
  { name: 'PD-LEGAL-002 (drop the NOT_RUN blocker)', find: line('PD-LEGAL-002'), replace: '' },
  { name: 'the four real branches', find: anchor, replace: branches + anchor },
];

for (const p of PATCHES) {
  const n = live.split(p.find).length - 1;
  if (n !== 1) throw new Error(`anchor for ${p.name} occurs ${n} times`);
}

const out = `// Four real injected-defect branches for public.fn_phase_d_run_injected_defects().
// Exact string replacement pairs against the LIVE function body. Apply in order; each \`find\`
// occurs exactly once in the live body and none of them touches PD-IDEM-002, PD-REV-002/004/005,
// PD-STATE-002/003, PD-TRACE-003 or PD-TRACE-004.
export const PATCHES = ${JSON.stringify(PATCHES, null, 2)};
`;
writeFileSync(new URL('./fourmore_patch.mjs', import.meta.url), out);
console.log('wrote fourmore_patch.mjs', out.length, 'bytes');
