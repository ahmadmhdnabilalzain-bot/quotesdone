// AUDIT 9.5 - inbound gate inventory, pass 2. Pass 1 over-reported: it counted the leftover
// `const secretOk = ...` helper DEFINITION and outbound fetch bodies as gates. This pass counts a
// gate only where a presented credential is actually COMPARED, and separates the three distinct
// secrets that live in these files (inbound_secret, deploy secret, force key).
import fs from 'node:fs';
import path from 'node:path';

const ROOT = 'C:/Users/Opera/quotesdone/supabase/functions';
const dirs = fs.readdirSync(ROOT, { withFileTypes: true })
  .filter((d) => d.isDirectory() && !d.name.startsWith('_'))
  .map((d) => d.name).sort();

const COND_A = /!secretOk\(__exp\)\s*\|\|\s*!(body|b)\.__secret\s*\|\|\s*(?:body|b)\.__secret\s*!==\s*__exp/;
const COND_B = /!secretOk\(__exp\)\s*\|\|\s*(body|b)\??\.__secret\s*!==\s*__exp/;

const isComment = (t) => /^(\/\/|\/\*|\*)/.test(t);
const isHelperDef = (t) => /^(const|function|let)\s+secretOk\b/.test(t);
// A property being SENT: `__secret: x` where it is not also being compared.
const isOutbound = (t) => /__(secret|deploy_secret)\s*:/.test(t) && !/__(secret|deploy_secret)\s*(!==|===|==)/.test(t);
// A comparison of a PRESENTED credential.
const CMP = /(__secret|__deploy_secret|__force_key)\s*(!==|===|==)|(!==|===|==)\s*[A-Za-z_$][\w$.?]*__secret|!\s*[A-Za-z_$][\w$]*\??\.__secret\b/;

function classify(t) {
  if (isComment(t)) return 'comment';
  if (/requireInternal\s*\(/.test(t)) return 'verifier';
  if (/import\s*\{[^}]*requireInternal/.test(t)) return 'verifier_import';
  if (isHelperDef(t)) return 'helper_def';
  if (isOutbound(t)) return 'outbound';
  if (CMP.test(t)) return 'gate';
  return 'other';
}

function whichSecret(t) {
  if (/__deploy_secret/.test(t)) return 'deploy';
  if (/__force_key/.test(t)) return 'force_key';
  if (/__test\b/.test(t) && !/__secret/.test(t)) return 'test_token';
  return 'inbound';
}

const rows = [];
for (const fn of dirs) {
  const p = path.join(ROOT, fn, 'index.ts');
  if (!fs.existsSync(p)) { rows.push({ fn, state: 'NO_INDEX', gates: [], kinds: [] }); continue; }
  const src = fs.readFileSync(p, 'utf8');
  const gates = [], verifier = [], outbound = [];
  src.split(/\r?\n/).forEach((l, i) => {
    const t = l.trim();
    if (!/__secret|__deploy_secret|__force_key|requireInternal|inbound_secret/.test(t)) return;
    const k = classify(t);
    if (k === 'gate') gates.push({ n: i + 1, t, s: whichSecret(t) });
    else if (k === 'verifier' || k === 'verifier_import') verifier.push(i + 1);
    else if (k === 'outbound') outbound.push({ n: i + 1, t, s: whichSecret(t) });
  });

  const inboundGates = gates.filter((g) => g.s === 'inbound');
  let state;
  if (inboundGates.length === 0 && verifier.length) state = 'MIGRATED';
  else if (inboundGates.length === 0 && gates.length) state = 'OTHER_SECRET_ONLY';
  else if (inboundGates.length === 0 && outbound.length) state = 'OUTBOUND_ONLY';
  else if (inboundGates.length === 0) state = 'NO_GATE';
  else if (verifier.length) state = 'PARTIAL';
  else if (COND_A.test(src)) state = 'SHAPE_A';
  else if (COND_B.test(src)) state = 'SHAPE_B';
  else state = 'UNRECOGNISED';

  rows.push({ fn, state, gates, inboundGates, outbound, verifier: verifier.length });
}

const out = [];
const byState = {};
for (const r of rows) (byState[r.state] ||= []).push(r);
out.push('=== AUDIT 9.5 INBOUND GATE INVENTORY (pass 2) ===');
out.push(`function directories scanned: ${rows.length}`);
out.push('');
for (const s of Object.keys(byState).sort()) {
  out.push(`${s.padEnd(18)} ${String(byState[s].length).padStart(4)}`);
  out.push(`     ${byState[s].map((r) => r.fn).join(' ')}`);
}

const todo = rows.filter((r) => ['SHAPE_A', 'SHAPE_B', 'UNRECOGNISED', 'PARTIAL'].includes(r.state));
out.push('');
out.push(`=== REMAINING INBOUND GATES: ${todo.length} functions, ` +
         `${todo.reduce((a, r) => a + r.inboundGates.length, 0)} comparison sites ===`);
for (const r of todo) {
  out.push('');
  out.push(`--- ${r.fn}  [${r.state}]  verifier_refs=${r.verifier}`);
  for (const g of r.inboundGates) out.push(`   L${String(g.n).padStart(4)}  ${g.t.slice(0, 190)}`);
}

// Outbound hops still presenting the shared secret to another function.
out.push('');
out.push('=== OUTBOUND HOPS PRESENTING A SECRET ===');
for (const r of rows) {
  for (const o of r.outbound) {
    const m = o.t.match(/functions\/v1\/([a-z0-9_]+)/);
    out.push(`${r.fn.padEnd(26)} -> ${(m ? m[1] : '(target not on this line)').padEnd(24)} [${o.s}] L${o.n}`);
  }
}
fs.writeFileSync('C:/Users/Opera/qd-check/inventory_gates2.out.txt', out.join('\n'), 'utf8');
console.log(out.slice(0, 30).join('\n'));
console.log(`\n[full report: ${out.length} lines]`);
