// A FIRST REQUEST IS GUIDED IN THE PORTAL AND CONFIRMED BY E-MAIL (customer_support, 29 Sep 2026; founder ledger 1018).
//
// scripts/sql/customer_support_guides_a_first_request_step_by_step_and_asks_a_held_one_for_its_specs.sql builds the
// guidance (fn_customer_concierge) and the first confirmation message (fn_customer_support_concierge_confirm); its
// _probe.sql proves what they say. A guide nobody shows and a confirmation nobody sends help no one, so this fails
// when the doors stop reaching them:
//   * customer_api answers action 'concierge' from fn_customer_concierge, and EVERY create_inquiry answer (single,
//     turnkey, split) confirms the request through fn_customer_support_concierge_confirm and carries its guidance;
//   * the portal's composer asks for the guidance and shows it on a first request, and the portal shows it again
//     after posting.
// Run: node --test scripts/checks/a_first_request_is_guided_and_confirmed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (f) => readFileSync(join(REPO, f), 'utf8');

test('customer_api serves the guidance and confirms every posted request', () => {
  const src = read('supabase/functions/customer_api/index.ts');
  assert.match(src, /action === 'concierge'[\s\S]{0,400}\.rpc\('fn_customer_concierge'/, "action 'concierge' no longer reads fn_customer_concierge");
  assert.match(src, /\.rpc\('fn_customer_support_concierge_confirm'/, 'create_inquiry no longer confirms the request');
  const start = src.indexOf("if (action === 'create_inquiry')");
  const body = src.slice(start, src.indexOf("if (action === 'rfq_note')", start));
  const posted = [...body.matchAll(/return J\((\{ \.\.\.)?posted(Single|Split)\(/g)];
  assert.ok(posted.length >= 3, `expected the single, turnkey and split answers, found ${posted.length}`);
  const bare = [...body.matchAll(/return J\(posted(Single|Split)\(/g)];
  assert.deepEqual(bare.map((m) => m[0]), [], 'a create_inquiry answer is returned without its concierge guidance');
});

test('the portal shows the guidance on a first request and after posting', () => {
  const nr = read('src/components/me/NewRequest.tsx');
  assert.match(nr, /action: 'concierge'/, 'the composer no longer asks for the guidance');
  assert.match(nr, /first_inquiry[\s\S]{0,120}<ConciergeSteps/, 'the composer does not show the guidance on a first request');
  const cp = read('src/components/me/CustomerPortal.tsx');
  assert.match(cp, /r\.concierge/, 'the portal ignores the guidance create_inquiry returns');
  assert.match(cp, /<ConciergeSteps/, 'the portal does not show the guidance after posting');
});
