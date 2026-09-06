// Compare two dispatch census CSVs: steps executed at least once, and the last refusal per step.
//   node scripts/tmp_diag/census_compare.mjs scripts/tmp_diag/census_s0.csv scripts/tmp_diag/census_s1.csv
import { readFileSync } from 'node:fs';
const parse = (l) => { const o = []; let c = '', q = false; for (let i = 0; i < l.length; i++) { const ch = l[i]; if (q) { if (ch === '"' && l[i + 1] === '"') { c += '"'; i++; } else if (ch === '"') q = false; else c += ch; } else if (ch === '"') q = true; else if (ch === ',') { o.push(c); c = ''; } else c += ch; } o.push(c); return o; };
const load = (f) => { const t = readFileSync(f, 'utf8').split('\n').filter(l => l.trim()); const h = parse(t[0]); return t.slice(1).map(parse).map(r => Object.fromEntries(h.map((k, i) => [k, r[i] || '']))); };
const [a, b] = process.argv.slice(2).map(load);
const summarise = (rows) => {
  const exec = new Set(rows.filter(r => r.outcome === 'EXECUTED').map(r => r.step_id));
  const last = {}; for (const r of rows) last[r.step_id] = r;
  return { rows: rows.length, steps: new Set(rows.map(r => r.step_id)).size, exec, last };
};
const A = summarise(a), B = summarise(b);
console.log(`before: ${A.rows} dispatch rows, ${A.steps} steps dispatched, ${A.exec.size} steps with an EXECUTED dispatch`);
console.log(`after:  ${B.rows} dispatch rows, ${B.steps} steps dispatched, ${B.exec.size} steps with an EXECUTED dispatch`);
const gained = [...B.exec].filter(s => !A.exec.has(s)).sort();
const lost = [...A.exec].filter(s => !B.exec.has(s)).sort();
console.log(`gained (${gained.length}): ${gained.join(' ')}`);
console.log(`lost (${lost.length}): ${lost.join(' ')}`);
const never = Object.keys(B.last).filter(s => !B.exec.has(s)).sort();
console.log(`\nstill never executed (${never.length}):`);
const byCode = {};
for (const s of never) { const r = B.last[s]; const k = (r.refusal_code || r.outcome) + ' ' + (r.ids || ''); (byCode[k] ||= []).push(s + ' [' + (r.reason || '').slice(0, 60) + ']'); }
for (const [k, v] of Object.entries(byCode).sort((x, y) => y[1].length - x[1].length)) console.log(`  ${k}: ${v.length}\n    ${v.join('\n    ')}`);
