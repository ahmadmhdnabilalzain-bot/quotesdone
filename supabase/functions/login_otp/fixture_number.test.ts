// A fixture number is never texted by login_otp (_shared/demo_identity.ts FIXTURE_CAPTURE_NOTE).
// On 14 Sep 2026 this function texted +971500000042 four times because a fixture supplier held it.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { FIXTURE, REAL_LOOKING, invoke, loadFunction } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('login_otp', () => import('./index.ts'));
// The 14 Sep shape: a supplier account really does hold the number, so every identity check passes.
const held = { rows: { leads: [{ claimed_by: 'qd-stub-sup1@example.invalid' }] } };

Deno.test('login_otp send: a fixture number an account holds makes zero requests to twilio.com', async () => {
  const r = await invoke(await fn(), held, { action: 'send', user_kind: 'supplier', identifier: FIXTURE });
  assertEquals(r.twilio.length, 0);
  assertEquals(r.json?.captured, true);
  assert(r.calls.some((c) => c.url.includes('/rest/v1/agent_runs') && c.body.includes('captured: reserved fixture mobile')), 'the capture is recorded');
});

Deno.test('login_otp verify: a fixture number is never checked with Twilio', async () => {
  const r = await invoke(await fn(), held, { action: 'verify', user_kind: 'supplier', identifier: FIXTURE, code: '123456' });
  assertEquals(r.twilio.length, 0);
  assertEquals(r.json?.captured, true);
});

Deno.test('login_otp positive control: the same account on a real-looking number does reach Twilio', async () => {
  const r = await invoke(await fn(), held, { action: 'send', user_kind: 'supplier', identifier: REAL_LOOKING });
  assertEquals(r.twilio.length, 1, JSON.stringify(r.json));
});
