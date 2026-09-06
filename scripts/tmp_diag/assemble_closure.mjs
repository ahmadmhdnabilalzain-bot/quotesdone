// Fill the @@FIGURES@@ placeholder in PHASE_D_BUILDER_CLOSURE.md from the deliverables themselves
// and from the live boards — never from a number typed by hand.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { q } from './q.mjs';

const D = 'docs/phase-d/';
const head = (f) => (existsSync(D + f) ? readFileSync(D + f, 'utf8').split('\n')[0] : '(missing)');
const numden = (f) => {
  const m = head(f).match(/\|\s*([\d,]+)\s+of\s+([\d,]+)\s+([^|]+)/);
  return m ? { n: m[1], d: m[2], of: m[3].trim() } : null;
};

const stepCases = await q(`select count(*)::text total, count(*) filter (where passed)::text passed
  from public.phase_d_step_case_result`);
const drift = await q(`select
  (select count(*) from public.fn_phase_a_baseline_drift())::text a,
  (select count(*) from public.fn_phase_b_baseline_drift())::text b,
  (select count(*) from public.fn_phase_c_freeze_drift() where not ok)::text c`);

// four-mode: read the CSV's own rows rather than its banner
const fourMode = (() => {
  const f = D + 'PHASE_D_FOUR_MODE_RESULT.csv';
  if (!existsSync(f)) return null;
  const lines = readFileSync(f, 'utf8').split('\n').filter((l) => l && !l.startsWith('#'));
  const hdr = lines[0].split(',');
  const mi = hdr.indexOf('mode');
  const oi = hdr.findIndex((h) => /reached|ok|result|outcome/i.test(h));
  if (mi < 0) return { raw: hdr.join('|') };
  const byMode = {};
  for (const l of lines.slice(1)) {
    const c = l.split(',');
    byMode[c[mi]] = (byMode[c[mi]] || 0) + 1;
  }
  return { byMode, column: oi >= 0 ? hdr[oi] : '(none)' };
})();

const defect = (() => {
  const f = D + 'PHASE_D_INJECTED_DEFECT_RESULT.csv';
  const t = readFileSync(f, 'utf8');
  const rows = [];
  let row = [], cur = '', qq = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (qq) { if (c === '"' && t[i + 1] === '"') { cur += '"'; i++; } else if (c === '"') qq = false; else cur += c; }
    else if (c === '"') qq = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c;
  }
  const body = rows.filter((r) => r.length > 1 && !r[0].startsWith('#'));
  const si = body[0].indexOf('status');
  const counts = {};
  for (const r of body.slice(1)) counts[r[si]] = (counts[r[si]] || 0) + 1;
  return { total: body.length - 1, counts };
})();

const CLOSED = ['REFUSED_AS_REQUIRED', 'SAFE_SCOPED_RESULT_AS_REQUIRED', 'IDEMPOTENT_NO_DUPLICATE',
  'FAIL_CLOSED_AS_REQUIRED', 'INVALID_TEST_CONTRACT_REPLACED'];
const closed = CLOSED.reduce((a, k) => a + (defect.counts[k] || 0), 0);

console.log('handler   ', JSON.stringify(numden('PHASE_D_HANDLER_IMPLEMENTATION_RESULT.csv')));
console.log('workflow  ', JSON.stringify(numden('PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv')));
console.log('handoff/ev', JSON.stringify(numden('PHASE_D_HANDOFF_EVENT_RESULT.csv')));
console.log('stepcase  ', JSON.stringify(numden('PHASE_D_STEP_CASE_RESULT.csv')), '->',
  stepCases[0].passed + ' of ' + stepCases[0].total + ' passing in the table');
console.log('migrations', JSON.stringify(numden('PHASE_D_MIGRATION_ROLLBACK_CLASSIFICATION.csv')));
console.log('defects   ', defect.total, 'rows', JSON.stringify(defect.counts), 'closed', closed);
console.log('four mode ', JSON.stringify(fourMode));
console.log('drift     ', JSON.stringify(drift[0]));
