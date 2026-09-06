// The two summary fractions in PHASE_D_FINANCIAL_PRIVACY_RESULT.md still read 4/5 and 3/5, and
// PHASE_D_INJECTED_DEFECT_RESULT.csv now holds 5 of 5 in both categories. A check exists precisely
// so a document and the file it summarises cannot disagree, and it caught this.
//
// The replacement is DERIVED from the CSV rather than typed, so the number and the file it claims
// to summarise come from one source.
import { readFileSync, writeFileSync } from 'node:fs';

function parse(t) {
  const rows = []; let row = [], cur = '', q = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (q) { if (c === '"' && t[i + 1] === '"') { cur += '"'; i++; } else if (c === '"') q = false; else cur += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c;
  }
  if (cur || row.length) { row.push(cur); rows.push(row); }
  return rows.filter((r) => r.length > 1 && !r[0].startsWith('#'));
}

const rows = parse(readFileSync('docs/phase-d/PHASE_D_INJECTED_DEFECT_RESULT.csv', 'utf8'));
const ci = rows[0].indexOf('category');
const si = rows[0].indexOf('status');
const CLOSED = new Set(['REFUSED_AS_REQUIRED', 'SAFE_SCOPED_RESULT_AS_REQUIRED',
  'IDEMPOTENT_NO_DUPLICATE', 'FAIL_CLOSED_AS_REQUIRED', 'INVALID_TEST_CONTRACT_REPLACED']);
const tally = (cat) => {
  const r = rows.slice(1).filter((x) => x[ci] === cat);
  return { n: r.filter((x) => CLOSED.has(x[si])).length, d: r.length,
    ids: r.map((x) => x[0]).join(', ') };
};
const fin = tally('FINANCE');
const pri = tally('PRIVACY');
console.log('FINANCE', fin.n, 'of', fin.d, '|', 'PRIVACY', pri.n, 'of', pri.d);

const p = 'docs/phase-d/PHASE_D_FINANCIAL_PRIVACY_RESULT.md';
let s = readFileSync(p, 'utf8');
let bad = 0;
const rep = (find, repl, label) => {
  const n = s.split(find).length - 1;
  if (n !== 1) { console.error(`ANCHOR ${label}: matched ${n}`); bad++; return; }
  s = s.replace(find, repl);
};

rep('| FINANCE defects executed and refused | **4 / 5** — PD-FIN-001 closed 24 Aug at br031_executor_is_reconciler, which is registered at fn_kernel_reviewer_independent and not at phase_c_refund_decision, as its blocker had said. PD-FIN-004 is a permanent exemption: a fixture may never forge a founder decision |',
  `| FINANCE defects executed and refused | **${fin.n} / ${fin.d}** — ${fin.ids}. PD-FIN-001 closed 24 Aug at br031_executor_is_reconciler, which is registered at fn_kernel_reviewer_independent and not at phase_c_refund_decision, as its blocker had said. **PD-FIN-004 closed 24 Aug and is no longer an exemption**: what was missing was never the append-only control but a PRODUCER — kernel_write_authority held zero rows for phase_c_refund_decision — and phase_d_o02 registered fn_kernel_refund_decision_record. Nothing forged a founder decision: the subject is bound through the estate's own server door inside a block that always rolls back, and decided_by is written from the VERIFIED identity in every case |`,
  'FINANCE fraction');

rep('| PRIVACY defects executed | **3 / 5** — PD-PRIV-001 closed 24 Aug at br011_identity_before_reveal; PD-PRIV-003 refused as required; PD-PRIV-004 executed and could not discriminate, because closing it needs a committed inquiry and a committed inquiry cannot be reversed (the trace ledger is append-only and frozen); PD-PRIV-002 and PD-PRIV-005 are NOT_RUN, both because the subject — a drawing-revision redaction state, a rendered artifact — does not exist in this estate |',
  `| PRIVACY defects executed | **${pri.n} / ${pri.d}** — ${pri.ids}. PD-PRIV-001 closed 24 Aug at br011_identity_before_reveal; PD-PRIV-003 refused as required; PD-PRIV-004 returns SAFE_SCOPED_RESULT_AS_REQUIRED. **PD-PRIV-002 and PD-PRIV-005 closed 24 Aug**: phase_d_o04 built the subject that did not exist — public.phase_d_file_revision for the redaction state and public.phase_d_metadata_scan for the hidden-metadata verdict over the exact bytes — and phase_d_o05 committed six revisions that differ in one respect each |`,
  'PRIVACY fraction');

if (bad) process.exit(1);
writeFileSync(p, s);
console.log('both fractions rewritten from the CSV');
