// A PHONE CODE ALREADY TYPED BACK IS NEVER SENT AGAIN BY SMS (it_engineer, 19 Nov 2026; ledger 1252).
// The supplier form keeps asking kyc phone_failover at 15/30/47/62 s after the WhatsApp code is sent (src/lib/otpFailover.ts),
// and it stays mounted after the mobile is verified; the two real codes on production were typed back 14 s and 20 s after the
// send. phone_failover never read phone_verifications.used_at, so at 47 s a status read that answered nothing bought a
// USD 0.1176 Verify SMS for a person already verified. Pinned: a used row makes zero requests to Twilio; the positive control
// (the same row unused) still fails over by SMS, so ruling 994's SMS failover is unchanged.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, REAL_LOOKING, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('kyc', () => import('./index.ts'));
const SM = 'SM' + 'd'.repeat(32);
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const statusDown = (_r: Request, u: URL) => u.pathname.endsWith('/Messages/' + SM + '.json') ? json({ message: 'down' }, 500) : undefined;
function stub(usedAt: string | null): Stub {
  const row = { code: 'qd:whatsapp:' + SM, created_at: new Date(Date.now() - 50_000).toISOString(), used_at: usedAt };
  return {
    twilio: statusDown,
    handle: (req, u) => (req.method === 'GET' && u.pathname.endsWith('/rest/v1/phone_verifications')) ? json(row) : undefined,
  };
}
const smsSent = (twilio: { url: string; body: string }[]) =>
  twilio.some((c) => new URL(c.url).hostname === 'verify.twilio.com' && c.url.endsWith('/Verifications') && new URLSearchParams(c.body).get('Channel') === 'sms');

Deno.test('kyc phone_failover: a WhatsApp code already typed back makes zero requests to Twilio', async () => {
  const r = await invoke(await fn(), stub(new Date(Date.now() - 30_000).toISOString()), { action: 'phone_failover', phone: REAL_LOOKING });
  assertEquals(r.json, { ok: true, state: 'nothing_to_do' });
  assertEquals(r.twilio.length, 0, r.twilio.map((c) => c.url).join(' '));
});

Deno.test('kyc phone_failover control: the same code unused, 50 s old, status unreadable, goes again by SMS', async () => {
  const r = await invoke(await fn(), stub(null), { action: 'phone_failover', phone: REAL_LOOKING });
  assert(smsSent(r.twilio), JSON.stringify(r.json) + ' ' + r.twilio.map((c) => c.url).join(' '));
  assertEquals(r.json?.state, 'sent_sms');
});
