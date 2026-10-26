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

// THE QUEUED ROW IS SERVED THE WAY THE FUNCTION NOW TAKES IT (22 Sep 2026, it_engineer, CONN-03).
// It used to be stubbed under `rows: { notifications: [...] }`, because send_sms read its queue with
// `admin.from('notifications').select(...).eq('status','queued')`. That plain SELECT is the defect this
// branch removes: send_sms is driven every 2 minutes AND from the resilience tick, so two overlapping
// runs saw the same row and both texted it. It now CLAIMS through fn_notifications_claim
// (FOR UPDATE SKIP LOCKED -> 'sending'), and a harness that still answers the table read hands the
// function nothing, so the flush has no row to suppress and the assertion below cannot be reached.
// NOTHING IN THE ASSERTION IS RELAXED — it is the same one, still requiring a PATCH marking the row
// 'suppressed' with the capture note and still requiring zero requests to twilio.com. Only the door
// the row comes through has moved, and a harness that does not mirror the real path proves nothing.
Deno.test('send_sms flush: a queued SMS to a fixture number is suppressed with the capture note, never sent', async () => {
  const claimed = { ...authed, rpc: { ...authed.rpc, fn_notifications_claim: [{ id: 7, to_phone: FIXTURE, body: 'hello' }] } };
  const r = await invoke(await fn(), claimed, { __secret: SECRET });
  assertEquals(r.twilio.length, 0);
  assert(r.calls.some((c) => c.method === 'PATCH' && c.url.includes('/rest/v1/notifications') && c.body.includes('"suppressed"') && c.body.includes('captured: reserved fixture mobile')),
    'the row is marked suppressed the way send_whatsapp marks it');
});

Deno.test('send_sms positive control: a real-looking number does reach Twilio', async () => {
  const r = await invoke(await fn(), authed, { __secret: SECRET, to: REAL_LOOKING, body: 'hello' });
  assertEquals(r.twilio.length, 1, JSON.stringify(r.json));
});
