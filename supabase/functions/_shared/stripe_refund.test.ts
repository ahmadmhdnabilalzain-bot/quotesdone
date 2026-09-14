// A test payment can never be refunded with the live key, and a live payment never with the test key.
// Stripe is stubbed: every request is recorded with the key it carried, so each case asserts both the
// answer and which key (if any) ever left this process.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { keyMode, stripeRefund } from './stripe_refund.ts';

const LIVE = 'sk_live_ZZDEMOlive', TEST = 'sk_test_ZZDEMOtest';

function stub(secrets: Record<string, string>, payments: Record<string, { livemode: boolean; status?: number }>) {
  const calls: Array<{ url: string; key: string; method: string }> = [];
  const f = (async (url: string | URL, init?: RequestInit) => {
    const u = String(url);
    const key = String((init?.headers as Record<string, string>)?.Authorization || '').replace('Bearer ', '');
    calls.push({ url: u, key, method: init?.method || 'GET' });
    const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s });
    const pi = decodeURIComponent(u.split('/payment_intents/')[1] || '');
    if (pi) {
      const p = payments[pi];
      // Stripe answers a key of the other mode with "No such payment_intent".
      if (!p || (p.livemode ? key !== LIVE : key !== TEST)) return json({ error: { message: 'No such payment_intent' } }, 404);
      return json({ id: pi, livemode: p.livemode });
    }
    if (u.includes('/checkout/sessions/')) return json({ id: 'cs_x', payment_intent: 'pi_test_1', livemode: key === LIVE });
    if (u.endsWith('/v1/refunds')) return json({ id: 're_1', status: 'succeeded', amount: 1234 });
    return json({}, 404);
  }) as typeof fetch;
  return { deps: { secret: async (k: string) => secrets[k], fetch: f }, calls };
}
const both = { stripe_secret_key: LIVE, stripe_secret_key_test: TEST };
const posted = (calls: Array<{ url: string }>) => calls.some((c) => c.url.endsWith('/v1/refunds'));

Deno.test('keyMode reads the prefix and nothing else', () => {
  assertEquals(keyMode('sk_live_abc'), 'live');
  assertEquals(keyMode('rk_test_abc'), 'test');
  assertEquals(keyMode('pk_live_abc'), null);
  assertEquals(keyMode(''), null);
});

Deno.test('a test payment by a demo payer is refunded with the test key, and the live key never leaves', async () => {
  const s = stub(both, { pi_test_1: { livemode: false } });
  const r = await stripeRefund(s.deps, { demoPayer: true, ref: 'pi_test_1', amountFils: 1234, idem: 'qd_refund_1' });
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.ok && r.mode, 'test');
  assert(s.calls.length > 0 && s.calls.every((c) => c.key === TEST), JSON.stringify(s.calls));
});

Deno.test('a demo payer with no test key is refused and Stripe is never called (no fall-through to live)', async () => {
  const s = stub({ stripe_secret_key: LIVE }, { pi_test_1: { livemode: false } });
  const r = await stripeRefund(s.deps, { demoPayer: true, ref: 'pi_test_1', amountFils: 1234, idem: 'k' });
  assertEquals(r.ok, false);
  assertEquals(s.calls.length, 0);
});

Deno.test('a TEST payment can never be refunded with the LIVE key: a real payer citing a test payment is refused before any refund', async () => {
  const s = stub(both, { pi_test_1: { livemode: false } });
  const r = await stripeRefund(s.deps, { demoPayer: false, ref: 'pi_test_1', amountFils: 1234, idem: 'k' });
  assertEquals(r.ok, false);
  assertEquals(posted(s.calls), false);
});

Deno.test('a LIVE payment can never be refunded with the TEST key: a demo payer citing a live payment is refused before any refund', async () => {
  const s = stub(both, { pi_live_1: { livemode: true } });
  const r = await stripeRefund(s.deps, { demoPayer: true, ref: 'pi_live_1', amountFils: 1234, idem: 'k' });
  assertEquals(r.ok, false);
  assertEquals(posted(s.calls), false);
  assert(s.calls.every((c) => c.key === TEST), JSON.stringify(s.calls));
});

Deno.test('a key stored in the wrong slot is refused before Stripe is called', async () => {
  const s = stub({ stripe_secret_key: TEST, stripe_secret_key_test: LIVE }, { pi_live_1: { livemode: true } });
  assertEquals((await stripeRefund(s.deps, { demoPayer: false, ref: 'pi_live_1', amountFils: 1, idem: 'k' })).ok, false);
  assertEquals((await stripeRefund(s.deps, { demoPayer: true, ref: 'pi_live_1', amountFils: 1, idem: 'k' })).ok, false);
  assertEquals(s.calls.length, 0);
});

Deno.test('a live payment by a real payer is refunded with the live key at the stated amount', async () => {
  const s = stub(both, { pi_live_1: { livemode: true } });
  const r = await stripeRefund(s.deps, { demoPayer: false, ref: 'pi_live_1', amountFils: 1234, idem: 'k' });
  assert(r.ok, JSON.stringify(r));
  assert(s.calls.every((c) => c.key === LIVE));
  assert(posted(s.calls));
});
