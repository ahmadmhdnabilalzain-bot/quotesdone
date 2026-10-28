// Supplier journey audit, 28 Oct 2026 (docs/reports/supplier_journey_audit_28_oct/sales_agent): replies told invited
// suppliers that "the only mandatory document to upload is your valid UAE trade licence" (case c8), and the company
// knowledge said "No supplier is approved automatically" and "Today approval is manual". Production approves when the
// gate passes (pricing_config.auto_approve_suppliers, fn_sales_engineer_verifies_supplier; SA v16 "Automated decisions")
// and the mandatory six need the licence AND the company profile, both uploaded (fn_supplier_mandatory_six, SA v16
// clause 13). This fails if any knowledge source an agent answers from says the old thing again.
// Source only: runs offline in the checks job.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const SOURCES = ['knowledge/brief/company.md', 'knowledge/brief/supplier_howto.md', 'knowledge/COMPANY_CANON.md',
  'supabase/functions/_shared/brief.generated.ts', 'supabase/seeds/dept_library.seed.sql', 'supabase/seeds/canon_eval_questions.seed.sql'];
const FALSE = [/no supplier is approved automatically/i, /approval is manual/i, /only required document/i,
  /only mandatory document/i, /auto-approve flag exists/i];

test('no knowledge source says approval is manual or the licence is the only required document', () => {
  for (const p of SOURCES) { const s = read(p); for (const re of FALSE) assert.doesNotMatch(s, re, `${p} says ${re}`); }
});

test('the brief and the canon name automatic approval and the profile as an uploaded document', () => {
  const brief = read('knowledge/brief/company.md');
  assert.match(brief, /Approval is \*\*automatic\*\* when the six are complete/);
  assert.match(brief, /company profile \(uploaded\)/);
  const canon = read('knowledge/COMPANY_CANON.md');
  assert.match(canon, /Approval is automatic when the mandatory six are complete/);
  assert.match(canon, /The two required documents are your trade licence and your company profile/);
});

test('the live copies are corrected by a file of their own', () => {
  const f = read('scripts/sql/a_supplier_is_told_approval_is_automatic_when_the_gate_passes.sql');
  assert.match(f, /update public\.dept_library/);
  assert.match(f, /update public\.canon_eval_questions/);
  assert.match(f, /raise exception 'dept_library still states/);
});
