// THE PUBLIC COMPANY BLOCK CARRIES NO INTERNAL FIGURES — customer_support, 22 Sep 2026, founder instruction 777.
//
// fn_company_context(…, 'public') is what the site assistant and wa_inbound hand a stranger's model. On
// 22 Sep 2026 it told them our revenue is under the AED 375,000 VAT threshold, that a category opens at 10
// verified suppliers, and that no real customer exists yet. This fails if any of them comes back, and if
// the INTERNAL block every seat reads loses them (the facts are right; they are just not public).
//
//   node --test scripts/checks/the_public_company_block_carries_no_internal_figures.test.mjs
// While scripts/sql/pending/<name>.txt exists the file is applied inside ONE transaction that is never
// committed and the block is read from there; once applied, production is read directly.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { sql } from '../lib/db.mjs';

const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/the_public_company_block_carries_no_internal_figures.sql';
const SIMULATE = !!process.env.SIMULATE || existsSync(join(ROOT, FILE.replace('scripts/sql/', 'scripts/sql/pending/').replace(/\.sql$/, '.txt')));
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

// Each is an internal figure or rule a stranger's model must never be handed.
const INTERNAL = [
  [/375,000|turnover/i, 'the VAT turnover threshold (tells anyone our revenue is below it)'],
  [/\b10 verified|v_category_open|CATEGORY OPENING/i, 'the category-opening supplier threshold'],
  [/PRE-LAUNCH|no real customer/i, 'the statement that no customer exists yet'],
  [/Corporate tax|Auditor:/i, 'the corporate-tax and auditor notes'],
];

test('the public company block states capabilities, not internal figures; the internal block keeps them', { skip: SKIP, timeout: 120000 }, async () => {
  const select = `select public.fn_company_context(16000, 'public')->>'block' pub, public.fn_company_context(16000, 'internal')->>'block' internal`;
  const r = SIMULATE
    ? (await sql(`begin;\n${readFileSync(join(ROOT, FILE), 'utf8')}\n;\n${select}`, { retry: false }))[0]
    : (await sql(select))[0];
  for (const [re, what] of INTERNAL) {
    assert.ok(!re.test(r.pub), `the PUBLIC block carries ${what}: ${r.pub.match(re)?.[0]}`);
    assert.ok(re.test(r.internal), `the INTERNAL block lost ${what}`);
  }
  assert.match(r.pub, /5\. MATCHING: every request goes only to verified suppliers of its exact trade/);
  assert.match(r.pub, /VAT: NOT registered; no invoice carries VAT\./);
});
