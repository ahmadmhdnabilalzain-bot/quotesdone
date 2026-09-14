// A fixture number is never texted by send_sms, direct or from the queue (_shared/demo_identity.ts).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { FIXTURE, REAL_LOOKING, invoke, loadFunction } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('send_sms', () => import('./index.ts'));
const SECRET = 'stub-internal-credential-0123456789';
const authed = { rpc: { fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false } } };

Deno.test('send_sms direct: a fixture number makes zero requests to twilio.com', async () => {
  const r = await invoke(await fn(), authed, { __secret: SECRET, to: FIXTURE, body: 'hello' });
  assertEquals(r.twilio.length, 0);
  assertEquals(r.json?.captured, true);
});

Deno.test('send_sms flush: a queued SMS to a fixture number is suppressed with the capture note, never sent', async () => {
  const r = await invoke(await fn(), { ...authed, rows: { notifications: [{ id: 7, to_phone: FIXTURE, body: 'hello' }] } }, { __secret: SECRET });
  assertEquals(r.twilio.length, 0);
  assert(r.calls.some((c) => c.method === 'PATCH' && c.url.includes('/rest/v1/notifications') && c.body.includes('"suppressed"') && c.body.includes('captured: reserved fixture mobile')),
    'the row is marked suppressed the way send_whatsapp marks it');
});

Deno.test('send_sms positive control: a real-looking number does reach Twilio', async () => {
  const r = await invoke(await fn(), authed, { __secret: SECRET, to: REAL_LOOKING, body: 'hello' });
  assertEquals(r.twilio.length, 1, JSON.stringify(r.json));
});
