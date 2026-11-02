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
// Independent review, 3 Nov 2026: the public site (src/content/marketing.json: /how-we-verify and the FAQ, English and
// Arabic) and the org-as-code eval references still said the old thing, because this check did not read them. It does now.
const SOURCES = ['knowledge/brief/company.md', 'knowledge/brief/supplier_howto.md', 'knowledge/COMPANY_CANON.md',
  'supabase/functions/_shared/brief.generated.ts', 'supabase/seeds/dept_library.seed.sql', 'supabase/seeds/canon_eval_questions.seed.sql',
  'src/content/marketing.json', 'ai-organization/org-as-code/canon_eval_questions.json'];
const FALSE = [/no supplier is approved automatically/i, /approval is manual/i, /only required document/i,
  /only mandatory document/i, /auto-approve flag exists/i, /not auto-approved/i,
  /لا يُ?وافَ?ق على أي مورّ?د تلقائي/, /لا نوافق على أي مورّ?د تلقائي/];

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

// FOUNDER LEDGER 1469 (2 Nov 2026): a supplier is held until it confirms its services. "Automatic when the six are complete and the licence is
// read and in date" (this PR's first text) is false under it: a supplier with all six and a good licence is pending / services_unconfirmed.
// Every source says the services are part of the condition and that the supplier is held until it confirms them.
const SERVICES_SOURCES = ['knowledge/brief/company.md', 'knowledge/COMPANY_CANON.md', 'supabase/functions/_shared/brief.generated.ts',
  'supabase/seeds/dept_library.seed.sql', 'supabase/seeds/canon_eval_questions.seed.sql', 'scripts/sql/a_supplier_is_told_approval_is_automatic_when_the_gate_passes.sql'];
const approvalSentences = (s) => s.replace(/\*/g, '').replace(/\s+/g, ' ').split(/(?<=\.)\s/).filter((x) => /automatic(?:ally)? (?:when|once)|automatically (?:when|once)/i.test(x) && /licence is read/i.test(x));

test('known-bad control: the first text of this PR (no services) is caught', () => {
  for (const bad of ['Approval is automatic when the mandatory six are complete and the licence is read and in date.',
    'Approval follows within 3 working days of complete documents, and is automatic when the six are complete and the licence is read and in date.',
    'approval follows within 3 working days of complete documents, automatically when the licence is read and in date.']) {
    const s = approvalSentences(bad);
    assert.ok(s.length === 1 && !/services/i.test(s[0]), 'the control must be an approval sentence without services: ' + bad);
  }
});

test('ledger 1469: every approval sentence names the services confirmation and the hold', () => {
  for (const p of SERVICES_SOURCES) {
    const found = approvalSentences(read(p));
    assert.ok(found.length > 0, `${p} has no approval sentence`);
    for (const s of found) assert.match(s, /services/i, `${p} promises approval without the services: ${s}`);
  }
  const rest = (p) => read(p).replace(/\s+/g, ' ');
  for (const p of ['knowledge/brief/company.md', 'knowledge/COMPANY_CANON.md', 'scripts/sql/a_supplier_is_told_approval_is_automatic_when_the_gate_passes.sql']) {
    assert.match(rest(p), /(held|hold)[^.]{0,80}(confirm|until)|until (?:it|you|the supplier)[^.]{0,40}confirm/i, `${p} does not say the supplier is held until it confirms`);
  }
});

test('the live copies are corrected by a file of their own', () => {
  const f = read('scripts/sql/a_supplier_is_told_approval_is_automatic_when_the_gate_passes.sql');
  assert.match(f, /update public\.dept_library/);
  assert.match(f, /update public\.canon_eval_questions/);
  assert.match(f, /raise exception 'dept_library still states/);
});

// FOUNDER LEDGER 1442 (2 Nov 2026; independent review, 3 Nov 2026): only a readable UAE authority is approved automatically.
// A licence from a foreign authority (licence_authority_not_uae) or one nobody can confirm (licence_authority_unconfirmed)
// is held by fn_sales_engineer_verifies_supplier. A source that promises automatic approval must say so.
const AUTHORITY = /authority outside the UAE|foreign or unconfirmed issuing authority/i;
const AUTHORITY_SOURCES = ['knowledge/brief/company.md', 'knowledge/COMPANY_CANON.md', 'supabase/functions/_shared/brief.generated.ts',
  'supabase/seeds/dept_library.seed.sql', 'supabase/seeds/canon_eval_questions.seed.sql', 'ai-organization/org-as-code/canon_eval_questions.json',
  'scripts/sql/a_supplier_is_told_approval_is_automatic_when_the_gate_passes.sql'];

test('known-bad control: the approval wording before the review (no authority hold) is caught', () => {
  assert.doesNotMatch('Approval is automatic when the mandatory six are complete, the licence is read and in date, and the supplier has confirmed the services it provides (Services tab); a supplier is held until it confirms them.', AUTHORITY);
});

test('ledger 1442: every source that promises automatic approval names the foreign or unconfirmed authority hold', () => {
  for (const p of AUTHORITY_SOURCES) assert.match(read(p), AUTHORITY, `${p} promises automatic approval without the authority hold`);
});

test('the public site: /how-we-verify and the FAQ name the real gate, the services and the authority hold, in English and Arabic', () => {
  const m = JSON.parse(read('src/content/marketing.json'));
  const hwvEn = m['how-we-verify'].en.html, hwvAr = m['how-we-verify'].ar.html;
  assert.match(hwvEn, /Approval is automatic once all six are complete/);
  assert.match(hwvEn, /confirmed the services it provides/);
  assert.match(hwvEn, AUTHORITY);
  assert.match(hwvAr, /وتصدر الموافقة تلقائيًا متى اكتملت المتطلبات الستة/);
  assert.match(hwvAr, /الخدمات التي يقدّمها/);
  assert.match(hwvAr, /جهة خارج الإمارات/);
  assert.match(m.faq.en.html, /approval is automatic once[^)]*services[^)]*foreign or unconfirmed issuing authority is held/);
  assert.match(m.faq.ar.html, /وتصدر الموافقة تلقائيًا[^)]*خدماته[^)]*جهة خارج الإمارات/);
  const found = approvalSentences(hwvEn);
  assert.ok(found.length > 0 && found.every((s) => /services/i.test(s)), '/how-we-verify promises approval without the services');
});
