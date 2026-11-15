// node --test src/components/me/auth/acceptTerms.test.mjs
// ProfileGate's "Finish & continue" (./acceptTerms.ts), executed: on 13 Nov 2026 kyc answered ok for an acceptance it had not
// recorded and the page opened the dashboard. kyc now answers 503 terms_not_recorded; the page must NEVER call onDone on it.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { acceptTermsStep } from './acceptTerms.ts';
import { errText } from '../portalText.ts';

// what kyc answers (supabase/functions/_shared/recorded_write.ts TERMS_NOT_RECORDED), read from the source so the two cannot drift
const SRC = readFileSync(new URL('../../../../supabase/functions/_shared/recorded_write.ts', import.meta.url), 'utf8');
const pick = (k) => SRC.match(new RegExp(`${k}: '([^']+)'`))[1];
const NOT_RECORDED = { error: 'terms_not_recorded', code: 'terms_not_recorded', retryable: true, message: pick('message'), message_ar: pick('message_ar') };

function run(answer, lang = 'en') {
  const seen = { done: 0, busy: [], msg: [], calls: [] };
  const call = async (fn, body) => { seen.calls.push(body.action); return body.action === 'accept_terms' ? answer() : { terms_signed: true }; };
  return acceptTermsStep({ call, token: 't', marketing_consent: false, lang, onDone: () => { seen.done++; }, setBusy: (b) => seen.busy.push(b),
    setMsg: (m) => seen.msg.push(m), errText, wait: async () => {} }).then((r) => ({ ...seen, r }));
}

test('terms_not_recorded: onDone is never called, the button comes back, and he reads the sentence in his language', async () => {
  for (const lang of ['en', 'ar']) {
    const s = await run(() => NOT_RECORDED, lang);
    assert.equal(s.done, 0, 'the dashboard must not open on an acceptance that was not recorded');
    assert.equal(s.r, false);
    assert.equal(s.busy.at(-1), '', 'the button is enabled again');
    assert.equal(s.msg.at(-1), lang === 'ar' ? NOT_RECORDED.message_ar : NOT_RECORDED.message);
    assert.deepEqual(s.calls, ['accept_terms'], 'no state polling after a refusal');
  }
});

test('a transport failure or any other refusal does not open the dashboard either; ok does, once', async () => {
  for (const answer of [() => null, () => Promise.reject(new Error('fetch failed')), () => ({ error: 'whatsapp_unanswered', code: 'whatsapp_unanswered' })]) {
    assert.equal((await run(answer)).done, 0);
  }
  const ok = await run(() => ({ ok: true, certificate: 'issuing' }));
  assert.equal(ok.done, 1);
  assert.deepEqual(ok.calls, ['accept_terms', 'state']);
});

test('ProfileGate uses this step for its Finish & continue', () => {
  const gate = readFileSync(new URL('./ProfileGate.tsx', import.meta.url), 'utf8');
  assert.match(gate, /await acceptTermsStep\(\{ call, token, marketing_consent: marketingOptIn === true, lang, onDone, setBusy, setMsg, errText \}\)/);
  assert.doesNotMatch(gate, /accept_terms[^\n]*onDone\(\)/, 'no second path to onDone around the step');
});
