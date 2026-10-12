// wa_inbound never replies to a fixture number (_shared/demo_identity.ts). Every reply leaves through
// sendWa(); this drives one real reply path (the no-exact-spec answer) end to end.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { FIXTURE, REAL_LOOKING, invoke, loadFunction } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const SECRET = 'stub-internal-credential-0123456789';
const stub = {
  rpc: {
    fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false },
    fn_spec_offer_whatsapp_reply: { handled: true, ok: false, error: 'unknown_option', options: 2 },
  },
  secrets: { wa_autoreply_enabled: 'true' },
  // The reply is the model's (rulings 1195-1197): the gateway is stubbed to answer, so a reply exists to be captured.
  handle: (_req: Request, u: URL) => u.pathname.startsWith('/functions/v1/')
    ? new Response(JSON.stringify({ content: JSON.stringify({ answer: 'ZZ DEMO model reply: please reply 1 or 2, or NO.' }), model: 'stub/model' }), { headers: { 'content-type': 'application/json' } })
    : undefined,
};

Deno.test('wa_inbound reply: a fixture number makes zero requests to twilio.com, and the capture is stored', async () => {
  const r = await invoke(await fn(), stub, { __secret: SECRET, From: 'whatsapp:' + FIXTURE, Body: '5' });
  assertEquals(r.twilio.length, 0);
  assert(r.calls.some((c) => c.url.includes('/rest/v1/wa_messages') && c.body.includes('captured: reserved fixture mobile')), 'send_error records the capture');
});

Deno.test('wa_inbound positive control: the same reply to a real-looking number does reach Twilio', async () => {
  const r = await invoke(await fn(), stub, { __secret: SECRET, From: 'whatsapp:' + REAL_LOOKING, Body: '5' });
  assertEquals(r.twilio.length, 1);
});
