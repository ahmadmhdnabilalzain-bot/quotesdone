// A fixture number is never sent or checked a Verify code by kyc (_shared/demo_identity.ts).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { FIXTURE, REAL_LOOKING, invoke, loadFunction } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('kyc', () => import('./index.ts'));

for (const action of ['send_sms', 'verify_sms', 'whatsapp_send_code', 'whatsapp_verify']) {
  Deno.test(`kyc ${action}: a fixture number makes zero requests to twilio.com`, async () => {
    const r = await invoke(await fn(), {}, { action, phone: FIXTURE, code: '123456' });
    assertEquals(r.twilio.length, 0);
    assertEquals(r.json?.captured, true);
    assert(r.calls.some((c) => c.url.includes('/rest/v1/agent_runs') && c.body.includes('captured: reserved fixture mobile')), 'the capture is recorded');
  });
}

Deno.test('kyc positive control: send_sms to a real-looking number does reach Twilio', async () => {
  const r = await invoke(await fn(), {}, { action: 'send_sms', phone: REAL_LOOKING });
  assertEquals(r.twilio.length, 1, JSON.stringify(r.json));
});
