// A WHATSAPP SIGN-IN CODE WITHOUT THE VERIFY FEE (ledger 1252, 27 Oct 2026; _shared/wa_code.ts).
// The founder found USD 0.17 a code too much. A WhatsApp code through Twilio Verify was still USD 0.0657 (0.0157 the
// message + 0.05 Verify's fee). These pin that a confirmed WhatsApp number gets OUR code by the approved login_code
// template (no Verify call at all), that our code signs in without Verify, that an SMS-failover code still signs in
// through Verify, and that anything short of a clean send of ours falls back to Verify exactly as before.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, REAL_LOOKING, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('login_otp', () => import('./index.ts'));
const SM = 'SM' + 'b'.repeat(32), HX = 'HX' + '3'.repeat(32);
const EMAIL = 'qd-stub-cust@example.invalid';
const customer = { email: EMAIL, phone: REAL_LOOKING, phone_verified: true, email_verified: true, whatsapp_phone: REAL_LOOKING, whatsapp_verified_at: '2026-10-20T10:00:00Z' };
const secrets = { wa_template_sids: JSON.stringify({ login_code: { en: HX, ar: HX } }), twilio_wa_from: '+97140000000' };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const isMessages = (u: URL) => u.hostname === 'api.twilio.com' && u.pathname.endsWith('/Messages.json');
const isVerify = (u: URL, what: string) => u.hostname === 'verify.twilio.com' && u.pathname.endsWith('/' + what);
function stub(o: { rpc?: Record<string, unknown>; twilio?: Stub['twilio'] } = {}): Stub {
  return {
    secrets, rpc: { fn_phone_code_issue: 7, ...(o.rpc ?? {}) },
    handle: (req, u) => {
      if (req.method !== 'GET' || !u.pathname.endsWith('/rest/v1/customers')) return undefined;
      return json([customer]);
    },
    twilio: o.twilio ?? ((_r, u) => isMessages(u) ? json({ sid: SM, status: 'queued' }, 201) : undefined),
  };
}
const minted = (calls: { url: string }[]) => calls.some((c) => c.url.includes('/auth/v1/admin/generate_link'));
const pvInsert = (calls: { url: string; method: string; body: string }[]) => calls.find((c) => c.method === 'POST' && c.url.includes('/rest/v1/phone_verifications'))?.body ?? '';

Deno.test('send: a confirmed WhatsApp number gets our code by the login_code template, and Verify is never asked', async () => {
  const r = await invoke(await fn(), stub(), { action: 'send', user_kind: 'customer', identifier: REAL_LOOKING });
  assertEquals(r.status, 200, JSON.stringify(r.json));
  assertEquals(r.twilio.length, 1, r.twilio.map((c) => c.url).join(' '));
  const form = new URLSearchParams(r.twilio[0].body);
  assertEquals([new URL(r.twilio[0].url).hostname, form.get('ContentSid'), form.get('To')], ['api.twilio.com', HX, 'whatsapp:' + REAL_LOOKING]);
  assert(pvInsert(r.calls).includes('qd:whatsapp:' + SM), pvInsert(r.calls));
  assert(!JSON.stringify(r.json).includes(JSON.parse(form.get('ContentVariables')!)['1']), 'the code came back to the caller');
});

Deno.test('send control: before the table is applied (fn_phone_code_issue answers nothing) the code goes by Verify as before', async () => {
  const r = await invoke(await fn(), stub({ rpc: { fn_phone_code_issue: null } }), { action: 'send', user_kind: 'customer', identifier: REAL_LOOKING });
  assertEquals(r.status, 200, JSON.stringify(r.json));
  assertEquals(r.twilio.map((c) => new URL(c.url).hostname), ['verify.twilio.com']);
  assertEquals(new URLSearchParams(r.twilio[0].body).get('Channel'), 'whatsapp');
});

Deno.test('send: Twilio refuses our template send, so the same request falls back to Verify and our stored code is spent', async () => {
  const r = await invoke(await fn(), stub({ twilio: (_r, u) => isMessages(u) ? json({ code: 63016, message: 'refused' }, 400) : undefined }),
    { action: 'send', user_kind: 'customer', identifier: REAL_LOOKING });
  assertEquals(r.status, 200, JSON.stringify(r.json));
  assertEquals(r.twilio.map((c) => new URL(c.url).hostname), ['api.twilio.com', 'verify.twilio.com']);
  const spent = r.calls.find((c) => c.url.endsWith('/rpc/fn_phone_code_sent'));
  assert(spent && JSON.parse(spent.body).p_accepted === false, 'the refused code was not spent');
});

Deno.test('verify: our code signs in without asking Verify', async () => {
  const r = await invoke(await fn(), stub({ rpc: { fn_phone_code_verify: 'ok' } }), { action: 'verify', user_kind: 'customer', identifier: REAL_LOOKING, code: '123456' });
  assert(minted(r.calls), JSON.stringify(r.json));
  assertEquals(r.twilio.length, 0);
});

Deno.test('verify: the SMS failover code (a Verify code) still signs in when ours does not match', async () => {
  const r = await invoke(await fn(), stub({ rpc: { fn_phone_code_verify: 'wrong' }, twilio: (_r, u) => isVerify(u, 'VerificationCheck') ? json({ status: 'approved' }) : undefined }),
    { action: 'verify', user_kind: 'customer', identifier: REAL_LOOKING, code: '654321' });
  assert(minted(r.calls), JSON.stringify(r.json));
});

Deno.test('verify: neither ours nor Verify matches, so there is no session; a burned code of ours says so', async () => {
  const no = (_r: Request, u: URL) => isVerify(u, 'VerificationCheck') ? json({ status: 'pending' }) : undefined;
  const w = await invoke(await fn(), stub({ rpc: { fn_phone_code_verify: 'wrong' }, twilio: no }), { action: 'verify', user_kind: 'customer', identifier: REAL_LOOKING, code: '111111' });
  assertEquals([w.status, w.json?.code, minted(w.calls)], [400, 'wrong_code', false]);
  const b = await invoke(await fn(), stub({ rpc: { fn_phone_code_verify: 'burned' }, twilio: no }), { action: 'verify', user_kind: 'customer', identifier: REAL_LOOKING, code: '111111' });
  assertEquals([b.status, b.json?.code, minted(b.calls)], [429, 'code_burned', false]);
});

Deno.test('failover: an undelivered WhatsApp code of ours is read from the Messages API and sent again by Verify SMS', async () => {
  const row = { code: 'qd:whatsapp:' + SM, created_at: new Date(Date.now() - 20_000).toISOString(), email: EMAIL };
  const s = stub({ twilio: (_r, u) => u.hostname === 'api.twilio.com' && u.pathname.endsWith('/Messages/' + SM + '.json') ? json({ sid: SM, status: 'undelivered' }) : undefined });
  const inner = s.handle!;
  s.handle = (req, u) => (req.method === 'GET' && u.pathname.endsWith('/rest/v1/phone_verifications')) ? json(row) : inner(req, u);
  const r = await invoke(await fn(), s, { action: 'failover', user_kind: 'customer', identifier: REAL_LOOKING });
  assertEquals(r.json, { ok: true });
  const hosts = r.twilio.map((c) => new URL(c.url).hostname + new URL(c.url).pathname.replace(/\/Services\/[^/]+/, ''));
  assert(hosts[0].endsWith('/Messages/' + SM + '.json'), hosts.join(' '));
  assert(hosts.some((h) => h === 'verify.twilio.com/v2/Verifications'), hosts.join(' '));
  assertEquals(r.twilio.some((c) => c.url.includes('/Attempts')), false, 'Verify Attempts was read for a message Verify never sent');
});
