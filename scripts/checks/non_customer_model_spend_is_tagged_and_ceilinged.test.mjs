// NON-CUSTOMER MODEL SPEND IS TAGGED AND HAS A DAILY CEILING; CUSTOMER SPEND NEVER MEETS ONE
// (it_engineer, 3 Nov 2026; the founder after the top-up: "just make sure we dont waste money in a stupid way").
// Measured: 7 days to 3 Nov, OpenRouter billed USD 141.20, nearly all tests; 48 WhatsApp exchange runs posted untagged.
// The pure rules are in supabase/functions/_shared/spend_ceiling.test.ts; this holds the wiring in place.
//
// FAILS if:
//   * the WhatsApp exchange driver makes a request to the handler without the run tag and secret, or runs without them;
//   * the exchange stops fingerprinting the code it exercises (a re-run of unchanged code is refused);
//   * ai_gateway's ceiling check moves before the fixture check or after the provider key is read, or stops being skipped
//     (annotated, never an error);
//   * anything other than a proven run tag or the explicit 'internal' declaration can put a request under a ceiling.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');

test('every request the WhatsApp exchange driver makes carries the run tag and its proof', () => {
  const d = read('scripts/e2e/wa_exchange_real_driver.ts');
  const requests = d.split('handler!(new Request(').length - 1;
  const tagged = (d.match(/handler!\(new Request\([^\n]*\.\.\.TAG_HEADERS/g) || []).length;
  assert.ok(requests >= 3, 'the driver makes its text, file and forged requests through the handler');
  assert.equal(tagged, requests, `${requests - tagged} handler request(s) without the run tag`);
  assert.match(d, /if \(!cfg\.e2e\?\.tag \|\| !cfg\.e2e\?\.secret\) throw/, 'an exchange without a tag must refuse to run');
  const m = read('scripts/e2e/wa_exchange_real.mjs');
  assert.match(m, /e2e: \{ tag, secret: await internalCred\(\) \}, \.\.\.\(SCRIPT/, 'every run, not only a scripted one, hands the driver its tag');
  assert.match(m, /note = \$\{q\('code=' \+ CODE \+ ':passed'\)\}/, 'a re-run of code that already passed is refused');
  assert.match(m, /if \(!SCRIPT && !process\.exitCode\) await mgmtFixture\(REF, `update public\.rehearsal_window set note = \$\{q\('code=' \+ CODE \+ ':passed'\)\}/,
    'only a run whose verdicts all passed marks its code exchanged');
});

test('ai_gateway checks the daily ceiling after the fixture check and before the provider key; a skip is not an error', () => {
  const gw = read('supabase/functions/ai_gateway/index.ts');
  const fx = gw.indexOf("admin.rpc('fn_ai_subject_is_fixture'");
  const ceil = gw.indexOf("admin.rpc('fn_ai_spend_ceiling'");
  const key = gw.indexOf("sec('openrouter_api_key')");
  assert.ok(fx > 0 && fx < ceil && ceil < key, 'order: fixture check, then the ceiling, then the provider key');
  assert.match(gw.slice(ceil, key), /\{ skipped: true, outcome: 'daily_ceiling' \}/);
  assert.match(gw.slice(ceil - 200, ceil), /spendClassOf\(e2eRunTag\(\), body\.spend_class\)/, 'the class comes from the proven tag or the declaration only');
  const ob = read('supabase/functions/_shared/observe.ts');
  assert.match(ob, /ann\?\.skipped === true\) return 'skipped'/);
});

test('internal duty spend is DECLARED per surface by the replay, never inferred from the audience or the function', () => {
  const th = read('supabase/functions/_shared/think.ts');
  assert.match(th, /const internalDuty = req\.internalDuty === true && INTERNAL_AUDIENCES\.has\(audience\);/);
  assert.match(th, /internalDuty: INTERNAL_DUTY_SURFACE\.test\(row\.surface\)/, 'only replayHeld declares it, by surface');
  assert.match(th, /const spendClass = o\.internal === true \? 'internal' as const : undefined;/);
  // nothing else in the functions tree may declare it
  const gw = read('supabase/functions/ai_gateway/index.ts');
  assert.doesNotMatch(gw, /spend_class: 'internal'/);
});
