// Classify the NOT_RUN injected defects by WHY they are not run, from the blocker text the
// deliverable already carries. Read-only; writes nothing.
import { readFileSync } from 'node:fs';

function parseCSV(t) {
  const rows = []; let row = [], cur = '', q = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (q) { if (c === '"') { if (t[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c;
  }
  if (cur !== '' || row.length) { row.push(cur); rows.push(row); }
  return rows;
}

const all = parseCSV(readFileSync('docs/phase-d/PHASE_D_INJECTED_DEFECT_RESULT.csv', 'utf8'))
  .filter(r => r.length > 4 && !String(r[0]).startsWith('#'));
const hdr = all[0];
const I = n => hdr.indexOf(n);
const rows = all.slice(1);

const BUCKETS = [
  ['needs a COMMITTED business row (the automation hold forbids it)',
   /commit|committed|sealing happens|seal|persist/i],
  ['needs two concurrent database sessions', /concurrent|race/i],
  ['the subject is a FROZEN Phase A/B/C property', /frozen|FROZEN/i],
  ['needs a §8 HTTP path the harness does not reach', /SECTION 8|§8|HTTP/i],
  ['needs a relation or permission the estate does not model', /no column|does not model|permission or relation|repository scan/i],
];

const by = new Map();
for (const r of rows) {
  if (r[I('status')] !== 'NOT_RUN') continue;
  const b = (r[I('blocker')] || '').replace(/\s+/g, ' ').trim();
  const hit = BUCKETS.find(([, re]) => re.test(b));
  const k = hit ? hit[0] : 'other';
  if (!by.has(k)) by.set(k, []);
  by.get(k).push([r[I('defect_id')], b.slice(0, 150)]);
}

let n = 0;
for (const [k, v] of [...by].sort((a, b) => b[1].length - a[1].length)) {
  console.log(`\n${v.length}  ${k}`);
  for (const [id, b] of v) console.log(`     ${id.padEnd(14)} ${b}`);
  n += v.length;
}
console.log(`\ntotal NOT_RUN ${n}`);
console.log('status counts:', JSON.stringify(
  rows.reduce((a, r) => (a[r[I('status')]] = (a[r[I('status')]] || 0) + 1, a), {})));
