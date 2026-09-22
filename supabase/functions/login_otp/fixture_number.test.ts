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

// 22 Sep 2026: fn_it_detect raised "login_otp turned away 58 of 69 callers (84%)" and all 58 were our own
// harness on the fixture block. The server now marks those run rows `fixture: 1` (refusal_rate leaves them
// out) and carries a registered policy reason onto the row the detector counts. These pin both, each with
// its control, so the watch cannot start counting our own traffic, or stop counting a real person, again.
const fnRow = (calls: { url: string; body: string }[]) =>
  calls.filter((c) => c.url.includes('/rest/v1/agent_runs') && c.body.includes('"fn:login_otp"')).map((c) => c.body).join('\n');

Deno.test('login_otp: a fixture number refused as unknown is marked fixture on the row refusal_rate counts', async () => {
  const r = await invoke(await fn(), {}, { action: 'send', user_kind: 'customer', identifier: FIXTURE });
  assertEquals(r.status, 404);
  assert(fnRow(r.calls).includes('"fixture":1'), 'the telemetry row does not carry fixture:1: ' + fnRow(r.calls));
});

Deno.test('login_otp control: a real-looking number refused as unknown is NOT marked fixture', async () => {
  const r = await invoke(await fn(), {}, { action: 'send', user_kind: 'customer', identifier: REAL_LOOKING });
  assertEquals(r.status, 404);
  const row = fnRow(r.calls);
  assert(row.includes('"http":404'), 'no telemetry row was written, so this control proves nothing: ' + row);
  assert(!row.includes('fixture'), 'a real person\'s refusal was marked as harness traffic: ' + row);
});

Deno.test('login_otp: a phone sign-up refusal carries its registered policy reason onto the counted row', async () => {
  const r = await invoke(await fn(), {}, { action: 'send', user_kind: 'customer', identifier: REAL_LOOKING, allow_signup: true });
  assertEquals(r.status, 404);
  assert(fnRow(r.calls).includes('"sms_signup_refused":1'), fnRow(r.calls));
});

Deno.test('login_otp: a shared number refusal carries ambiguous_phone onto the counted row', async () => {
  const shared = { rows: { customers: [{ email: 'qd-a@example.invalid' }, { email: 'qd-b@example.invalid' }] } };
  const r = await invoke(await fn(), shared, { action: 'send', user_kind: 'customer', identifier: REAL_LOOKING });
  assertEquals(r.status, 409);
  const row = fnRow(r.calls);
  assert(row.includes('"ambiguous_phone":1') && !row.includes('fixture'), row);
});

// 22 Sep 2026: the harness also signs in by reserved-domain email, and those SUCCESSES were counted as customers
// while its refused phone calls were left out -- tilting refusal_rate's share toward health. Both sides are ours.
// These two run after earlier successes in this file, so they also fail if observe() goes back to sampling
// login_otp's successes at one a minute (okEveryMs 0): the row they read would not be written.
Deno.test('login_otp: a reserved test address is marked fixture on the row refusal_rate counts', async () => {
  const r = await invoke(await fn(), {}, { action: 'send', user_kind: 'customer', identifier: 'qd-stub-login@example.invalid' });
  assert(fnRow(r.calls).includes('"fixture":1'), 'a reserved-domain sign-in was counted as a customer: ' + fnRow(r.calls));
});

Deno.test('login_otp control: a real-looking address is NOT marked fixture', async () => {
  const r = await invoke(await fn(), {}, { action: 'send', user_kind: 'customer', identifier: 'someone@quotesdone-customer.ae' });
  const row = fnRow(r.calls);
  assert(row.includes('"http":'), 'no telemetry row was written, so this control proves nothing: ' + row);
  assert(!row.includes('fixture'), 'a real address was marked as harness traffic: ' + row);
});
