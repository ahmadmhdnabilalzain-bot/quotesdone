// Splice the eight branches from the eight-injection candidate onto the CURRENT live body.
// The candidate was generated from the body BEFORE M06, so it carries the old text for M06's
// sixteen; only the eight it owns are taken from it.
import { sql } from '../phase_b/lib/db.mjs';
import { readFileSync, writeFileSync } from 'node:fs';

const IDS = ['PD-IDEM-002','PD-REV-002','PD-REV-004','PD-REV-005',
             'PD-STATE-002','PD-STATE-003','PD-TRACE-003','PD-TRACE-004'];

const cand = readFileSync('scripts/tmp_diag/m03_candidate.sql', 'utf8');
let live = (await sql(`select pg_get_functiondef('public.fn_phase_d_run_injected_defects()'::regprocedure) def`))[0].def;

// A branch runs from just after the previous `return next;` to the end of its own `return next;`.
const branch = (src, id) => {
  const at = src.indexOf(`defect_id:='${id}'`);
  if (at < 0) throw new Error(`${id} not found`);
  if (src.indexOf(`defect_id:='${id}'`, at + 1) >= 0) throw new Error(`${id} appears twice`);
  const prev = src.lastIndexOf('return next;', at);
  const start = prev < 0 ? 0 : prev + 'return next;'.length;
  const end = src.indexOf('return next;', at);
  if (end < 0) throw new Error(`${id} has no return next`);
  return src.slice(start, end + 'return next;'.length);
};

for (const id of IDS) {
  const from = branch(live, id);
  const to = branch(cand, id);
  if (live.split(from).length - 1 !== 1) throw new Error(`${id} live branch is not unique`);
  live = live.replace(from, to);
  console.log(`${id}: ${from.length} -> ${to.length} chars`);
}
writeFileSync('scripts/tmp_diag/m08_merged_body.sql', live);
console.log('merged length ' + live.length);
