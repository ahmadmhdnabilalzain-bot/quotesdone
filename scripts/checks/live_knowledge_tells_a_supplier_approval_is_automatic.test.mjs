// 3 Nov 2026, sales_engineer. The "Supplier onboarding policy" answer agents read live said suppliers are "not
// auto-approved" (company_faq 159/786, kb_chunks 174359/177559, agent_knowledge 1047, ops_knowledge
// qd-company:faq-company-policies). Production approves when the gate passes (pricing_config.auto_approve_suppliers,
// fn_sales_engineer_verifies_supplier; ledger 1469 services, ledger 1442 foreign/unconfirmed authority held).
// The live rows are corrected by scripts/sql/live_knowledge_tells_a_supplier_approval_is_automatic_when_the_gate_passes.sql;
// this check fails if the repo copies the agent_knowledge table is seeded from say the old thing again, or if that file
// stops correcting one of the six rows. (#1731's check covers the canon, brief, site, dept_library and eval seeds.)
// Source only: runs offline in the checks job.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const SEEDS = ['ai-organization/org-as-code/agent_knowledge.json', 'supabase/seeds/agent_knowledge.seed.sql'];
const FALSE = [/not auto-approved/i, /no supplier is (ever )?approved automatically/i, /approval is manual/i,
  /not approved automatically/i, /auto-approve flag exists/i,
  /لا (تُمنح|تمنح|يتم) الموافقة[^.]{0,30}تلقائي/, /لا (يُوافَق|يوافق) على أي (مورّد|مورد) تلقائي/, /لا نوافق على أي (مورّد|مورد) تلقائي/];
const TRUE_EN = 'approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).';
const SQL = 'scripts/sql/live_knowledge_tells_a_supplier_approval_is_automatic_when_the_gate_passes.sql';

test('known-bad control: the sentence that was live is caught, in English and Arabic', () => {
  for (const bad of ['(verification within a maximum of 3 working days; suppliers are not auto-approved).',
    '(خلال 3 أيام عمل كحد أقصى، ولا تُمنح الموافقة تلقائيًا).']) {
    assert.ok(FALSE.some((re) => re.test(bad)), 'the control must match a false pattern: ' + bad);
  }
  assert.ok(!FALSE.some((re) => re.test(TRUE_EN)), 'the true sentence must not match a false pattern');
});

test('the agent_knowledge seeds say approval is automatic and never the opposite', () => {
  for (const p of SEEDS) {
    const s = read(p);
    for (const re of FALSE) assert.doesNotMatch(s, re, `${p} says ${re}`);
    assert.ok(s.includes(TRUE_EN), `${p} lost the automatic-approval sentence`);
  }
});

test('the live-row file corrects each of the six rows by exact text and ends on a verdict', () => {
  const f = read(SQL).replace(/\s+/g, ' ');
  for (const w of ['where id = 159 and strpos(answer,', 'where id = 786 and strpos(answer,',
    'where id in (174359, 177559) and strpos(content,', 'where id = 1047 and strpos(content,',
    "where record_id = 'qd-company:faq-company-policies' and strpos(content,"]) {
    assert.ok(f.includes(w), `${SQL} no longer has: ${w}`);
  }
  assert.ok(f.split(TRUE_EN).length - 1 >= 4, `${SQL} does not write the true sentence into every English row`);
  assert.match(f, /update public\.kb_chunks set content = replace\([^']*'[^']*', '[^']*'\), embedding_gte = null, embed_claimed_at = null/);
  assert.match(f, /update public\.agent_knowledge set content = replace\([^']*'[^']*', '[^']*'\), embedding_gte = null/);
  assert.match(f, /'PROBE FAILED: live knowledge still says supplier approval is not automatic: '/);
  assert.doesNotMatch(f, /\bdelete from\b/i);
});
