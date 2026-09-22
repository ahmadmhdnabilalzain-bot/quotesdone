// NO PAID CALL REPEATS ITSELF (it_engineer, 22 Sep 2026, founder instruction 705: "if there is a bug that
// is costing us something or repeated work, that needs to be checked before we activate").
//
// The sweep of every consumer in the OpenRouter inventory found these repeat-spend shapes. Each one FAILS
// here if it comes back. Repository only; the pure rules are replayed in _shared/spend_guards.test.ts, the
// resend_inbound redelivery in resend_inbound/index.test.ts, the spec sweep in
// a_failed_spec_check_backs_off.test.mjs and our own test traffic in
// our_own_test_traffic_never_reaches_a_paid_model.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');

test('ai_gateway: at most two paid calls per request, and none after a refusal that cannot change', () => {
  const gw = read('supabase/functions/ai_gateway/index.ts');
  assert.match(gw, /const plan = attemptPlan\(ladder\)/, 'the paid attempts must come from attemptPlan');
  assert.match(gw, /pi = nextAttempt\(plan, pi, failureKind\(failStatus\)\)/, 'the next attempt must depend on why the last one failed');
  assert.doesNotMatch(gw, /for \(let attempt = 0; attempt < 2; attempt\+\+\)/, 'the nested 2-attempts-per-model loop (4 calls a request) is back');
});

test('quote_compare: one gateway request per card view, and a failure is cached with a retry-after', () => {
  const qc = read('supabase/functions/quote_compare/index.ts');
  assert.equal((qc.match(/\/functions\/v1\/ai_gateway'/g) || []).length, 1, 'quote_compare must make exactly one gateway request');
  assert.doesNotMatch(qc, /for \(let attempt = 0; attempt < 2/, 'the 2-attempt loop over the gateway (up to 8 calls a view) is back');
  assert.match(qc, /await rememberFailure\(String\(lastDetail\)\)/, 'a failed comparison must be cached');
  assert.match(qc, /await rememberFailure\('empty_shortlist'\)/, 'an empty shortlist must be cached as a failure');
  assert.match(qc, /activeFailure\(priorFailure\)/, 'a cached failure must be served inside its retry window');
  assert.match(qc, /Date\.now\(\) - reqStart/, 'the wall must run on the request clock, not the worker\'s age');
});

test('doc_extract: a document that cannot be claimed is not read (its attempts would never rise)', () => {
  const de = read('supabase/functions/doc_extract/index.ts');
  const claim = de.indexOf("update({status:'processing',attempts:");
  const stop = de.indexOf("if(claimErr) return j(");
  const firstRead = de.indexOf('llmJSON(', claim);
  assert.ok(claim > 0 && stop > claim && (firstRead < 0 || stop < firstRead), 'a failed claim must return before any read');
});

test('email_triage: an answer that cannot be recorded stops the batch instead of being re-paid next run', () => {
  const et = read('supabase/functions/email_triage/index.ts');
  assert.match(et, /const \{ error: markErr \} = await admin\.from\('inbound_messages'\)\.update\(/);
  assert.match(et, /if \(markErr\) \{[^\n]*return J\(\{ ok: false, error: 'mark_failed'/);
});

test('resend_inbound: an email already on file is answered before any reader or model', () => {
  const ri = read('supabase/functions/resend_inbound/index.ts');
  const dedupe = ri.indexOf(".eq('provider_email_id', providerEmailId)");
  const firstModel = ri.indexOf('/functions/v1/ai_gateway');
  const firstReaderCall = ri.indexOf('await extractDoc(');
  assert.ok(dedupe > 0, 'resend_inbound no longer looks the email up by its Resend id');
  assert.ok(dedupe < firstModel && (firstReaderCall < 0 || dedupe < firstReaderCall), 'the redelivery check must come before every model and reader call');
});
