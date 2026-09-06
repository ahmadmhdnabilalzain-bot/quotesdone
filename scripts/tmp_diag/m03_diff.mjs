// Before/after per-defect status diff: live body vs candidate, both in aborted transactions.
import { readFileSync } from 'node:fs';
import { sql } from '../phase_b/lib/db.mjs';
const CAND = readFileSync('scripts/tmp_diag/m03_injected_defects_candidate.sql', 'utf8');

async function run(withCandidate) {
  const q = `
do $emit$
declare v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','m03-diff'));
  ${withCandidate ? `execute $cand$${CAND}$cand$;` : ''}
  for r in select * from public.fn_phase_d_run_injected_defects() order by defect_id loop
    v_out := v_out || r.defect_id || '=' || r.status || ' ';
  end loop;
  raise exception 'T<<%>>', v_out;
end $emit$;`;
  try { await sql(q); throw new Error('did not raise'); }
  catch (e) {
    const m = String(e.message ?? e); const a = m.indexOf('T<<');
    if (a < 0) throw new Error(m.slice(0, 2000));
    return new Map(m.slice(a + 3, m.lastIndexOf('>>')).trim().split(/\s+/).map(p => p.split('=')));
  }
}
const before = await run(false), after = await run(true);
const tal = m => { const t = {}; for (const v of m.values()) t[v] = (t[v] || 0) + 1; return t; };
console.log('BEFORE n=' + before.size, JSON.stringify(tal(before)));
console.log('AFTER  n=' + after.size, JSON.stringify(tal(after)));
const changed = [...after].filter(([k, v]) => before.get(k) !== v);
console.log('CHANGED ' + changed.length + ':');
for (const [k, v] of changed) console.log(`  ${k}  ${before.get(k)} -> ${v}`);
const unchanged = [...after].filter(([k, v]) => before.get(k) === v);
console.log('UNCHANGED ' + unchanged.length);
