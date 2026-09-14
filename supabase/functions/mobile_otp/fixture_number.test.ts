// A fixture number is never sent or checked a Verify code by mobile_otp (_shared/demo_identity.ts).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { FIXTURE, REAL_LOOKING, invoke, loadFunction } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('mobile_otp', () => import('./index.ts'));
const customer = { rows: { customers: [{ id: 'c-stub', phone: null, phone_verified: false, locale: 'en' }] } };

for (const action of ['send', 'verify']) {
  Deno.test(`mobile_otp ${action}: a fixture number makes zero requests to twilio.com`, async () => {
    const r = await invoke(await fn(), customer, { action, phone: FIXTURE, code: '123456' });
    assertEquals(r.twilio.length, 0);
    assertEquals(r.json?.captured, true);
    assert(r.calls.some((c) => c.url.includes('/rest/v1/agent_runs') && c.body.includes('captured: reserved fixture mobile')), 'the capture is recorded');
  });
}

Deno.test('mobile_otp positive control: send to a real-looking number does reach Twilio', async () => {
  const r = await invoke(await fn(), customer, { action: 'send', phone: REAL_LOOKING });
  assertEquals(r.twilio.length, 1, JSON.stringify(r.json));
});
