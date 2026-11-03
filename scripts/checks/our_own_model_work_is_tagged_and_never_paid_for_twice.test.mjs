// OUR OWN MODEL WORK IS TAGGED, AND NEVER PAID FOR TWICE (it_engineer, 3 Nov 2026; the founder after the top-up: "just
// make sure we dont waste money in a stupid way"). Measured: 7 days to 3 Nov, OpenRouter billed USD 141.20, nearly all
// tests; 48 WhatsApp exchange runs posted untagged; the CEO's Opus replays paid twice for empty answers.
// No cap of any kind (founder, 24 Sep 2026: "I don't want caps... It shouldn't reach the limit because the code is
// correct, not because we have a cap"): the fixes are tagging, not re-running, and not re-asking.
//
// FAILS if:
//   * the WhatsApp exchange driver makes a request to the handler without the run tag and secret, or runs without them;
//   * the exchange stops refusing a re-run of code that already passed, or marks a failed run as passed;
//   * the internal-duty declaration is inferred from anything but replayHeld's surface list and an internal audience;
//   * a daily ceiling or spend cap is reintroduced in ai_gateway.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
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

test('internal duty is DECLARED per surface by the replay, never inferred from the audience or the function', () => {
  const th = read('supabase/functions/_shared/think.ts');
  assert.match(th, /const internalDuty = req\.internalDuty === true && INTERNAL_AUDIENCES\.has\(audience\);/);
  assert.match(th, /internalDuty: INTERNAL_DUTY_SURFACE\.test\(row\.surface\)/, 'only replayHeld declares it, by surface');
  assert.match(th, /\(ownWork && \/empty_completion\/\.test\(e\)\)/, 'only our own work skips the retry after a paid empty answer');
  const gw = read('supabase/functions/ai_gateway/index.ts');
  assert.match(gw, /const ownWorkCall = !!e2eRunTag\(\) \|\| body\.internal_duty === true;/);
  assert.match(gw, /emptyPaid = ownWorkCall;/, 'a customer request keeps its same-model retry after an empty answer');
});

test('no daily ceiling or spend cap exists (founder ruling of 24 Sep 2026)', () => {
  const gw = read('supabase/functions/ai_gateway/index.ts');
  assert.doesNotMatch(gw, /fn_ai_spend_ceiling|daily_ceiling|spend_ceiling/);
  assert.ok(!existsSync(join(REPO, 'supabase/functions/_shared/spend_ceiling.ts')));
  assert.ok(!existsSync(join(REPO, 'scripts/sql/the_non_customer_model_spend_stops_at_a_daily_ceiling.sql')));
});
